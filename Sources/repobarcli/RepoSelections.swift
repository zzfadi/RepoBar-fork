import Commander
import Foundation
import RepoBarCore

enum RepoScopeSelection: String, CaseIterable, ExpressibleFromArgument, Sendable {
    case all
    case pinned
    case hidden

    init?(argument: String) {
        self.init(rawValue: argument.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

extension RepoScopeSelection {
    var repositoryScope: RepositoryScope {
        switch self {
        case .all: return .all
        case .pinned: return .pinned
        case .hidden: return .hidden
        }
    }
}

enum RepoFilterSelection: String, CaseIterable, ExpressibleFromArgument, Sendable {
    case all
    case work
    case issues
    case prs

    init?(argument: String) {
        let token = argument.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch token {
        case "all":
            self = .all
        case "work":
            self = .work
        case "issues", "issue":
            self = .issues
        case "prs", "pr", "pull", "pulls":
            self = .prs
        default:
            return nil
        }
    }

    var onlyWith: RepositoryOnlyWith {
        switch self {
        case .all:
            return .none
        case .work:
            return RepositoryOnlyWith(requireIssues: true, requirePRs: true)
        case .issues:
            return RepositoryOnlyWith(requireIssues: true)
        case .prs:
            return RepositoryOnlyWith(requirePRs: true)
        }
    }
}
