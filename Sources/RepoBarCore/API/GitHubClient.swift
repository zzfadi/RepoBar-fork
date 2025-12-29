import Foundation
import OSLog

/// Lightweight GitHub client using REST plus a minimal GraphQL enrichment step.
public actor GitHubClient {
    public var apiHost: URL = .init(string: "https://api.github.com")!
    private let tokenStore = TokenStore()
    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let etagCache = ETagCache()
    private let backoff = BackoffTracker()
    private var lastRateLimitReset: Date?
    private var lastRateLimitError: String?
    private var tokenProvider: (@Sendable () async throws -> OAuthTokens?)?
    private let graphQL = GraphQLClient()
    private let diag = DiagnosticsLogger.shared
    private var prefetchedRepos: [Repository] = []
    private var prefetchedReposExpiry: Date?
    private var latestRestRateLimit: RateLimitSnapshot?
    private var repoDetailStore = RepoDetailStore()
    private let repoDetailCachePolicy = RepoDetailCachePolicy.default
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

    public func rateLimitReset(now: Date = Date()) -> Date? {
        guard let reset = self.lastRateLimitReset, reset > now else {
            self.lastRateLimitReset = nil
            self.lastRateLimitError = nil
            return nil
        }
        return reset
    }

    public func rateLimitMessage(now: Date = Date()) -> String? {
        guard self.rateLimitReset(now: now) != nil else { return nil }
        return self.lastRateLimitError
    }

    // MARK: - High level fetchers

    public func defaultRepositories(limit: Int, for _: String) async throws -> [Repository] {
        let repos = try await userReposSorted(limit: max(limit, 10))
        return try await self.expandRepoItems(Array(repos.prefix(limit)))
    }

    public func activityRepositories(limit: Int?) async throws -> [Repository] {
        let items = try await self.userReposPaginated(limit: limit)
        let allowedOwners = try await self.allowedOwnerLogins()
        let filtered = items.filter { allowedOwners.contains($0.owner.login.lowercased()) }
        return try await self.expandActivityItems(filtered)
    }

    /// Latest release (including prereleases). Returns `nil` if the repo has no releases.
    public func latestRelease(owner: String, name: String) async throws -> Release? {
        do {
            return try await self.latestReleaseAny(owner: owner, name: name)
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

    private func expandActivityItems(_ items: [RepoItem]) async throws -> [Repository] {
        try await withThrowingTaskGroup(of: Repository.self) { group in
            for repo in items {
                group.addTask { try await self.activityRepository(from: repo) }
            }
            var out: [Repository] = []
            for try await repo in group {
                out.append(repo)
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
        var accumulator = RepoErrorAccumulator()

        let details: RepoItem
        do {
            details = try await self.repoDetails(owner: owner, name: name)
        } catch {
            accumulator.absorb(error)
            return Repository(
                id: "\(owner)/\(name)",
                name: name,
                owner: owner,
                sortOrder: nil,
                error: accumulator.message,
                rateLimitedUntil: accumulator.rateLimit,
                ciStatus: .unknown,
                ciRunCount: nil,
                openIssues: 0,
                openPulls: 0,
                stars: 0,
                pushedAt: nil,
                latestRelease: nil,
                latestActivity: nil,
                traffic: nil,
                heatmap: []
            )
        }

        let now = Date()
        let owner = details.owner.login
        let name = details.name
        var cache = self.repoDetailStore.load(apiHost: self.apiHost, owner: owner, name: name)
        let cacheState = self.repoDetailCachePolicy.state(for: cache, now: now)
        let cachedOpenPulls = cache.openPulls ?? 0
        let cachedCiDetails = cache.ciDetails ?? CIStatusDetails(status: .unknown, runCount: nil)
        let cachedActivity = cache.latestActivity
        let cachedActivityEvents = cache.activityEvents ?? []
        let cachedTraffic = cache.traffic
        let cachedHeatmap = cache.heatmap ?? []
        let cachedRelease = cache.latestRelease

        let shouldFetchPulls = cacheState.openPulls.needsRefresh
        let shouldFetchCI = cacheState.ci.needsRefresh
        let shouldFetchActivity = cacheState.activity.needsRefresh
        let shouldFetchTraffic = cacheState.traffic.needsRefresh
        let shouldFetchHeatmap = cacheState.heatmap.needsRefresh
        let shouldFetchRelease = cacheState.release.needsRefresh
        var didUpdateCache = false

        // Run all expensive lookups in parallel; individual failures are folded into the accumulator.
        async let openPullsResult: Result<Int, Error> = shouldFetchPulls
            ? self.capture { try await self.openPullRequestCount(owner: owner, name: name) }
            : .success(cachedOpenPulls)
        async let ciResult: Result<CIStatusDetails, Error> = shouldFetchCI
            ? self.capture { try await self.ciStatus(owner: owner, name: name) }
            : .success(cachedCiDetails)
        async let activityResult: Result<ActivitySnapshot, Error> = shouldFetchActivity
            ? self.capture { try await self.recentActivity(owner: owner, name: name, limit: 10) }
            : .success(ActivitySnapshot(events: cachedActivityEvents, latest: cachedActivity))
        async let trafficResult: Result<TrafficStats?, Error> = shouldFetchTraffic
            ? self.capture { try await self.trafficStats(owner: owner, name: name) }
            : .success(cachedTraffic)
        async let heatmapResult: Result<[HeatmapCell], Error> = shouldFetchHeatmap
            ? self.capture { try await self.commitHeatmap(owner: owner, name: name) }
            : .success(cachedHeatmap)
        async let releaseResult: Result<Release?, Error> = shouldFetchRelease
            ? self.capture { try await self.latestReleaseAny(owner: owner, name: name) }
            : .success(cachedRelease)

        let openPulls: Int
        switch await openPullsResult {
        case let .success(value):
            openPulls = value
            if shouldFetchPulls {
                cache.openPulls = value
                cache.openPullsFetchedAt = now
                didUpdateCache = true
            }
        case let .failure(error):
            accumulator.absorb(error)
            openPulls = cache.openPulls ?? 0
        }
        let issues = max(details.openIssuesCount - openPulls, 0)

        let ciDetails: CIStatusDetails?
        switch await ciResult {
        case let .success(value):
            ciDetails = value
            if shouldFetchCI {
                cache.ciDetails = value
                cache.ciFetchedAt = now
                didUpdateCache = true
            }
        case let .failure(error):
            accumulator.absorb(error)
            ciDetails = cache.ciDetails
        }
        let ci = ciDetails?.status ?? .unknown
        let ciRunCount = ciDetails?.runCount

        let activity: ActivityEvent?
        let activityEvents: [ActivityEvent]
        switch await activityResult {
        case let .success(snapshot):
            activity = snapshot.latest ?? snapshot.events.first
            activityEvents = snapshot.events
            if shouldFetchActivity {
                cache.latestActivity = activity
                cache.activityEvents = snapshot.events
                cache.activityFetchedAt = now
                didUpdateCache = true
            }
        case let .failure(error):
            accumulator.absorb(error)
            activity = cache.latestActivity
            activityEvents = cache.activityEvents ?? []
        }

        let traffic: TrafficStats?
        switch await trafficResult {
        case let .success(value):
            traffic = value
            if shouldFetchTraffic {
                cache.traffic = value
                cache.trafficFetchedAt = now
                didUpdateCache = true
            }
        case let .failure(error):
            accumulator.absorb(error)
            traffic = cache.traffic
        }

        let heatmap: [HeatmapCell]
        switch await heatmapResult {
        case let .success(value):
            heatmap = value
            if shouldFetchHeatmap {
                cache.heatmap = value
                cache.heatmapFetchedAt = now
                didUpdateCache = true
            }
        case let .failure(error):
            accumulator.absorb(error)
            heatmap = cache.heatmap ?? []
        }

        let releaseREST: Release?
        switch await releaseResult {
        case let .success(value):
            releaseREST = value
            if shouldFetchRelease {
                cache.latestRelease = value
                cache.releaseFetchedAt = now
                didUpdateCache = true
            }
        case let .failure(error):
            accumulator.absorb(error)
            releaseREST = cache.latestRelease
        }

        let finalIssues = issues
        let finalPulls = openPulls
        let finalRelease = releaseREST
        let finalActivity: ActivityEvent? = activity
        let finalActivityEvents = activityEvents

        let finalCacheState = self.repoDetailCachePolicy.state(for: cache, now: now)
        if didUpdateCache {
            self.repoDetailStore.save(cache, apiHost: self.apiHost, owner: owner, name: name)
        }

        return Repository(
            id: "\(details.id)",
            name: details.name,
            owner: details.owner.login,
            isFork: details.fork,
            isArchived: details.archived,
            sortOrder: nil,
            error: accumulator.message,
            rateLimitedUntil: accumulator.rateLimit,
            ciStatus: ci,
            ciRunCount: ciRunCount,
            openIssues: finalIssues,
            openPulls: finalPulls,
            stars: details.stargazersCount,
            forks: details.forksCount,
            pushedAt: details.pushedAt,
            latestRelease: finalRelease,
            latestActivity: finalActivity,
            activityEvents: finalActivityEvents,
            traffic: traffic,
            heatmap: heatmap,
            detailCacheState: finalCacheState
        )
    }

    private func activityRepository(from item: RepoItem) async throws -> Repository {
        var accumulator = RepoErrorAccumulator()
        let owner = item.owner.login
        let name = item.name

        async let openPullsResult: Result<Int, Error> = self.capture {
            try await self.openPullRequestCount(owner: owner, name: name)
        }
        async let activityResult: Result<ActivitySnapshot, Error> = self.capture {
            try await self.recentActivity(owner: owner, name: name, limit: 10)
        }

        let openPulls = await self.value(from: openPullsResult, into: &accumulator) ?? 0
        let issues = max(item.openIssuesCount - openPulls, 0)
        let snapshot = await self.value(from: activityResult, into: &accumulator)
        let activity: ActivityEvent? = snapshot?.latest ?? snapshot?.events.first
        let activityEvents = snapshot?.events ?? []

        return Repository(
            id: item.id.description,
            name: item.name,
            owner: owner,
            isFork: item.fork,
            isArchived: item.archived,
            sortOrder: nil,
            error: accumulator.message,
            rateLimitedUntil: accumulator.rateLimit,
            ciStatus: .unknown,
            ciRunCount: nil,
            openIssues: issues,
            openPulls: openPulls,
            stars: item.stargazersCount,
            forks: item.forksCount,
            pushedAt: item.pushedAt,
            latestRelease: nil,
            latestActivity: activity,
            activityEvents: activityEvents,
            traffic: nil,
            heatmap: []
        )
    }

    public func currentUser() async throws -> UserIdentity {
        let token = try await validAccessToken()
        let url = self.apiHost.appending(path: "/user")
        let (data, _) = try await authorizedGet(url: url, token: token)
        let user = try jsonDecoder.decode(CurrentUser.self, from: data)
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        let rawHost = url.host ?? "github.com"
        components.host = rawHost == "api.github.com" ? "github.com" : rawHost
        let hostURL = components.url ?? URL(string: "https://github.com")!
        return UserIdentity(username: user.login, host: hostURL)
    }

    public func searchRepositories(matching query: String) async throws -> [Repository] {
        let token = try await validAccessToken()
        var components = URLComponents(
            url: apiHost.appending(path: "/search/repositories"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "per_page", value: "5")]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        let decoded = try jsonDecoder.decode(SearchResponse.self, from: data)
        return decoded.items.map { item in
            Repository(
                id: item.id.description,
                name: item.name,
                owner: item.owner.login,
                isFork: item.fork,
                isArchived: item.archived,
                sortOrder: nil,
                error: nil,
                rateLimitedUntil: nil,
                ciStatus: .unknown,
                ciRunCount: nil,
                openIssues: item.openIssuesCount,
                openPulls: 0,
                stars: item.stargazersCount,
                forks: item.forksCount,
                pushedAt: item.pushedAt,
                latestRelease: nil,
                latestActivity: nil,
                traffic: nil,
                heatmap: []
            )
        }
    }

    public func clearCache() async {
        await self.etagCache.clear()
        await self.backoff.clear()
        self.lastRateLimitReset = nil
        self.lastRateLimitError = nil
        self.prefetchedRepos = []
        self.prefetchedReposExpiry = nil
        self.repoDetailStore.clear()
    }

    public func diagnostics() async -> DiagnosticsSummary {
        let etagCount = await self.etagCache.count()
        let backoffCount = await self.backoff.count()
        return await DiagnosticsSummary(
            apiHost: self.apiHost,
            rateLimitReset: self.lastRateLimitReset,
            lastRateLimitError: self.lastRateLimitError,
            etagEntries: etagCount,
            backoffEntries: backoffCount,
            restRateLimit: self.latestRestRateLimit,
            graphQLRateLimit: self.graphQL.rateLimitSnapshot()
        )
    }

    /// Recent repositories for the authenticated user, sorted by activity.
    public func recentRepositories(limit: Int = 8) async throws -> [Repository] {
        let items = try await self.userReposSorted(limit: limit)
        return items.map { item in
            Repository(
                id: item.id.description,
                name: item.name,
                owner: item.owner.login,
                isFork: item.fork,
                isArchived: item.archived,
                sortOrder: nil,
                error: nil,
                rateLimitedUntil: nil,
                ciStatus: .unknown,
                ciRunCount: nil,
                openIssues: item.openIssuesCount,
                openPulls: 0,
                stars: item.stargazersCount,
                forks: item.forksCount,
                pushedAt: item.pushedAt,
                latestRelease: nil,
                latestActivity: nil,
                traffic: nil,
                heatmap: []
            )
        }
    }

    /// Contribution heatmap for a user (year view), used to render the header without fetching remote images.
    public func userContributionHeatmap(login: String) async throws -> [HeatmapCell] {
        try await self.graphQL.userContributionHeatmap(login: login)
    }

    // MARK: - Internal REST helpers

    private func userReposSorted(limit: Int) async throws -> [RepoItem] {
        let token = try await validAccessToken()
        var components = URLComponents(url: apiHost.appending(path: "/user/repos"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "per_page", value: "\(limit)"),
            URLQueryItem(name: "sort", value: "pushed"),
            URLQueryItem(name: "direction", value: "desc")
        ]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        return try self.jsonDecoder.decode([RepoItem].self, from: data)
    }

    /// Prefetch up to `RepoCacheConstants.maxRepositoriesToPrefetch` repos once per hour for fast autocomplete.
    public func prefetchedRepositories(
        max: Int = RepoCacheConstants.maxRepositoriesToPrefetch
    ) async throws -> [Repository] {
        let now = Date()
        if let expires = self.prefetchedReposExpiry, expires > now, !self.prefetchedRepos.isEmpty {
            return Array(self.prefetchedRepos.prefix(max))
        }

        let items = try await self.userReposPaginated(limit: max)
        let repos = items.map { item in
            Repository(
                id: item.id.description,
                name: item.name,
                owner: item.owner.login,
                isFork: item.fork,
                isArchived: item.archived,
                sortOrder: nil,
                error: nil,
                rateLimitedUntil: nil,
                ciStatus: .unknown,
                ciRunCount: nil,
                openIssues: item.openIssuesCount,
                openPulls: 0,
                stars: item.stargazersCount,
                forks: item.forksCount,
                pushedAt: item.pushedAt,
                latestRelease: nil,
                latestActivity: nil,
                traffic: nil,
                heatmap: []
            )
        }
        self.prefetchedRepos = repos
        self.prefetchedReposExpiry = now.addingTimeInterval(RepoCacheConstants.cacheTTL)
        return repos
    }

    /// Pulls paginated `/user/repos` in 100-item pages until the limit is reached or GitHub runs out.
    private func userReposPaginated(limit: Int?) async throws -> [RepoItem] {
        let pageSize = 100 // GitHub maximum.
        var collected: [RepoItem] = []
        var page = 1

        while true {
            // Each page is a separate request; stop early if GitHub returns a short page.
            let token = try await validAccessToken()
            var components = URLComponents(url: apiHost.appending(path: "/user/repos"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "per_page", value: "\(pageSize)"),
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "sort", value: "pushed"),
                URLQueryItem(name: "direction", value: "desc")
            ]
            let (data, _) = try await authorizedGet(url: components.url!, token: token)
            let items = try self.jsonDecoder.decode([RepoItem].self, from: data)
            collected.append(contentsOf: items)

            if let limit, collected.count >= limit {
                break
            }
            if items.count < pageSize {
                break // GitHub returned a short page.
            }
            page += 1
        }

        if let limit {
            return Array(collected.prefix(limit))
        }
        return collected
    }

    private func allowedOwnerLogins() async throws -> Set<String> {
        let user = try await self.currentUser()
        var allowed = Set<String>()
        allowed.insert(user.username.lowercased())
        do {
            let orgs = try await self.ownedOrgLogins()
            for org in orgs {
                allowed.insert(org.lowercased())
            }
        } catch {
            await self.diag.message("Failed to fetch org memberships; filtering to user only.")
        }
        return allowed
    }

    private func ownedOrgLogins() async throws -> [String] {
        let pageSize = 100
        var collected: [OrgMembership] = []
        var page = 1

        while true {
            let token = try await validAccessToken()
            var components = URLComponents(
                url: apiHost.appending(path: "/user/memberships/orgs"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [
                URLQueryItem(name: "per_page", value: "\(pageSize)"),
                URLQueryItem(name: "page", value: "\(page)")
            ]
            let (data, _) = try await authorizedGet(url: components.url!, token: token)
            let items = try jsonDecoder.decode([OrgMembership].self, from: data)
            collected.append(contentsOf: items)

            if items.count < pageSize {
                break
            }
            page += 1
        }

        return collected
            .filter { ($0.state ?? "active") == "active" }
            .filter { $0.role == "admin" }
            .map(\.organization.login)
    }

    private func repoDetails(owner: String, name: String) async throws -> RepoItem {
        let token = try await validAccessToken()
        let url = self.apiHost.appending(path: "/repos/\(owner)/\(name)")
        let (data, _) = try await authorizedGet(url: url, token: token)
        return try self.jsonDecoder.decode(RepoItem.self, from: data)
    }

    private func ciStatus(owner: String, name: String) async throws -> CIStatusDetails {
        let token = try await validAccessToken()
        var components = URLComponents(
            url: apiHost.appending(path: "/repos/\(owner)/\(name)/actions/runs"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "per_page", value: "1"),
            URLQueryItem(name: "branch", value: "main")
        ]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        let runs = try jsonDecoder.decode(ActionsRunsResponse.self, from: data)
        guard let run = runs.workflowRuns.first else { return CIStatusDetails(status: .unknown, runCount: runs.totalCount) }
        let status: CIStatus = switch run.conclusion ?? run.status {
        case "success": .passing
        case "failure", "cancelled", "timed_out": .failing
        case "in_progress", "queued", "waiting": .pending
        default: .unknown
        }
        return CIStatusDetails(status: status, runCount: runs.totalCount)
    }

    private struct ActivitySnapshot: Sendable {
        let events: [ActivityEvent]
        let latest: ActivityEvent?
    }

    private func recentActivity(owner: String, name: String, limit: Int) async throws -> ActivitySnapshot {
        let token = try await validAccessToken()
        var components = URLComponents(
            url: self.apiHost.appending(path: "/repos/\(owner)/\(name)/events"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "per_page", value: "30")]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        let events = try jsonDecoder.decode([RepoEvent].self, from: data)
        let mapped = events.map { event in
            (event: event, activity: event.activityEvent(owner: owner, name: name))
        }
        let limited = Array(mapped.prefix(max(limit, 0)))
        let preferred = limited.first(where: { $0.event.hasRichPayload })?.activity
        return ActivitySnapshot(
            events: limited.map(\.activity),
            latest: preferred ?? limited.first?.activity
        )
    }

    private func trafficStats(owner: String, name: String) async throws -> TrafficStats? {
        do {
            let token = try await validAccessToken()
            let viewsURL = self.apiHost.appending(path: "/repos/\(owner)/\(name)/traffic/views")
            let clonesURL = self.apiHost.appending(path: "/repos/\(owner)/\(name)/traffic/clones")
            async let viewsPair = self.authorizedGet(url: viewsURL, token: token)
            async let clonesPair = self.authorizedGet(url: clonesURL, token: token)
            let views = try await jsonDecoder.decode(TrafficResponse.self, from: viewsPair.0)
            let clones = try await jsonDecoder.decode(TrafficResponse.self, from: clonesPair.0)
            return TrafficStats(uniqueVisitors: views.uniques, uniqueCloners: clones.uniques)
        } catch let error as GitHubAPIError {
            if case let .badStatus(code, _) = error, code == 403 {
                await self.diag.message("Traffic endpoints forbidden for \(owner)/\(name); skipping")
                return nil
            }
            throw error
        }
    }

    private func commitHeatmap(owner: String, name: String) async throws -> [HeatmapCell] {
        do {
            let token = try await validAccessToken()
            let (data, _) = try await authorizedGet(
                url: apiHost.appending(path: "/repos/\(owner)/\(name)/stats/commit_activity"),
                token: token
            )
            let weeks = try jsonDecoder.decode([CommitActivityWeek].self, from: data)
            return weeks.flatMap { week in
                zip(0 ..< 7, week.days).map { offset, count in
                    let date = Date(timeIntervalSince1970: TimeInterval(week.weekStart + offset * 86400))
                    return HeatmapCell(date: date, count: count)
                }
            }
        } catch let error as GitHubAPIError {
            if case let .badStatus(code, _) = error, code == 403 {
                await self.diag.message("Commit activity forbidden for \(owner)/\(name); skipping heatmap")
                return []
            }
            throw error
        }
    }

    private func openPullRequestCount(owner: String, name: String) async throws -> Int {
        let token = try await validAccessToken()
        var components = URLComponents(
            url: apiHost.appending(path: "/repos/\(owner)/\(name)/pulls"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "state", value: "open"),
            URLQueryItem(name: "per_page", value: "1"),
            URLQueryItem(name: "page", value: "1")
        ]
        let (data, response) = try await authorizedGet(url: components.url!, token: token)
        let pulls = try jsonDecoder.decode([PullRequestListItem].self, from: data)

        if let link = response.value(forHTTPHeaderField: "Link"), let last = Self.lastPage(from: link) {
            return last
        }

        return pulls.count
    }

    // MARK: - Recent PRs & issues (repo submenus)

    public func recentPullRequests(owner: String, name: String, limit: Int = 20) async throws -> [RepoPullRequestSummary] {
        let token = try await validAccessToken()
        let limit = max(1, min(limit, 100))
        var components = URLComponents(
            url: apiHost.appending(path: "/repos/\(owner)/\(name)/pulls"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "state", value: "open"),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "direction", value: "desc"),
            URLQueryItem(name: "per_page", value: "\(limit)")
        ]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        return try Self.decodeRecentPullRequests(from: data)
    }

    public func recentIssues(owner: String, name: String, limit: Int = 20) async throws -> [RepoIssueSummary] {
        let token = try await validAccessToken()
        let limit = max(1, min(limit, 100))
        var components = URLComponents(
            url: apiHost.appending(path: "/repos/\(owner)/\(name)/issues"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "state", value: "open"),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "direction", value: "desc"),
            URLQueryItem(name: "per_page", value: "\(limit)")
        ]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        return try Self.decodeRecentIssues(from: data)
    }

    public func recentReleases(owner: String, name: String, limit: Int = 20) async throws -> [RepoReleaseSummary] {
        let token = try await validAccessToken()
        let limit = max(1, min(limit, 100))
        var components = URLComponents(
            url: apiHost.appending(path: "/repos/\(owner)/\(name)/releases"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "per_page", value: "\(limit)")]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        return try Self.decodeRecentReleases(from: data)
    }

    /// Most recent release (including prereleases) ordered by creation date; skips drafts.
    /// Returns `nil` if the repository has no releases.
    private func latestReleaseAny(owner: String, name: String) async throws -> Release? {
        let token = try await validAccessToken()
        var components = URLComponents(
            url: apiHost.appending(path: "/repos/\(owner)/\(name)/releases"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "per_page", value: "20")]
        let (data, response) = try await authorizedGet(url: components.url!, token: token, allowedStatuses: [200, 304, 404])
        guard response.statusCode != 404 else { throw URLError(.fileDoesNotExist) }
        let releases = try jsonDecoder.decode([ReleaseResponse].self, from: data)
        return Self.latestRelease(from: releases)
    }

    static func decodeRecentPullRequests(from data: Data) throws -> [RepoPullRequestSummary] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let responses = try decoder.decode([PullRequestRecentResponse].self, from: data)
        return responses.map {
            RepoPullRequestSummary(
                number: $0.number,
                title: $0.title,
                url: $0.htmlUrl,
                updatedAt: $0.updatedAt,
                authorLogin: $0.user?.login,
                authorAvatarURL: $0.user?.avatarUrl,
                isDraft: $0.draft ?? false,
                commentCount: $0.comments ?? 0,
                reviewCommentCount: $0.reviewComments ?? 0,
                labels: ($0.labels ?? []).map { RepoIssueLabel(name: $0.name, colorHex: $0.color) },
                headRefName: $0.head?.refName,
                baseRefName: $0.base?.refName
            )
        }
    }

    static func decodeRecentIssues(from data: Data) throws -> [RepoIssueSummary] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let responses = try decoder.decode([IssueRecentResponse].self, from: data)
        return responses
            .filter { $0.pullRequest == nil }
            .map {
                RepoIssueSummary(
                    number: $0.number,
                    title: $0.title,
                    url: $0.htmlUrl,
                    updatedAt: $0.updatedAt,
                    authorLogin: $0.user?.login,
                    authorAvatarURL: $0.user?.avatarUrl,
                    commentCount: $0.comments,
                    labels: $0.labels.map { RepoIssueLabel(name: $0.name, colorHex: $0.color) }
                )
            }
    }

    static func decodeRecentReleases(from data: Data) throws -> [RepoReleaseSummary] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let responses = try decoder.decode([ReleaseRecentResponse].self, from: data)
        return responses
            .filter { $0.draft != true }
            .map {
                let title = ($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let published = $0.publishedAt ?? $0.createdAt ?? Date.distantPast
                let assets = $0.assets ?? []
                let downloads = assets.reduce(0) { $0 + ($1.downloadCount ?? 0) }
                return RepoReleaseSummary(
                    name: title.isEmpty ? $0.tagName : title,
                    tag: $0.tagName,
                    url: $0.htmlUrl,
                    publishedAt: published,
                    isPrerelease: $0.prerelease ?? false,
                    authorLogin: $0.author?.login,
                    authorAvatarURL: $0.author?.avatarUrl,
                    assetCount: assets.count,
                    downloadCount: downloads
                )
            }
    }

    private struct PullRequestRecentResponse: Decodable {
        let number: Int
        let title: String
        let htmlUrl: URL
        let updatedAt: Date
        let user: RecentUser?
        let draft: Bool?
        let comments: Int?
        let reviewComments: Int?
        let labels: [IssueLabel]?
        let head: PullRequestRef?
        let base: PullRequestRef?

        enum CodingKeys: String, CodingKey {
            case number, title, user, draft, comments, labels, head, base
            case htmlUrl = "html_url"
            case updatedAt = "updated_at"
            case reviewComments = "review_comments"
        }
    }

    private struct PullRequestRef: Decodable {
        let refName: String

        enum CodingKeys: String, CodingKey {
            case refName = "ref"
        }
    }

    private struct IssueRecentResponse: Decodable {
        let number: Int
        let title: String
        let htmlUrl: URL
        let updatedAt: Date
        let comments: Int
        let user: RecentUser?
        let labels: [IssueLabel]
        let pullRequest: PullRequestMarker?

        enum CodingKeys: String, CodingKey {
            case number, title, user, comments, labels
            case htmlUrl = "html_url"
            case updatedAt = "updated_at"
            case pullRequest = "pull_request"
        }
    }

    private struct PullRequestMarker: Decodable {}

    private struct RecentUser: Decodable {
        let login: String
        let avatarUrl: URL?

        enum CodingKeys: String, CodingKey {
            case login
            case avatarUrl = "avatar_url"
        }
    }

    private struct ReleaseRecentResponse: Decodable {
        let name: String?
        let tagName: String
        let publishedAt: Date?
        let createdAt: Date?
        let draft: Bool?
        let prerelease: Bool?
        let htmlUrl: URL
        let author: RecentUser?
        let assets: [ReleaseAsset]?

        enum CodingKeys: String, CodingKey {
            case name, draft, prerelease, author, assets
            case tagName = "tag_name"
            case publishedAt = "published_at"
            case createdAt = "created_at"
            case htmlUrl = "html_url"
        }

        struct ReleaseAsset: Decodable {
            let downloadCount: Int?

            enum CodingKeys: String, CodingKey {
                case downloadCount = "download_count"
            }
        }
    }

    private struct IssueLabel: Decodable {
        let name: String
        let color: String
    }

    /// Pick the newest non-draft release, preferring publishedAt over createdAt.
    static func latestRelease(from responses: [ReleaseResponse]) -> Release? {
        let candidates = responses
            .filter { $0.draft != true }
            .sorted {
                let lhsDate = $0.publishedAt ?? $0.createdAt ?? .distantPast
                let rhsDate = $1.publishedAt ?? $1.createdAt ?? .distantPast
                return lhsDate > rhsDate
            }
        guard let rel = candidates.first else { return nil }
        let published = rel.publishedAt ?? rel.createdAt ?? Date.distantPast
        return Release(name: rel.name ?? rel.tagName, tag: rel.tagName, publishedAt: published, url: rel.htmlUrl)
    }

    private func authorizedGet(
        url: URL,
        token: String,
        allowedStatuses: Set<Int> = [200, 304]
    ) async throws -> (Data, HTTPURLResponse) {
        let startedAt = Date()
        await self.diag.message("GET \(url.absoluteString)")
        if await self.etagCache.isRateLimited(), let until = await etagCache.rateLimitUntil() {
            await self.diag.message("Blocked by local rateLimit until \(until)")
            throw GitHubAPIError.rateLimited(
                until: until,
                message: "GitHub rate limit hit; resets \(RelativeFormatter.string(from: until, relativeTo: Date()))."
            )
        }
        if let cooldown = await backoff.cooldown(for: url) {
            await self.diag.message("Cooldown active for \(url.absoluteString) until \(cooldown)")
            throw GitHubAPIError.serviceUnavailable(
                retryAfter: cooldown,
                message: "Cooling down until \(RelativeFormatter.string(from: cooldown, relativeTo: Date()))."
            )
        }

        var request = URLRequest(url: url)
        // GitHub requires "Bearer" here for OAuth access tokens; "token" is for classic tokens.
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let cached = await etagCache.cached(for: url) {
            request.addValue(cached.etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, responseAny) = try await URLSession.shared.data(for: request)
        guard let response = responseAny as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        await self.logResponse("GET", url: url, response: response, startedAt: startedAt)

        let status = response.statusCode
        if status == 304, let cached = await etagCache.cached(for: url) {
            await self.diag.message("304 Not Modified for \(url.lastPathComponent); using cached")
            return (cached.data, response)
        }

        if status == 202 {
            let retryAfter = self.retryAfterDate(from: response) ?? Date().addingTimeInterval(90)
            await self.backoff.setCooldown(url: response.url ?? url, until: retryAfter)
            let retryText = RelativeFormatter.string(from: retryAfter, relativeTo: Date())
            let message = "GitHub is generating repository stats; some numbers may be stale. RepoBar will retry \(retryText)."
            await self.diag.message("202 for \(url.lastPathComponent); cooldown until \(retryAfter)")
            throw GitHubAPIError.serviceUnavailable(
                retryAfter: retryAfter,
                message: message
            )
        }

        if status == 403 || status == 429 {
            let remainingHeader = response.value(forHTTPHeaderField: "X-RateLimit-Remaining")
            let remaining = Int(remainingHeader ?? "")

            // If we still have quota, this 403 is likely permissions/abuse detection; surface it as a normal error.
            if let remaining, remaining > 0 {
                await self.diag.message("403 with remaining=\(remaining) on \(url.lastPathComponent); treating as bad status")
                throw GitHubAPIError.badStatus(code: status, message: HTTPURLResponse.localizedString(forStatusCode: status))
            }

            let resetDate = self.rateLimitDate(from: response) ?? Date().addingTimeInterval(60)
            self.lastRateLimitReset = resetDate
            await self.etagCache.setRateLimitReset(date: resetDate)
            await self.backoff.setCooldown(url: response.url ?? url, until: resetDate)
            self.lastRateLimitError = "GitHub rate limit hit; resets " +
                "\(RelativeFormatter.string(from: resetDate, relativeTo: Date()))."
            await self.diag.message("Rate limited on \(url.lastPathComponent); resets \(resetDate)")
            throw GitHubAPIError.rateLimited(until: resetDate, message: self.lastRateLimitError ?? "Rate limited.")
        }

        guard allowedStatuses.contains(status) else {
            await self.diag.message("Unexpected status \(status) for \(url.lastPathComponent)")
            throw GitHubAPIError.badStatus(
                code: status,
                message: HTTPURLResponse.localizedString(forStatusCode: status)
            )
        }

        if let etag = response.value(forHTTPHeaderField: "ETag") {
            await self.etagCache.save(url: url, etag: etag, data: data)
            await self.diag.message("Cached ETag for \(url.lastPathComponent)")
        }
        if let snapshot = RateLimitSnapshot.from(response: response) {
            self.latestRestRateLimit = snapshot
        }
        self.detectRateLimit(from: response)
        return (data, response)
    }

    private func logResponse(
        _ method: String,
        url: URL,
        response: HTTPURLResponse,
        startedAt: Date
    ) async {
        let durationMs = Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
        let snapshot = RateLimitSnapshot.from(response: response)
        if let snapshot { self.latestRestRateLimit = snapshot }

        let remaining = snapshot?.remaining.map(String.init) ?? response.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? "?"
        let limit = snapshot?.limit.map(String.init) ?? response.value(forHTTPHeaderField: "X-RateLimit-Limit") ?? "?"
        let used = snapshot?.used.map(String.init) ?? response.value(forHTTPHeaderField: "X-RateLimit-Used") ?? "?"
        let resetDate = snapshot?.reset ?? self.rateLimitDate(from: response)
        let resetText = resetDate.map { RelativeFormatter.string(from: $0, relativeTo: Date()) } ?? "n/a"
        let resource = snapshot?.resource ?? response.value(forHTTPHeaderField: "X-RateLimit-Resource") ?? "rest"

        await self.diag.message(
            "HTTP \(method) \(url.path) status=\(response.statusCode) res=\(resource) lim=\(limit) rem=\(remaining) used=\(used) reset=\(resetText) dur=\(durationMs)ms"
        )
    }

    private func rateLimitDate(from response: HTTPURLResponse) -> Date? {
        guard let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
              let epoch = TimeInterval(reset) else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }

    private func retryAfterDate(from response: HTTPURLResponse) -> Date? {
        if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"), let seconds = TimeInterval(retryAfter) {
            return Date().addingTimeInterval(seconds)
        }
        return nil
    }

    private func detectRateLimit(from response: HTTPURLResponse) {
        guard
            let remainingText = response.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
            let remaining = Int(remainingText)
        else { return }

        if remaining <= 0 {
            self.lastRateLimitReset = self.rateLimitDate(from: response)
        } else if let reset = self.lastRateLimitReset, reset <= Date() {
            self.lastRateLimitReset = nil
            self.lastRateLimitError = nil
        }
    }

    private func validAccessToken() async throws -> String {
        if let provider = tokenProvider, let tokens = try await provider() { return tokens.accessToken }
        if let token = try tokenStore.load()?.accessToken { return token }
        throw URLError(.userAuthenticationRequired)
    }

    // MARK: - Small helpers

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

    private static func lastPage(from linkHeader: String) -> Int? {
        // Example: <https://api.github.com/repositories/1300192/pulls?state=open&per_page=1&page=2>; rel="next",
        //          <https://api.github.com/repositories/1300192/pulls?state=open&per_page=1&page=4>; rel="last"
        for part in linkHeader.split(separator: ",") {
            let segments = part.split(separator: ";")
            guard segments.contains(where: { $0.contains("rel=\"last\"") }) else { continue }
            let urlPart = segments[0].trimmingCharacters(in: .whitespaces)
            let trimmed = urlPart.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
            guard let components = URLComponents(string: trimmed),
                  let page = components.queryItems?.first(where: { $0.name == "page" })?.value,
                  let pageNumber = Int(page) else { continue }
            return pageNumber
        }
        return nil
    }
}

private struct InstallationReposResponse: Decodable {
    let totalCount: Int
    let repositories: [RepoItem]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case repositories
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
