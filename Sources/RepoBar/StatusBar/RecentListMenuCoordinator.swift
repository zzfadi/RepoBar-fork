import AppKit
import Foundation
import RepoBarCore

@MainActor
final class RecentListMenuCoordinator {
    unowned let actionHandler: StatusBarMenuManager
    let appState: AppState
    let menuBuilder: StatusBarMenuBuilder
    let menuItemFactory: MenuItemViewFactory
    private let menuService: RecentMenuService
    private var recentListMenus: [ObjectIdentifier: RecentListMenuEntry] = [:]
    let issueLabelChipLimit = AppLimits.RecentLists.issueLabelChipLimit

    var webURLBuilder: RepoWebURLBuilder {
        RepoWebURLBuilder(host: self.appState.session.settings.githubHost)
    }

    init(
        appState: AppState,
        menuBuilder: StatusBarMenuBuilder,
        menuItemFactory: MenuItemViewFactory,
        menuService: RecentMenuService,
        actionHandler: StatusBarMenuManager
    ) {
        self.appState = appState
        self.menuBuilder = menuBuilder
        self.menuItemFactory = menuItemFactory
        self.menuService = menuService
        self.actionHandler = actionHandler
    }

    func registerRecentListMenu(_ menu: NSMenu, context: RepoRecentMenuContext) {
        self.recentListMenus[ObjectIdentifier(menu)] = RecentListMenuEntry(menu: menu, context: context)
    }

    func cachedRecentListCount(fullName: String, kind: RepoRecentMenuKind) -> Int? {
        self.menuService.cachedRecentListCount(fullName: fullName, kind: kind)
    }

    func cachedRecentCommitCount(fullName: String) -> Int? {
        self.menuService.cachedRecentCommitCount(fullName: fullName)
    }

    func pruneMenus() {
        self.recentListMenus = self.recentListMenus.filter { $0.value.menu != nil }
    }

    func clearMenus() {
        self.recentListMenus.removeAll(keepingCapacity: true)
    }

    func handleMenuWillOpen(_ menu: NSMenu) -> Bool {
        guard let entry = self.recentListMenus[ObjectIdentifier(menu)] else { return false }
        self.menuBuilder.refreshMenuViewHeights(in: menu)
        Task { @MainActor [weak self] in
            await self?.refreshRecentListMenu(menu: menu, context: entry.context)
        }
        return true
    }

    func handleFilterChanges() {
        self.pruneMenus()
        for entry in self.recentListMenus.values {
            guard entry.context.kind == .pullRequests || entry.context.kind == .issues,
                  let menu = entry.menu
            else { continue }
            Task { @MainActor [weak self] in
                await self?.refreshRecentListMenu(menu: menu, context: entry.context)
            }
        }
    }

    func toggleIssueLabelFilter(label: String) {
        var selection = self.appState.session.recentIssueLabelSelection
        if selection.contains(label) {
            selection.remove(label)
        } else {
            selection.insert(label)
        }
        self.appState.session.recentIssueLabelSelection = selection
        NotificationCenter.default.post(name: .recentListFiltersDidChange, object: nil)
    }

    func clearIssueLabelFilters() {
        self.appState.session.recentIssueLabelSelection.removeAll()
        NotificationCenter.default.post(name: .recentListFiltersDidChange, object: nil)
    }

    func prefetchRecentLists(fullNames: Set<String>) {
        guard case .loggedIn = self.appState.session.account else { return }
        guard fullNames.isEmpty == false else { return }

        let kinds = self.menuService.descriptors().keys
        for fullName in fullNames {
            for kind in kinds {
                self.prefetchRecentList(fullName: fullName, kind: kind)
            }
        }
    }

    func prefetchRecentList(fullName: String, kind: RepoRecentMenuKind) {
        guard let (owner, name) = self.ownerAndName(from: fullName) else { return }
        let now = Date()
        guard let descriptor = self.menuService.descriptor(for: kind) else { return }
        guard descriptor.needsRefresh(fullName, now, self.menuService.cacheTTL) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await descriptor.load(fullName, owner, name, self.menuService.listLimit)
        }
    }

    private func refreshRecentListMenu(menu: NSMenu, context: RepoRecentMenuContext) async {
        guard case .loggedIn = self.appState.session.account else {
            let header = RecentMenuHeader(title: "Sign in to view", action: nil, fullName: context.fullName, systemImage: nil)
            self.populateRecentListMenu(menu, header: header, content: .signedOut)
            menu.update()
            return
        }
        guard let (owner, name) = self.ownerAndName(from: context.fullName) else {
            let header = RecentMenuHeader(
                title: "Open on GitHub",
                action: #selector(StatusBarMenuManager.openRepo(_:)),
                fullName: context.fullName,
                systemImage: "folder"
            )
            self.populateRecentListMenu(menu, header: header, content: .message("Invalid repository name"))
            menu.update()
            return
        }

        let now = Date()
        guard let descriptor = self.menuService.descriptor(for: context.kind) else { return }

        let header = RecentMenuHeader(
            title: descriptor.headerTitle,
            action: self.openAction(for: context.kind),
            fullName: context.fullName,
            systemImage: descriptor.headerIcon
        )
        let actions = self.actions(for: context.kind, fullName: context.fullName)
        let cached = descriptor.cached(context.fullName, now, self.menuService.cacheTTL)
        let stale = cached ?? descriptor.stale(context.fullName)
        let staleExtras = self.recentListExtras(for: context, items: stale)
        if let stale {
            self.populateRecentListMenu(
                menu,
                header: header,
                actions: actions,
                extras: staleExtras,
                content: .items(stale, emptyTitle: descriptor.emptyTitle, render: { menu, items in
                    self.renderRecentItems(items, for: context.kind, repoFullName: context.fullName, menu: menu)
                })
            )
        } else {
            self.populateRecentListMenu(menu, header: header, actions: actions, extras: staleExtras, content: .loading)
        }
        menu.update()

        guard descriptor.needsRefresh(context.fullName, now, self.menuService.cacheTTL) else { return }
        do {
            let items = try await descriptor.load(context.fullName, owner, name, self.menuService.listLimit)
            self.populateRecentListMenu(
                menu,
                header: header,
                actions: actions,
                extras: self.recentListExtras(for: context, items: items),
                content: .items(items, emptyTitle: descriptor.emptyTitle, render: { menu, items in
                    self.renderRecentItems(items, for: context.kind, repoFullName: context.fullName, menu: menu)
                })
            )
        } catch is AsyncTimeoutError {
            if stale == nil {
                self.populateRecentListMenu(
                    menu,
                    header: header,
                    actions: actions,
                    extras: staleExtras,
                    content: .message("Timed out")
                )
            }
        } catch {
            if stale == nil {
                self.populateRecentListMenu(
                    menu,
                    header: header,
                    actions: actions,
                    extras: staleExtras,
                    content: .message("Failed to load")
                )
            }
        }
        menu.update()
    }

    private func renderRecentItems(_ items: RecentMenuItems, for kind: RepoRecentMenuKind, repoFullName: String, menu: NSMenu) {
        switch items {
        case let .issues(issueItems):
            let filtered = self.filteredIssues(issueItems)
            if filtered.isEmpty {
                self.addEmptyListItem("No matching issues", to: menu)
                return
            }
            for issue in filtered.prefix(self.menuService.listLimit) {
                self.addIssueMenuItem(issue, to: menu)
            }
        case let .pullRequests(pullRequestItems):
            let filtered = self.filteredPullRequests(pullRequestItems)
            if filtered.isEmpty {
                self.addEmptyListItem("No matching pull requests", to: menu)
                return
            }
            for pullRequest in filtered.prefix(self.menuService.listLimit) {
                self.addPullRequestMenuItem(pullRequest, to: menu)
            }
        case let .releases(releases):
            for release in releases.prefix(self.menuService.listLimit) {
                self.addReleaseMenuItem(release, to: menu)
            }
        case let .workflowRuns(runs):
            for run in runs.prefix(self.menuService.listLimit) {
                self.addWorkflowRunMenuItem(run, to: menu)
            }
        case let .discussions(discussions):
            for discussion in discussions.prefix(self.menuService.listLimit) {
                self.addDiscussionMenuItem(discussion, to: menu)
            }
        case let .commits(commits):
            for commit in commits.prefix(self.menuService.previewLimit) {
                self.addCommitMenuItem(commit, to: menu)
            }
            if commits.count > self.menuService.previewLimit {
                menu.addItem(self.moreCommitsMenuItem(items: commits))
            }
        case let .tags(tags):
            for tag in tags.prefix(self.menuService.listLimit) {
                self.addTagMenuItem(tag, repoFullName: repoFullName, to: menu)
            }
        case let .branches(branches):
            for branch in branches.prefix(self.menuService.listLimit) {
                self.addBranchMenuItem(branch, repoFullName: repoFullName, to: menu)
            }
        case let .contributors(contributors):
            for contributor in contributors.prefix(self.menuService.listLimit) {
                self.addContributorMenuItem(contributor, to: menu)
            }
        }
    }

    private func actions(for kind: RepoRecentMenuKind, fullName: String) -> [RecentMenuAction] {
        switch kind {
        case .releases:
            let hasLatestRelease = self.appState.session.repositories
                .first(where: { $0.fullName == fullName })?
                .latestRelease != nil
            guard hasLatestRelease else { return [] }
            return [
                RecentMenuAction(
                    title: "Open Latest Release",
                    action: #selector(StatusBarMenuManager.openLatestRelease(_:)),
                    systemImage: "tag.fill",
                    representedObject: fullName,
                    isEnabled: true
                )
            ]
        default:
            return []
        }
    }

    private func openAction(for kind: RepoRecentMenuKind) -> Selector {
        switch kind {
        case .commits: #selector(StatusBarMenuManager.openCommits(_:))
        case .issues: #selector(StatusBarMenuManager.openIssues(_:))
        case .pullRequests: #selector(StatusBarMenuManager.openPulls(_:))
        case .releases: #selector(StatusBarMenuManager.openReleases(_:))
        case .ciRuns: #selector(StatusBarMenuManager.openActions(_:))
        case .discussions: #selector(StatusBarMenuManager.openDiscussions(_:))
        case .tags: #selector(StatusBarMenuManager.openTags(_:))
        case .branches: #selector(StatusBarMenuManager.openBranches(_:))
        case .contributors: #selector(StatusBarMenuManager.openContributors(_:))
        }
    }

    private func filteredPullRequests(_ items: [RepoPullRequestSummary]) -> [RepoPullRequestSummary] {
        var filtered = items
        let scope = self.appState.session.recentPullRequestScope
        if scope == .mine {
            guard case let .loggedIn(user) = self.appState.session.account else { return [] }
            filtered = filtered.filter { pullRequest in
                guard let author = pullRequest.authorLogin else { return false }
                return author.caseInsensitiveCompare(user.username) == .orderedSame
            }
        }

        switch self.appState.session.recentPullRequestEngagement {
        case .all:
            break
        case .commented:
            filtered = filtered.filter { $0.commentCount > 0 }
        case .reviewed:
            filtered = filtered.filter { $0.reviewCommentCount > 0 }
        }

        return filtered
    }

    private func filteredIssues(_ items: [RepoIssueSummary]) -> [RepoIssueSummary] {
        var filtered = items
        let scope = self.appState.session.recentIssueScope
        if scope == .mine {
            guard case let .loggedIn(user) = self.appState.session.account else { return [] }
            let username = user.username.lowercased()
            filtered = filtered.filter { issue in
                if let author = issue.authorLogin?.lowercased(), author == username {
                    return true
                }
                return issue.assigneeLogins.contains(where: { $0.lowercased() == username })
            }
        }

        let selectedLabels = self.appState.session.recentIssueLabelSelection
        if !selectedLabels.isEmpty {
            let lowered = Set(selectedLabels.map { $0.lowercased() })
            filtered = filtered.filter { issue in
                issue.labels.contains { lowered.contains($0.name.lowercased()) }
            }
        }

        return filtered
    }

}
