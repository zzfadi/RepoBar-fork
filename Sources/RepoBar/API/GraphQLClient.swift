import Foundation

/// Minimal GraphQL helper (no codegen) to enrich repo data. Uses the same OAuth token as REST.
actor GraphQLClient {
    private var endpoint: URL = .init(string: "https://api.github.com/graphql")!
    private var tokenProvider: (@Sendable () async throws -> String)?
    private var rateLimit: RateLimitSnapshot?
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let diag = DiagnosticsLogger.shared

    func setEndpoint(apiHost: URL) {
        // For GitHub.com apiHost is https://api.github.com
        // For GHE apiHost is https://host/api/v3 -> GraphQL lives at /api/graphql
        var components = URLComponents(url: apiHost, resolvingAgainstBaseURL: false)
        if apiHost.path.contains("/api/v3") {
            components?.path = "/api/graphql"
        } else {
            components?.path = "/graphql"
        }
        self.endpoint = components?.url ?? self.endpoint
    }

    func setTokenProvider(_ provider: @Sendable @escaping () async throws -> String) {
        self.tokenProvider = provider
    }

    func repoSummary(owner: String, name: String) async throws -> RepoSummary {
        let token = try await tokenProvider?() ?? { throw URLError(.userAuthenticationRequired) }()
        await diag.message("GraphQL RepoSummary \(owner)/\(name)")
        let startedAt = Date()

        let body = GraphQLRequest(
            query: """
            query RepoSummary($owner: String!, $name: String!) {
              repository(owner: $owner, name: $name) {
                name
                releases(last: 1, orderBy: {field: CREATED_AT, direction: DESC}) {
                  nodes { name tagName publishedAt url }
                }
                issues(states: OPEN) { totalCount }
                pullRequests(states: OPEN) { totalCount }
              }
            }
            """,
            variables: ["owner": owner, "name": name]
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        await self.logGraphQLResponse(http, label: "RepoSummary", startedAt: startedAt)
        if let snapshot = RateLimitSnapshot.from(response: http) {
            self.rateLimit = snapshot
        }
        guard http.statusCode == 200 else {
            await self.diag.message("GraphQL status \(http.statusCode) for \(owner)/\(name)")
            throw URLError(.badServerResponse)
        }

        let decoded = try decoder.decode(GraphQLResponse<RepoSummaryData>.self, from: data)
        guard let repo = decoded.data.repository else {
            await self.diag.message("GraphQL missing repository for \(owner)/\(name)")
            throw URLError(.cannotParseResponse)
        }

        let release: Release? = repo.releases.nodes?.first.flatMap {
            Release(name: $0.name ?? $0.tagName, tag: $0.tagName, publishedAt: $0.publishedAt, url: $0.url)
        }

        return RepoSummary(
            openIssues: repo.issues.totalCount,
            openPulls: repo.pullRequests.totalCount,
            release: release
        )
    }

    func userContributionHeatmap(login: String) async throws -> [HeatmapCell] {
        let token = try await tokenProvider?() ?? { throw URLError(.userAuthenticationRequired) }()
        await diag.message("GraphQL UserContributions \(login)")
        let startedAt = Date()

        let body = GraphQLRequest(
            query: """
            query UserContributions($login: String!) {
              user(login: $login) {
                contributionsCollection {
                  contributionCalendar {
                    weeks {
                      contributionDays {
                        date
                        contributionCount
                      }
                    }
                  }
                }
              }
            }
            """,
            variables: ["login": login]
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        await self.logGraphQLResponse(http, label: "UserContributions", startedAt: startedAt)
        if let snapshot = RateLimitSnapshot.from(response: http) {
            self.rateLimit = snapshot
        }
        guard http.statusCode == 200 else {
            await self.diag.message("GraphQL status \(http.statusCode) for contributions \(login)")
            throw URLError(.badServerResponse)
        }

        let decoded = try decoder.decode(GraphQLResponse<UserContributionData>.self, from: data)
        guard let weeks = decoded.data.user?.contributionsCollection.contributionCalendar.weeks else {
            await self.diag.message("GraphQL missing contribution weeks for \(login)")
            return []
        }

        return weeks.flatMap { week in
            week.contributionDays.compactMap { day in
                HeatmapCell(date: day.date, count: day.contributionCount)
            }
        }
    }

    func rateLimitSnapshot() -> RateLimitSnapshot? {
        self.rateLimit
    }

    // MARK: - Logging

    private func logGraphQLResponse(_ response: HTTPURLResponse, label: String, startedAt: Date) async {
        let durationMs = Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
        let snapshot = RateLimitSnapshot.from(response: response)
        if let snapshot { self.rateLimit = snapshot }

        let remaining = snapshot?.remaining.map(String.init) ?? response.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? "?"
        let limit = snapshot?.limit.map(String.init) ?? response.value(forHTTPHeaderField: "X-RateLimit-Limit") ?? "?"
        let used = snapshot?.used.map(String.init) ?? response.value(forHTTPHeaderField: "X-RateLimit-Used") ?? "?"
        let resetDate = snapshot?.reset ?? {
            if let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset"), let epoch = TimeInterval(reset) {
                return Date(timeIntervalSince1970: epoch)
            }
            return nil
        }()
        let resetText = resetDate.map { RelativeFormatter.string(from: $0, relativeTo: Date()) } ?? "n/a"
        let resource = snapshot?.resource ?? response.value(forHTTPHeaderField: "X-RateLimit-Resource") ?? "graphql"

        await self.diag.message(
            "GraphQL \(label) status=\(response.statusCode) res=\(resource) lim=\(limit) rem=\(remaining) used=\(used) reset=\(resetText) dur=\(durationMs)ms"
        )
    }
}

struct RepoSummary {
    let openIssues: Int
    let openPulls: Int
    let release: Release?
}

// MARK: - Wire models

private struct GraphQLRequest: Encodable {
    let query: String
    let variables: [String: String]
}

private struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T
}

private struct RepoSummaryData: Decodable {
    let repository: RepoSummaryNode?
}

private struct RepoSummaryNode: Decodable {
    let releases: ReleaseConnection
    let issues: CountContainer
    let pullRequests: CountContainer
}

private struct ReleaseConnection: Decodable {
    let nodes: [ReleaseNode]?
}

private struct ReleaseNode: Decodable {
    let name: String?
    let tagName: String
    let publishedAt: Date
    let url: URL
}

private struct CountContainer: Decodable {
    let totalCount: Int
}

private struct UserContributionData: Decodable {
    let user: ContributionUser?
}

private struct ContributionUser: Decodable {
    let contributionsCollection: ContributionsCollection
}

private struct ContributionsCollection: Decodable {
    let contributionCalendar: ContributionCalendar
}

private struct ContributionCalendar: Decodable {
    let weeks: [ContributionWeek]
}

private struct ContributionWeek: Decodable {
    let contributionDays: [ContributionDay]
}

private struct ContributionDay: Decodable {
    let date: Date
    let contributionCount: Int
}
