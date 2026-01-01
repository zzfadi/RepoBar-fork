import Foundation

struct ActivitySnapshot: Sendable {
    let events: [ActivityEvent]
    let latest: ActivityEvent?
}

struct GitHubRestAPI: Sendable {
    let apiHost: @Sendable () async -> URL
    let tokenProvider: @Sendable () async throws -> String
    let requestRunner: GitHubRequestRunner
    let diag: DiagnosticsLogger

    static func userReposQueryItems() -> [URLQueryItem] {
        [
            URLQueryItem(name: "sort", value: "pushed"),
            URLQueryItem(name: "direction", value: "desc"),
            URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"),
            URLQueryItem(name: "visibility", value: "all")
        ]
    }

    func userReposSorted(limit: Int) async throws -> [RepoItem] {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        var components = URLComponents(url: baseURL.appending(path: "/user/repos"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "per_page", value: "\(limit)")] + Self.userReposQueryItems()
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        return try GitHubDecoding.decode([RepoItem].self, from: data)
    }

    /// Pulls paginated `/user/repos` in 100-item pages until the limit is reached or GitHub runs out.
    func userReposPaginated(limit: Int?) async throws -> [RepoItem] {
        try await self.fetchAllPages(
            path: "/user/repos",
            queryItems: Self.userReposQueryItems(),
            limit: limit,
            decode: { try GitHubDecoding.decode([RepoItem].self, from: $0) }
        )
    }

    func fetchCurrentUser() async throws -> CurrentUser {
        let token = try await tokenProvider()
        let baseURL = await self.apiHost()
        let url = baseURL.appending(path: "/user")
        let (data, _) = try await authorizedGet(url: url, token: token)
        return try GitHubDecoding.decode(CurrentUser.self, from: data)
    }

    func searchRepositories(matching query: String) async throws -> [RepoItem] {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents(
            url: baseURL.appending(path: "/search/repositories"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "q", value: Self.repoSearchQuery(from: trimmed)),
            URLQueryItem(name: "per_page", value: "8")
        ]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        let decoded = try GitHubDecoding.decode(SearchResponse.self, from: data)
        return decoded.items
    }

    private static func repoSearchQuery(from query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "stars:>0" }

        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            let owner = parts.first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = (parts.count > 1 ? String(parts[1]) : "").trimmingCharacters(in: .whitespacesAndNewlines)

            if !owner.isEmpty, !name.isEmpty {
                return "\(name) in:name user:\(owner)"
            }
            if !owner.isEmpty {
                return "user:\(owner)"
            }
        }

        return "\(trimmed) in:name"
    }

    func userEvents(username: String, scope: GlobalActivityScope) async throws -> [RepoEvent] {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        let path = scope == .allActivity
            ? "/users/\(username)/received_events"
            : "/users/\(username)/events"
        var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "per_page", value: "30")]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        return try GitHubDecoding.decode([RepoEvent].self, from: data)
    }

    func repoDetails(owner: String, name: String) async throws -> RepoItem {
        let token = try await tokenProvider()
        let baseURL = await self.apiHost()
        let url = baseURL.appending(path: "/repos/\(owner)/\(name)")
        let (data, _) = try await authorizedGet(url: url, token: token)
        return try GitHubDecoding.decode(RepoItem.self, from: data)
    }

    func ciStatus(owner: String, name: String) async throws -> CIStatusDetails {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/actions/runs"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "per_page", value: "1"),
            URLQueryItem(name: "branch", value: "main")
        ]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        let runs = try GitHubDecoding.decode(ActionsRunsResponse.self, from: data)
        guard let run = runs.workflowRuns.first else { return CIStatusDetails(status: .unknown, runCount: runs.totalCount) }
        let status = GitHubStatusMapper.ciStatus(fromStatus: run.status, conclusion: run.conclusion)
        return CIStatusDetails(status: status, runCount: runs.totalCount)
    }

    func recentActivity(owner: String, name: String, limit: Int) async throws -> ActivitySnapshot {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        let webHost = self.webHostURL(from: baseURL)
        var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/events"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "per_page", value: "30")]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        let events = try GitHubDecoding.decode([RepoEvent].self, from: data)
        let mapped = events.map { event in
            (event: event, activity: event.activityEvent(owner: owner, name: name, webHost: webHost))
        }
        let limited = Array(mapped.prefix(max(limit, 0)))
        let preferred = limited.first(where: { $0.event.hasRichPayload })?.activity
        return ActivitySnapshot(
            events: limited.map(\.activity),
            latest: preferred ?? limited.first?.activity
        )
    }

    private func webHostURL(from apiHost: URL) -> URL {
        var components = URLComponents()
        components.scheme = apiHost.scheme ?? "https"
        let rawHost = apiHost.host ?? "github.com"
        components.host = rawHost == "api.github.com" ? "github.com" : rawHost
        return components.url ?? URL(string: "https://github.com")!
    }

    func trafficStats(owner: String, name: String) async throws -> TrafficStats? {
        do {
            let token = try await tokenProvider()
            let baseURL = await apiHost()
            let viewsURL = baseURL.appending(path: "/repos/\(owner)/\(name)/traffic/views")
            let clonesURL = baseURL.appending(path: "/repos/\(owner)/\(name)/traffic/clones")
            async let viewsPair = self.authorizedGet(url: viewsURL, token: token)
            async let clonesPair = self.authorizedGet(url: clonesURL, token: token)
            let views = try await GitHubDecoding.decode(TrafficResponse.self, from: viewsPair.0)
            let clones = try await GitHubDecoding.decode(TrafficResponse.self, from: clonesPair.0)
            return TrafficStats(uniqueVisitors: views.uniques, uniqueCloners: clones.uniques)
        } catch let error as GitHubAPIError {
            if case let .badStatus(code, _) = error, code == 403 {
                await self.diag.message("Traffic endpoints forbidden for \(owner)/\(name); skipping")
                return nil
            }
            throw error
        }
    }

    func commitHeatmap(owner: String, name: String) async throws -> [HeatmapCell] {
        do {
            let token = try await tokenProvider()
            let baseURL = await apiHost()
            let (data, _) = try await authorizedGet(
                url: baseURL.appending(path: "/repos/\(owner)/\(name)/stats/commit_activity"),
                token: token
            )
            let weeks = try GitHubDecoding.decode([CommitActivityWeek].self, from: data)
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

    func repoContents(owner: String, name: String, path: String? = nil) async throws -> [RepoContentItem] {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let suffix = trimmed.isEmpty ? "" : "/\(trimmed)"
        let url = baseURL.appending(path: "/repos/\(owner)/\(name)/contents\(suffix)")
        let (data, response) = try await authorizedGet(
            url: url,
            token: token,
            allowedStatuses: [200, 304, 404]
        )
        if response.statusCode == 404 {
            return []
        }
        if let list = try? GitHubDecoding.decode([RepoContentItem].self, from: data) {
            return list
        }
        let item = try GitHubDecoding.decode(RepoContentItem.self, from: data)
        return [item]
    }

    func repoFileContents(owner: String, name: String, path: String) async throws -> Data {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = baseURL.appending(path: "/repos/\(owner)/\(name)/contents/\(trimmed)")
        let (data, _) = try await authorizedGet(
            url: url,
            token: token,
            headers: ["Accept": "application/vnd.github.raw"],
            useETag: false
        )
        return data
    }

    func openPullRequestCount(owner: String, name: String) async throws -> Int {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/pulls"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "state", value: "open"),
            URLQueryItem(name: "per_page", value: "1"),
            URLQueryItem(name: "page", value: "1")
        ]
        let (data, response) = try await authorizedGet(url: components.url!, token: token)
        let pulls = try GitHubDecoding.decode([PullRequestListItem].self, from: data)

        if let link = response.value(forHTTPHeaderField: "Link"), let last = GitHubPagination.lastPage(from: link) {
            return last
        }

        return pulls.count
    }

    func commitTotalCount(owner: String, name: String) async throws -> Int? {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/commits"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "per_page", value: "1")]
        let (data, response) = try await authorizedGet(url: components.url!, token: token)
        if let link = response.value(forHTTPHeaderField: "Link"), let last = GitHubPagination.lastPage(from: link) {
            return last
        }
        let items = try GitHubDecoding.decode([CommitRecentResponse].self, from: data)
        return items.count
    }

    func recentPullRequests(owner: String, name: String, limit: Int = 20) async throws -> [RepoPullRequestSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "pulls",
            limit: limit,
            queryItems: [
                URLQueryItem(name: "state", value: "open"),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "direction", value: "desc")
            ],
            decode: GitHubRecentDecoders.decodeRecentPullRequests(from:)
        )
    }

    func recentIssues(owner: String, name: String, limit: Int = 20) async throws -> [RepoIssueSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "issues",
            limit: limit,
            queryItems: [
                URLQueryItem(name: "state", value: "open"),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "direction", value: "desc")
            ],
            decode: GitHubRecentDecoders.decodeRecentIssues(from:)
        )
    }

    func recentReleases(owner: String, name: String, limit: Int = 20) async throws -> [RepoReleaseSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "releases",
            limit: limit,
            decode: GitHubRecentDecoders.decodeRecentReleases(from:)
        )
    }

    func recentWorkflowRuns(owner: String, name: String, limit: Int = 20) async throws -> [RepoWorkflowRunSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "actions/runs",
            limit: limit,
            decode: GitHubRecentDecoders.decodeRecentWorkflowRuns(from:)
        )
    }

    func recentCommits(owner: String, name: String, limit: Int = 20) async throws -> RepoCommitList {
        let token = try await tokenProvider()
        let limit = max(1, min(limit, 100))
        let baseURL = await apiHost()
        var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/commits"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "per_page", value: "\(limit)")]
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        let items = try GitHubRecentDecoders.decodeRecentCommits(from: data)
        let totalCount = try await self.commitTotalCount(owner: owner, name: name)
        return RepoCommitList(items: items, totalCount: totalCount)
    }

    func recentDiscussions(owner: String, name: String, limit: Int = 20) async throws -> [RepoDiscussionSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "discussions",
            limit: limit,
            queryItems: [
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "direction", value: "desc")
            ],
            decode: GitHubRecentDecoders.decodeRecentDiscussions(from:)
        )
    }

    func recentTags(owner: String, name: String, limit: Int = 20) async throws -> [RepoTagSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "tags",
            limit: limit,
            decode: GitHubRecentDecoders.decodeRecentTags(from:)
        )
    }

    func recentBranches(owner: String, name: String, limit: Int = 20) async throws -> [RepoBranchSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "branches",
            limit: limit,
            decode: GitHubRecentDecoders.decodeRecentBranches(from:)
        )
    }

    func topContributors(owner: String, name: String, limit: Int = 20) async throws -> [RepoContributorSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "contributors",
            limit: limit,
            decode: GitHubRecentDecoders.decodeContributors(from:)
        )
    }

    /// Most recent release (including prereleases) ordered by creation date; skips drafts.
    /// Returns `nil` if the repository has no releases.
    func latestReleaseAny(owner: String, name: String) async throws -> Release? {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/releases"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "per_page", value: "20")]
        let (data, response) = try await authorizedGet(url: components.url!, token: token, allowedStatuses: [200, 304, 404])
        guard response.statusCode != 404 else { throw URLError(.fileDoesNotExist) }
        let releases = try GitHubDecoding.decode([ReleaseResponse].self, from: data)
        return GitHubReleasePicker.latestRelease(from: releases)
    }

    private func recentList<T>(
        owner: String,
        name: String,
        path: String,
        limit: Int,
        queryItems: [URLQueryItem] = [],
        decode: (Data) throws -> [T]
    ) async throws -> [T] {
        let token = try await tokenProvider()
        let limit = max(1, min(limit, 100))
        let baseURL = await apiHost()
        var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/\(path)"),
            resolvingAgainstBaseURL: false
        )!
        var items = queryItems.filter { $0.name != "per_page" }
        items.append(URLQueryItem(name: "per_page", value: "\(limit)"))
        components.queryItems = items
        let (data, _) = try await authorizedGet(url: components.url!, token: token)
        return try decode(data)
    }

    private func fetchAllPages<T>(
        path: String,
        queryItems: [URLQueryItem],
        limit: Int?,
        decode: @escaping (Data) throws -> [T]
    ) async throws -> [T] {
        let pageSize = 100 // GitHub maximum.
        var collected: [T] = []
        var page = 1

        while true {
            // Each page is a separate request; stop early if GitHub returns a short page.
            let token = try await tokenProvider()
            let baseURL = await apiHost()
            var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
            var items = queryItems.filter { $0.name != "per_page" && $0.name != "page" }
            items.append(URLQueryItem(name: "per_page", value: "\(pageSize)"))
            items.append(URLQueryItem(name: "page", value: "\(page)"))
            components.queryItems = items
            let (data, _) = try await authorizedGet(url: components.url!, token: token)
            let itemsPage = try decode(data)
            collected.append(contentsOf: itemsPage)

            if let limit, collected.count >= limit {
                break
            }
            if itemsPage.count < pageSize {
                break // GitHub returned a short page.
            }
            page += 1
        }

        if let limit {
            return Array(collected.prefix(limit))
        }
        return collected
    }

    private func authorizedGet(
        url: URL,
        token: String,
        allowedStatuses: Set<Int> = [200, 304],
        headers: [String: String] = [:],
        useETag: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        try await self.requestRunner.get(
            url: url,
            token: token,
            allowedStatuses: allowedStatuses,
            headers: headers,
            useETag: useETag
        )
    }
}

private struct CommitRecentResponse: Decodable {
    let sha: String
}

private struct InstallationReposResponse: Decodable {
    let totalCount: Int
    let repositories: [RepoItem]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case repositories
    }
}
