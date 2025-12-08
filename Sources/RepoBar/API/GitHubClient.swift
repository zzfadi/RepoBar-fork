import Foundation
import OSLog

/// Lightweight GitHub client using REST plus a minimal GraphQL enrichment step.
actor GitHubClient {
    var apiHost: URL = .init(string: "https://api.github.com")!
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

    // MARK: - Config

    func setAPIHost(_ host: URL) {
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

    func setTokenProvider(_ provider: @Sendable @escaping () async throws -> OAuthTokens?) {
        self.tokenProvider = provider
        Task {
            await self.graphQL.setTokenProvider {
                guard let tokens = try await provider() else { throw URLError(.userAuthenticationRequired) }
                return tokens.accessToken
            }
        }
    }

    func rateLimitReset(now: Date = Date()) -> Date? {
        guard let reset = self.lastRateLimitReset, reset > now else {
            self.lastRateLimitReset = nil
            self.lastRateLimitError = nil
            return nil
        }
        return reset
    }

    func rateLimitMessage(now: Date = Date()) -> String? {
        guard self.rateLimitReset(now: now) != nil else { return nil }
        return self.lastRateLimitError
    }

    // MARK: - High level fetchers

    func defaultRepositories(limit: Int, for _: String) async throws -> [Repository] {
        let repos = try await userReposSorted(limit: max(limit, 10))
        return try await self.expandRepoItems(Array(repos.prefix(limit)))
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

    func fullRepository(owner: String, name: String) async throws -> Repository {
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
                openIssues: 0,
                openPulls: 0,
                latestRelease: nil,
                latestActivity: nil,
                traffic: nil,
                heatmap: []
            )
        }

        // Run all expensive lookups in parallel; individual failures are folded into the accumulator.
        async let openPullsResult: Result<Int, Error> = self.capture {
            try await self.openPullRequestCount(owner: owner, name: name)
        }
        async let ciResult: Result<CIStatusDetails, Error> = self.capture { try await self.ciStatus(owner: owner, name: name) }
        async let activityResult: Result<ActivityEvent?, Error> = self.capture { try await self.latestActivity(
            owner: owner,
            name: name
        ) }
        async let trafficResult: Result<TrafficStats, Error> = self.capture { try await self.trafficStats(
            owner: owner,
            name: name
        ) }
        async let heatmapResult: Result<[HeatmapCell], Error> = self.capture { try await self.commitHeatmap(
            owner: owner,
            name: name
        ) }
        let openPulls = await self.value(from: openPullsResult, into: &accumulator) ?? 0
        let issues = max(details.openIssuesCount - openPulls, 0)
        let releaseREST: Release? = try? await self.latestReleaseAny(owner: owner, name: name)
        let ciDetails = await self.value(from: ciResult, into: &accumulator)
        let ci = ciDetails?.status ?? .unknown
        let ciRunCount = ciDetails?.runCount
        let activity: ActivityEvent? = await self.value(from: activityResult, into: &accumulator) ?? nil // swiftlint:disable:this redundant_nil_coalescing
        let traffic = await self.value(from: trafficResult, into: &accumulator)
        let heatmap = await self.value(from: heatmapResult, into: &accumulator) ?? []

        let finalIssues = issues
        let finalPulls = openPulls
        let finalRelease = releaseREST
        let finalActivity: ActivityEvent? = activity

        return Repository(
            id: "\(details.id)",
            name: details.name,
            owner: details.owner.login,
            sortOrder: nil,
            error: accumulator.message,
            rateLimitedUntil: accumulator.rateLimit,
            ciStatus: ci,
            ciRunCount: ciRunCount,
            openIssues: finalIssues,
            openPulls: finalPulls,
            latestRelease: finalRelease,
            latestActivity: finalActivity,
            traffic: traffic,
            heatmap: heatmap
        )
    }

    func currentUser() async throws -> UserIdentity {
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

    func searchRepositories(matching query: String) async throws -> [Repository] {
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
                sortOrder: nil,
                error: nil,
                rateLimitedUntil: nil,
                ciStatus: .unknown,
                ciRunCount: nil,
                openIssues: item.openIssuesCount,
                openPulls: 0,
                latestRelease: nil,
                latestActivity: nil,
                traffic: nil,
                heatmap: []
            )
        }
    }

    func clearCache() async {
        await self.etagCache.clear()
        await self.backoff.clear()
        self.lastRateLimitReset = nil
        self.lastRateLimitError = nil
        self.prefetchedRepos = []
        self.prefetchedReposExpiry = nil
    }

    func diagnostics() async -> DiagnosticsSummary {
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
    func recentRepositories(limit: Int = 8) async throws -> [Repository] {
        let items = try await self.userReposSorted(limit: limit)
        return items.map { item in
            Repository(
                id: item.id.description,
                name: item.name,
                owner: item.owner.login,
                sortOrder: nil,
                error: nil,
                rateLimitedUntil: nil,
                ciStatus: .unknown,
                ciRunCount: nil,
                openIssues: item.openIssuesCount,
                openPulls: 0,
                latestRelease: nil,
                latestActivity: nil,
                traffic: nil,
                heatmap: []
            )
        }
    }

    /// Contribution heatmap for a user (year view), used to render the header without fetching remote images.
    func userContributionHeatmap(login: String) async throws -> [HeatmapCell] {
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
    func prefetchedRepositories(
        max: Int = RepoCacheConstants.maxRepositoriesToPrefetch
    ) async throws -> [Repository] {
        let now = Date()
        if let expires = self.prefetchedReposExpiry, expires > now, !self.prefetchedRepos.isEmpty {
            return Array(self.prefetchedRepos.prefix(max))
        }

        let repos = try await self.userReposPaginated(limit: max)
        self.prefetchedRepos = repos
        self.prefetchedReposExpiry = now.addingTimeInterval(RepoCacheConstants.cacheTTL)
        return repos
    }

    /// Pulls paginated `/user/repos` in 100-item pages until the limit is reached or GitHub runs out.
    private func userReposPaginated(limit: Int) async throws -> [Repository] {
        let pageSize = 100 // GitHub maximum.
        let totalPages = Int(ceil(Double(limit) / Double(pageSize)))
        var collected: [RepoItem] = []

        for page in 1 ... totalPages {
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

            if collected.count >= limit || items.count < pageSize {
                break // Hit requested limit or GitHub returned a short page.
            }
        }

        let trimmed = Array(collected.prefix(limit))
        return trimmed.map { item in
            Repository(
                id: item.id.description,
                name: item.name,
                owner: item.owner.login,
                sortOrder: nil,
                error: nil,
                rateLimitedUntil: nil,
                ciStatus: .unknown,
                openIssues: item.openIssuesCount,
                openPulls: 0,
                latestRelease: nil,
                latestActivity: nil,
                traffic: nil,
                heatmap: []
            )
        }
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

    private func latestActivity(owner: String, name: String) async throws -> ActivityEvent? {
        let token = try await validAccessToken()
        var components = URLComponents(
            url: self.apiHost.appending(path: "/repos/\(owner)/\(name)/events"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "per_page", value: "1")]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        let events = try jsonDecoder.decode([RepoEvent].self, from: data)
        guard let event = events.first else { return nil }

        let preview = event.payload.comment?.bodyPreview ?? event.type
        let fallbackURL = URL(string: "https://github.com/\(owner)/\(name)")!
        let url = event.payload.comment?.htmlUrl ?? event.payload.issue?.htmlUrl ?? event.payload.pullRequest?.htmlUrl ?? fallbackURL
        return ActivityEvent(
            title: preview,
            actor: event.actor.login,
            date: event.createdAt,
            url: url
        )
    }

    private func trafficStats(owner: String, name: String) async throws -> TrafficStats {
        let token = try await validAccessToken()
        let viewsURL = self.apiHost.appending(path: "/repos/\(owner)/\(name)/traffic/views")
        let clonesURL = self.apiHost.appending(path: "/repos/\(owner)/\(name)/traffic/clones")
        async let viewsPair = self.authorizedGet(url: viewsURL, token: token)
        async let clonesPair = self.authorizedGet(url: clonesURL, token: token)
        let views = try await jsonDecoder.decode(TrafficResponse.self, from: viewsPair.0)
        let clones = try await jsonDecoder.decode(TrafficResponse.self, from: clonesPair.0)
        return TrafficStats(uniqueVisitors: views.uniques, uniqueCloners: clones.uniques)
    }

    private func commitHeatmap(owner: String, name: String) async throws -> [HeatmapCell] {
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

    /// Most recent release (including prereleases) ordered by creation date; skips drafts.
    private func latestReleaseAny(owner: String, name: String) async throws -> Release {
        let token = try await validAccessToken()
        var components = URLComponents(
            url: apiHost.appending(path: "/repos/\(owner)/\(name)/releases"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "per_page", value: "20")]
        let (data, response) = try await authorizedGet(url: components.url!, token: token, allowedStatuses: [200, 304, 404])
        guard response.statusCode != 404 else { throw URLError(.fileDoesNotExist) }
        let releases = try jsonDecoder.decode([ReleaseResponse].self, from: data)
        guard let rel = Self.latestRelease(from: releases) else { throw URLError(.cannotParseResponse) }
        return rel
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
            let message = "GitHub is preparing stats; retry \(retryText)."
            await self.diag.message("202 for \(url.lastPathComponent); cooldown until \(retryAfter)")
            throw GitHubAPIError.serviceUnavailable(
                retryAfter: retryAfter,
                message: message
            )
        }

        if status == 403 || status == 429 {
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
        if let token = try tokenStore.load()?.accessToken { return token }
        if let provider = tokenProvider, let tokens = try await provider() { return tokens.accessToken }
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

struct DiagnosticsSummary {
    let apiHost: URL
    let rateLimitReset: Date?
    let lastRateLimitError: String?
    let etagEntries: Int
    let backoffEntries: Int
    let restRateLimit: RateLimitSnapshot?
    let graphQLRateLimit: RateLimitSnapshot?

    static let empty = DiagnosticsSummary(
        apiHost: URL(string: "https://api.github.com")!,
        rateLimitReset: nil,
        lastRateLimitError: nil,
        etagEntries: 0,
        backoffEntries: 0,
        restRateLimit: nil,
        graphQLRateLimit: nil
    )
}
