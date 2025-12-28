import AppKit
import Observation
import RepoBarCore
import SwiftUI

@MainActor
final class StatusBarMenuManager: NSObject, NSMenuDelegate {
    private static let menuFixedWidth: CGFloat = 360

    private let appState: AppState
    private var mainMenu: NSMenu?
    private var lastMenuRefresh: Date?
    private let menuRefreshInterval: TimeInterval = 30

    init(appState: AppState) {
        self.appState = appState
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.menuFiltersChanged),
            name: .menuFiltersDidChange,
            object: nil
        )
    }

    func attachMainMenu(to statusItem: NSStatusItem) {
        let menu = self.mainMenu ?? self.makeMainMenu()
        self.mainMenu = menu
        statusItem.menu = menu
    }

    // MARK: - Menu actions

    @objc private func refreshNow() {
        self.appState.refreshScheduler.forceRefresh()
    }

    @objc private func openPreferences() {
        SettingsOpener.shared.open()
    }

    @objc private func openAbout() {
        AppActions.openAbout()
    }

    @objc private func checkForUpdates() {
        SparkleController.shared.checkForUpdates()
    }

    @objc private func menuFiltersChanged() {
        guard let menu = self.mainMenu else { return }
        self.appState.persistSettings()
        self.populateMainMenu(menu)
        self.refreshMenuViewHeights(in: menu)
        menu.update()
    }

    @objc private func logOut() {
        Task { @MainActor in
            await self.appState.auth.logout()
            self.appState.session.account = .loggedOut
            self.appState.session.repositories = []
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func signIn() {
        Task { await self.appState.quickLogin() }
    }

    @objc private func openRepo(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender),
              let url = self.repoURL(for: fullName) else { return }
        self.open(url: url)
    }

    private func openRepoFromMenu(fullName: String) {
        guard let url = self.repoURL(for: fullName) else { return }
        self.open(url: url)
    }

    @objc private func openIssues(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "issues")
    }

    @objc private func openPulls(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "pulls")
    }

    @objc private func openActions(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "actions")
    }

    @objc private func openReleases(_ sender: NSMenuItem) {
        self.openRepoPath(sender: sender, path: "releases")
    }

    @objc private func openLatestRelease(_ sender: NSMenuItem) {
        guard let repo = self.repoModel(from: sender),
              let url = repo.source.latestRelease?.url else { return }
        self.open(url: url)
    }

    @objc private func openActivity(_ sender: NSMenuItem) {
        guard let repo = self.repoModel(from: sender),
              let url = repo.activityURL else { return }
        self.open(url: url)
    }

    @objc private func openActivityEvent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        self.open(url: url)
    }

    @objc private func copyRepoName(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(fullName, forType: .string)
    }

    @objc private func copyRepoURL(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender),
              let url = self.repoURL(for: fullName) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
    }

    @objc private func pinRepo(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender) else { return }
        Task { await self.appState.addPinned(fullName) }
    }

    @objc private func unpinRepo(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender) else { return }
        Task { await self.appState.removePinned(fullName) }
    }

    @objc private func hideRepo(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender) else { return }
        Task { await self.appState.hide(fullName) }
    }

    @objc private func moveRepoUp(_ sender: NSMenuItem) {
        self.moveRepo(sender: sender, direction: -1)
    }

    @objc private func moveRepoDown(_ sender: NSMenuItem) {
        self.moveRepo(sender: sender, direction: 1)
    }

    private func moveRepo(sender: NSMenuItem, direction: Int) {
        guard let fullName = self.repoFullName(from: sender) else { return }
        var pins = self.appState.session.settings.pinnedRepositories
        guard let currentIndex = pins.firstIndex(of: fullName) else { return }
        let maxIndex = max(pins.count - 1, 0)
        let target = max(0, min(maxIndex, currentIndex + direction))
        guard target != currentIndex else { return }
        pins.move(fromOffsets: IndexSet(integer: currentIndex), toOffset: target > currentIndex ? target + 1 : target)
        self.appState.session.settings.pinnedRepositories = pins
        self.appState.persistSettings()
        Task { await self.appState.refresh() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.appearance = NSApp.effectiveAppearance
        if menu === self.mainMenu {
            self.refreshIfNeededOnOpen()
            self.populateMainMenu(menu)
            self.refreshMenuViewHeights(in: menu)
            DispatchQueue.main.async { [weak self] in
                self?.clearHighlights(in: menu)
            }
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === self.mainMenu {
            self.clearHighlights(in: menu)
        }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for menuItem in menu.items {
            guard let view = menuItem.view as? MenuItemHighlighting else { continue }
            let highlighted = menuItem == item && menuItem.isEnabled
            view.setHighlighted(highlighted)
        }
    }

    // MARK: - Main menu

    private func makeMainMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.appearance = nil
        return menu
    }

    private func populateMainMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let session = self.appState.session
        let settings = session.settings

        if settings.showContributionHeader,
           settings.showHeatmap,
           let username = self.currentUsername(),
           let displayName = self.currentDisplayName()
        {
            let header = ContributionHeaderView(
                username: username,
                displayName: displayName,
                session: session,
                appState: self.appState
            )
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)
            menu.addItem(self.viewItem(for: header, enabled: true, highlightable: true))
            menu.addItem(.separator())
        }

        switch session.account {
        case .loggedOut:
            let loggedOut = MenuLoggedOutView()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            menu.addItem(self.viewItem(for: loggedOut, enabled: false))
            menu.addItem(.separator())
            let signInItem = self.actionItem(title: "Sign in to GitHub", action: #selector(self.signIn))
            menu.addItem(signInItem)
            menu.addItem(.separator())
            menu.addItem(self.actionItem(title: "Preferences…", action: #selector(self.openPreferences), keyEquivalent: ","))
            menu.addItem(self.actionItem(title: "About RepoBar", action: #selector(self.openAbout)))
            menu.addItem(self.actionItem(title: "Quit RepoBar", action: #selector(self.quitApp), keyEquivalent: "q"))
            return
        case .loggingIn:
            let loggedOut = MenuLoggedOutView()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            menu.addItem(self.viewItem(for: loggedOut, enabled: false))
            menu.addItem(.separator())
            let signInItem = self.actionItem(title: "Signing in…", action: #selector(self.signIn))
            signInItem.isEnabled = false
            menu.addItem(signInItem)
            menu.addItem(.separator())
            menu.addItem(self.actionItem(title: "Preferences…", action: #selector(self.openPreferences), keyEquivalent: ","))
            menu.addItem(self.actionItem(title: "About RepoBar", action: #selector(self.openAbout)))
            menu.addItem(self.actionItem(title: "Quit RepoBar", action: #selector(self.quitApp), keyEquivalent: "q"))
            return
        case .loggedIn:
            break
        }

        if let reset = session.rateLimitReset {
            let banner = RateLimitBanner(reset: reset)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            menu.addItem(self.viewItem(for: banner, enabled: false))
            menu.addItem(.separator())
        } else if let error = session.lastError {
            let banner = ErrorBanner(message: error)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            menu.addItem(self.viewItem(for: emptyState, enabled: false))
        } else {
            for (index, repo) in repos.enumerated() {
                let isPinned = settings.pinnedRepositories.contains(repo.title)
                let card = RepoMenuCardView(
                    repo: repo,
                    isPinned: isPinned,
                    showsSeparator: index < repos.count - 1,
                    showHeatmap: settings.showHeatmap,
                    heatmapSpan: settings.heatmapSpan,
                    accentTone: settings.accentTone,
                    onOpen: { [weak self] in
                        self?.openRepoFromMenu(fullName: repo.title)
                    }
                )
                let submenu = self.makeRepoSubmenu(for: repo, isPinned: isPinned)
                let item = self.viewItem(for: card, enabled: true, highlightable: true, submenu: submenu)
                item.representedObject = repo.title
                menu.addItem(item)
            }
        }

        menu.addItem(self.paddedSeparator())
        menu.addItem(self.actionItem(title: "Preferences…", action: #selector(self.openPreferences), keyEquivalent: ","))
        menu.addItem(self.actionItem(title: "About RepoBar", action: #selector(self.openAbout)))
        if SparkleController.shared.updateStatus.isUpdateReady {
            menu.addItem(self.actionItem(title: "Restart to update", action: #selector(self.checkForUpdates)))
        }
        menu.addItem(self.actionItem(title: "Quit RepoBar", action: #selector(self.quitApp), keyEquivalent: "q"))
    }

    private func makeRepoSubmenu(for repo: RepositoryViewModel, isPinned: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(self.actionItem(
            title: "Open Repository",
            action: #selector(self.openRepo),
            represented: repo.title,
            systemImage: "folder"))
        menu.addItem(self.actionItem(
            title: "Open Issues",
            action: #selector(self.openIssues),
            represented: repo.title,
            systemImage: "exclamationmark.circle"))
        menu.addItem(self.actionItem(
            title: "Open Pull Requests",
            action: #selector(self.openPulls),
            represented: repo.title,
            systemImage: "arrow.triangle.branch"))
        menu.addItem(self.actionItem(
            title: "Open Actions",
            action: #selector(self.openActions),
            represented: repo.title,
            systemImage: "bolt"))
        menu.addItem(self.actionItem(
            title: "Open Releases",
            action: #selector(self.openReleases),
            represented: repo.title,
            systemImage: "tag"))
        if repo.source.latestRelease != nil {
            menu.addItem(self.actionItem(
                title: "Open Latest Release",
                action: #selector(self.openLatestRelease),
                represented: repo.title,
                systemImage: "tag.fill"))
        }
        if repo.activityURL != nil {
            menu.addItem(self.actionItem(
                title: "Open Latest Activity",
                action: #selector(self.openActivity),
                represented: repo.title,
                systemImage: "clock.arrow.circlepath"))
        }

        let activityItems = self.repoActivityItems(for: repo)
        if !activityItems.isEmpty {
            menu.addItem(.separator())
            menu.addItem(self.infoItem("Recent Activity"))
            activityItems.forEach { menu.addItem($0) }
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
                action: #selector(self.unpinRepo),
                represented: repo.title,
                systemImage: "pin.slash"))
        } else {
            menu.addItem(self.actionItem(
                title: "Pin",
                action: #selector(self.pinRepo),
                represented: repo.title,
                systemImage: "pin"))
        }
        menu.addItem(self.actionItem(
            title: "Hide",
            action: #selector(self.hideRepo),
            represented: repo.title,
            systemImage: "eye.slash"))

        if isPinned {
            let pins = self.appState.session.settings.pinnedRepositories
            if let index = pins.firstIndex(of: repo.title) {
                let moveUp = self.actionItem(
                    title: "Move Up",
                    action: #selector(self.moveRepoUp),
                    represented: repo.title,
                    systemImage: "arrow.up")
                moveUp.isEnabled = index > 0
                let moveDown = self.actionItem(
                    title: "Move Down",
                    action: #selector(self.moveRepoDown),
                    represented: repo.title,
                    systemImage: "arrow.down")
                moveDown.isEnabled = index < pins.count - 1
                menu.addItem(.separator())
                menu.addItem(moveUp)
                menu.addItem(moveDown)
            }
        }

        return menu
    }

    private func repoDetailItems(for repo: RepositoryViewModel) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
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

    private func repoActivityItems(for repo: RepositoryViewModel) -> [NSMenuItem] {
        let now = Date()
        return repo.activityEvents.prefix(10).map { event in
            let when = RelativeFormatter.string(from: event.date, relativeTo: now)
            let title = "\(when) • \(event.actor): \(event.title)"
            return self.actionItem(
                title: title,
                action: #selector(self.openActivityEvent),
                represented: event.url,
                systemImage: self.activitySymbolName(for: event))
        }
    }

    private func activitySymbolName(for event: ActivityEvent) -> String {
        guard let type = event.eventType else { return "clock" }
        switch type {
        case "PullRequestEvent": return "arrow.triangle.branch"
        case "PullRequestReviewEvent": return "checkmark.bubble"
        case "PullRequestReviewCommentEvent": return "text.bubble"
        case "PullRequestReviewThreadEvent": return "text.bubble"
        case "IssueCommentEvent": return "text.bubble"
        case "IssuesEvent": return "exclamationmark.circle"
        case "PushEvent": return "arrow.up.circle"
        case "ReleaseEvent": return "tag"
        case "WatchEvent": return "star"
        case "ForkEvent": return "doc.on.doc"
        case "CreateEvent": return "plus"
        case "DeleteEvent": return "trash"
        case "MemberEvent": return "person.badge.plus"
        case "GollumEvent": return "book"
        case "CommitCommentEvent": return "text.bubble"
        case "DiscussionEvent": return "bubble.left.and.bubble.right"
        case "SponsorshipEvent": return "heart"
        default: return "clock"
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
        item.target = self
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

    private func viewItem<Content: View>(
        for content: Content,
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
            item.target = self
            item.action = #selector(self.menuItemNoOp(_:))
        }
        return item
    }

    private func refreshMenuViewHeights(in menu: NSMenu) {
        let width = self.menuWidth(for: menu)
        for item in menu.items {
            guard let view = item.view,
                  let measuring = view as? MenuItemMeasuring else { continue }
            let height = measuring.measuredHeight(width: width)
            view.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        }
    }

    private func menuWidth(for _: NSMenu) -> CGFloat {
        Self.menuFixedWidth
    }

    private func clearHighlights(in menu: NSMenu) {
        for item in menu.items {
            (item.view as? MenuItemHighlighting)?.setHighlighted(false)
        }
    }

    private func orderedViewModels() -> [RepositoryViewModel] {
        let session = self.appState.session
        let repos = session.repositories
            .map { RepositoryViewModel(repo: $0) }
        let sortKey = session.settings.menuSortKey
        var sorted = repos.sorted { lhs, rhs in
            switch (lhs.sortOrder, rhs.sortOrder) {
            case let (left?, right?):
                return left < right
            case (.none, .some):
                return false
            case (.some, .none):
                return true
            default:
                return RepositorySort.isOrderedBefore(lhs.source, rhs.source, sortKey: sortKey)
            }
        }
        if session.menuRepoSelection.isPinnedScope {
            let pinned = Set(session.settings.pinnedRepositories)
            sorted = sorted.filter { pinned.contains($0.title) }
        }
        let onlyWith = session.menuRepoSelection.onlyWith
        if onlyWith.isActive {
            sorted = sorted.filter { onlyWith.matches($0.source) }
        }
        let limit = max(session.settings.repoDisplayLimit, 0)
        return Array(sorted.prefix(limit))
    }

    private func emptyStateMessage(for session: Session) -> (String, String) {
        let hasPinned = !session.settings.pinnedRepositories.isEmpty
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

    private func repoModel(from sender: NSMenuItem) -> RepositoryViewModel? {
        guard let fullName = self.repoFullName(from: sender) else { return nil }
        guard let repo = self.appState.session.repositories.first(where: { $0.fullName == fullName }) else { return nil }
        return RepositoryViewModel(repo: repo)
    }

    private func repoFullName(from sender: NSMenuItem) -> String? {
        sender.representedObject as? String
    }

    private func repoURL(for fullName: String) -> URL? {
        let parts = fullName.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        var url = self.appState.session.settings.githubHost
        url.appendPathComponent(String(parts[0]))
        url.appendPathComponent(String(parts[1]))
        return url
    }

    private func openRepoPath(sender: NSMenuItem, path: String) {
        guard let fullName = self.repoFullName(from: sender),
              var url = self.repoURL(for: fullName) else { return }
        url.appendPathComponent(path)
        self.open(url: url)
    }

    private func open(url: URL) {
        NSWorkspace.shared.open(url)
    }

    @objc private func menuItemNoOp(_: NSMenuItem) {}

    private func refreshIfNeededOnOpen() {
        let now = Date()
        if let lastMenuRefresh, now.timeIntervalSince(lastMenuRefresh) < self.menuRefreshInterval {
            return
        }
        self.lastMenuRefresh = now
        self.refreshNow()
    }

    private var isLightAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }
}

@MainActor
private protocol MenuItemMeasuring: AnyObject {
    func measuredHeight(width: CGFloat) -> CGFloat
}

@MainActor
private protocol MenuItemHighlighting: AnyObject {
    func setHighlighted(_ highlighted: Bool)
}

@MainActor
@Observable
private final class MenuItemHighlightState {
    var isHighlighted = false
}

private struct MenuItemContainerView<Content: View>: View {
    @Bindable var highlightState: MenuItemHighlightState
    let showsSubmenuIndicator: Bool
    let content: Content

    init(
        highlightState: MenuItemHighlightState,
        showsSubmenuIndicator: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.highlightState = highlightState
        self.showsSubmenuIndicator = showsSubmenuIndicator
        self.content = content()
    }

    var body: some View {
        self.content
            .padding(.trailing, self.showsSubmenuIndicator ? 18 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.menuItemHighlighted, self.highlightState.isHighlighted)
            .foregroundStyle(MenuHighlightStyle.primary(self.highlightState.isHighlighted))
            .background(alignment: .topLeading) {
                if self.highlightState.isHighlighted {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(MenuHighlightStyle.selectionBackground(true))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if self.showsSubmenuIndicator {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MenuHighlightStyle.secondary(self.highlightState.isHighlighted))
                        .padding(.top, 8)
                        .padding(.trailing, 10)
                }
            }
    }
}

@MainActor
private final class MenuItemHostingView: NSHostingView<AnyView>, MenuItemMeasuring, MenuItemHighlighting {
    private let highlightState: MenuItemHighlightState?

    override var allowsVibrancy: Bool { true }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        guard self.frame.width > 0 else { return size }
        return NSSize(width: self.frame.width, height: size.height)
    }

    init(rootView: AnyView, highlightState: MenuItemHighlightState) {
        self.highlightState = highlightState
        super.init(rootView: rootView)
    }

    @MainActor
    required init(rootView: AnyView) {
        self.highlightState = nil
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        let controller = NSHostingController(rootView: self.rootView)
        let measured = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        return measured.height
    }

    func setHighlighted(_ highlighted: Bool) {
        guard let highlightState else { return }
        guard highlighted != highlightState.isHighlighted else { return }
        highlightState.isHighlighted = highlighted
    }
}
