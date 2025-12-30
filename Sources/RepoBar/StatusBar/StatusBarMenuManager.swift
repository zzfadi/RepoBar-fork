import AppKit
import Observation
import OSLog
import RepoBarCore
import SwiftUI

@MainActor
final class StatusBarMenuManager: NSObject, NSMenuDelegate {
    private let appState: AppState
    private var mainMenu: NSMenu?
    private weak var statusItem: NSStatusItem?
    private lazy var menuBuilder = StatusBarMenuBuilder(appState: self.appState, target: self)
    private let signposter = OSSignposter(subsystem: "com.steipete.repobar", category: "menu")
    private var recentListMenus: [ObjectIdentifier: RecentListMenuEntry] = [:]
    private weak var menuResizeWindow: NSWindow?
    private var lastMainMenuWidth: CGFloat?
    private var lastMainMenuSignature: MenuBuildSignature?
    private var lastMainMenuWidthSignature: MenuBuildSignature?
    private var webURLBuilder: RepoWebURLBuilder { RepoWebURLBuilder(host: self.appState.session.settings.githubHost) }

    private let recentListLimit = 20
    private let recentListCacheTTL: TimeInterval = 90
    private let recentIssuesCache = RecentListCache<RepoIssueSummary>()
    private let recentPullRequestsCache = RecentListCache<RepoPullRequestSummary>()
    private let recentReleasesCache = RecentListCache<RepoReleaseSummary>()
    private let recentWorkflowRunsCache = RecentListCache<RepoWorkflowRunSummary>()
    private let recentDiscussionsCache = RecentListCache<RepoDiscussionSummary>()
    private let recentTagsCache = RecentListCache<RepoTagSummary>()
    private let recentBranchesCache = RecentListCache<RepoBranchSummary>()
    private let recentContributorsCache = RecentListCache<RepoContributorSummary>()

    init(appState: AppState) {
        self.appState = appState
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.menuFiltersChanged),
            name: .menuFiltersDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.recentListFiltersChanged),
            name: .recentListFiltersDidChange,
            object: nil
        )
    }

    func attachMainMenu(to statusItem: NSStatusItem) {
        let menu = self.mainMenu ?? self.menuBuilder.makeMainMenu()
        self.mainMenu = menu
        self.statusItem = statusItem
        statusItem.menu = menu
        self.configureStatusItemButton(statusItem)
    }

    private func configureStatusItemButton(_ statusItem: NSStatusItem) {
        statusItem.button?.target = self
        statusItem.button?.action = #selector(self.statusItemButtonClicked(_:))
    }

    @objc private func statusItemButtonClicked(_ sender: NSStatusBarButton) {
        guard let statusItem = self.statusItem else { return }
        if statusItem.menu == nil {
            self.attachMainMenu(to: statusItem)
        }
        sender.performClick(nil)
    }

    // MARK: - Menu actions

    @objc func refreshNow() {
        self.appState.requestRefresh(cancelInFlight: true)
    }

    @objc func openPreferences() {
        SettingsOpener.shared.open()
    }

    @objc func openAbout() {
        self.appState.session.settingsSelectedTab = .about
        SettingsOpener.shared.open()
    }

    @objc func checkForUpdates() {
        SparkleController.shared.checkForUpdates()
    }

    @objc func menuFiltersChanged() {
        guard let menu = self.mainMenu else { return }
        self.recentListMenus.removeAll(keepingCapacity: true)
        self.appState.persistSettings()
        let plan = self.menuBuilder.mainMenuPlan()
        self.menuBuilder.populateMainMenu(menu, repos: plan.repos)
        self.lastMainMenuSignature = plan.signature
        self.menuBuilder.refreshMenuViewHeights(in: menu)
        menu.update()
    }

    @objc private func recentListFiltersChanged() {
        self.pruneRecentListMenus()
        for entry in self.recentListMenus.values {
            guard entry.context.kind == .pullRequests, let menu = entry.menu else { continue }
            Task { @MainActor [weak self] in
                await self?.refreshRecentListMenu(menu: menu, context: entry.context)
            }
        }
    }

    @objc func logOut() {
        Task { @MainActor in
            await self.appState.auth.logout()
            self.appState.session.account = .loggedOut
            self.appState.session.repositories = []
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    @objc func signIn() {
        Task { await self.appState.quickLogin() }
    }

    @objc func openRepo(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender),
              let url = self.webURLBuilder.repoURL(fullName: fullName) else { return }
        self.open(url: url)
    }

    func openRepoFromMenu(fullName: String) {
        guard let url = self.webURLBuilder.repoURL(fullName: fullName) else { return }
        self.open(url: url)
    }

    @objc func openIssues(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "issues")
    }

    @objc func openPulls(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "pulls")
    }

    @objc func openActions(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "actions")
    }

    @objc func openDiscussions(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "discussions")
    }

    @objc func openTags(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "tags")
    }

    @objc func openBranches(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "branches")
    }

    @objc func openContributors(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "graphs/contributors")
    }

    @objc func openReleases(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "releases")
    }

    @objc func openLatestRelease(_ sender: NSMenuItem) {
        guard let repo = self.repoModel(from: sender),
              let url = repo.source.latestRelease?.url else { return }
        self.open(url: url)
    }

    @objc func openActivity(_ sender: NSMenuItem) {
        guard let repo = self.repoModel(from: sender),
              let url = repo.activityURL else { return }
        self.open(url: url)
    }

    @objc func openActivityEvent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        self.open(url: url)
    }

    @objc func openURLItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        self.open(url: url)
    }

    @objc func openLocalFinder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        self.open(url: url)
    }

    @objc func openLocalTerminal(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let preferred = self.appState.session.settings.localProjects.preferredTerminal
        let terminal = TerminalApp.resolve(preferred)
        terminal.open(
            at: url,
            rootBookmarkData: self.appState.session.settings.localProjects.rootBookmarkData,
            ghosttyOpenMode: self.appState.session.settings.localProjects.ghosttyOpenMode
        )
    }

    @objc func copyRepoName(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(fullName, forType: .string)
    }

    @objc func copyRepoURL(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender),
              let url = self.webURLBuilder.repoURL(fullName: fullName) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
    }

    @objc func pinRepo(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender) else { return }
        Task { await self.appState.addPinned(fullName) }
    }

    @objc func unpinRepo(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender) else { return }
        Task { await self.appState.removePinned(fullName) }
    }

    @objc func hideRepo(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender) else { return }
        Task { await self.appState.hide(fullName) }
    }

    @objc func moveRepoUp(_ sender: NSMenuItem) {
        self.moveRepo(sender: sender, direction: -1)
    }

    @objc func moveRepoDown(_ sender: NSMenuItem) {
        self.moveRepo(sender: sender, direction: 1)
    }

    private func moveRepo(sender: NSMenuItem, direction: Int) {
        guard let fullName = self.repoFullName(from: sender) else { return }
        var pins = self.appState.session.settings.repoList.pinnedRepositories
        guard let currentIndex = pins.firstIndex(of: fullName) else { return }
        let maxIndex = max(pins.count - 1, 0)
        let target = max(0, min(maxIndex, currentIndex + direction))
        guard target != currentIndex else { return }
        pins.move(fromOffsets: IndexSet(integer: currentIndex), toOffset: target > currentIndex ? target + 1 : target)
        self.appState.session.settings.repoList.pinnedRepositories = pins
        self.appState.persistSettings()
        self.appState.requestRefresh(cancelInFlight: true)
    }

    func menuWillOpen(_ menu: NSMenu) {
        let signpost = self.signposter.beginInterval("menuWillOpen")
        defer { self.signposter.endInterval("menuWillOpen", signpost) }
        menu.appearance = NSApp.effectiveAppearance
        if let entry = self.recentListMenus[ObjectIdentifier(menu)] {
            let context = entry.context
            self.menuBuilder.refreshMenuViewHeights(in: menu)
            Task { @MainActor [weak self] in
                await self?.refreshRecentListMenu(menu: menu, context: context)
            }
            return
        }
        if menu === self.mainMenu {
            let plan = self.menuBuilder.mainMenuPlan()
            self.recentListMenus.removeAll(keepingCapacity: true)
            if self.appState.session.settings.appearance.showContributionHeader {
                if case let .loggedIn(user) = self.appState.session.account {
                    Task { await self.appState.loadContributionHeatmapIfNeeded(for: user.username) }
                }
            }
            self.appState.refreshIfNeededForMenu()
            if self.lastMainMenuSignature != plan.signature || menu.items.isEmpty {
                self.menuBuilder.populateMainMenu(menu, repos: plan.repos)
                self.lastMainMenuSignature = plan.signature
            }
            if let cachedWidth = self.lastMainMenuWidth {
                self.menuBuilder.refreshMenuViewHeights(in: menu, width: cachedWidth)
            } else {
                self.menuBuilder.refreshMenuViewHeights(in: menu)
            }

            let repoFullNames = Set(menu.items.compactMap { $0.representedObject as? String }.filter { $0.contains("/") })
            self.prefetchRecentLists(fullNames: repoFullNames)

            let shouldRecomputeWidth = self.lastMainMenuWidth == nil || self.lastMainMenuWidthSignature != plan.signature
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if shouldRecomputeWidth {
                    let measuredWidth = self.menuBuilder.menuWidth(for: menu)
                    let priorWidth = self.lastMainMenuWidth
                    let shouldRemeasure = priorWidth == nil || abs(measuredWidth - (priorWidth ?? 0)) > 0.5
                    self.lastMainMenuWidth = measuredWidth
                    self.lastMainMenuWidthSignature = plan.signature
                    if shouldRemeasure {
                        self.menuBuilder.refreshMenuViewHeights(in: menu, width: measuredWidth)
                        menu.update()
                    }
                }
                self.menuBuilder.clearHighlights(in: menu)
                self.startObservingMenuResize(for: menu)
            }
        } else {
            self.menuBuilder.refreshMenuViewHeights(in: menu)
            let submenuFullName = menu.supermenu?.items.first(where: { $0.submenu === menu })?.representedObject as? String
            if let fullName = submenuFullName, fullName.contains("/") {
                // Repo submenu opened; prefetch so nested recent lists appear instantly.
                self.prefetchRecentLists(fullNames: [fullName])
            }
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === self.mainMenu {
            self.menuBuilder.clearHighlights(in: menu)
            self.stopObservingMenuResize()
        }
    }

    private func pruneRecentListMenus() {
        self.recentListMenus = self.recentListMenus.filter { $0.value.menu != nil }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for menuItem in menu.items {
            guard let view = menuItem.view as? MenuItemHighlighting else { continue }
            let highlighted = menuItem == item && menuItem.isEnabled
            view.setHighlighted(highlighted)
        }
    }

    private func startObservingMenuResize(for menu: NSMenu) {
        self.stopObservingMenuResize()
        guard let window = menu.items.compactMap(\.view).first?.window else { return }
        self.menuResizeWindow = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.menuWindowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )
    }

    private func stopObservingMenuResize() {
        guard let window = self.menuResizeWindow else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: window)
        self.menuResizeWindow = nil
    }

    @objc private func menuWindowDidResize(_: Notification) {
        guard let menu = self.mainMenu else { return }
        let width = self.menuBuilder.menuWidth(for: menu)
        self.lastMainMenuWidth = width
        self.menuBuilder.refreshMenuViewHeights(in: menu, width: width)
        menu.update()
    }

    // MARK: - Main menu

    private func recentMenuDescriptor(for kind: RepoRecentMenuKind) -> RecentMenuDescriptor? {
        self.recentMenuDescriptors()[kind]
    }

    private func recentMenuDescriptors() -> [RepoRecentMenuKind: RecentMenuDescriptor] {
        let releaseActions: (String) -> [RecentMenuAction] = { fullName in
            let hasLatestRelease = self.appState.session.repositories
                .first(where: { $0.fullName == fullName })?
                .latestRelease != nil
            return hasLatestRelease
                ? [
                    RecentMenuAction(
                        title: "Open Latest Release",
                        action: #selector(self.openLatestRelease),
                        systemImage: "tag.fill",
                        representedObject: fullName,
                        isEnabled: true
                    )
                ]
                : []
        }

        let descriptors: [RecentMenuDescriptor] = [
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .issues,
                headerTitle: "Open Issues",
                headerIcon: "exclamationmark.circle",
                openAction: #selector(self.openIssues),
                emptyTitle: "No open issues",
                cache: self.recentIssuesCache,
                wrap: RecentMenuItems.issues,
                unwrap: { boxed in
                    if case let .issues(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentIssues(owner: owner, name: name, limit: limit)
                },
                render: { menu, _, items in
                    for issue in items.prefix(self.recentListLimit) {
                        self.addIssueMenuItem(issue, to: menu)
                    }
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .pullRequests,
                headerTitle: "Open Pull Requests",
                headerIcon: "arrow.triangle.branch",
                openAction: #selector(self.openPulls),
                emptyTitle: "No open pull requests",
                cache: self.recentPullRequestsCache,
                wrap: RecentMenuItems.pullRequests,
                unwrap: { boxed in
                    if case let .pullRequests(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentPullRequests(owner: owner, name: name, limit: limit)
                },
                render: { menu, _, items in
                    let filtered = self.filteredPullRequests(items)
                    if filtered.isEmpty {
                        self.addEmptyListItem("No matching pull requests", to: menu)
                        return
                    }
                    for pr in filtered.prefix(self.recentListLimit) {
                        self.addPullRequestMenuItem(pr, to: menu)
                    }
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .releases,
                headerTitle: "Open Releases",
                headerIcon: "tag",
                openAction: #selector(self.openReleases),
                emptyTitle: "No releases",
                cache: self.recentReleasesCache,
                wrap: RecentMenuItems.releases,
                unwrap: { boxed in
                    if case let .releases(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentReleases(owner: owner, name: name, limit: limit)
                },
                render: { menu, _, items in
                    for release in items.prefix(self.recentListLimit) {
                        self.addReleaseMenuItem(release, to: menu)
                    }
                }
            ), actions: releaseActions),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .ciRuns,
                headerTitle: "Open Actions",
                headerIcon: "bolt",
                openAction: #selector(self.openActions),
                emptyTitle: "No CI runs",
                cache: self.recentWorkflowRunsCache,
                wrap: RecentMenuItems.workflowRuns,
                unwrap: { boxed in
                    if case let .workflowRuns(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentWorkflowRuns(owner: owner, name: name, limit: limit)
                },
                render: { menu, _, items in
                    for run in items.prefix(self.recentListLimit) {
                        self.addWorkflowRunMenuItem(run, to: menu)
                    }
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .discussions,
                headerTitle: "Open Discussions",
                headerIcon: "bubble.left.and.bubble.right",
                openAction: #selector(self.openDiscussions),
                emptyTitle: "No discussions",
                cache: self.recentDiscussionsCache,
                wrap: RecentMenuItems.discussions,
                unwrap: { boxed in
                    if case let .discussions(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentDiscussions(owner: owner, name: name, limit: limit)
                },
                render: { menu, _, items in
                    for discussion in items.prefix(self.recentListLimit) {
                        self.addDiscussionMenuItem(discussion, to: menu)
                    }
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .tags,
                headerTitle: "Open Tags",
                headerIcon: "tag",
                openAction: #selector(self.openTags),
                emptyTitle: "No tags",
                cache: self.recentTagsCache,
                wrap: RecentMenuItems.tags,
                unwrap: { boxed in
                    if case let .tags(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentTags(owner: owner, name: name, limit: limit)
                },
                render: { menu, fullName, items in
                    for tag in items.prefix(self.recentListLimit) {
                        self.addTagMenuItem(tag, repoFullName: fullName, to: menu)
                    }
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .branches,
                headerTitle: "Open Branches",
                headerIcon: "point.topleft.down.curvedto.point.bottomright.up",
                openAction: #selector(self.openBranches),
                emptyTitle: "No branches",
                cache: self.recentBranchesCache,
                wrap: RecentMenuItems.branches,
                unwrap: { boxed in
                    if case let .branches(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentBranches(owner: owner, name: name, limit: limit)
                },
                render: { menu, fullName, items in
                    for branch in items.prefix(self.recentListLimit) {
                        self.addBranchMenuItem(branch, repoFullName: fullName, to: menu)
                    }
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .contributors,
                headerTitle: "Open Contributors",
                headerIcon: "person.2",
                openAction: #selector(self.openContributors),
                emptyTitle: "No contributors",
                cache: self.recentContributorsCache,
                wrap: RecentMenuItems.contributors,
                unwrap: { boxed in
                    if case let .contributors(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.topContributors(owner: owner, name: name, limit: limit)
                },
                render: { menu, _, items in
                    for contributor in items.prefix(self.recentListLimit) {
                        self.addContributorMenuItem(contributor, to: menu)
                    }
                }
            ))
        ]

        return Dictionary(uniqueKeysWithValues: descriptors.map { ($0.kind, $0) })
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

    private func makeDescriptor(
        _ config: RecentMenuDescriptorConfig<some Sendable>,
        actions: @escaping (String) -> [RecentMenuAction] = { _ in [] }
    ) -> RecentMenuDescriptor {
        let github = self.appState.github
        let fetch = config.fetch

        return RecentMenuDescriptor(
            kind: config.kind,
            headerTitle: config.headerTitle,
            headerIcon: config.headerIcon,
            openAction: config.openAction,
            emptyTitle: config.emptyTitle,
            actions: actions,
            cached: { key, now, ttl in
                config.cache.cached(for: key, now: now, maxAge: ttl).map(config.wrap)
            },
            stale: { key in
                config.cache.stale(for: key).map(config.wrap)
            },
            needsRefresh: { key, now, ttl in
                config.cache.needsRefresh(for: key, now: now, maxAge: ttl)
            },
            load: { key, owner, name, limit in
                let task = config.cache.task(for: key) {
                    try await fetch(github, owner, name, limit)
                }
                defer { config.cache.clearInflight(for: key) }
                let items = try await task.value
                config.cache.store(items, for: key, fetchedAt: Date())
                return config.wrap(items)
            },
            render: { menu, fullName, boxed in
                guard let items = config.unwrap(boxed) else { return }
                config.render(menu, fullName, items)
            }
        )
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
                action: #selector(self.openRepo),
                fullName: context.fullName,
                systemImage: "folder"
            )
            self.populateRecentListMenu(menu, header: header, content: .message("Invalid repository name"))
            menu.update()
            return
        }

        let now = Date()
        guard let descriptor = self.recentMenuDescriptor(for: context.kind) else { return }

        let header = RecentMenuHeader(
            title: descriptor.headerTitle,
            action: descriptor.openAction,
            fullName: context.fullName,
            systemImage: descriptor.headerIcon
        )
        let actions = descriptor.actions(context.fullName)
        let extras = self.pullRequestFilterMenuItems(for: context)
        let cached = descriptor.cached(context.fullName, now, self.recentListCacheTTL)
        let stale = cached ?? descriptor.stale(context.fullName)
        if let stale {
            self.populateRecentListMenu(
                menu,
                header: header,
                actions: actions,
                extras: extras,
                content: .items(stale, emptyTitle: descriptor.emptyTitle, render: { menu, items in
                    descriptor.render(menu, header.fullName, items)
                })
            )
        } else {
            self.populateRecentListMenu(menu, header: header, actions: actions, extras: extras, content: .loading)
        }
        menu.update()

        guard descriptor.needsRefresh(context.fullName, now, self.recentListCacheTTL) else { return }
        do {
            let items = try await descriptor.load(context.fullName, owner, name, self.recentListLimit)
            self.populateRecentListMenu(
                menu,
                header: header,
                actions: actions,
                extras: extras,
                content: .items(items, emptyTitle: descriptor.emptyTitle, render: { menu, items in
                    descriptor.render(menu, header.fullName, items)
                })
            )
        } catch {
            if stale == nil {
                self.populateRecentListMenu(menu, header: header, actions: actions, extras: extras, content: .message("Failed to load"))
            }
        }
        menu.update()
    }

    private func prefetchRecentLists(fullNames: Set<String>) {
        guard case .loggedIn = self.appState.session.account else { return }
        guard fullNames.isEmpty == false else { return }

        let kinds = Array(self.recentMenuDescriptors().keys)
        for fullName in fullNames {
            for kind in kinds {
                self.prefetchRecentList(fullName: fullName, kind: kind)
            }
        }
    }

    private func prefetchRecentList(fullName: String, kind: RepoRecentMenuKind) {
        guard let (owner, name) = self.ownerAndName(from: fullName) else { return }
        let now = Date()
        guard let descriptor = self.recentMenuDescriptor(for: kind) else { return }
        guard descriptor.needsRefresh(fullName, now, self.recentListCacheTTL) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await descriptor.load(fullName, owner, name, self.recentListLimit)
        }
    }

    private enum RecentMenuContent {
        case signedOut
        case loading
        case message(String)
        case items(RecentMenuItems, emptyTitle: String, render: (NSMenu, RecentMenuItems) -> Void)
    }

    private enum RecentMenuItems: Sendable {
        case issues([RepoIssueSummary])
        case pullRequests([RepoPullRequestSummary])
        case releases([RepoReleaseSummary])
        case workflowRuns([RepoWorkflowRunSummary])
        case discussions([RepoDiscussionSummary])
        case tags([RepoTagSummary])
        case branches([RepoBranchSummary])
        case contributors([RepoContributorSummary])

        var isEmpty: Bool {
            switch self {
            case let .issues(items): items.isEmpty
            case let .pullRequests(items): items.isEmpty
            case let .releases(items): items.isEmpty
            case let .workflowRuns(items): items.isEmpty
            case let .discussions(items): items.isEmpty
            case let .tags(items): items.isEmpty
            case let .branches(items): items.isEmpty
            case let .contributors(items): items.isEmpty
            }
        }

        var count: Int {
            switch self {
            case let .issues(items): items.count
            case let .pullRequests(items): items.count
            case let .releases(items): items.count
            case let .workflowRuns(items): items.count
            case let .discussions(items): items.count
            case let .tags(items): items.count
            case let .branches(items): items.count
            case let .contributors(items): items.count
            }
        }
    }

    private struct RecentMenuHeader {
        let title: String
        let action: Selector?
        let fullName: String
        let systemImage: String?
    }

    private struct RecentMenuAction {
        let title: String
        let action: Selector
        let systemImage: String?
        let representedObject: Any
        let isEnabled: Bool
    }

    private struct ListMenuHeader {
        let title: String
        let action: Selector?
        let systemImage: String?
        let representedObject: Any?
    }

    private struct ListMenuAction {
        let title: String
        let action: Selector
        let systemImage: String?
        let representedObject: Any?
        let isEnabled: Bool
    }

    private enum ListMenuContent {
        case message(String)
        case items(isEmpty: Bool, emptyTitle: String?, render: (NSMenu) -> Void)
    }

    private struct RecentMenuDescriptorConfig<Item: Sendable> {
        let kind: RepoRecentMenuKind
        let headerTitle: String
        let headerIcon: String?
        let openAction: Selector
        let emptyTitle: String
        let cache: RecentListCache<Item>
        let wrap: ([Item]) -> RecentMenuItems
        let unwrap: (RecentMenuItems) -> [Item]?
        let fetch: @Sendable (GitHubClient, String, String, Int) async throws -> [Item]
        let render: (NSMenu, String, [Item]) -> Void
    }

    private struct RecentMenuDescriptor {
        let kind: RepoRecentMenuKind
        let headerTitle: String
        let headerIcon: String?
        let openAction: Selector
        let emptyTitle: String
        let actions: (String) -> [RecentMenuAction]
        let cached: (String, Date, TimeInterval) -> RecentMenuItems?
        let stale: (String) -> RecentMenuItems?
        let needsRefresh: (String, Date, TimeInterval) -> Bool
        let load: @MainActor (String, String, String, Int) async throws -> RecentMenuItems
        let render: (NSMenu, String, RecentMenuItems) -> Void
    }

    private func populateListMenu(
        _ menu: NSMenu,
        header: ListMenuHeader,
        actions: [ListMenuAction] = [],
        extras: [NSMenuItem] = [],
        content: ListMenuContent
    ) {
        menu.removeAllItems()

        let open = NSMenuItem(title: header.title, action: header.action, keyEquivalent: "")
        open.target = self
        open.representedObject = header.representedObject
        if let systemImage = header.systemImage, let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil) {
            image.size = NSSize(width: 14, height: 14)
            image.isTemplate = true
            open.image = image
        }
        open.isEnabled = header.action != nil
        menu.addItem(open)

        for action in actions {
            let item = NSMenuItem(title: action.title, action: action.action, keyEquivalent: "")
            item.target = self
            item.representedObject = action.representedObject
            item.isEnabled = action.isEnabled
            if let systemImage = action.systemImage, let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil) {
                image.size = NSSize(width: 14, height: 14)
                image.isTemplate = true
                item.image = image
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        for extra in extras {
            menu.addItem(extra)
        }

        switch content {
        case let .message(text):
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        case let .items(isEmpty, emptyTitle, render):
            if isEmpty {
                if let emptyTitle {
                    let item = NSMenuItem(title: emptyTitle, action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    menu.addItem(item)
                }
            } else {
                render(menu)
            }
        }

        if menu.items.contains(where: { $0.view != nil }) {
            self.menuBuilder.refreshMenuViewHeights(in: menu)
        }
    }

    private func populateRecentListMenu(
        _ menu: NSMenu,
        header: RecentMenuHeader,
        actions: [RecentMenuAction] = [],
        extras: [NSMenuItem] = [],
        content: RecentMenuContent
    ) {
        let listHeader = ListMenuHeader(
            title: header.title,
            action: header.action,
            systemImage: header.systemImage,
            representedObject: header.fullName
        )
        let listActions = actions.map {
            ListMenuAction(
                title: $0.title,
                action: $0.action,
                systemImage: $0.systemImage,
                representedObject: $0.representedObject,
                isEnabled: $0.isEnabled
            )
        }

        let listContent: ListMenuContent = switch content {
        case .signedOut:
            .message("Sign in to load items")
        case .loading:
            .message("Loading…")
        case let .message(text):
            .message(text)
        case let .items(items, emptyTitle, render):
            .items(isEmpty: items.isEmpty, emptyTitle: emptyTitle, render: { menu in
                render(menu, items)
            })
        }

        self.populateListMenu(menu, header: listHeader, actions: listActions, extras: extras, content: listContent)
    }

    private func addEmptyListItem(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func pullRequestFilterMenuItems(for context: RepoRecentMenuContext) -> [NSMenuItem] {
        guard context.kind == .pullRequests else { return [] }
        let filters = RecentPullRequestFiltersView(session: self.appState.session)
        let item = self.hostingMenuItem(for: filters, enabled: true)
        return [item, .separator()]
    }

    private func hostingMenuItem(for view: some View, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = enabled
        item.view = MenuItemHostingView(rootView: AnyView(view))
        return item
    }

    private func addIssueMenuItem(_ issue: RepoIssueSummary, to menu: NSMenu) {
        let highlightState = MenuItemHighlightState()
        let view = MenuItemContainerView(highlightState: highlightState, showsSubmenuIndicator: false) {
            IssueMenuItemView(issue: issue) { [weak self] in
                self?.open(url: issue.url)
            }
        }

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.view = MenuItemHostingView(rootView: AnyView(view), highlightState: highlightState)
        item.toolTip = self.recentItemTooltip(title: issue.title, author: issue.authorLogin, updatedAt: issue.updatedAt)
        menu.addItem(item)
    }

    private func addPullRequestMenuItem(_ pullRequest: RepoPullRequestSummary, to menu: NSMenu) {
        let highlightState = MenuItemHighlightState()
        let view = MenuItemContainerView(highlightState: highlightState, showsSubmenuIndicator: false) {
            PullRequestMenuItemView(pullRequest: pullRequest) { [weak self] in
                self?.open(url: pullRequest.url)
            }
        }

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.view = MenuItemHostingView(rootView: AnyView(view), highlightState: highlightState)
        item.toolTip = self.recentItemTooltip(
            title: pullRequest.title,
            author: pullRequest.authorLogin,
            updatedAt: pullRequest.updatedAt
        )
        menu.addItem(item)
    }

    private func addReleaseMenuItem(_ release: RepoReleaseSummary, to menu: NSMenu) {
        let highlightState = MenuItemHighlightState()
        let hasAssets = release.assets.isEmpty == false
        let view = MenuItemContainerView(highlightState: highlightState, showsSubmenuIndicator: hasAssets) {
            ReleaseMenuItemView(release: release) { [weak self] in
                self?.open(url: release.url)
            }
        }

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.view = MenuItemHostingView(rootView: AnyView(view), highlightState: highlightState)
        item.toolTip = self.recentItemTooltip(title: release.name, author: release.authorLogin, updatedAt: release.publishedAt)
        if hasAssets {
            item.submenu = self.releaseAssetsMenu(for: release)
            item.target = self
            item.action = #selector(self.menuItemNoOp(_:))
        }
        menu.addItem(item)
    }

    private func addWorkflowRunMenuItem(_ run: RepoWorkflowRunSummary, to menu: NSMenu) {
        let highlightState = MenuItemHighlightState()
        let view = MenuItemContainerView(highlightState: highlightState, showsSubmenuIndicator: false) {
            WorkflowRunMenuItemView(run: run) { [weak self] in
                self?.open(url: run.url)
            }
        }

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.view = MenuItemHostingView(rootView: AnyView(view), highlightState: highlightState)
        item.toolTip = self.recentItemTooltip(title: run.name, author: run.actorLogin, updatedAt: run.updatedAt)
        menu.addItem(item)
    }

    private func addDiscussionMenuItem(_ discussion: RepoDiscussionSummary, to menu: NSMenu) {
        let highlightState = MenuItemHighlightState()
        let view = MenuItemContainerView(highlightState: highlightState, showsSubmenuIndicator: false) {
            DiscussionMenuItemView(discussion: discussion) { [weak self] in
                self?.open(url: discussion.url)
            }
        }

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.view = MenuItemHostingView(rootView: AnyView(view), highlightState: highlightState)
        item.toolTip = self.recentItemTooltip(
            title: discussion.title,
            author: discussion.authorLogin,
            updatedAt: discussion.updatedAt
        )
        menu.addItem(item)
    }

    private func addTagMenuItem(_ tag: RepoTagSummary, repoFullName: String, to menu: NSMenu) {
        let highlightState = MenuItemHighlightState()
        let view = MenuItemContainerView(highlightState: highlightState, showsSubmenuIndicator: false) {
            TagMenuItemView(tag: tag) { [weak self] in
                guard let self, let url = self.webURLBuilder.tagURL(fullName: repoFullName, tag: tag.name) else { return }
                self.open(url: url)
            }
        }

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.view = MenuItemHostingView(rootView: AnyView(view), highlightState: highlightState)
        item.toolTip = "\(tag.name)\n\(tag.commitSHA)"
        menu.addItem(item)
    }

    private func addBranchMenuItem(_ branch: RepoBranchSummary, repoFullName: String, to menu: NSMenu) {
        let highlightState = MenuItemHighlightState()
        let view = MenuItemContainerView(highlightState: highlightState, showsSubmenuIndicator: false) {
            BranchMenuItemView(branch: branch) { [weak self] in
                guard let self, let url = self.webURLBuilder.branchURL(fullName: repoFullName, branch: branch.name) else { return }
                self.open(url: url)
            }
        }

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.view = MenuItemHostingView(rootView: AnyView(view), highlightState: highlightState)
        item.toolTip = "\(branch.name)\n\(branch.commitSHA)"
        menu.addItem(item)
    }

    private func addContributorMenuItem(_ contributor: RepoContributorSummary, to menu: NSMenu) {
        let highlightState = MenuItemHighlightState()
        let view = MenuItemContainerView(highlightState: highlightState, showsSubmenuIndicator: false) {
            ContributorMenuItemView(contributor: contributor) { [weak self] in
                guard let url = contributor.url else { return }
                self?.open(url: url)
            }
        }

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.view = MenuItemHostingView(rootView: AnyView(view), highlightState: highlightState)
        item.toolTip = "\(contributor.login)\n\(contributor.contributions) contributions"
        menu.addItem(item)
    }

    private func releaseAssetsMenu(for release: RepoReleaseSummary) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let header = ListMenuHeader(
            title: "Open Release",
            action: #selector(self.openURLFromMenuItem(_:)),
            systemImage: nil,
            representedObject: release.url
        )
        self.populateListMenu(
            menu,
            header: header,
            content: .items(
                isEmpty: release.assets.isEmpty,
                emptyTitle: "No assets",
                render: { menu in
                    for asset in release.assets {
                        self.addReleaseAssetMenuItem(asset, to: menu)
                    }
                }
            )
        )

        return menu
    }

    private func addReleaseAssetMenuItem(_ asset: RepoReleaseAssetSummary, to menu: NSMenu) {
        let highlightState = MenuItemHighlightState()
        let view = MenuItemContainerView(highlightState: highlightState, showsSubmenuIndicator: false) {
            ReleaseAssetMenuItemView(asset: asset) { [weak self] in
                self?.open(url: asset.url)
            }
        }

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.view = MenuItemHostingView(rootView: AnyView(view), highlightState: highlightState)
        item.toolTip = asset.name
        menu.addItem(item)
    }

    private func recentItemTooltip(title: String, author: String?, updatedAt: Date) -> String {
        var parts: [String] = []
        if let author, !author.isEmpty {
            parts.append("@\(author)")
        }
        parts.append("Updated \(RelativeFormatter.string(from: updatedAt, relativeTo: Date()))")
        parts.append(title)
        return parts.joined(separator: "\n")
    }

    private func repoModel(from sender: NSMenuItem) -> RepositoryDisplayModel? {
        guard let fullName = self.repoFullName(from: sender) else { return nil }
        guard let repo = self.appState.session.repositories.first(where: { $0.fullName == fullName }) else { return nil }
        let local = self.appState.session.localRepoIndex.status(forFullName: fullName)
        return RepositoryDisplayModel(repo: repo, localStatus: local)
    }

    private func repoFullName(from sender: NSMenuItem) -> String? {
        sender.representedObject as? String
    }

    private func ownerAndName(from fullName: String) -> (String, String)? {
        let parts = fullName.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    private func openRepoPath(sender: NSMenuItem, path: String) {
        guard let fullName = self.repoFullName(from: sender),
              let url = self.webURLBuilder.repoPathURL(fullName: fullName, path: path) else { return }
        self.open(url: url)
    }

    func open(url: URL) {
        SecurityScopedBookmark.withAccess(
            to: url,
            rootBookmarkData: self.appState.session.settings.localProjects.rootBookmarkData
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func menuItemNoOp(_: NSMenuItem) {}

    @objc private func openURLFromMenuItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        self.open(url: url)
    }

    func registerRecentListMenu(_ menu: NSMenu, context: RepoRecentMenuContext) {
        self.recentListMenus[ObjectIdentifier(menu)] = RecentListMenuEntry(menu: menu, context: context)
    }

    func cachedRecentListCount(fullName: String, kind: RepoRecentMenuKind) -> Int? {
        guard let descriptor = self.recentMenuDescriptor(for: kind) else { return nil }
        return descriptor.stale(fullName)?.count
    }
}

private final class RecentListMenuEntry {
    weak var menu: NSMenu?
    let context: RepoRecentMenuContext

    init(menu: NSMenu, context: RepoRecentMenuContext) {
        self.menu = menu
        self.context = context
    }
}

private final class RecentListCache<Item: Sendable> {
    struct Entry { var fetchedAt: Date
        var items: [Item]
    }

    private var entries: [String: Entry] = [:]
    private var inflight: [String: Task<[Item], Error>] = [:]

    func cached(for key: String, now: Date, maxAge: TimeInterval) -> [Item]? {
        guard let entry = entries[key] else { return nil }
        guard now.timeIntervalSince(entry.fetchedAt) <= maxAge else { return nil }
        return entry.items
    }

    func stale(for key: String) -> [Item]? {
        self.entries[key]?.items
    }

    func needsRefresh(for key: String, now: Date, maxAge: TimeInterval) -> Bool {
        guard let entry = entries[key] else { return true }
        return now.timeIntervalSince(entry.fetchedAt) > maxAge
    }

    func task(for key: String, factory: @escaping @Sendable () async throws -> [Item]) -> Task<[Item], Error> {
        if let existing = inflight[key] { return existing }
        let task = Task { try await factory() }
        self.inflight[key] = task
        return task
    }

    func clearInflight(for key: String) {
        self.inflight[key] = nil
    }

    func store(_ items: [Item], for key: String, fetchedAt: Date) {
        self.entries[key] = Entry(fetchedAt: fetchedAt, items: items)
    }
}
