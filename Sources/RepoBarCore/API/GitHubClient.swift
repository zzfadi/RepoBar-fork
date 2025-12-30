import Foundation

/// Lightweight GitHub client using REST plus a minimal GraphQL enrichment step.
public actor GitHubClient {
    public var apiHost: URL = .init(string: "https://api.github.com")!
    private let tokenStore = TokenStore()
    private var tokenProvider: (@Sendable () async throws -> OAuthTokens?)?
    private let graphQL = GraphQLClient()
    private let diag = DiagnosticsLogger.shared
    private let requestRunner = GitHubRequestRunner()
    private lazy var restAPI = GitHubRestAPI(
        apiHost: { [weak self] in self?.apiHost ?? URL(string: "https://api.github.com")! },
        tokenProvider: { [weak self] in
            guard let self else { throw URLError(.userAuthenticationRequired) }
            return try await self.validAccessToken()
        },
        requestRunner: requestRunner,
        diag: diag
    )
    private lazy var repoDetailCoordinator = RepoDetailCoordinator(
        restAPI: restAPI,
        policy: RepoDetailCachePolicy.default
    )
    private var prefetchedRepos: [Repository] = []
    private var prefetchedReposExpiry: Date?
    private var inflightRepoDetails: [String: Task<Repository, Error>] = [:]

    public init() {}

    // MARK: - Config

    public func setAPIHost(_ host: URL) {
        do {
            let trusted = try self.trusted(host)
            self.apiHost = trusted
            Task { await self.graphQL.setEndpoint(apiHost: trusted) }
            Task { await self.diag.message("API host set to \(trusted.absoluteString)") }
        } catch {
            Task { await self.diag.message("Rejected API host \(host) (must be https with hostname)") }
        }
    }

    private func trusted(_ host: URL) throws -> URL {
        guard host.scheme?.lowercased() == "https" else { throw GitHubAPIError.invalidHost }
        guard host.host != nil else { throw GitHubAPIError.invalidHost }
        return host
    }

    public func setTokenProvider(_ provider: @Sendable @escaping () async throws -> OAuthTokens?) {
        self.tokenProvider = provider
        Task {
            await self.graphQL.setTokenProvider {
                guard let tokens = try await provider() else { throw URLError(.userAuthenticationRequired) }
                return tokens.accessToken
            }
        }
    }

    public func rateLimitReset(now: Date = Date()) async -> Date? {
        await self.requestRunner.rateLimitReset(now: now)
    }

    public func rateLimitMessage(now: Date = Date()) async -> String? {
        await self.requestRunner.rateLimitMessage(now: now)
    }

    // MARK: - High level fetchers

    public func defaultRepositories(limit: Int, for _: String) async throws -> [Repository] {
        let repos = try await self.restAPI.userReposSorted(limit: max(limit, 10))
        return try await self.expandRepoItems(Array(repos.prefix(limit)))
    }

    public func activityRepositories(limit: Int?) async throws -> [Repository] {
        let items = try await self.restAPI.userReposPaginated(limit: limit)
        let allowedOwners = try await self.allowedOwnerLogins()
        let filtered = items.filter { allowedOwners.contains($0.owner.login.lowercased()) }
        let activityResults = await self.fetchActivityResults(for: filtered)
        return filtered.map { item in
            let fullName = "\(item.owner.login)/\(item.name)"
            let result = activityResults[fullName] ?? ActivityFetchResult(
                pulls: .failure(URLError(.unknown)),
                activity: .failure(URLError(.unknown))
            )
            return self.activityRepository(
                from: item,
                openPullsResult: result.pulls,
                activityResult: result.activity
            )
        }
    }

    public func userActivityEvents(
        username: String,
        scope: GlobalActivityScope,
        limit: Int
    ) async throws -> [ActivityEvent] {
        let events = try await self.restAPI.userEvents(username: username, scope: scope)
        let mapped = events.compactMap { $0.activityEventFromRepo() }
        return Array(mapped.prefix(max(limit, 0)))
    }

    public func userCommitEvents(
        username: String,
        scope: GlobalActivityScope,
        limit: Int
    ) async throws -> [RepoCommitSummary] {
        let events = try await self.restAPI.userEvents(username: username, scope: scope)
        let commits = events.flatMap { $0.commitSummaries() }
        return Array(commits.prefix(max(limit, 0)))
    }

    /// Latest release (including prereleases). Returns `nil` if the repo has no releases.
    public func latestRelease(owner: String, name: String) async throws -> Release? {
        do {
            return try await self.restAPI.latestReleaseAny(owner: owner, name: name)
        } catch let error as URLError where error.code == .fileDoesNotExist {
            return nil
        }
    }

    private func expandRepoItems(_ items: [RepoItem]) async throws -> [Repository] {
        try await withThrowingTaskGroup(of: Repository.self) { group in
            for repo in items {
                group.addTask { try await self.fullRepository(owner: repo.owner.login, name: repo.name) }
            }
            var out: [Repository] = []
            for try await repo in group {
                out.append(repo)
            }
            return out
        }
    }

    private struct ActivityFetchResult {
        let pulls: Result<Int, Error>
        let activity: Result<ActivitySnapshot, Error>
    }

    private func fetchActivityResults(for items: [RepoItem]) async -> [String: ActivityFetchResult] {
        await withTaskGroup(of: (String, ActivityFetchResult).self) { group in
            for item in items {
                group.addTask { [self] in
                    let owner = item.owner.login
                    let name = item.name
                    let fullName = "\(owner)/\(name)"
                    async let openPullsResult: Result<Int, Error> = self.capture {
                        try await self.restAPI.openPullRequestCount(owner: owner, name: name)
                    }
                    async let activityResult: Result<ActivitySnapshot, Error> = self.capture {
                        try await self.restAPI.recentActivity(owner: owner, name: name, limit: 10)
                    }
                    let result = await ActivityFetchResult(
                        pulls: openPullsResult,
                        activity: activityResult
                    )
                    return (fullName, result)
                }
            }
            var out: [String: ActivityFetchResult] = [:]
            for await (fullName, result) in group {
                out[fullName] = result
            }
            return out
        }
    }

    public func fullRepository(owner: String, name: String) async throws -> Repository {
        let key = "\(owner.lowercased())/\(name.lowercased())"
        if let task = self.inflightRepoDetails[key] {
            return try await task.value
        }
        let task = Task { [weak self] () throws -> Repository in
            guard let self else { throw CancellationError() }
            return try await self.fullRepositoryInternal(owner: owner, name: name)
        }
        self.inflightRepoDetails[key] = task
        defer { self.inflightRepoDetails[key] = nil }
        return try await task.value
    }

    private func fullRepositoryInternal(owner: String, name: String) async throws -> Repository {
        try await self.repoDetailCoordinator.fullRepository(owner: owner, name: name)
    }

    private func activityRepository(
        from item: RepoItem,
        openPullsResult: Result<Int, Error>,
        activityResult: Result<ActivitySnapshot, Error>
    ) -> Repository {
        var accumulator = RepoErrorAccumulator()
        let owner = item.owner.login
        let openPulls = self.value(from: openPullsResult, into: &accumulator) ?? 0
        let issues = max(item.openIssuesCount - openPulls, 0)
        let snapshot = self.value(from: activityResult, into: &accumulator)
        let activity: ActivityEvent? = snapshot?.latest ?? snapshot?.events.first
        let activityEvents = snapshot?.events ?? []

        return Repository.from(
            item: item,
            openPulls: openPulls,
            issues: issues,
            latestActivity: activity,
            activityEvents: activityEvents,
            error: accumulator.message,
            rateLimitedUntil: accumulator.rateLimit
        )
    }

    public func currentUser() async throws -> UserIdentity {
        let user = try await self.restAPI.fetchCurrentUser()
        var components = URLComponents()
        components.scheme = apiHost.scheme ?? "https"
        let rawHost = apiHost.host ?? "github.com"
        components.host = rawHost == "api.github.com" ? "github.com" : rawHost
        let hostURL = components.url ?? URL(string: "https://github.com")!
        return UserIdentity(username: user.login, host: hostURL)
    }

    public func searchRepositories(matching query: String) async throws -> [Repository] {
        let items = try await self.restAPI.searchRepositories(matching: query)
        return items.map { Repository.from(item: $0) }
    }

    public func clearCache() async {
        await self.requestRunner.clear()
        self.prefetchedRepos = []
        self.prefetchedReposExpiry = nil
        self.repoDetailCoordinator.clearCache()
    }

    public func diagnostics() async -> DiagnosticsSummary {
        let requestDiagnostics = await self.requestRunner.diagnosticsSnapshot()
        return await DiagnosticsSummary(
            apiHost: self.apiHost,
            rateLimitReset: requestDiagnostics.rateLimitReset,
            lastRateLimitError: requestDiagnostics.lastRateLimitError,
            etagEntries: requestDiagnostics.etagEntries,
            backoffEntries: requestDiagnostics.backoffEntries,
            restRateLimit: requestDiagnostics.restRateLimit,
            graphQLRateLimit: self.graphQL.rateLimitSnapshot()
        )
    }

    /// Recent repositories for the authenticated user, sorted by activity.
    public func recentRepositories(limit: Int = 8) async throws -> [Repository] {
        let items = try await self.restAPI.userReposSorted(limit: limit)
        return items.map { Repository.from(item: $0) }
    }

    /// Contribution heatmap for a user (year view), used to render the header without fetching remote images.
    public func userContributionHeatmap(login: String) async throws -> [HeatmapCell] {
        try await self.graphQL.userContributionHeatmap(login: login)
    }

    /// Prefetch up to `RepoCacheConstants.maxRepositoriesToPrefetch` repos once per hour for fast autocomplete.
    public func prefetchedRepositories(
        max: Int = RepoCacheConstants.maxRepositoriesToPrefetch
    ) async throws -> [Repository] {
        let now = Date()
        if let expires = self.prefetchedReposExpiry, expires > now, !self.prefetchedRepos.isEmpty {
            return Array(self.prefetchedRepos.prefix(max))
        }

        let items = try await self.restAPI.userReposPaginated(limit: max)
        let repos = items.map { Repository.from(item: $0) }
        self.prefetchedRepos = repos
        self.prefetchedReposExpiry = now.addingTimeInterval(RepoCacheConstants.cacheTTL)
        return repos
    }

    public func recentPullRequests(owner: String, name: String, limit: Int = 20) async throws -> [RepoPullRequestSummary] {
        try await self.restAPI.recentPullRequests(owner: owner, name: name, limit: limit)
    }

    public func recentIssues(owner: String, name: String, limit: Int = 20) async throws -> [RepoIssueSummary] {
        try await self.restAPI.recentIssues(owner: owner, name: name, limit: limit)
    }

    public func recentReleases(owner: String, name: String, limit: Int = 20) async throws -> [RepoReleaseSummary] {
        try await self.restAPI.recentReleases(owner: owner, name: name, limit: limit)
    }

    public func recentWorkflowRuns(owner: String, name: String, limit: Int = 20) async throws -> [RepoWorkflowRunSummary] {
        try await self.restAPI.recentWorkflowRuns(owner: owner, name: name, limit: limit)
    }

    public func recentCommits(owner: String, name: String, limit: Int = 20) async throws -> RepoCommitList {
        try await self.restAPI.recentCommits(owner: owner, name: name, limit: limit)
    }

    public func recentDiscussions(owner: String, name: String, limit: Int = 20) async throws -> [RepoDiscussionSummary] {
        try await self.restAPI.recentDiscussions(owner: owner, name: name, limit: limit)
    }

    public func recentTags(owner: String, name: String, limit: Int = 20) async throws -> [RepoTagSummary] {
        try await self.restAPI.recentTags(owner: owner, name: name, limit: limit)
    }

    public func recentBranches(owner: String, name: String, limit: Int = 20) async throws -> [RepoBranchSummary] {
        try await self.restAPI.recentBranches(owner: owner, name: name, limit: limit)
    }

    public func topContributors(owner: String, name: String, limit: Int = 20) async throws -> [RepoContributorSummary] {
        try await self.restAPI.topContributors(owner: owner, name: name, limit: limit)
    }

    // MARK: - Internal helpers

    private func allowedOwnerLogins() async throws -> Set<String> {
        let user = try await self.currentUser()
        var allowed = Set<String>()
        allowed.insert(user.username.lowercased())
        do {
            let orgs = try await self.restAPI.ownedOrgLogins()
            for org in orgs {
                allowed.insert(org.lowercased())
            }
        } catch {
            await self.diag.message("Failed to fetch org memberships; filtering to user only.")
        }
        return allowed
    }

    private func validAccessToken() async throws -> String {
        if let provider = tokenProvider, let tokens = try await provider() { return tokens.accessToken }
        if let token = try tokenStore.load()?.accessToken { return token }
        throw URLError(.userAuthenticationRequired)
    }

    private func capture<T>(_ work: @escaping () async throws -> T) async -> Result<T, Error> {
        do { return try await .success(work()) } catch { return .failure(error) }
    }

    private func value<T>(from result: Result<T, Error>, into accumulator: inout RepoErrorAccumulator) -> T? {
        switch result {
        case let .success(value): return value
        case let .failure(error):
            accumulator.absorb(error)
            return nil
        }
    }
}

public struct DiagnosticsSummary: Sendable {
    public let apiHost: URL
    public let rateLimitReset: Date?
    public let lastRateLimitError: String?
    public let etagEntries: Int
    public let backoffEntries: Int
    public let restRateLimit: RateLimitSnapshot?
    public let graphQLRateLimit: RateLimitSnapshot?

    public static let empty = DiagnosticsSummary(
        apiHost: URL(string: "https://api.github.com")!,
        rateLimitReset: nil,
        lastRateLimitError: nil,
        etagEntries: 0,
        backoffEntries: 0,
        restRateLimit: nil,
        graphQLRateLimit: nil
    )
}
