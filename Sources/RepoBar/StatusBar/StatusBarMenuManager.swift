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
    private let recentListLoadTimeout: TimeInterval = 12
    private let issueLabelChipLimit = 6
    private let recentIssuesCache = RecentListCache<RepoIssueSummary>()
    private let recentPullRequestsCache = RecentListCache<RepoPullRequestSummary>()
    private let recentReleasesCache = RecentListCache<RepoReleaseSummary>()
    private let recentWorkflowRunsCache = RecentListCache<RepoWorkflowRunSummary>()
    private let recentDiscussionsCache = RecentListCache<RepoDiscussionSummary>()
    private let recentTagsCache = RecentListCache<RepoTagSummary>()
    private let recentBranchesCache = RecentListCache<RepoBranchSummary>()
    private let recentContributorsCache = RecentListCache<RepoContributorSummary>()
    private var localBranchMenus: [ObjectIdentifier: LocalGitMenuEntry] = [:]
    private var localWorktreeMenus: [ObjectIdentifier: LocalGitMenuEntry] = [:]
    private weak var checkoutProgressWindow: NSWindow?

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
            guard entry.context.kind == .pullRequests || entry.context.kind == .issues,
                  let menu = entry.menu
            else { continue }
            Task { @MainActor [weak self] in
                await self?.refreshRecentListMenu(menu: menu, context: entry.context)
            }
        }
    }

    @objc private func toggleIssueLabelFilter(_ sender: NSMenuItem) {
        guard let label = sender.representedObject as? String else { return }
        var selection = self.appState.session.recentIssueLabelSelection
        if selection.contains(label) {
            selection.remove(label)
        } else {
            selection.insert(label)
        }
        self.appState.session.recentIssueLabelSelection = selection
        NotificationCenter.default.post(name: .recentListFiltersDidChange, object: nil)
    }

    @objc private func clearIssueLabelFilters() {
        self.appState.session.recentIssueLabelSelection.removeAll()
        NotificationCenter.default.post(name: .recentListFiltersDidChange, object: nil)
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
        self.openLocalFinder(at: url)
    }

    func openLocalFinder(at url: URL) {
        self.open(url: url)
    }

    @objc func openLocalTerminal(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        self.openLocalTerminal(at: url)
    }

    func openLocalTerminal(at url: URL) {
        let preferred = self.appState.session.settings.localProjects.preferredTerminal
        let terminal = TerminalApp.resolve(preferred)
        terminal.open(
            at: url,
            rootBookmarkData: self.appState.session.settings.localProjects.rootBookmarkData,
            ghosttyOpenMode: self.appState.session.settings.localProjects.ghosttyOpenMode
        )
    }

    func syncLocalRepo(_ status: LocalRepoStatus) {
        self.runLocalGitTask(
            title: "Sync failed",
            status: status,
            notifyOnSuccess: true,
            action: .sync(status.path)
        )
    }

    func rebaseLocalRepo(_ status: LocalRepoStatus) {
        self.runLocalGitTask(
            title: "Rebase failed",
            status: status,
            notifyOnSuccess: false,
            action: .rebase(status.path)
        )
    }

    func resetLocalRepo(_ status: LocalRepoStatus) {
        let confirmed = self.confirmHardReset(for: status)
        guard confirmed else { return }
        self.runLocalGitTask(
            title: "Reset failed",
            status: status,
            notifyOnSuccess: false,
            action: .reset(status.path)
        )
    }

    @objc func switchLocalBranch(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? LocalBranchAction else { return }
        self.runLocalGitTask(
            title: "Switch branch failed",
            status: nil,
            notifyOnSuccess: false,
            action: .switchBranch(action.repoPath, action.branch)
        )
    }

    @objc func switchLocalWorktree(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? LocalWorktreeAction else { return }
        self.switchLocalWorktree(path: action.path, fullName: action.fullName)
    }

    @objc func createLocalBranch(_ sender: NSMenuItem) {
        guard let repoURL = sender.representedObject as? URL else { return }
        let name = self.promptForText(
            title: "Create branch",
            message: "Enter a new branch name."
        )
        guard let name, name.isEmpty == false else { return }
        self.runLocalGitTask(
            title: "Create branch failed",
            status: nil,
            notifyOnSuccess: false,
            action: .createBranch(repoURL, name)
        )
    }

    @objc func createLocalWorktree(_ sender: NSMenuItem) {
        guard let repoURL = sender.representedObject as? URL else { return }
        let branchName = self.promptForText(
            title: "Create worktree",
            message: "Enter a branch name for the new worktree."
        )
        guard let branchName, branchName.isEmpty == false else { return }
        let folderName = self.appState.session.settings.localProjects.worktreeFolderName
        let defaultPath = repoURL
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(branchName, isDirectory: true)
        let pathText = self.promptForText(
            title: "Worktree folder",
            message: "Enter the folder path for the new worktree.",
            defaultValue: defaultPath.path
        )
        guard let pathText, pathText.isEmpty == false else { return }
        let worktreeURL = URL(fileURLWithPath: pathText, isDirectory: true)
        do {
            let parent = worktreeURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            self.presentAlert(title: "Create worktree failed", message: error.userFacingMessage)
            return
        }
        self.runLocalGitTask(
            title: "Create worktree failed",
            status: nil,
            notifyOnSuccess: false,
            action: .createWorktree(repoURL, worktreeURL, branchName)
        )
    }

    @objc func checkoutRepoFromMenu(_ sender: NSMenuItem) {
        guard let fullName = self.repoFullName(from: sender) else { return }
        let settings = self.appState.session.settings.localProjects
        guard let rootPath = settings.rootPath, rootPath.isEmpty == false else {
            let alert = NSAlert()
            alert.messageText = "Set a local projects folder"
            alert.informativeText = "Choose a Local Projects folder in Settings to enable checkout."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                self.openPreferences()
            }
            return
        }

        guard let remoteURL = self.cloneURL(for: fullName) else {
            self.presentAlert(title: "Checkout failed", message: "Invalid repository URL.")
            return
        }

        let repoName = fullName.split(separator: "/").last.map(String.init) ?? fullName
        let destination = URL(fileURLWithPath: PathFormatter.expandTilde(rootPath), isDirectory: true)
            .appendingPathComponent(repoName, isDirectory: true)

        if FileManager.default.fileExists(atPath: destination.path) {
            self.presentAlert(title: "Folder exists", message: "\(destination.path) already exists.")
            return
        }

        self.showCheckoutProgress(fullName: fullName, destination: destination)
        let rootBookmark = settings.rootBookmarkData
        Task.detached { [weak self] in
            guard let self else { return }
            let result = Result {
                var capturedError: Error?
                SecurityScopedBookmark.withAccess(to: destination, rootBookmarkData: rootBookmark) {
                    do {
                        try LocalGitService().cloneRepo(remoteURL: remoteURL, to: destination)
                    } catch {
                        capturedError = error
                    }
                }
                if let capturedError { throw capturedError }
            }
            await MainActor.run {
                self.closeCheckoutProgress()
                switch result {
                case .success:
                    self.appState.session.settings.localProjects.preferredLocalPathsByFullName[fullName] = destination.path
                    self.appState.persistSettings()
                    self.appState.refreshLocalProjects()
                    self.openLocalFinder(at: destination)
                case let .failure(error):
                    self.presentAlert(title: "Checkout failed", message: error.userFacingMessage)
                }
            }
        }
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
        if let entry = self.localBranchMenus[ObjectIdentifier(menu)] {
            self.menuBuilder.refreshMenuViewHeights(in: menu)
            Task { @MainActor [weak self] in
                await self?.refreshLocalBranchMenu(menu: menu, entry: entry)
            }
            return
        }
        if let entry = self.localWorktreeMenus[ObjectIdentifier(menu)] {
            self.menuBuilder.refreshMenuViewHeights(in: menu)
            Task { @MainActor [weak self] in
                await self?.refreshLocalWorktreeMenu(menu: menu, entry: entry)
            }
            return
        }
        if menu === self.mainMenu {
            let plan = self.menuBuilder.mainMenuPlan()
            self.pruneRecentListMenus()
            self.pruneLocalGitMenus()
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

    private func pruneLocalGitMenus() {
        self.localBranchMenus = self.localBranchMenus.filter { $0.value.menu != nil }
        self.localWorktreeMenus = self.localWorktreeMenus.filter { $0.value.menu != nil }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for menuItem in menu.items {
            guard let view = menuItem.view as? MenuItemHighlighting else { continue }
            let highlighted = menuItem == item && menuItem.isEnabled
            view.setHighlighted(highlighted)
        }
    }

    private enum LocalGitAction: Sendable {
        case sync(URL)
        case rebase(URL)
        case reset(URL)
        case switchBranch(URL, String)
        case createBranch(URL, String)
        case createWorktree(URL, URL, String)

        var repoURL: URL {
            switch self {
            case let .sync(url),
                 let .rebase(url),
                 let .reset(url),
                 let .switchBranch(url, _),
                 let .createBranch(url, _),
                 let .createWorktree(url, _, _):
                url
            }
        }
    }

    struct LocalGitMenuEntry {
        weak var menu: NSMenu?
        let repoPath: URL
        let fullName: String
        let localStatus: LocalRepoStatus?
    }

    struct LocalBranchAction {
        let repoPath: URL
        let branch: String
        let fullName: String
    }

    struct LocalWorktreeAction {
        let path: URL
        let fullName: String
    }

    private struct LocalBranchMenuItemData {
        let name: String
        let isCurrent: Bool
        let isDetached: Bool
        let upstream: String?
        let aheadCount: Int?
        let behindCount: Int?
        let lastCommitDate: Date?
        let lastCommitAuthor: String?
        let dirtySummary: String?
        let repoPath: URL
        let fullName: String
    }

    private struct LocalWorktreeMenuItemData {
        let displayPath: String
        let branch: String
        let isCurrent: Bool
        let upstream: String?
        let aheadCount: Int?
        let behindCount: Int?
        let lastCommitDate: Date?
        let lastCommitAuthor: String?
        let dirtySummary: String?
        let path: URL
        let fullName: String
    }

    func registerLocalBranchMenu(_ menu: NSMenu, repoPath: URL, fullName: String, localStatus: LocalRepoStatus) {
        self.localBranchMenus[ObjectIdentifier(menu)] = LocalGitMenuEntry(
            menu: menu,
            repoPath: repoPath,
            fullName: fullName,
            localStatus: localStatus
        )
    }

    func registerLocalWorktreeMenu(_ menu: NSMenu, repoPath: URL, fullName: String) {
        self.localWorktreeMenus[ObjectIdentifier(menu)] = LocalGitMenuEntry(
            menu: menu,
            repoPath: repoPath,
            fullName: fullName,
            localStatus: nil
        )
    }

    private func refreshLocalBranchMenu(menu: NSMenu, entry: LocalGitMenuEntry) async {
        let repoPath = entry.repoPath
        let fullName = entry.fullName
        let result = await Task.detached { () -> Result<LocalGitBranchSnapshot, Error> in
            Result { try LocalGitService().branchDetails(at: repoPath) }
        }.value

        menu.removeAllItems()
        self.addLocalBranchMenuHeader(menu: menu, repoPath: repoPath)
        switch result {
        case let .success(snapshot):
            if snapshot.branches.isEmpty, snapshot.isDetachedHead == false {
                menu.addItem(self.menuBuilder.infoItem("No branches"))
                self.menuBuilder.refreshMenuViewHeights(in: menu)
                menu.update()
                return
            }
            if snapshot.isDetachedHead {
                let detached = self.makeLocalBranchMenuItem(LocalBranchMenuItemData(
                    name: "Detached HEAD",
                    isCurrent: true,
                    isDetached: true,
                    upstream: nil,
                    aheadCount: nil,
                    behindCount: nil,
                    lastCommitDate: snapshot.detachedCommitDate,
                    lastCommitAuthor: snapshot.detachedCommitAuthor,
                    dirtySummary: entry.localStatus?.dirtyCounts?.summary,
                    repoPath: repoPath,
                    fullName: fullName
                ))
                menu.addItem(detached)
            }
            for branch in snapshot.branches {
                let dirtySummary = branch.isCurrent ? entry.localStatus?.dirtyCounts?.summary : nil
                let item = self.makeLocalBranchMenuItem(LocalBranchMenuItemData(
                    name: branch.name,
                    isCurrent: branch.isCurrent,
                    isDetached: false,
                    upstream: branch.upstream,
                    aheadCount: branch.aheadCount,
                    behindCount: branch.behindCount,
                    lastCommitDate: branch.lastCommitDate,
                    lastCommitAuthor: branch.lastCommitAuthor,
                    dirtySummary: dirtySummary,
                    repoPath: repoPath,
                    fullName: fullName
                ))
                menu.addItem(item)
            }
            self.menuBuilder.refreshMenuViewHeights(in: menu)
            menu.update()
        case let .failure(error):
            menu.addItem(self.menuBuilder.infoItem("Failed to load branches"))
            self.presentAlert(title: "Branch list failed", message: error.userFacingMessage)
            self.menuBuilder.refreshMenuViewHeights(in: menu)
            menu.update()
        }
    }

    private func refreshLocalWorktreeMenu(menu: NSMenu, entry: LocalGitMenuEntry) async {
        let repoPath = entry.repoPath
        let fullName = entry.fullName
        let result = await Task.detached { () -> Result<[LocalGitWorktree], Error> in
            Result { try LocalGitService().worktrees(at: repoPath) }
        }.value

        menu.removeAllItems()
        self.addLocalWorktreeMenuHeader(menu: menu, repoPath: repoPath)
        switch result {
        case let .success(worktrees):
            if worktrees.isEmpty {
                menu.addItem(self.menuBuilder.infoItem("No worktrees"))
                self.menuBuilder.refreshMenuViewHeights(in: menu)
                menu.update()
                return
            }
            for worktree in worktrees {
                let branch = worktree.branch ?? "Detached"
                let displayPath = PathFormatter.displayString(worktree.path.path)
                menu.addItem(self.makeLocalWorktreeMenuItem(LocalWorktreeMenuItemData(
                    displayPath: displayPath,
                    branch: branch,
                    isCurrent: worktree.isCurrent,
                    upstream: worktree.upstream,
                    aheadCount: worktree.aheadCount,
                    behindCount: worktree.behindCount,
                    lastCommitDate: worktree.lastCommitDate,
                    lastCommitAuthor: worktree.lastCommitAuthor,
                    dirtySummary: worktree.dirtyCounts?.summary,
                    path: worktree.path,
                    fullName: fullName
                )))
            }
            self.menuBuilder.refreshMenuViewHeights(in: menu)
            menu.update()
        case let .failure(error):
            menu.addItem(self.menuBuilder.infoItem("Failed to load worktrees"))
            self.presentAlert(title: "Worktree list failed", message: error.userFacingMessage)
            self.menuBuilder.refreshMenuViewHeights(in: menu)
            menu.update()
        }
    }

    private func makeLocalWorktreeMenuItem(_ data: LocalWorktreeMenuItemData) -> NSMenuItem {
        let row = LocalWorktreeMenuRowView(
            path: data.displayPath,
            branch: data.branch,
            isCurrent: data.isCurrent,
            upstream: data.upstream,
            aheadCount: data.aheadCount,
            behindCount: data.behindCount,
            lastCommitDate: data.lastCommitDate,
            lastCommitAuthor: data.lastCommitAuthor,
            dirtySummary: data.dirtySummary
        )
        let item = self.menuBuilder.viewItem(for: row, enabled: true, highlightable: true)
        item.target = self
        item.action = #selector(self.switchLocalWorktree(_:))
        item.representedObject = LocalWorktreeAction(path: data.path, fullName: data.fullName)
        return item
    }

    private func makeLocalBranchMenuItem(_ data: LocalBranchMenuItemData) -> NSMenuItem {
        let row = LocalBranchMenuRowView(
            name: data.name,
            isCurrent: data.isCurrent,
            isDetached: data.isDetached,
            upstream: data.upstream,
            aheadCount: data.aheadCount,
            behindCount: data.behindCount,
            lastCommitDate: data.lastCommitDate,
            lastCommitAuthor: data.lastCommitAuthor,
            dirtySummary: data.dirtySummary
        )
        let item = self.menuBuilder.viewItem(for: row, enabled: true, highlightable: true)
        item.target = self
        item.action = #selector(self.switchLocalBranch)
        item.representedObject = LocalBranchAction(
            repoPath: data.repoPath,
            branch: data.name,
            fullName: data.fullName
        )
        item.state = data.isCurrent ? .on : .off
        return item
    }

    private func addLocalBranchMenuHeader(menu: NSMenu, repoPath: URL) {
        menu.addItem(self.menuBuilder.actionItem(
            title: "Create Branch…",
            action: #selector(self.createLocalBranch),
            represented: repoPath,
            systemImage: "plus"
        ))
        menu.addItem(.separator())
    }

    private func addLocalWorktreeMenuHeader(menu: NSMenu, repoPath: URL) {
        menu.addItem(self.menuBuilder.actionItem(
            title: "Create Worktree…",
            action: #selector(self.createLocalWorktree),
            represented: repoPath,
            systemImage: "plus"
        ))
        menu.addItem(.separator())
    }

    private func runLocalGitTask(
        title: String,
        status: LocalRepoStatus?,
        notifyOnSuccess: Bool,
        action: LocalGitAction
    ) {
        let rootBookmark = self.appState.session.settings.localProjects.rootBookmarkData
        Task.detached { [weak self] in
            guard let self else { return }
            let result = Result {
                var capturedError: Error?
                SecurityScopedBookmark.withAccess(to: action.repoURL, rootBookmarkData: rootBookmark) {
                    do {
                        try Self.performLocalGitAction(action)
                    } catch {
                        capturedError = error
                    }
                }
                if let capturedError { throw capturedError }
            }
            await MainActor.run {
                switch result {
                case .success:
                    self.appState.refreshLocalProjects()
                    if notifyOnSuccess, let status {
                        Task { await LocalSyncNotifier.shared.notifySync(for: status) }
                    }
                case let .failure(error):
                    self.presentAlert(title: title, message: error.userFacingMessage)
                }
            }
        }
    }

    private nonisolated static func performLocalGitAction(_ action: LocalGitAction) throws {
        let service = LocalGitService()
        switch action {
        case let .sync(url):
            _ = try service.smartSync(at: url)
        case let .rebase(url):
            try service.rebaseOntoUpstream(at: url)
        case let .reset(url):
            try service.hardResetToUpstream(at: url)
        case let .switchBranch(url, branch):
            try service.switchBranch(at: url, branch: branch)
        case let .createBranch(url, name):
            try service.createBranch(at: url, name: name)
        case let .createWorktree(url, path, branch):
            try service.createWorktree(at: url, path: path, branch: branch)
        }
    }

    private func promptForText(title: String, message: String, defaultValue: String? = nil) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        field.stringValue = defaultValue ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cloneURL(for fullName: String) -> URL? {
        let host = self.appState.session.settings.githubHost
        var url = host.appendingPathComponent(fullName)
        url.appendPathExtension("git")
        return url
    }

    private func switchLocalWorktree(path: URL, fullName: String) {
        let pathString = path.path
        guard FileManager.default.fileExists(atPath: pathString) else {
            self.presentAlert(title: "Worktree missing", message: "Could not find \(pathString).")
            return
        }
        self.appState.session.settings.localProjects.preferredLocalPathsByFullName[fullName] = pathString
        self.appState.persistSettings()
        self.appState.refreshLocalProjects()
    }

    private func showCheckoutProgress(fullName: String, destination: URL) {
        self.closeCheckoutProgress()
        let alert = NSAlert()
        alert.messageText = "Checking out \(fullName)"
        alert.informativeText = PathFormatter.displayString(destination.path)

        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.startAnimation(nil)

        let stack = NSStackView(views: [indicator])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        alert.accessoryView = stack

        let window = alert.window
        window.level = .floating
        self.checkoutProgressWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeCheckoutProgress() {
        self.checkoutProgressWindow?.close()
        self.checkoutProgressWindow = nil
    }

    private func confirmHardReset(for status: LocalRepoStatus) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Hard reset \(status.displayName)?"
        alert.informativeText = "This will discard uncommitted changes and reset to \(status.upstreamBranch ?? "upstream")."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
                    let filtered = self.filteredIssues(items)
                    if filtered.isEmpty {
                        self.addEmptyListItem("No matching issues", to: menu)
                        return
                    }
                    for issue in filtered.prefix(self.recentListLimit) {
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
                let items = try await AsyncTimeout.value(within: self.recentListLoadTimeout, task: task)
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
        let cached = descriptor.cached(context.fullName, now, self.recentListCacheTTL)
        let stale = cached ?? descriptor.stale(context.fullName)
        let staleExtras = self.recentListExtras(for: context, items: stale)
        if let stale {
            self.populateRecentListMenu(
                menu,
                header: header,
                actions: actions,
                extras: staleExtras,
                content: .items(stale, emptyTitle: descriptor.emptyTitle, render: { menu, items in
                    descriptor.render(menu, header.fullName, items)
                })
            )
        } else {
            self.populateRecentListMenu(menu, header: header, actions: actions, extras: staleExtras, content: .loading)
        }
        menu.update()

        guard descriptor.needsRefresh(context.fullName, now, self.recentListCacheTTL) else { return }
        do {
            let items = try await descriptor.load(context.fullName, owner, name, self.recentListLimit)
            self.populateRecentListMenu(
                menu,
                header: header,
                actions: actions,
                extras: self.recentListExtras(for: context, items: items),
                content: .items(items, emptyTitle: descriptor.emptyTitle, render: { menu, items in
                    descriptor.render(menu, header.fullName, items)
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

        menu.addItem(self.makeListItem(
            title: header.title,
            action: header.action,
            representedObject: header.representedObject,
            systemImage: header.systemImage,
            isEnabled: header.action != nil
        ))

        for action in actions {
            menu.addItem(self.makeListItem(
                title: action.title,
                action: action.action,
                representedObject: action.representedObject,
                systemImage: action.systemImage,
                isEnabled: action.isEnabled
            ))
        }

        menu.addItem(.separator())
        for extra in extras {
            menu.addItem(extra)
        }

        switch content {
        case let .message(text):
            menu.addItem(self.makeListItem(
                title: text,
                action: nil,
                representedObject: nil,
                systemImage: nil,
                isEnabled: false
            ))
        case let .items(isEmpty, emptyTitle, render):
            if isEmpty {
                if let emptyTitle {
                    menu.addItem(self.makeListItem(
                        title: emptyTitle,
                        action: nil,
                        representedObject: nil,
                        systemImage: nil,
                        isEnabled: false
                    ))
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

    private func makeListItem(
        title: String,
        action: Selector?,
        representedObject: Any?,
        systemImage: String?,
        isEnabled: Bool
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = representedObject
        item.isEnabled = isEnabled
        if let systemImage {
            self.applyMenuItemSymbol(systemImage, to: item)
        }
        return item
    }

    private func applyMenuItemSymbol(_ systemImage: String, to item: NSMenuItem) {
        guard let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil) else { return }
        image.size = NSSize(width: 14, height: 14)
        image.isTemplate = true
        item.image = image
    }

    private func addEmptyListItem(_ title: String, to menu: NSMenu) {
        menu.addItem(self.makeListItem(
            title: title,
            action: nil,
            representedObject: nil,
            systemImage: nil,
            isEnabled: false
        ))
    }

    private func recentListExtras(for context: RepoRecentMenuContext, items: RecentMenuItems?) -> [NSMenuItem] {
        switch context.kind {
        case .pullRequests:
            self.pullRequestFilterMenuItems()
        case .issues:
            self.issueFilterMenuItems(items: items)
        default:
            []
        }
    }

    private func pullRequestFilterMenuItems() -> [NSMenuItem] {
        let filters = RecentPullRequestFiltersView(session: self.appState.session)
        let item = self.hostingMenuItem(for: filters, enabled: true)
        return [item, .separator()]
    }

    private func issueFilterMenuItems(items: RecentMenuItems?) -> [NSMenuItem] {
        guard case let .issues(issueItems) = items ?? .issues([]) else { return [] }
        let labelOptions = self.issueLabelOptions(for: issueItems)
        let chipOptions = self.issueLabelChipOptions(from: labelOptions)
        let filters = RecentIssueFiltersView(session: self.appState.session, labels: chipOptions)
        let item = self.hostingMenuItem(for: filters, enabled: true)
        var extras: [NSMenuItem] = [item]
        if let moreItem = self.issueLabelMoreMenuItem(for: labelOptions) {
            extras.append(moreItem)
        }
        extras.append(.separator())
        return extras
    }

    private func issueLabelOptions(for items: [RepoIssueSummary]) -> [RecentIssueLabelOption] {
        var counts: [String: (count: Int, colorHex: String)] = [:]
        for issue in items {
            for label in issue.labels {
                let key = label.name
                if var entry = counts[key] {
                    entry.count += 1
                    counts[key] = entry
                } else {
                    counts[key] = (count: 1, colorHex: label.colorHex)
                }
            }
        }

        var options = counts.map { RecentIssueLabelOption(name: $0.key, colorHex: $0.value.colorHex, count: $0.value.count) }
        options.sort {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let selected = self.appState.session.recentIssueLabelSelection
        let known = Set(options.map(\.name))
        let missing = selected.subtracting(known)
        for name in missing.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            options.append(RecentIssueLabelOption(name: name, colorHex: "", count: 0))
        }

        return options
    }

    private func issueLabelChipOptions(from options: [RecentIssueLabelOption]) -> [RecentIssueLabelOption] {
        let selected = self.appState.session.recentIssueLabelSelection
        let selectedOptions = options.filter { selected.contains($0.name) }
        let remaining = options.filter { !selected.contains($0.name) }
        let combined = selectedOptions + remaining
        return Array(combined.prefix(self.issueLabelChipLimit))
    }

    private func issueLabelMoreMenuItem(for options: [RecentIssueLabelOption]) -> NSMenuItem? {
        guard options.count > self.issueLabelChipLimit else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let all = NSMenuItem(title: "All Labels", action: #selector(self.clearIssueLabelFilters), keyEquivalent: "")
        all.target = self
        all.state = self.appState.session.recentIssueLabelSelection.isEmpty ? .on : .off
        menu.addItem(all)
        menu.addItem(.separator())

        for option in options {
            let title = option.count > 0 ? "\(option.name) (\(option.count))" : option.name
            let item = NSMenuItem(title: title, action: #selector(self.toggleIssueLabelFilter(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.name
            item.state = self.appState.session.recentIssueLabelSelection.contains(option.name) ? .on : .off
            menu.addItem(item)
        }

        let parent = NSMenuItem(title: "More Labels…", action: nil, keyEquivalent: "")
        parent.submenu = menu
        return parent
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

    #if DEBUG
        func setMainMenuForTesting(_ menu: NSMenu) {
            self.mainMenu = menu
        }
    #endif

    func isRecentListMenu(_ menu: NSMenu) -> Bool {
        self.recentListMenus[ObjectIdentifier(menu)] != nil
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
