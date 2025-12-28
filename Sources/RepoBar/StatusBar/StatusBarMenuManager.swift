import AppKit
import RepoBarCore
import SwiftUI

@MainActor
final class StatusBarMenuManager: NSObject, NSMenuDelegate {
    private static let menuMinWidth: CGFloat = 360
    private static let menuMaxWidth: CGFloat = 440

    private let appState: AppState
    private var mainMenu: NSMenu?
    private var addRepoWindowController: AddRepoWindowController?

    init(appState: AppState) {
        self.appState = appState
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
        AppActions.openSettings()
    }

    @objc private func checkForUpdates() {
        SparkleController.shared.checkForUpdates()
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

    @objc private func openAddRepo() {
        if self.addRepoWindowController == nil {
            self.addRepoWindowController = AddRepoWindowController(appState: self.appState)
        }
        self.addRepoWindowController?.show()
    }

    @objc private func signIn() {
        Task { await self.appState.quickLogin() }
    }

    @objc private func openRepo(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender),
              let url = self.repoURL(for: fullName) else { return }
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
            self.populateMainMenu(menu)
            self.refreshMenuViewHeights(in: menu)
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

        menu.addItem(self.accountStateItem())
        menu.addItem(.separator())

        if settings.showContributionHeader,
           settings.showHeatmap,
           let username = self.currentUsername()
        {
            let header = ContributionHeaderView(username: username)
                .environmentObject(session)
                .environmentObject(self.appState)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            menu.addItem(self.viewItem(for: header, enabled: false))
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

        menu.addItem(self.sectionHeaderItem(title: "Repositories"))
        menu.addItem(self.actionItem(title: "Add Repository…", action: #selector(self.openAddRepo)))
        menu.addItem(.separator())

        let repos = self.orderedViewModels()
        if repos.isEmpty {
            let emptyState = MenuEmptyStateView()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            menu.addItem(self.viewItem(for: emptyState, enabled: false))
        } else {
            for repo in repos {
                let isPinned = settings.pinnedRepositories.contains(repo.title)
                let card = RepoMenuCardView(
                    repo: repo,
                    isPinned: isPinned,
                    showHeatmap: settings.showHeatmap,
                    heatmapSpan: settings.heatmapSpan,
                    accentTone: settings.accentTone
                )
                let submenu = self.makeRepoSubmenu(for: repo, isPinned: isPinned)
                let item = self.viewItem(for: card, enabled: true, highlightable: true, submenu: submenu)
                item.representedObject = repo.title
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(self.actionItem(title: "Refresh now", action: #selector(self.refreshNow), keyEquivalent: "r"))
        menu.addItem(self.actionItem(title: "Preferences…", action: #selector(self.openPreferences), keyEquivalent: ","))
        menu.addItem(self.actionItem(title: "Check for Updates…", action: #selector(self.checkForUpdates)))
        menu.addItem(.separator())
        menu.addItem(self.actionItem(title: "Quit RepoBar", action: #selector(self.quitApp), keyEquivalent: "q"))
    }

    private func sectionHeaderItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        item.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
        return item
    }

    private func accountStateItem() -> NSMenuItem {
        let title: String
        switch self.appState.session.account {
        case .loggedOut: title = "Not signed in"
        case .loggingIn: title = "Signing in…"
        case let .loggedIn(user):
            let host = user.host.host ?? "github.com"
            title = "Signed in as \(user.username)@\(host)"
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
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

        menu.addItem(.separator())
        menu.addItem(self.actionItem(
            title: "Copy Repository Name",
            action: #selector(self.copyRepoName),
            represented: repo.title,
            systemImage: "doc.on.doc"))
        menu.addItem(self.actionItem(
            title: "Copy Repository URL",
            action: #selector(self.copyRepoURL),
            represented: repo.title,
            systemImage: "link"))
        return menu
    }

    private func actionItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        represented: String? = nil,
        systemImage: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if let represented { item.representedObject = represented }
        if let systemImage, let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil) {
            image.isTemplate = true
            image.size = NSSize(width: 14, height: 14)
            item.image = image
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

    private func menuWidth(for menu: NSMenu) -> CGFloat {
        let widths = menu.items.compactMap { $0.view?.fittingSize.width }
        let maxWidth = widths.max() ?? Self.menuMinWidth
        return min(max(maxWidth, Self.menuMinWidth), Self.menuMaxWidth)
    }

    private func clearHighlights(in menu: NSMenu) {
        for item in menu.items {
            (item.view as? MenuItemHighlighting)?.setHighlighted(false)
        }
    }

    private func orderedViewModels() -> [RepositoryViewModel] {
        let repos = self.appState.session.repositories
            .prefix(self.appState.session.settings.repoDisplayLimit)
            .map { RepositoryViewModel(repo: $0) }
        return repos.sorted { lhs, rhs in
            switch (lhs.sortOrder, rhs.sortOrder) {
            case let (left?, right?):
                return left < right
            case (.none, .some):
                return false
            case (.some, .none):
                return true
            default:
                return RepositorySort.isOrderedBefore(lhs.source, rhs.source, sortKey: .activity)
            }
        }
    }

    private func currentUsername() -> String? {
        if case let .loggedIn(user) = self.appState.session.account { return user.username }
        return nil
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
private final class MenuItemHighlightState: ObservableObject {
    @Published var isHighlighted = false
}

private struct MenuItemContainerView<Content: View>: View {
    @ObservedObject var highlightState: MenuItemHighlightState
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
