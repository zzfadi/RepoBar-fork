import Foundation

struct SearchResponse: Decodable {
    let items: [RepoItem]
}

struct RepoItem: Decodable {
    let id: Int
    let name: String
    let fullName: String
    let openIssuesCount: Int
    let owner: Owner

    struct Owner: Decodable { let login: String }

    enum CodingKeys: String, CodingKey {
        case id, name
        case fullName = "full_name"
        case openIssuesCount = "open_issues_count"
        case owner
    }
}

struct CurrentUser: Decodable {
    let login: String
    let htmlUrl: String

    enum CodingKeys: String, CodingKey {
        case login
        case htmlUrl = "html_url"
    }
}

struct SearchIssuesResponse: Decodable {
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
    }
}

struct ReleaseResponse: Decodable {
    let name: String?
    let tagName: String
    let publishedAt: Date?
    let createdAt: Date?
    let draft: Bool?
    let prerelease: Bool?
    let htmlUrl: URL

    enum CodingKeys: String, CodingKey {
        case name
        case tagName = "tag_name"
        case publishedAt = "published_at"
        case createdAt = "created_at"
        case draft
        case prerelease
        case htmlUrl = "html_url"
    }
}

struct ActionsRunsResponse: Decodable {
    let totalCount: Int?
    let workflowRuns: [WorkflowRun]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case workflowRuns = "workflow_runs"
    }

    struct WorkflowRun: Decodable {
        let status: String?
        let conclusion: String?
    }
}

struct CommentResponse: Decodable {
    let body: String
    let user: CommentUser
    let htmlUrl: URL
    let createdAt: Date

    var bodyPreview: String {
        let trimmed = self.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = String(trimmed.prefix(80))
        return prefix + (trimmed.count > 80 ? "…" : "")
    }

    enum CodingKeys: String, CodingKey {
        case body
        case user
        case htmlUrl = "html_url"
        case createdAt = "created_at"
    }

    struct CommentUser: Decodable {
        let login: String
    }
}

struct TrafficResponse: Decodable {
    let uniques: Int
}

struct CommitActivityWeek: Decodable {
    let total: Int
    let weekStart: Int
    let days: [Int]

    enum CodingKeys: String, CodingKey {
        case total
        case weekStart = "week"
        case days
    }
}

struct PullRequestListItem: Decodable {
    let id: Int
}

struct RepoEvent: Decodable {
    let type: String
    let actor: EventActor
    let payload: EventPayload
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case type, actor, payload
        case createdAt = "created_at"
    }
}

struct EventActor: Decodable {
    let login: String
}

struct EventPayload: Decodable {
    let comment: EventComment?
    let issue: EventIssue?
    let pullRequest: EventPullRequest?

    enum CodingKeys: String, CodingKey {
        case comment, issue
        case pullRequest = "pull_request"
    }
}

struct EventComment: Decodable {
    let body: String?
    let htmlUrl: URL?

    enum CodingKeys: String, CodingKey {
        case body
        case htmlUrl = "html_url"
    }

    var bodyPreview: String {
        let trimmed = (body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = String(trimmed.prefix(80))
        return prefix + (trimmed.count > 80 ? "…" : "")
    }
}

struct EventIssue: Decodable {
    let htmlUrl: URL?

    enum CodingKeys: String, CodingKey {
        case htmlUrl = "html_url"
    }
}

struct EventPullRequest: Decodable {
    let htmlUrl: URL?

    enum CodingKeys: String, CodingKey {
        case htmlUrl = "html_url"
    }
}
