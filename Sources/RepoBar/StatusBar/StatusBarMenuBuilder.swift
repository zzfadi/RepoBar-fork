import AppKit
import OSLog
import RepoBarCore
import SwiftUI

@MainActor
final class StatusBarMenuBuilder {
    private static let menuFixedWidth: CGFloat = 360

    private let appState: AppState
    private unowned let target: StatusBarMenuManager
    private let signposter = OSSignposter(subsystem: "com.steipete.repobar", category: "menu")
    private var repoMenuItemCache: [String: NSMenuItem] = [:]
    private var repoSubmenuCache: [String: RepoSubmenuCacheEntry] = [:]
    private var systemImageCache: [String: NSImage] = [:]

    init(appState: AppState, target: StatusBarMenuManager) {
        self.appState = appState
        self.target = target
    }

    func makeMainMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self.target
        menu.appearance = nil
        return menu
    }

    func mainMenuPlan(now: Date = Date()) -> MainMenuPlan {
        let session = self.appState.session
        let settings = session.settings
        let repos = self.orderedViewModels(now: now)
        let signature = MenuBuildSignature(
            account: AccountSignature(session.account),
            settings: MenuSettingsSignature(settings: settings, selection: session.menuRepoSelection),
            hasLoadedRepositories: session.hasLoadedRepositories,
            rateLimitReset: session.rateLimitReset,
            lastError: session.lastError,
            contribution: ContributionSignature(
                user: session.contributionUser,
                error: session.contributionError,
                heatmapCount: session.contributionHeatmap.count
            ),
            heatmapRangeStart: session.heatmapRange.start.timeIntervalSinceReferenceDate,
            heatmapRangeEnd: session.heatmapRange.end.timeIntervalSinceReferenceDate,
            reposDigest: RepoSignature.digest(for: repos),
            timeBucket: Int(now.timeIntervalSinceReferenceDate / 60)
        )
        return MainMenuPlan(repos: repos, signature: signature)
    }

    func populateMainMenu(_ menu: NSMenu, repos: [RepositoryDisplayModel]) {
        let signpost = self.signposter.beginInterval("populateMainMenu")
        defer { self.signposter.endInterval("populateMainMenu", signpost) }
        menu.removeAllItems()
        let session = self.appState.session
        let settings = session.settings

        let hasContributionHeatmap = session.contributionHeatmap.isEmpty == false
        let shouldShowContributionHeader = settings.appearance.showContributionHeader
            && (hasContributionHeatmap || session.contributionError == nil)
        let username = self.currentUsername()
        let displayName = self.currentDisplayName()
        if shouldShowContributionHeader, let username, let displayName {
            let header = ContributionHeaderView(
                username: username,
                displayName: displayName,
                session: session,
                appState: self.appState
            )
            .padding(.horizontal, MenuStyle.headerHorizontalPadding)
            .padding(.top, MenuStyle.headerTopPadding)
            .padding(.bottom, MenuStyle.headerBottomPadding)
            menu.addItem(self.viewItem(for: header, enabled: true, highlightable: false))
            menu.addItem(.separator())
        }

        switch session.account {
        case .loggedOut:
            let loggedOut = MenuLoggedOutView()
                .padding(.horizontal, MenuStyle.sectionHorizontalPadding)
                .padding(.vertical, MenuStyle.sectionVerticalPadding)
            menu.addItem(self.viewItem(for: loggedOut, enabled: false))
            menu.addItem(.separator())
            let signInItem = self.actionItem(title: "Sign in to GitHub", action: #selector(self.target.signIn))
            menu.addItem(signInItem)
            menu.addItem(.separator())
            menu.addItem(self.actionItem(title: "Preferences…", action: #selector(self.target.openPreferences), keyEquivalent: ","))
            menu.addItem(self.actionItem(title: "About RepoBar", action: #selector(self.target.openAbout)))
            menu.addItem(self.actionItem(title: "Quit RepoBar", action: #selector(self.target.quitApp), keyEquivalent: "q"))
            return
        case .loggingIn:
            let loggedOut = MenuLoggedOutView()
                .padding(.horizontal, MenuStyle.sectionHorizontalPadding)
                .padding(.vertical, MenuStyle.sectionVerticalPadding)
            menu.addItem(self.viewItem(for: loggedOut, enabled: false))
            menu.addItem(.separator())
            let signInItem = self.actionItem(title: "Signing in…", action: #selector(self.target.signIn))
            signInItem.isEnabled = false
            menu.addItem(signInItem)
            menu.addItem(.separator())
            menu.addItem(self.actionItem(title: "Preferences…", action: #selector(self.target.openPreferences), keyEquivalent: ","))
            menu.addItem(self.actionItem(title: "About RepoBar", action: #selector(self.target.openAbout)))
            menu.addItem(self.actionItem(title: "Quit RepoBar", action: #selector(self.target.quitApp), keyEquivalent: "q"))
            return
        case .loggedIn:
            break
        }

        if let reset = session.rateLimitReset {
            let banner = RateLimitBanner(reset: reset)
                .padding(.horizontal, MenuStyle.bannerHorizontalPadding)
                .padding(.vertical, MenuStyle.bannerVerticalPadding)
            menu.addItem(self.viewItem(for: banner, enabled: false))
            menu.addItem(.separator())
        } else if let error = session.lastError {
            let banner = ErrorBanner(message: error)
                .padding(.horizontal, MenuStyle.bannerHorizontalPadding)
                .padding(.vertical, MenuStyle.bannerVerticalPadding)
            menu.addItem(self.viewItem(for: banner, enabled: false))
            menu.addItem(.separator())
        }

        let showFilters = session.hasLoadedRepositories
        if showFilters {
            let filters = MenuRepoFiltersView(session: session)
                .padding(.horizontal, 0)
                .padding(.vertical, 0)
            menu.addItem(self.viewItem(for: filters, enabled: true))
            menu.addItem(.separator())
        }

        if repos.isEmpty {
            let (title, subtitle) = self.emptyStateMessage(for: session)
            let emptyState = MenuEmptyStateView(title: title, subtitle: subtitle)
                .padding(.horizontal, MenuStyle.sectionHorizontalPadding)
                .padding(.vertical, MenuStyle.sectionVerticalPadding)
            menu.addItem(self.viewItem(for: emptyState, enabled: false))
        } else {
            var usedRepoKeys: Set<String> = []
            for (index, repo) in repos.enumerated() {
                let isPinned = settings.repoList.pinnedRepositories.contains(repo.title)
                let item = self.repoMenuItem(for: repo, isPinned: isPinned)
                item.representedObject = repo.title
                menu.addItem(item)
                if index < repos.count - 1 {
                    menu.addItem(self.repoCardSeparator())
                }
                usedRepoKeys.insert(repo.title)
            }
            self.repoMenuItemCache = self.repoMenuItemCache.filter { usedRepoKeys.contains($0.key) }
            self.repoSubmenuCache = self.repoSubmenuCache.filter { usedRepoKeys.contains($0.key) }
        }

        menu.addItem(self.paddedSeparator())
        menu.addItem(self.actionItem(title: "Preferences…", action: #selector(self.target.openPreferences), keyEquivalent: ","))
        menu.addItem(self.actionItem(title: "About RepoBar", action: #selector(self.target.openAbout)))
        if SparkleController.shared.updateStatus.isUpdateReady {
            menu.addItem(self.actionItem(title: "Restart to update", action: #selector(self.target.checkForUpdates)))
        }
        menu.addItem(self.actionItem(title: "Quit RepoBar", action: #selector(self.target.quitApp), keyEquivalent: "q"))
    }

    func makeRepoSubmenu(for repo: RepositoryDisplayModel, isPinned: Bool) -> NSMenu {
        let signpost = self.signposter.beginInterval("makeRepoSubmenu")
        defer { self.signposter.endInterval("makeRepoSubmenu", signpost) }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self.target
        let settings = self.appState.session.settings

        let openRow = RecentListSubmenuRowView(
            title: "Open \(repo.title)",
            systemImage: "folder",
            badgeText: nil,
            onOpen: { [weak target] in
                target?.openRepoFromMenu(fullName: repo.title)
            }
        )
        menu.addItem(self.viewItem(for: openRow, enabled: true, highlightable: true))

        menu.addItem(self.recentListSubmenuItem(RecentListConfig(
            title: "Issues",
            systemImage: "exclamationmark.circle",
            fullName: repo.title,
            kind: .issues,
            openTitle: "Open Issues",
            openAction: #selector(self.target.openIssues),
            badgeText: repo.issues > 0 ? StatValueFormatter.compact(repo.issues) : nil
        )))
        menu.addItem(self.recentListSubmenuItem(RecentListConfig(
            title: "Pull Requests",
            systemImage: "arrow.triangle.branch",
            fullName: repo.title,
            kind: .pullRequests,
            openTitle: "Open Pull Requests",
            openAction: #selector(self.target.openPulls),
            badgeText: repo.pulls > 0 ? StatValueFormatter.compact(repo.pulls) : nil
        )))
        let cachedReleaseCount = self.target.cachedRecentListCount(fullName: repo.title, kind: .releases)
        menu.addItem(self.recentListSubmenuItem(RecentListConfig(
            title: "Releases",
            systemImage: "tag",
            fullName: repo.title,
            kind: .releases,
            openTitle: "Open Releases",
            openAction: #selector(self.target.openReleases),
            badgeText: cachedReleaseCount.flatMap { $0 > 0 ? String($0) : nil }
        )))
        let runBadge = repo.ciRunCount.flatMap { $0 > 0 ? String($0) : nil }
        menu.addItem(self.recentListSubmenuItem(RecentListConfig(
            title: "CI Runs",
            systemImage: "bolt",
            fullName: repo.title,
            kind: .ciRuns,
            openTitle: "Open Actions",
            openAction: #selector(self.target.openActions),
            badgeText: runBadge
        )))
        let cachedDiscussionCount = self.target.cachedRecentListCount(fullName: repo.title, kind: .discussions)
        menu.addItem(self.recentListSubmenuItem(RecentListConfig(
            title: "Discussions",
            systemImage: "bubble.left.and.bubble.right",
            fullName: repo.title,
            kind: .discussions,
            openTitle: "Open Discussions",
            openAction: #selector(self.target.openDiscussions),
            badgeText: cachedDiscussionCount.flatMap { $0 > 0 ? String($0) : nil }
        )))
        let cachedTagCount = self.target.cachedRecentListCount(fullName: repo.title, kind: .tags)
        menu.addItem(self.recentListSubmenuItem(RecentListConfig(
            title: "Tags",
            systemImage: "tag",
            fullName: repo.title,
            kind: .tags,
            openTitle: "Open Tags",
            openAction: #selector(self.target.openTags),
            badgeText: cachedTagCount.flatMap { $0 > 0 ? String($0) : nil }
        )))
        let cachedBranchCount = self.target.cachedRecentListCount(fullName: repo.title, kind: .branches)
        menu.addItem(self.recentListSubmenuItem(RecentListConfig(
            title: "Branches",
            systemImage: "point.topleft.down.curvedto.point.bottomright.up",
            fullName: repo.title,
            kind: .branches,
            openTitle: "Open Branches",
            openAction: #selector(self.target.openBranches),
            badgeText: cachedBranchCount.flatMap { $0 > 0 ? String($0) : nil }
        )))
        let cachedContributorCount = self.target.cachedRecentListCount(fullName: repo.title, kind: .contributors)
        menu.addItem(self.recentListSubmenuItem(RecentListConfig(
            title: "Contributors",
            systemImage: "person.2",
            fullName: repo.title,
            kind: .contributors,
            openTitle: "Open Contributors",
            openAction: #selector(self.target.openContributors),
            badgeText: cachedContributorCount.flatMap { $0 > 0 ? String($0) : nil }
        )))

        if repo.activityURL != nil {
            menu.addItem(self.actionItem(
                title: "Open Activity",
                action: #selector(self.target.openActivity),
                represented: repo.title,
                systemImage: "clock.arrow.circlepath"
            ))
        }
        if let local = repo.localStatus {
            menu.addItem(self.actionItem(
                title: "Open in Finder",
                action: #selector(self.target.openLocalFinder),
                represented: local.path,
                systemImage: "folder"
            ))
            menu.addItem(self.actionItem(
                title: "Open in Terminal",
                action: #selector(self.target.openLocalTerminal),
                represented: local.path,
                systemImage: "terminal"
            ))
        }

        if settings.heatmap.display == .submenu, !repo.heatmap.isEmpty {
            let filtered = HeatmapFilter.filter(repo.heatmap, range: self.appState.session.heatmapRange)
            let heatmap = VStack(spacing: 4) {
                HeatmapView(
                    cells: filtered,
                    accentTone: settings.appearance.accentTone,
                    height: MenuStyle.heatmapSubmenuHeight
                )
                HeatmapAxisLabelsView(range: self.appState.session.heatmapRange, foregroundStyle: Color.secondary)
            }
            .padding(.horizontal, MenuStyle.cardHorizontalPadding)
            .padding(.vertical, MenuStyle.cardVerticalPadding)
            menu.addItem(.separator())
            menu.addItem(self.viewItem(for: heatmap, enabled: false))
        }

        let events = Array(repo.activityEvents.prefix(10))
        if events.isEmpty == false {
            menu.addItem(.separator())
            menu.addItem(self.infoItem("Activity"))
            events.forEach { menu.addItem(self.repoActivityItem(for: $0)) }
        }

        let detailItems = self.repoDetailItems(for: repo)
        if !detailItems.isEmpty {
            menu.addItem(.separator())
            menu.addItem(self.infoItem("Details"))
            detailItems.forEach { menu.addItem($0) }
        }

        menu.addItem(.separator())

        if isPinned {
            menu.addItem(self.actionItem(
                title: "Unpin",
                action: #selector(self.target.unpinRepo),
                represented: repo.title,
                systemImage: "pin.slash"
            ))
        } else {
            menu.addItem(self.actionItem(
                title: "Pin",
                action: #selector(self.target.pinRepo),
                represented: repo.title,
                systemImage: "pin"
            ))
        }
        menu.addItem(self.actionItem(
            title: "Hide",
            action: #selector(self.target.hideRepo),
            represented: repo.title,
            systemImage: "eye.slash"
        ))

        if isPinned {
            let pins = self.appState.session.settings.repoList.pinnedRepositories
            if let index = pins.firstIndex(of: repo.title) {
                let moveUp = self.actionItem(
                    title: "Move Up",
                    action: #selector(self.target.moveRepoUp),
                    represented: repo.title,
                    systemImage: "arrow.up"
                )
                moveUp.isEnabled = index > 0
                let moveDown = self.actionItem(
                    title: "Move Down",
                    action: #selector(self.target.moveRepoDown),
                    represented: repo.title,
                    systemImage: "arrow.down"
                )
                moveDown.isEnabled = index < pins.count - 1
                menu.addItem(.separator())
                menu.addItem(moveUp)
                menu.addItem(moveDown)
            }
        }

        return menu
    }

    private struct RecentListConfig {
        let title: String
        let systemImage: String
        let fullName: String
        let kind: RepoRecentMenuKind
        let openTitle: String
        let openAction: Selector
        let badgeText: String?
    }

    private func recentListSubmenuItem(_ config: RecentListConfig) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self.target
        self.target.registerRecentListMenu(
            submenu,
            context: RepoRecentMenuContext(fullName: config.fullName, kind: config.kind)
        )

        submenu.addItem(self.actionItem(
            title: config.openTitle,
            action: config.openAction,
            represented: config.fullName,
            systemImage: config.systemImage
        ))
        submenu.addItem(.separator())
        let loading = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
        loading.isEnabled = false
        submenu.addItem(loading)

        let row = RecentListSubmenuRowView(
            title: config.title,
            systemImage: config.systemImage,
            badgeText: config.badgeText
        )
        return self.viewItem(for: row, enabled: true, highlightable: true, submenu: submenu)
    }

    func refreshMenuViewHeights(in menu: NSMenu) {
        let signpost = self.signposter.beginInterval("refreshMenuViewHeights")
        defer { self.signposter.endInterval("refreshMenuViewHeights", signpost) }
        self.refreshMenuViewHeights(in: menu, width: self.menuWidth(for: menu))
    }

    func refreshMenuViewHeights(in menu: NSMenu, width: CGFloat) {
        let signpost = self.signposter.beginInterval("refreshMenuViewHeightsWidth")
        defer { self.signposter.endInterval("refreshMenuViewHeightsWidth", signpost) }
        for item in menu.items {
            guard let view = item.view,
                  let measuring = view as? MenuItemMeasuring else { continue }
            let height = measuring.measuredHeight(width: width)
            if abs(view.frame.size.height - height) > 0.5 || view.frame.size.width != width {
                view.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
            }
        }
    }

    func clearHighlights(in menu: NSMenu) {
        for item in menu.items {
            (item.view as? MenuItemHighlighting)?.setHighlighted(false)
        }
    }

    func menuWidth(for menu: NSMenu) -> CGFloat {
        let signpost = self.signposter.beginInterval("menuWidth")
        defer { self.signposter.endInterval("menuWidth", signpost) }
        if let view = menu.items.compactMap(\.view).first {
            if let contentWidth = view.window?.contentView?.bounds.width, contentWidth > 0 {
                return max(contentWidth, Self.menuFixedWidth)
            }
            if let windowWidth = view.window?.frame.width, windowWidth > 0 {
                return max(windowWidth, Self.menuFixedWidth)
            }
        }
        let menuWidth = menu.size.width
        if menuWidth > 0 { return max(menuWidth, Self.menuFixedWidth) }
        return Self.menuFixedWidth
    }

    private func repoDetailItems(for repo: RepositoryDisplayModel) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if let error = repo.error, RepositoryErrorClassifier.isNonCriticalMenuWarning(error) {
            items.append(self.infoItem(error))
        }
        if let local = repo.localStatus {
            items.append(self.infoItem("Branch: \(local.branch)"))
            items.append(self.infoItem("Sync: \(local.syncDetail)"))
        }
        if let visitors = repo.trafficVisitors {
            items.append(self.infoItem("Visitors (14d): \(visitors)"))
        }
        if let cloners = repo.trafficCloners {
            items.append(self.infoItem("Cloners (14d): \(cloners)"))
        }
        return items
    }

    private func paddedSeparator() -> NSMenuItem {
        self.viewItem(for: MenuPaddedSeparatorView(), enabled: false)
    }

    private func repoCardSeparator() -> NSMenuItem {
        self.viewItem(for: RepoCardSeparatorRowView(), enabled: false)
    }

    private func repoMenuItem(for repo: RepositoryDisplayModel, isPinned: Bool) -> NSMenuItem {
        let card = RepoMenuCardView(
            repo: repo,
            isPinned: isPinned,
            showHeatmap: self.appState.session.settings.heatmap.display == .inline,
            heatmapRange: self.appState.session.heatmapRange,
            accentTone: self.appState.session.settings.appearance.accentTone,
            onOpen: { [weak target] in
                target?.openRepoFromMenu(fullName: repo.title)
            }
        )
        let submenu = self.repoSubmenu(for: repo, isPinned: isPinned)
        if let cached = self.repoMenuItemCache[repo.title], let view = cached.view as? MenuItemHostingView {
            view.updateHighlightableRootView(AnyView(card), showsSubmenuIndicator: true)
            cached.isEnabled = true
            cached.submenu = submenu
            cached.target = self.target
            cached.action = #selector(self.target.menuItemNoOp(_:))
            return cached
        }
        let item = self.viewItem(for: card, enabled: true, highlightable: true, submenu: submenu)
        self.repoMenuItemCache[repo.title] = item
        return item
    }

    private func repoSubmenu(for repo: RepositoryDisplayModel, isPinned: Bool) -> NSMenu {
        let signature = RepoSubmenuSignature(
            repo: repo,
            settings: self.appState.session.settings,
            heatmapRange: self.appState.session.heatmapRange,
            recentCounts: RepoRecentCountSignature(
                releases: self.target.cachedRecentListCount(fullName: repo.title, kind: .releases),
                discussions: self.target.cachedRecentListCount(fullName: repo.title, kind: .discussions),
                tags: self.target.cachedRecentListCount(fullName: repo.title, kind: .tags),
                branches: self.target.cachedRecentListCount(fullName: repo.title, kind: .branches),
                contributors: self.target.cachedRecentListCount(fullName: repo.title, kind: .contributors)
            ),
            isPinned: isPinned
        )
        if let cached = self.repoSubmenuCache[repo.title], cached.signature == signature {
            return cached.menu
        }
        let menu = self.makeRepoSubmenu(for: repo, isPinned: isPinned)
        self.repoSubmenuCache[repo.title] = RepoSubmenuCacheEntry(menu: menu, signature: signature)
        return menu
    }

    private func repoActivityItem(for event: ActivityEvent) -> NSMenuItem {
        let view = ActivityMenuItemView(event: event, symbolName: self.activitySymbolName(for: event)) { [weak target] in
            target?.open(url: event.url)
        }
        return self.viewItem(for: view, enabled: true, highlightable: true)
    }

    private func activitySymbolName(for event: ActivityEvent) -> String {
        guard let type = event.eventTypeEnum else { return "clock" }
        switch type {
        case .pullRequest: return "arrow.triangle.branch"
        case .pullRequestReview: return "checkmark.bubble"
        case .pullRequestReviewComment: return "text.bubble"
        case .pullRequestReviewThread: return "text.bubble"
        case .issueComment: return "text.bubble"
        case .issues: return "exclamationmark.circle"
        case .push: return "arrow.up.circle"
        case .release: return "tag"
        case .watch: return "star"
        case .fork: return "doc.on.doc"
        case .create: return "plus"
        case .delete: return "trash"
        case .member: return "person.badge.plus"
        case .public: return "globe"
        case .gollum: return "book"
        case .commitComment: return "text.bubble"
        case .discussion: return "bubble.left.and.bubble.right"
        case .sponsorship: return "heart"
        }
    }

    private func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        represented: Any? = nil,
        systemImage: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self.target
        if let represented { item.representedObject = represented }
        if let systemImage, let image = self.cachedSystemImage(named: systemImage) {
            item.image = image
        }
        return item
    }

    private func cachedSystemImage(named name: String) -> NSImage? {
        let key = "\(name)|\(self.isLightAppearance ? "light" : "dark")"
        if let cached = self.systemImageCache[key] {
            return cached
        }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        image.size = NSSize(width: 14, height: 14)
        if name == "eye.slash", self.isLightAppearance {
            let config = NSImage.SymbolConfiguration(hierarchicalColor: .secondaryLabelColor)
            let tinted = image.withSymbolConfiguration(config)
            tinted?.isTemplate = false
            if let tinted {
                self.systemImageCache[key] = tinted
                return tinted
            }
        }
        image.isTemplate = true
        self.systemImageCache[key] = image
        return image
    }

    private func viewItem(
        for content: some View,
        enabled: Bool,
        highlightable: Bool = false,
        submenu: NSMenu? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = enabled
        if highlightable {
            let highlightState = MenuItemHighlightState()
            let wrapped = MenuItemContainerView(
                highlightState: highlightState,
                showsSubmenuIndicator: submenu != nil
            ) {
                content
            }
            item.view = MenuItemHostingView(rootView: AnyView(wrapped), highlightState: highlightState)
        } else {
            item.view = MenuItemHostingView(rootView: AnyView(content))
        }
        item.submenu = submenu
        if submenu != nil {
            item.target = self.target
            item.action = #selector(self.target.menuItemNoOp(_:))
        }
        return item
    }

    private func orderedViewModels(now: Date) -> [RepositoryDisplayModel] {
        let session = self.appState.session
        let selection = session.menuRepoSelection
        let settings = session.settings
        let scope: RepositoryScope = selection.isPinnedScope ? .pinned : .all
        let query = RepositoryQuery(
            scope: scope,
            onlyWith: selection.onlyWith,
            includeForks: settings.repoList.showForks,
            includeArchived: settings.repoList.showArchived,
            sortKey: settings.repoList.menuSortKey,
            limit: settings.repoList.displayLimit,
            pinned: settings.repoList.pinnedRepositories,
            hidden: Set(settings.repoList.hiddenRepositories),
            pinPriority: true
        )
        let baseRepos = session.repositories.isEmpty
            ? (session.menuSnapshot?.repositories ?? [])
            : session.repositories
        let sorted = RepositoryPipeline.apply(baseRepos, query: query)
        let displayIndex = session.menuDisplayIndex
        return sorted.map { repo in
            displayIndex[repo.fullName]
                ?? RepositoryDisplayModel(
                    repo: repo,
                    localStatus: session.localRepoIndex.status(for: repo),
                    now: now
                )
        }
    }

    private func emptyStateMessage(for session: Session) -> (String, String) {
        let hasPinned = !session.settings.repoList.pinnedRepositories.isEmpty
        let isPinnedScope = session.menuRepoSelection.isPinnedScope
        let hasFilter = session.menuRepoSelection.onlyWith.isActive
        if isPinnedScope, !hasPinned {
            return ("No pinned repositories", "Pin a repository to see activity here.")
        }
        if isPinnedScope || hasFilter {
            return ("No repositories match this filter", "Try All or a different filter.")
        }
        return ("No repositories yet", "Pin a repository to see activity here.")
    }

    private func currentUsername() -> String? {
        if case let .loggedIn(user) = self.appState.session.account { return user.username }
        return nil
    }

    private func currentDisplayName() -> String? {
        guard case let .loggedIn(user) = self.appState.session.account else { return nil }
        let host = user.host.host ?? "github.com"
        return "\(user.username)@\(host)"
    }

    private var isLightAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }
}

struct MainMenuPlan {
    let repos: [RepositoryDisplayModel]
    let signature: MenuBuildSignature
}

struct MenuBuildSignature: Hashable {
    let account: AccountSignature
    let settings: MenuSettingsSignature
    let hasLoadedRepositories: Bool
    let rateLimitReset: Date?
    let lastError: String?
    let contribution: ContributionSignature
    let heatmapRangeStart: TimeInterval
    let heatmapRangeEnd: TimeInterval
    let reposDigest: Int
    let timeBucket: Int
}

struct AccountSignature: Hashable {
    let state: String
    let user: String?
    let host: String?

    init(_ account: AccountState) {
        switch account {
        case .loggedOut:
            self.state = "loggedOut"
            self.user = nil
            self.host = nil
        case .loggingIn:
            self.state = "loggingIn"
            self.user = nil
            self.host = nil
        case let .loggedIn(user):
            self.state = "loggedIn"
            self.user = user.username
            self.host = user.host.host
        }
    }
}

struct MenuSettingsSignature: Hashable {
    let showContributionHeader: Bool
    let cardDensity: CardDensity
    let accentTone: AccentTone
    let heatmapDisplay: HeatmapDisplay
    let heatmapSpan: HeatmapSpan
    let displayLimit: Int
    let showForks: Bool
    let showArchived: Bool
    let menuSortKey: RepositorySortKey
    let pinned: [String]
    let hidden: [String]
    let selection: MenuRepoSelection

    init(settings: UserSettings, selection: MenuRepoSelection) {
        self.showContributionHeader = settings.appearance.showContributionHeader
        self.cardDensity = settings.appearance.cardDensity
        self.accentTone = settings.appearance.accentTone
        self.heatmapDisplay = settings.heatmap.display
        self.heatmapSpan = settings.heatmap.span
        self.displayLimit = settings.repoList.displayLimit
        self.showForks = settings.repoList.showForks
        self.showArchived = settings.repoList.showArchived
        self.menuSortKey = settings.repoList.menuSortKey
        self.pinned = settings.repoList.pinnedRepositories
        self.hidden = settings.repoList.hiddenRepositories
        self.selection = selection
    }
}

struct ContributionSignature: Hashable {
    let user: String?
    let error: String?
    let heatmapCount: Int
}

struct RepoSignature: Hashable {
    let fullName: String
    let ciStatus: CIStatus
    let ciRunCount: Int?
    let issues: Int
    let pulls: Int
    let stars: Int
    let forks: Int
    let pushedAt: Date?
    let latestReleaseTag: String?
    let latestActivityDate: Date?
    let activityEventCount: Int
    let trafficVisitors: Int?
    let trafficCloners: Int?
    let heatmapCount: Int
    let error: String?
    let rateLimitedUntil: Date?
    let localBranch: String?
    let localSyncState: LocalSyncState?
    let localDirtySummary: String?

    static func digest(for repos: [RepositoryDisplayModel]) -> Int {
        var hasher = Hasher()
        repos.map(Self.init).forEach { hasher.combine($0) }
        return hasher.finalize()
    }

    init(_ repo: RepositoryDisplayModel) {
        self.fullName = repo.title
        self.ciStatus = repo.ciStatus
        self.ciRunCount = repo.ciRunCount
        self.issues = repo.issues
        self.pulls = repo.pulls
        self.stars = repo.stars
        self.forks = repo.forks
        self.pushedAt = repo.source.stats.pushedAt
        self.latestReleaseTag = repo.source.latestRelease?.tag
        self.latestActivityDate = repo.source.latestActivity?.date
        self.activityEventCount = repo.activityEvents.count
        self.trafficVisitors = repo.trafficVisitors
        self.trafficCloners = repo.trafficCloners
        self.heatmapCount = repo.heatmap.count
        self.error = repo.error
        self.rateLimitedUntil = repo.rateLimitedUntil
        self.localBranch = repo.localStatus?.branch
        self.localSyncState = repo.localStatus?.syncState
        self.localDirtySummary = repo.localStatus?.dirtyCounts?.summary
    }
}

struct RepoSubmenuCacheEntry {
    let menu: NSMenu
    let signature: RepoSubmenuSignature
}

struct RepoRecentCountSignature: Hashable {
    let releases: Int?
    let discussions: Int?
    let tags: Int?
    let branches: Int?
    let contributors: Int?
}

struct RepoSubmenuSignature: Hashable {
    let fullName: String
    let issues: Int
    let pulls: Int
    let ciRunCount: Int?
    let activityURLPresent: Bool
    let localPath: String?
    let localBranch: String?
    let localSyncState: LocalSyncState?
    let localDirtySummary: String?
    let trafficVisitors: Int?
    let trafficCloners: Int?
    let heatmapDisplay: HeatmapDisplay
    let heatmapCount: Int
    let heatmapRangeStart: TimeInterval
    let heatmapRangeEnd: TimeInterval
    let activityDigest: Int
    let recentCounts: RepoRecentCountSignature
    let isPinned: Bool

    init(
        repo: RepositoryDisplayModel,
        settings: UserSettings,
        heatmapRange: HeatmapRange,
        recentCounts: RepoRecentCountSignature,
        isPinned: Bool
    ) {
        self.fullName = repo.title
        self.issues = repo.issues
        self.pulls = repo.pulls
        self.ciRunCount = repo.ciRunCount
        self.activityURLPresent = repo.activityURL != nil
        self.localPath = repo.localStatus?.path.path
        self.localBranch = repo.localStatus?.branch
        self.localSyncState = repo.localStatus?.syncState
        self.localDirtySummary = repo.localStatus?.dirtyCounts?.summary
        self.trafficVisitors = repo.trafficVisitors
        self.trafficCloners = repo.trafficCloners
        self.heatmapDisplay = settings.heatmap.display
        self.heatmapCount = repo.heatmap.count
        self.heatmapRangeStart = heatmapRange.start.timeIntervalSinceReferenceDate
        self.heatmapRangeEnd = heatmapRange.end.timeIntervalSinceReferenceDate
        self.activityDigest = RepoSubmenuSignature.digest(events: repo.activityEvents)
        self.recentCounts = recentCounts
        self.isPinned = isPinned
    }

    private static func digest(events: [ActivityEvent]) -> Int {
        var hasher = Hasher()
        events.prefix(10).forEach { event in
            hasher.combine(event.title)
            hasher.combine(event.actor)
            hasher.combine(event.date.timeIntervalSinceReferenceDate)
            hasher.combine(event.eventType ?? "")
        }
        return hasher.finalize()
    }
}
