import AppKit
import RepoBarCore
import SwiftUI

struct RepoBarMenuContent: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var hoveredRepo: String?
    @ObservedObject private var updateStatus = SparkleController.shared.updateStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if self.session.settings.showContributionHeader,
               self.session.settings.showHeatmap,
               let username = self.currentUsername,
               let displayName = self.currentDisplayName
            {
                ContributionHeaderView(username: username, displayName: displayName)
                    .environmentObject(self.session)
                    .environmentObject(self.appState)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                Divider()
            }

            switch self.session.account {
            case .loggedOut:
                MenuLoggedOutView()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                Divider()
                Button("Sign in to GitHub") { self.signIn() }
                Divider()
                self.footer
            case .loggingIn:
                MenuLoggedOutView()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                Divider()
                Button("Signing in…") {}
                    .disabled(true)
                Divider()
                self.footer
            case .loggedIn:
                if let reset = self.session.rateLimitReset {
                    RateLimitBanner(reset: reset)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                    Divider()
                } else if let error = self.session.lastError {
                    ErrorBanner(message: error)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                    Divider()
                }

                if self.session.hasLoadedRepositories {
                    MenuRepoFiltersView()
                        .environmentObject(self.session)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    Divider()
                }

                if self.viewModels.isEmpty {
                    let (title, subtitle) = self.emptyStateMessage()
                    MenuEmptyStateView(title: title, subtitle: subtitle)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                } else {
                    ForEach(self.viewModels) { repo in
                        let isPinned = self.session.settings.pinnedRepositories.contains(repo.title)
                        Menu {
                            Button { self.openRepo(repo.title) } label: {
                                Label("Open Repository", systemImage: "folder")
                            }
                            Button { self.openRepoPath(repo.title, path: "issues") } label: {
                                Label("Open Issues", systemImage: "exclamationmark.circle")
                            }
                            Button { self.openRepoPath(repo.title, path: "pulls") } label: {
                                Label("Open Pull Requests", systemImage: "arrow.triangle.branch")
                            }
                            Button { self.openRepoPath(repo.title, path: "actions") } label: {
                                Label("Open Actions", systemImage: "bolt")
                            }
                            Button { self.openRepoPath(repo.title, path: "releases") } label: {
                                Label("Open Releases", systemImage: "tag")
                            }
                            if repo.source.latestRelease != nil {
                                Button { self.openLatestRelease(repo) } label: {
                                    Label("Open Latest Release", systemImage: "tag.fill")
                                }
                            }
                            if repo.activityURL != nil {
                                Button { self.openActivity(repo) } label: {
                                    Label("Open Latest Activity", systemImage: "clock.arrow.circlepath")
                                }
                            }
                            Divider()
                            if isPinned {
                                Button { self.unpin(repo.title) } label: {
                                    Label("Unpin", systemImage: "pin.slash")
                                }
                            } else {
                                Button { self.pin(repo.title) } label: {
                                    Label("Pin", systemImage: "pin")
                                }
                            }
                            Button { self.hide(repo.title) } label: {
                                Label("Hide", systemImage: "eye.slash")
                            }
                            if isPinned, let index = self.pinnedIndex(for: repo.title) {
                                let maxIndex = max(self.session.settings.pinnedRepositories.count - 1, 0)
                                Divider()
                                Button { self.movePinned(repo.title, direction: -1) } label: {
                                    Label("Move Up", systemImage: "arrow.up")
                                }
                                    .disabled(index == 0)
                                Button { self.movePinned(repo.title, direction: 1) } label: {
                                    Label("Move Down", systemImage: "arrow.down")
                                }
                                    .disabled(index >= maxIndex)
                            }
                        } label: {
                            RepoMenuCardView(
                                repo: repo,
                                isPinned: isPinned,
                                showsSeparator: repo.id != self.viewModels.last?.id,
                                showHeatmap: self.session.settings.showHeatmap,
                                heatmapSpan: self.session.settings.heatmapSpan,
                                accentTone: self.session.settings.accentTone
                            )
                            .environment(\.menuItemHighlighted, self.hoveredRepo == repo.id)
                        }
                        .onHover { hovering in
                            self.hoveredRepo = hovering ? repo.id : nil
                        }
                    }
                }

                Divider()
                self.footer
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("About RepoBar") { AppActions.openAbout() }
            Button("Preferences…") {
                NSApp.activate(ignoringOtherApps: true)
                self.openSettings()
            }
                .keyboardShortcut(",", modifiers: [.command])
            if self.updateStatus.isUpdateReady {
                Button("Restart to update") { SparkleController.shared.checkForUpdates() }
            }
            Button("Quit RepoBar") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 6)
    }

    private var viewModels: [RepositoryViewModel] {
        let repos = self.session.repositories
            .prefix(self.session.settings.repoDisplayLimit)
            .map { RepositoryViewModel(repo: $0) }
        var sorted = repos.sorted { lhs, rhs in
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
        if self.session.menuRepoScope == .pinned {
            let pinned = Set(self.session.settings.pinnedRepositories)
            sorted = sorted.filter { pinned.contains($0.title) }
        }
        let onlyWith = self.session.menuRepoFilter.onlyWith
        if onlyWith.isActive {
            sorted = sorted.filter { onlyWith.matches($0.source) }
        }
        return sorted
    }

    private func emptyStateMessage() -> (String, String) {
        let hasPinned = !self.session.settings.pinnedRepositories.isEmpty
        let isPinnedScope = self.session.menuRepoScope == .pinned
        let hasFilter = self.session.menuRepoFilter.onlyWith.isActive
        if isPinnedScope, !hasPinned {
            return ("No pinned repositories", "Pin a repository to see activity here.")
        }
        if isPinnedScope || hasFilter {
            return ("No repositories match this filter", "Try All or a different filter.")
        }
        return ("No repositories yet", "Pin a repository to see activity here.")
    }

    private var currentUsername: String? {
        if case let .loggedIn(user) = self.session.account { return user.username }
        return nil
    }

    private var currentDisplayName: String? {
        guard case let .loggedIn(user) = self.session.account else { return nil }
        let host = user.host.host ?? "github.com"
        return "\(user.username)@\(host)"
    }

    private func signIn() {
        Task { await self.appState.quickLogin() }
    }

    private func pin(_ fullName: String) {
        Task { await self.appState.addPinned(fullName) }
    }

    private func unpin(_ fullName: String) {
        Task { await self.appState.removePinned(fullName) }
    }

    private func hide(_ fullName: String) {
        Task { await self.appState.hide(fullName) }
    }

    private func pinnedIndex(for fullName: String) -> Int? {
        self.session.settings.pinnedRepositories.firstIndex(of: fullName)
    }

    private func movePinned(_ fullName: String, direction: Int) {
        var pins = self.session.settings.pinnedRepositories
        guard let currentIndex = pins.firstIndex(of: fullName) else { return }
        let maxIndex = max(pins.count - 1, 0)
        let target = max(0, min(maxIndex, currentIndex + direction))
        guard target != currentIndex else { return }
        pins.move(fromOffsets: IndexSet(integer: currentIndex), toOffset: target > currentIndex ? target + 1 : target)
        self.session.settings.pinnedRepositories = pins
        self.appState.persistSettings()
        Task { await self.appState.refresh() }
    }

    private func openRepo(_ fullName: String) {
        guard let url = self.repoURL(for: fullName) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openRepoPath(_ fullName: String, path: String) {
        guard var url = self.repoURL(for: fullName) else { return }
        url.appendPathComponent(path)
        NSWorkspace.shared.open(url)
    }

    private func openLatestRelease(_ repo: RepositoryViewModel) {
        guard let url = repo.source.latestRelease?.url else { return }
        NSWorkspace.shared.open(url)
    }

    private func openActivity(_ repo: RepositoryViewModel) {
        guard let url = repo.activityURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func repoURL(for fullName: String) -> URL? {
        let parts = fullName.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        var url = self.session.settings.githubHost
        url.appendPathComponent(String(parts[0]))
        url.appendPathComponent(String(parts[1]))
        return url
    }
}
