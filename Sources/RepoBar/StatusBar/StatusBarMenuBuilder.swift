import AppKit
import RepoBarCore
import SwiftUI

@MainActor
final class StatusBarMenuBuilder {
    private static let menuFixedWidth: CGFloat = 360

    private let appState: AppState
    private unowned let target: StatusBarMenuManager

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

    func populateMainMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let session = self.appState.session
        let settings = session.settings

        if settings.appearance.showContributionHeader,
           let username = self.currentUsername(),
           let displayName = self.currentDisplayName()
        {
            let header = ContributionHeaderView(
                username: username,
                displayName: displayName,
                session: session,
                appState: self.appState
            )
            .padding(.horizontal, MenuStyle.headerHorizontalPadding)
            .padding(.top, MenuStyle.headerTopPadding)
            .padding(.bottom, MenuStyle.headerBottomPadding)
            menu.addItem(self.viewItem(for: header, enabled: true, highlightable: true))
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

        let repos = self.orderedViewModels()
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
            for (index, repo) in repos.enumerated() {
                let isPinned = settings.repoList.pinnedRepositories.contains(repo.title)
                let card = RepoMenuCardView(
                    repo: repo,
                    isPinned: isPinned,
                    showsSeparator: index < repos.count - 1,
                    showHeatmap: settings.heatmap.display == .inline,
                    heatmapRange: session.heatmapRange,
                    accentTone: settings.appearance.accentTone,
                    onOpen: { [weak target] in
                        target?.openRepoFromMenu(fullName: repo.title)
                    }
                )
                let submenu = self.makeRepoSubmenu(for: repo, isPinned: isPinned)
                let item = self.viewItem(for: card, enabled: true, highlightable: true, submenu: submenu)
                item.representedObject = repo.title
                menu.addItem(item)
            }
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
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self.target
        let settings = self.appState.session.settings

        menu.addItem(self.actionItem(
            title: "Open \(repo.title)",
            action: #selector(self.target.openRepo),
            represented: repo.title,
            systemImage: "folder"
        ))

        menu.addItem(self.recentListSubmenuItem(
            title: "Issues",
            systemImage: "exclamationmark.circle",
            fullName: repo.title,
            kind: .issues,
            openTitle: "Open Issues",
            openAction: #selector(self.target.openIssues),
            badgeText: repo.issues > 0 ? StatValueFormatter.compact(repo.issues) : nil
        ))
        menu.addItem(self.recentListSubmenuItem(
            title: "Pull Requests",
            systemImage: "arrow.triangle.branch",
            fullName: repo.title,
            kind: .pullRequests,
            openTitle: "Open Pull Requests",
            openAction: #selector(self.target.openPulls),
            badgeText: repo.pulls > 0 ? StatValueFormatter.compact(repo.pulls) : nil
        ))
        let cachedReleaseCount = self.target.cachedRecentListCount(fullName: repo.title, kind: .releases)
        menu.addItem(self.recentListSubmenuItem(
            title: "Releases",
            systemImage: "tag",
            fullName: repo.title,
            kind: .releases,
            openTitle: "Open Releases",
            openAction: #selector(self.target.openReleases),
            badgeText: cachedReleaseCount.flatMap { $0 > 0 ? String($0) : nil }
        ))

        menu.addItem(self.actionItem(
            title: "Open Actions",
            action: #selector(self.target.openActions),
            represented: repo.title,
            systemImage: "bolt"
        ))
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
            let heatmap = HeatmapView(
                cells: filtered,
                accentTone: settings.appearance.accentTone,
                height: MenuStyle.heatmapSubmenuHeight
            )
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

        self.refreshMenuViewHeights(in: menu)
        return menu
    }

    private func recentListSubmenuItem(
        title: String,
        systemImage: String,
        fullName: String,
        kind: RepoRecentMenuKind,
        openTitle: String,
        openAction: Selector,
        badgeText: String? = nil
    ) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self.target
        self.target.registerRecentListMenu(submenu, context: RepoRecentMenuContext(fullName: fullName, kind: kind))

        submenu.addItem(self.actionItem(
            title: openTitle,
            action: openAction,
            represented: fullName,
            systemImage: systemImage
        ))
        submenu.addItem(.separator())
        let loading = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
        loading.isEnabled = false
        submenu.addItem(loading)

        let row = RecentListSubmenuRowView(title: title, systemImage: systemImage, badgeText: badgeText)
        return self.viewItem(for: row, enabled: true, highlightable: true, submenu: submenu)
    }

    func refreshMenuViewHeights(in menu: NSMenu) {
        let width = self.menuWidth(for: menu)
        for item in menu.items {
            guard let view = item.view,
                  let measuring = view as? MenuItemMeasuring else { continue }
            let height = measuring.measuredHeight(width: width)
            view.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        }
    }

    func clearHighlights(in menu: NSMenu) {
        for item in menu.items {
            (item.view as? MenuItemHighlighting)?.setHighlighted(false)
        }
    }

    private func menuWidth(for menu: NSMenu) -> CGFloat {
        if let view = menu.items.compactMap(\.view).first,
           let windowWidth = view.window?.frame.width,
           windowWidth > 0
        {
            return max(windowWidth, Self.menuFixedWidth)
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
        if let runCount = repo.ciRunCount {
            items.append(self.infoItem("CI runs: \(runCount)"))
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
        if let systemImage, let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil) {
            image.size = NSSize(width: 14, height: 14)
            if systemImage == "eye.slash", self.isLightAppearance {
                let config = NSImage.SymbolConfiguration(hierarchicalColor: .secondaryLabelColor)
                item.image = image.withSymbolConfiguration(config)
                item.image?.isTemplate = false
            } else {
                image.isTemplate = true
                item.image = image
            }
        }
        return item
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

    private func orderedViewModels() -> [RepositoryDisplayModel] {
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
        return sorted.map { repo in
            RepositoryDisplayModel(repo: repo, localStatus: session.localRepoIndex.status(for: repo))
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
