import AppKit
import MenuBarExtraAccess
import Nuke
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
        var config = ImagePipeline.Configuration()
        let dataCache = try? DataCache(name: "RepoBarAvatars")
        dataCache?.sizeLimit = 64 * 1024 * 1024
        config.dataCache = dataCache
        let imageCache = ImageCache()
        imageCache.costLimit = 64 * 1024 * 1024
        config.imageCache = imageCache
        ImagePipeline.shared = ImagePipeline(configuration: config)
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
    private var lastMenuRefresh: Date?
    private let menuRefreshInterval: TimeInterval = 30

    // Default GitHub App values for convenience login from the main window.
    private let defaultClientID = RepoBarAuthDefaults.clientID
    private let defaultClientSecret = RepoBarAuthDefaults.clientSecret
    private let defaultLoopbackPort = RepoBarAuthDefaults.loopbackPort
    private let defaultGitHubHost = RepoBarAuthDefaults.githubHost
    private let defaultAPIHost = RepoBarAuthDefaults.apiHost

    init() {
        self.session.settings = self.settingsStore.load()
        Task {
            await self.github.setTokenProvider { @Sendable [weak self] () async throws -> OAuthTokens? in
                try? await self?.auth.refreshIfNeeded()
            }
        }
        self.refreshScheduler.configure(interval: self.session.settings.refreshInterval.seconds) { [weak self] in
            Task { await self?.refresh() }
        }
        Task { await DiagnosticsLogger.shared.setEnabled(self.session.settings.diagnosticsEnabled) }
    }

    func refreshIfNeededForMenu() {
        let now = Date()
        if let lastMenuRefresh, now.timeIntervalSince(lastMenuRefresh) < self.menuRefreshInterval {
            return
        }
        self.lastMenuRefresh = now
        self.refreshScheduler.forceRefresh()
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
        do {
            if self.auth.loadTokens() == nil {
                await MainActor.run {
                    self.session.repositories = []
                    self.session.lastError = nil
                }
                return
            }
            // If we have tokens but no user in session, fetch identity once per launch.
            if case .loggedOut = self.session.account {
                if let user = try? await self.github.currentUser() {
                    await MainActor.run { self.session.account = .loggedIn(user) }
                }
            }
            let repos = try await self.github.activityRepositories(limit: nil)
            let trimmed = AppState.selectVisible(
                all: repos,
                pinned: self.session.settings.pinnedRepositories,
                hidden: Set(self.session.settings.hiddenRepositories),
                includeForks: self.session.settings.showForks,
                includeArchived: self.session.settings.showArchived,
                limit: Int.max
            )
            let ordered = self.applyPinnedOrder(to: trimmed)
            let menuTargets = self.menuTargets(from: ordered)
            let detailed = await self.fetchDetailedRepos(menuTargets)
            let merged = self.mergeDetailed(detailed, into: ordered)
            let final = self.applyPinnedOrder(to: merged)
            await MainActor.run {
                self.session.repositories = final
                self.session.hasLoadedRepositories = true
                self.session.rateLimitReset = nil
                self.session.lastError = nil
            }
            let now = Date()
            let reset = await self.github.rateLimitReset(now: now)
            let message = await self.github.rateLimitMessage(now: now)
            await MainActor.run {
                self.session.rateLimitReset = reset
                self.session.lastError = message
            }
        } catch {
            await MainActor.run { self.session.lastError = error.userFacingMessage }
        }
    }

    private func menuTargets(from repos: [Repository]) -> [Repository] {
        RepositoryPipeline.apply(repos, query: self.menuQuery())
    }

    private func menuQuery() -> RepositoryQuery {
        let selection = self.session.menuRepoSelection
        let settings = self.session.settings
        let scope: RepositoryScope = selection.isPinnedScope ? .pinned : .all
        return RepositoryQuery(
            scope: scope,
            onlyWith: selection.onlyWith,
            includeForks: settings.showForks,
            includeArchived: settings.showArchived,
            sortKey: settings.menuSortKey,
            limit: settings.repoDisplayLimit,
            pinned: settings.pinnedRepositories,
            hidden: Set(settings.hiddenRepositories),
            pinPriority: true
        )
    }

    private func fetchDetailedRepos(_ repos: [Repository]) async -> [Repository] {
        await withTaskGroup(of: Repository?.self) { group in
            for repo in repos {
                group.addTask { [github] in
                    try? await github.fullRepository(owner: repo.owner, name: repo.name)
                }
            }
            var detailed: [Repository] = []
            for await repo in group {
                if let repo { detailed.append(repo) }
            }
            return detailed
        }
    }

    private func mergeDetailed(_ detailed: [Repository], into repos: [Repository]) -> [Repository] {
        let lookup = Dictionary(uniqueKeysWithValues: detailed.map { ($0.fullName, $0) })
        return repos.map { lookup[$0.fullName] ?? $0 }
    }

    private func applyPinnedOrder(to repos: [Repository]) -> [Repository] {
        let pinned = self.session.settings.pinnedRepositories
        return repos.map { repo in
            if let idx = pinned.firstIndex(of: repo.fullName) {
                return repo.withOrder(idx)
            }
            return repo
        }
    }

    func addPinned(_ fullName: String) async {
        guard !self.session.settings.pinnedRepositories.contains(fullName) else { return }
        self.session.settings.pinnedRepositories.append(fullName)
        self.settingsStore.save(self.session.settings)
        await self.refresh()
    }

    func removePinned(_ fullName: String) async {
        self.session.settings.pinnedRepositories.removeAll { $0 == fullName }
        self.settingsStore.save(self.session.settings)
        await self.refresh()
    }

    func hide(_ fullName: String) async {
        guard !self.session.settings.hiddenRepositories.contains(fullName) else { return }
        self.session.settings.hiddenRepositories.append(fullName)
        // If hidden, also unpin to avoid stale pin list.
        self.session.settings.pinnedRepositories.removeAll { $0 == fullName }
        self.settingsStore.save(self.session.settings)
        self.session.repositories.removeAll { $0.fullName == fullName }
        await self.refresh()
    }

    func unhide(_ fullName: String) async {
        self.session.settings.hiddenRepositories.removeAll { $0 == fullName }
        self.settingsStore.save(self.session.settings)
        await self.refresh()
    }

    /// Sets a repository's visibility in one place, keeping pinned/hidden arrays consistent.
    func setVisibility(for fullName: String, to visibility: RepoVisibility) async {
        // Always trim first to avoid storing whitespace variants.
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Remove from both buckets before re-adding.
        self.session.settings.pinnedRepositories.removeAll { $0 == trimmed }
        self.session.settings.hiddenRepositories.removeAll { $0 == trimmed }

        switch visibility {
        case .pinned:
            self.session.settings.pinnedRepositories.append(trimmed)
        case .hidden:
            self.session.settings.hiddenRepositories.append(trimmed)
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
        guard self.session.settings.showContributionHeader, self.session.hasLoadedRepositories else { return }
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

    nonisolated static func selectVisible(
        all repos: [Repository],
        pinned: [String],
        hidden: Set<String>,
        includeForks: Bool,
        includeArchived: Bool,
        limit: Int
    ) -> [Repository] {
        let pinnedSet = Set(pinned)
        let filtered = repos.filter { !hidden.contains($0.fullName) }
        let visible = RepositoryFilter.apply(
            filtered,
            includeForks: includeForks,
            includeArchived: includeArchived,
            pinned: pinnedSet
        )
        let limited = Array(visible.prefix(max(limit, 0)))
        return limited.sorted { lhs, rhs in
            switch (pinned.firstIndex(of: lhs.fullName), pinned.firstIndex(of: rhs.fullName)) {
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
    var hasLoadedRepositories = false
    var settings = UserSettings()
    var rateLimitReset: Date?
    var lastError: String?
    var contributionHeatmap: [HeatmapCell] = []
    var contributionUser: String?
    var contributionError: String?
    var menuRepoSelection: MenuRepoSelection = .all
}

enum AccountState: Equatable {
    case loggedOut
    case loggingIn
    case loggedIn(UserIdentity)
}
