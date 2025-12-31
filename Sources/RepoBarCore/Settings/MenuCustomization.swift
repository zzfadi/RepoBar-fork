import Foundation

public enum MainMenuItemGroup: String, Hashable, Sendable {
    case auth
    case header
    case status
    case filters
    case repos
    case footer
}

public enum MainMenuItemID: String, CaseIterable, Codable, Hashable, Sendable {
    case loggedOutPrompt
    case signInAction
    case contributionHeader
    case statusBanner
    case filters
    case repoList
    case preferences
    case about
    case restartToUpdate
    case quit

    public var title: String {
        switch self {
        case .loggedOutPrompt: "Account Status"
        case .signInAction: "Sign In"
        case .contributionHeader: "Contribution Header"
        case .statusBanner: "Status Banner"
        case .filters: "Menu Filters"
        case .repoList: "Repository Cards"
        case .preferences: "Preferences"
        case .about: "About RepoBar"
        case .restartToUpdate: "Restart to Update"
        case .quit: "Quit RepoBar"
        }
    }

    public var subtitle: String? {
        switch self {
        case .loggedOutPrompt: "Login state banner"
        case .signInAction: "GitHub sign-in action"
        case .contributionHeader: "Heatmap header + submenu"
        case .statusBanner: "Rate-limit or error banner"
        case .filters: "Pinned/hidden filter chips"
        case .repoList: "Repo cards + inline heatmap"
        case .preferences: nil
        case .about: nil
        case .restartToUpdate: "Shown when an update is ready"
        case .quit: nil
        }
    }

    public var group: MainMenuItemGroup {
        switch self {
        case .loggedOutPrompt, .signInAction: .auth
        case .contributionHeader: .header
        case .statusBanner: .status
        case .filters: .filters
        case .repoList: .repos
        case .preferences, .about, .restartToUpdate, .quit: .footer
        }
    }
}

public enum RepoSubmenuItemGroup: String, Hashable, Sendable {
    case open
    case local
    case lists
    case heatmap
    case commits
    case activity
    case manage
}

public enum RepoSubmenuItemID: String, CaseIterable, Codable, Hashable, Sendable {
    case openOnGitHub
    case openInFinder
    case openInTerminal
    case checkoutRepo
    case localState
    case worktrees
    case issues
    case pulls
    case releases
    case ciRuns
    case discussions
    case tags
    case branches
    case contributors
    case heatmap
    case commits
    case activity
    case pinToggle
    case hideRepo
    case moveUp
    case moveDown

    public var title: String {
        switch self {
        case .openOnGitHub: "Open on GitHub"
        case .openInFinder: "Open in Finder"
        case .openInTerminal: "Open in Terminal"
        case .checkoutRepo: "Checkout Repo"
        case .localState: "Local Repo Status"
        case .worktrees: "Worktrees"
        case .issues: "Issues"
        case .pulls: "Pull Requests"
        case .releases: "Releases"
        case .ciRuns: "CI Runs"
        case .discussions: "Discussions"
        case .tags: "Tags"
        case .branches: "Branches"
        case .contributors: "Contributors"
        case .heatmap: "Heatmap"
        case .commits: "Commits"
        case .activity: "Activity"
        case .pinToggle: "Pin/Unpin"
        case .hideRepo: "Hide Repo"
        case .moveUp: "Move Up"
        case .moveDown: "Move Down"
        }
    }

    public var subtitle: String? {
        switch self {
        case .openOnGitHub: "Open repository in browser"
        case .openInFinder: "Local checkout"
        case .openInTerminal: "Local checkout"
        case .checkoutRepo: "Clone or checkout"
        case .localState: "Sync + dirty state"
        case .worktrees: "Switch or create worktrees"
        case .issues: "Recent issues list"
        case .pulls: "Recent pull requests"
        case .releases: "Recent releases list"
        case .ciRuns: "Recent CI runs"
        case .discussions: "Recent discussions"
        case .tags: "Recent tags"
        case .branches: "Branch menu"
        case .contributors: "Recent contributors"
        case .heatmap: "Repo heatmap submenu"
        case .commits: "Commit list preview"
        case .activity: "Activity feed preview"
        case .pinToggle: nil
        case .hideRepo: nil
        case .moveUp: nil
        case .moveDown: nil
        }
    }

    public var group: RepoSubmenuItemGroup {
        switch self {
        case .openOnGitHub: .open
        case .openInFinder, .openInTerminal, .checkoutRepo, .localState, .worktrees: .local
        case .issues, .pulls, .releases, .ciRuns, .discussions, .tags, .branches, .contributors: .lists
        case .heatmap: .heatmap
        case .commits: .commits
        case .activity: .activity
        case .pinToggle, .hideRepo, .moveUp, .moveDown: .manage
        }
    }
}

public struct MenuCustomization: Equatable, Codable, Hashable, Sendable {
    public var hiddenMainMenuItems: Set<MainMenuItemID> = []
    public var mainMenuOrder: [MainMenuItemID] = Self.defaultMainMenuOrder
    public var hiddenRepoSubmenuItems: Set<RepoSubmenuItemID> = []
    public var repoSubmenuOrder: [RepoSubmenuItemID] = Self.defaultRepoSubmenuOrder

    public init() {}

    public mutating func normalize() {
        self.mainMenuOrder = Self.normalizedOrder(self.mainMenuOrder, defaults: Self.defaultMainMenuOrder)
        self.repoSubmenuOrder = Self.normalizedOrder(self.repoSubmenuOrder, defaults: Self.defaultRepoSubmenuOrder)
    }

    public func normalized() -> MenuCustomization {
        var copy = self
        copy.normalize()
        return copy
    }

    public static let requiredMainMenuItems: Set<MainMenuItemID> = [
        .preferences,
        .about,
        .quit
    ]

    public static let defaultMainMenuOrder: [MainMenuItemID] = [
        .loggedOutPrompt,
        .signInAction,
        .contributionHeader,
        .statusBanner,
        .filters,
        .repoList,
        .preferences,
        .about,
        .restartToUpdate,
        .quit
    ]

    public static let defaultRepoSubmenuOrder: [RepoSubmenuItemID] = [
        .openOnGitHub,
        .openInFinder,
        .openInTerminal,
        .checkoutRepo,
        .localState,
        .worktrees,
        .issues,
        .pulls,
        .releases,
        .ciRuns,
        .discussions,
        .tags,
        .branches,
        .contributors,
        .heatmap,
        .commits,
        .activity,
        .pinToggle,
        .hideRepo
    ]

    private static func normalizedOrder<T: Hashable>(_ order: [T], defaults: [T]) -> [T] {
        var seen = Set<T>()
        var result: [T] = []
        let allowed = Set(defaults)
        for item in order where allowed.contains(item) && seen.insert(item).inserted {
            result.append(item)
        }
        for item in defaults where seen.insert(item).inserted {
            result.append(item)
        }
        return result
    }
}

public extension MainMenuItemID {
    var isRequired: Bool { MenuCustomization.requiredMainMenuItems.contains(self) }
}
