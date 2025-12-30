import AppKit
import Kingfisher
import MenuBarExtraAccess
import Observation
import RepoBarCore
import SwiftUI

@main
struct RepoBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate
    @State private var appState = AppState()
    @State private var isMenuPresented = false
    @State private var menuManager: StatusBarMenuManager?

    @SceneBuilder
    var body: some Scene {
        MenuBarExtra {
            EmptyView()
        } label: {
            StatusItemLabelView(session: self.appState.session)
        }
        .menuBarExtraStyle(.menu)
        .menuBarExtraAccess(isPresented: self.$isMenuPresented) { item in
            if self.menuManager == nil {
                self.menuManager = StatusBarMenuManager(appState: self.appState)
            }
            self.menuManager?.attachMainMenu(to: item)
        }

        Settings {
            SettingsView(session: self.appState.session, appState: self.appState)
        }
        .defaultSize(width: 540, height: 420)
        .windowResizability(.contentSize)
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        guard ensureSingleInstance() else {
            NSApp.terminate(nil)
            return
        }
        configureImagePipeline()
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}

extension AppDelegate {
    /// Prevent multiple instances when LS UI flag is unavailable under SwiftPM.
    private func ensureSingleInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID && !$0.isEqual(NSRunningApplication.current)
        }
        return others.isEmpty
    }

    private func configureImagePipeline() {
        let cache = ImageCache(name: "RepoBarAvatars")
        cache.memoryStorage.config.totalCostLimit = 64 * 1024 * 1024
        cache.diskStorage.config.sizeLimit = 64 * 1024 * 1024
        KingfisherManager.shared.cache = cache
    }
}

// MARK: - AppState container

@MainActor
@Observable
final class AppState {
    var session = Session()
    let auth = OAuthCoordinator()
    let github = GitHubClient()
    let refreshScheduler = RefreshScheduler()
    private let settingsStore = SettingsStore()
    private let localRepoManager = LocalRepoManager()
    private let menuRefreshInterval: TimeInterval = 30
    private var refreshTask: Task<Void, Never>?
    private var localProjectsTask: Task<Void, Never>?
    private var tokenRefreshTask: Task<Void, Never>?
    private var menuRefreshTask: Task<Void, Never>?
    private var refreshTaskToken = UUID()
    private let hydrateConcurrencyLimit = 4
    private var prefetchTask: Task<Void, Never>?
    private let tokenRefreshInterval: TimeInterval = 300

    // Default GitHub App values for convenience login from the main window.
    private let defaultClientID = RepoBarAuthDefaults.clientID
    private let defaultClientSecret = RepoBarAuthDefaults.clientSecret
    private let defaultLoopbackPort = RepoBarAuthDefaults.loopbackPort
    private let defaultGitHubHost = RepoBarAuthDefaults.githubHost
    private let defaultAPIHost = RepoBarAuthDefaults.apiHost

    init() {
        self.session.settings = self.settingsStore.load()
        _ = self.auth.loadTokens()
        Task {
            await self.github.setTokenProvider { @Sendable [weak self] () async throws -> OAuthTokens? in
                try? await self?.auth.refreshIfNeeded()
            }
        }
        self.tokenRefreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if self.auth.loadTokens() != nil {
                    try? await self.auth.refreshIfNeeded()
                }
                try? await Task.sleep(for: .seconds(self.tokenRefreshInterval))
            }
        }
        self.refreshScheduler.configure(interval: self.session.settings.refreshInterval.seconds) { [weak self] in
            self?.requestRefresh()
        }
        Task { await DiagnosticsLogger.shared.setEnabled(self.session.settings.diagnosticsEnabled) }
    }

    func refreshIfNeededForMenu() {
        let now = Date()
        let hasFreshSnapshot = self.session.menuSnapshot.map {
            $0.isStale(now: now, interval: self.menuRefreshInterval) == false
        } ?? false
        if hasFreshSnapshot {
            return
        }
        if self.refreshTask != nil || self.menuRefreshTask != nil { return }
        self.menuRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            await MainActor.run {
                guard let self else { return }
                self.menuRefreshTask = nil
                self.requestRefresh(cancelInFlight: false)
            }
        }
    }

    func requestRefresh(cancelInFlight: Bool = false) {
        if cancelInFlight {
            self.refreshTask?.cancel()
            self.prefetchTask?.cancel()
        }
        guard cancelInFlight || self.refreshTask == nil else { return }
        let token = UUID()
        self.refreshTaskToken = token
        self.refreshTask = Task { [weak self] in
            await self?.refresh()
            await MainActor.run {
                guard let self, self.refreshTaskToken == token else { return }
                self.refreshTask = nil
            }
        }
    }

    /// Starts the OAuth flow using the default GitHub App credentials, invoked from the logged-out prompt.
    func quickLogin() async {
        self.session.account = .loggingIn
        self.session.settings.loopbackPort = self.defaultLoopbackPort
        await self.github.setAPIHost(self.defaultAPIHost)
        self.session.settings.githubHost = self.defaultGitHubHost
        self.session.settings.enterpriseHost = nil

        do {
            try await self.auth.login(
                clientID: self.defaultClientID,
                clientSecret: self.defaultClientSecret,
                host: self.defaultGitHubHost,
                loopbackPort: self.defaultLoopbackPort
            )
            if let user = try? await self.github.currentUser() {
                self.session.account = .loggedIn(user)
                self.session.lastError = nil
            } else {
                self.session.account = .loggedIn(UserIdentity(username: "", host: self.defaultGitHubHost))
            }
            await self.refresh()
        } catch {
            self.session.account = .loggedOut
            self.session.lastError = error.userFacingMessage
        }
    }

    func refresh() async {
        let localSettings = self.session.settings.localProjects
        self.session.localProjectsScanInProgress = (localSettings.rootPath?.isEmpty == false)
        do {
            if Task.isCancelled { return }
            let now = Date()
            self.updateHeatmapRange(now: now)
            if self.auth.loadTokens() == nil {
                let matchNames = self.localMatchRepoNamesForLocalProjects(repos: [], includePinned: true)
                let localSnapshot = await self.localRepoManager.snapshot(
                    rootPath: localSettings.rootPath,
                    rootBookmarkData: localSettings.rootBookmarkData,
                    autoSyncEnabled: localSettings.autoSyncEnabled,
                    matchRepoNames: matchNames,
                    forceRescan: false
                )
                await MainActor.run {
                    self.session.repositories = []
                    self.session.menuSnapshot = nil
                    self.session.hasLoadedRepositories = false
                    self.session.lastError = nil
                    self.session.localRepoIndex = localSnapshot.repoIndex
                    self.session.localDiscoveredRepoCount = localSnapshot.discoveredCount
                    self.session.localProjectsAccessDenied = localSnapshot.accessDenied
                    self.session.localProjectsScanInProgress = false
                }
                return
            }
            // If we have tokens but no user in session, fetch identity once per launch.
            if case .loggedOut = self.session.account {
                if let user = try? await self.github.currentUser() {
                    await MainActor.run { self.session.account = .loggedIn(user) }
                }
            }
            let repos = try await self.fetchActivityRepos()
            try Task.checkCancellation()
            let visible = self.applyVisibilityFilters(to: repos)
            let ordered = self.applyPinnedOrder(to: visible)
            let matchNames = self.localMatchRepoNamesForLocalProjects(repos: ordered, includePinned: true)
            let localSnapshotTask = Task {
                await self.localRepoManager.snapshot(
                    rootPath: localSettings.rootPath,
                    rootBookmarkData: localSettings.rootBookmarkData,
                    autoSyncEnabled: localSettings.autoSyncEnabled,
                    matchRepoNames: matchNames,
                    forceRescan: false
                )
            }
            let targets = self.selectMenuTargets(from: ordered)
            let hydrated = await self.hydrateMenuTargets(targets)
            try Task.checkCancellation()
            let merged = self.mergeHydrated(hydrated, into: ordered)
            let final = self.applyPinnedOrder(to: merged)
            let localSnapshot = await localSnapshotTask.value
            await self.updateSession(with: final, now: now)
            await MainActor.run {
                self.session.localRepoIndex = localSnapshot.repoIndex
                self.session.localDiscoveredRepoCount = localSnapshot.discoveredCount
                self.session.localProjectsAccessDenied = localSnapshot.accessDenied
                self.session.localProjectsScanInProgress = false
            }
            self.prefetchMenuTargets(from: final, visibleCount: targets.count, token: self.refreshTaskToken)
            let reset = await self.github.rateLimitReset(now: now)
            let message = await self.github.rateLimitMessage(now: now)
            await MainActor.run {
                self.session.rateLimitReset = reset
                self.session.lastError = message
            }
        } catch {
            await MainActor.run {
                self.session.localProjectsScanInProgress = false
                self.session.lastError = error.userFacingMessage
            }
        }
    }

    func refreshLocalProjects(cancelInFlight: Bool = true, forceRescan: Bool = false) {
        if cancelInFlight {
            self.localProjectsTask?.cancel()
        }

        let settings = self.session.settings.localProjects
        guard let rootPath = settings.rootPath,
              rootPath.isEmpty == false
        else {
            self.session.localRepoIndex = .empty
            self.session.localDiscoveredRepoCount = 0
            self.session.localProjectsAccessDenied = false
            self.session.localProjectsScanInProgress = false
            return
        }

        self.session.localProjectsScanInProgress = true
        self.localProjectsTask = Task { [weak self] in
            guard let self else { return }
            let matchNames = self.localMatchRepoNamesForLocalProjects(
                repos: self.session.repositories.isEmpty
                    ? (self.session.menuSnapshot?.repositories ?? [])
                    : self.session.repositories,
                includePinned: true
            )
            let localSnapshot = await self.localRepoManager.snapshot(
                rootPath: settings.rootPath,
                rootBookmarkData: settings.rootBookmarkData,
                autoSyncEnabled: settings.autoSyncEnabled,
                matchRepoNames: matchNames,
                forceRescan: forceRescan
            )
            await MainActor.run {
                self.session.localRepoIndex = localSnapshot.repoIndex
                self.session.localDiscoveredRepoCount = localSnapshot.discoveredCount
                self.session.localProjectsAccessDenied = localSnapshot.accessDenied
                self.session.localProjectsScanInProgress = false
            }
        }
    }

    private func localMatchRepoNamesForLocalProjects(repos: [Repository], includePinned: Bool) -> Set<String> {
        var names = Set(repos.map(\.name))
        guard includePinned else { return names }
        let pinned = self.session.settings.repoList.pinnedRepositories
        for fullName in pinned {
            if let last = fullName.split(separator: "/").last {
                names.insert(String(last))
            }
        }
        return names
    }

    private func fetchActivityRepos() async throws -> [Repository] {
        try await self.github.activityRepositories(limit: nil)
    }

    private func applyVisibilityFilters(to repos: [Repository]) -> [Repository] {
        let options = AppState.VisibleSelectionOptions(
            pinned: self.session.settings.repoList.pinnedRepositories,
            hidden: Set(self.session.settings.repoList.hiddenRepositories),
            includeForks: self.session.settings.repoList.showForks,
            includeArchived: self.session.settings.repoList.showArchived,
            limit: Int.max
        )
        return AppState.selectVisible(all: repos, options: options)
    }

    private func selectMenuTargets(from repos: [Repository]) -> [Repository] {
        RepositoryPipeline.apply(repos, query: self.menuQuery())
    }

    private func menuQuery() -> RepositoryQuery {
        let selection = self.session.menuRepoSelection
        let settings = self.session.settings
        let scope: RepositoryScope = selection.isPinnedScope ? .pinned : .all
        let ageCutoff = RepositoryQueryDefaults.ageCutoff(
            scope: scope,
            ageDays: RepositoryQueryDefaults.defaultAgeDays
        )
        return RepositoryQuery(
            scope: scope,
            onlyWith: selection.onlyWith,
            includeForks: settings.repoList.showForks,
            includeArchived: settings.repoList.showArchived,
            sortKey: settings.repoList.menuSortKey,
            limit: settings.repoList.displayLimit,
            ageCutoff: ageCutoff,
            pinned: settings.repoList.pinnedRepositories,
            hidden: Set(settings.repoList.hiddenRepositories),
            pinPriority: true
        )
    }

    func updateHeatmapRange(now: Date = Date()) {
        self.session.heatmapRange = HeatmapFilter.range(
            span: self.session.settings.heatmap.span,
            now: now,
            alignToWeek: true
        )
    }

    private func hydrateMenuTargets(_ repos: [Repository]) async -> [Repository] {
        guard !repos.isEmpty else { return [] }
        let limit = max(1, min(self.hydrateConcurrencyLimit, repos.count))
        var detailed: [Repository] = []
        for batch in repos.chunked(into: limit) {
            if Task.isCancelled { break }
            let batchResult = await withTaskGroup(of: Repository?.self) { group in
                for repo in batch {
                    group.addTask { [github] in
                        try? await github.fullRepository(owner: repo.owner, name: repo.name)
                    }
                }
                var batchOutput: [Repository] = []
                for await repo in group {
                    if let repo { batchOutput.append(repo) }
                }
                return batchOutput
            }
            detailed.append(contentsOf: batchResult)
        }
        return detailed
    }

    private func mergeHydrated(_ detailed: [Repository], into repos: [Repository]) -> [Repository] {
        let lookup = Dictionary(uniqueKeysWithValues: detailed.map { ($0.fullName, $0) })
        return repos.map { lookup[$0.fullName] ?? $0 }
    }

    private func applyPinnedOrder(to repos: [Repository]) -> [Repository] {
        let pinned = self.session.settings.repoList.pinnedRepositories
        return repos.map { repo in
            if let idx = pinned.firstIndex(of: repo.fullName) {
                return repo.withOrder(idx)
            }
            return repo
        }
    }

    private func updateSession(with repos: [Repository], now: Date) async {
        await MainActor.run {
            self.session.repositories = repos
            self.session.menuSnapshot = MenuSnapshot(repositories: repos, capturedAt: now)
            self.session.hasLoadedRepositories = true
            self.session.rateLimitReset = nil
            self.session.lastError = nil
        }
    }

    private func prefetchMenuTargets(
        from repos: [Repository],
        visibleCount: Int,
        token: UUID
    ) {
        let limit = self.session.settings.repoList.displayLimit
        guard limit > 0 else { return }
        let startIndex = min(visibleCount, repos.count)
        let prefetchTargets = Array(repos.dropFirst(startIndex).prefix(limit))
        guard prefetchTargets.isEmpty == false else { return }

        self.prefetchTask?.cancel()
        self.prefetchTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            let hydrated = await self.hydrateMenuTargets(prefetchTargets)
            guard Task.isCancelled == false, hydrated.isEmpty == false else { return }
            await MainActor.run {
                guard self.refreshTaskToken == token else { return }
                let merged = self.mergeHydrated(hydrated, into: self.session.repositories)
                self.session.repositories = merged
                if let snapshot = self.session.menuSnapshot {
                    self.session.menuSnapshot = MenuSnapshot(
                        repositories: merged,
                        capturedAt: snapshot.capturedAt
                    )
                }
            }
        }
    }

    func addPinned(_ fullName: String) async {
        guard !self.session.settings.repoList.pinnedRepositories.contains(fullName) else { return }
        self.session.settings.repoList.pinnedRepositories.append(fullName)
        self.settingsStore.save(self.session.settings)
        await self.refresh()
    }

    func removePinned(_ fullName: String) async {
        self.session.settings.repoList.pinnedRepositories.removeAll { $0 == fullName }
        self.settingsStore.save(self.session.settings)
        await self.refresh()
    }

    func hide(_ fullName: String) async {
        guard !self.session.settings.repoList.hiddenRepositories.contains(fullName) else { return }
        self.session.settings.repoList.hiddenRepositories.append(fullName)
        // If hidden, also unpin to avoid stale pin list.
        self.session.settings.repoList.pinnedRepositories.removeAll { $0 == fullName }
        self.settingsStore.save(self.session.settings)
        self.session.repositories.removeAll { $0.fullName == fullName }
        await self.refresh()
    }

    func unhide(_ fullName: String) async {
        self.session.settings.repoList.hiddenRepositories.removeAll { $0 == fullName }
        self.settingsStore.save(self.session.settings)
        await self.refresh()
    }

    /// Sets a repository's visibility in one place, keeping pinned/hidden arrays consistent.
    func setVisibility(for fullName: String, to visibility: RepoVisibility) async {
        // Always trim first to avoid storing whitespace variants.
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Remove from both buckets before re-adding.
        self.session.settings.repoList.pinnedRepositories.removeAll { $0 == trimmed }
        self.session.settings.repoList.hiddenRepositories.removeAll { $0 == trimmed }

        switch visibility {
        case .pinned:
            self.session.settings.repoList.pinnedRepositories.append(trimmed)
        case .hidden:
            self.session.settings.repoList.hiddenRepositories.append(trimmed)
        case .visible:
            break
        }

        self.settingsStore.save(self.session.settings)
        await self.refresh()
    }

    func diagnostics() async -> DiagnosticsSummary {
        await self.github.diagnostics()
    }

    func clearCaches() async {
        await self.github.clearCache()
        ContributionCacheStore.clear()
    }

    func persistSettings() {
        self.settingsStore.save(self.session.settings)
    }

    /// Preloads the user's contribution heatmap so the header can render without remote images.
    func loadContributionHeatmapIfNeeded(for username: String) async {
        guard self.session.settings.appearance.showContributionHeader, self.session.hasLoadedRepositories else { return }
        if self.session.contributionUser == username, !self.session.contributionHeatmap.isEmpty { return }
        let hasExisting = self.session.contributionUser == username && !self.session.contributionHeatmap.isEmpty
        if let cached = ContributionCacheStore.load(), cached.username == username, cached.isValid {
            await MainActor.run {
                self.session.contributionUser = username
                self.session.contributionHeatmap = cached.cells
                self.session.contributionError = nil
            }
            return
        }
        do {
            let cells = try await self.github.userContributionHeatmap(login: username)
            await MainActor.run {
                self.session.contributionUser = username
                self.session.contributionHeatmap = cells
                self.session.contributionError = nil
            }
            let cache = ContributionCache(
                username: username,
                expires: Date().addingTimeInterval(24 * 60 * 60),
                cells: cells
            )
            ContributionCacheStore.save(cache)
        } catch {
            await MainActor.run {
                if !hasExisting {
                    self.session.contributionHeatmap = []
                    self.session.contributionUser = username
                }
                self.session.contributionError = error.userFacingMessage
            }
        }
    }

    func clearContributionCache() {
        ContributionCacheStore.clear()
        self.session.contributionHeatmap = []
        self.session.contributionUser = nil
        self.session.contributionError = nil
    }

    struct VisibleSelectionOptions {
        let pinned: [String]
        let hidden: Set<String>
        let includeForks: Bool
        let includeArchived: Bool
        let limit: Int
    }

    nonisolated static func selectVisible(all repos: [Repository], options: VisibleSelectionOptions) -> [Repository] {
        let pinnedSet = Set(options.pinned)
        let filtered = repos.filter { !options.hidden.contains($0.fullName) }
        let visible = RepositoryFilter.apply(
            filtered,
            includeForks: options.includeForks,
            includeArchived: options.includeArchived,
            pinned: pinnedSet
        )
        let limited = Array(visible.prefix(max(options.limit, 0)))
        return limited.sorted { lhs, rhs in
            switch (options.pinned.firstIndex(of: lhs.fullName), options.pinned.firstIndex(of: rhs.fullName)) {
            case let (l?, r?): l < r
            case (.some, .none): true
            case (.none, .some): false
            default: false
            }
        }
    }
}

@Observable
final class Session {
    var account: AccountState = .loggedOut
    var repositories: [Repository] = []
    var menuSnapshot: MenuSnapshot?
    var hasLoadedRepositories = false
    var settings = UserSettings()
    var settingsSelectedTab: SettingsTab = .general
    var rateLimitReset: Date?
    var lastError: String?
    var contributionHeatmap: [HeatmapCell] = []
    var contributionUser: String?
    var contributionError: String?
    var heatmapRange: HeatmapRange = HeatmapFilter.range(span: .twelveMonths, now: Date(), alignToWeek: true)
    var menuRepoSelection: MenuRepoSelection = .all
    var recentPullRequestScope: RecentPullRequestScope = .all
    var recentPullRequestEngagement: RecentPullRequestEngagement = .all
    var localRepoIndex: LocalRepoIndex = .empty
    var localDiscoveredRepoCount = 0
    var localProjectsScanInProgress = false
    var localProjectsAccessDenied = false
}

enum AccountState: Equatable {
    case loggedOut
    case loggingIn
    case loggedIn(UserIdentity)
}

private extension Array {
    func chunked(into size: Int) -> [ArraySlice<Element>] {
        guard size > 0 else { return [self[...]] }
        var result: [ArraySlice<Element>] = []
        var index = startIndex
        while index < endIndex {
            let nextIndex = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(self[index ..< nextIndex])
            index = nextIndex
        }
        return result
    }
}
