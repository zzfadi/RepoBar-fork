import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var appState: AppState
    @State private var showingAddRepo = false
    @State private var contributionWidth: CGFloat = 480

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if self.session.settings.showContributionHeader {
                ContributionHeaderView(username: self.currentUsername())
                    .frame(maxWidth: .infinity)
            }

            if self.isLoggedOut {
                LoggedOutView(onLogin: self.openLogin)
            } else {
                if let reset = session.rateLimitReset {
                    RateLimitBanner(reset: reset)
                }
                if let error = session.lastError {
                    ErrorBanner(message: error)
                }

                HStack {
                    Label("Repositories", systemImage: "shippingbox.fill")
                        .font(.headline)
                    Spacer()
                    Button {
                        self.showingAddRepo = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                }
                if !self.session.settings.pinnedRepositories.isEmpty {
                    Text("Drag cards or use the ... menu to reorder pinned repos.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if self.viewModels().isEmpty {
                    EmptyStateView(
                        isLoggedIn: true,
                        onLogin: self.openLogin)
                } else {
                    RepoGridView(repositories: self.viewModels(), unpin: self.unpin, move: self.movePin)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .sheet(isPresented: self.$showingAddRepo) {
            AddRepoView(isPresented: self.$showingAddRepo) { repo in
                Task { await self.appState.addPinned(repo.fullName) }
            }
            .environmentObject(self.appState)
            .environmentObject(self.session)
        }
        .frame(minWidth: 420, maxWidth: 560)
    }

    private func currentUsername() -> String? {
        if case let .loggedIn(user) = session.account { return user.username }
        return nil
    }

    private func viewModels() -> [RepositoryViewModel] {
        self.session.repositories.prefix(self.session.settings.repoDisplayLimit).map { RepositoryViewModel(repo: $0) }
    }

    private var isLoggedOut: Bool {
        if case .loggedOut = self.session.account { return true }
        return false
    }

    private func unpin(_ repo: RepositoryViewModel) {
        Task { await self.appState.removePinned(repo.title) }
    }

    private func movePin(from source: IndexSet, to destination: Int) {
        var pins = self.session.settings.pinnedRepositories
        pins.move(fromOffsets: source, toOffset: destination)
        self.session.settings.pinnedRepositories = pins
        self.appState.persistSettings()
        Task { await self.appState.refresh() }
    }

    private func openLogin() {
        Task { await self.appState.quickLogin() }
    }
}

private struct LoggedOutView: View {
    let onLogin: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.12))
                    .frame(width: 74, height: 74)
                Image(systemName: "person.crop.circle.badge.exclam")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text("Sign in to see your repositories")
                .font(.headline)
            Text("Connect your GitHub account to load pins and activity.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                self.onLogin()
            } label: {
                Text("Sign in to GitHub")
                    .padding(.horizontal, 14)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

private struct EmptyStateView: View {
    let isLoggedIn: Bool
    let onLogin: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .frame(width: 90, height: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.gray.opacity(0.1), lineWidth: 1))
                Image(systemName: "tray.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text("No repositories yet")
                .font(.headline)
            Text("Pin a repository or sign in to load your recent activity.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !self.isLoggedIn {
                Button("Sign in to GitHub") {
                    self.onLogin()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(.vertical, 16)
    }
}

private struct RateLimitBanner: View {
    let reset: Date
    var body: some View {
        HStack {
            Image(systemName: "clock")
            Text("Rate limited. Resets \(RelativeFormatter.string(from: self.reset, relativeTo: Date()))")
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.yellow.opacity(0.18))
        .clipShape(Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rate limited. Resets \(RelativeFormatter.string(from: self.reset, relativeTo: Date()))")
    }
}

private struct ErrorBanner: View {
    let message: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            Text(self.message)
                .lineLimit(2)
                .foregroundStyle(.white)
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.85))
        .clipShape(Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(self.message)")
    }
}

struct RepoGridView: View {
    let repositories: [RepositoryViewModel]
    let unpin: (RepositoryViewModel) -> Void
    let move: (IndexSet, Int) -> Void

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 12)]

    var body: some View {
        let ordered = self.sorted(self.repositories)
        ScrollView {
            LazyVGrid(columns: self.columns, spacing: 12) {
                ForEach(ordered) { repo in
                    RepoCardView(
                        repo: repo,
                        unpin: { self.unpin(repo) },
                        moveUp: { self.moveStep(repo: repo, in: ordered, direction: -1) },
                        moveDown: { self.moveStep(repo: repo, in: ordered, direction: 1) })
                        .onDrag {
                            let provider = NSItemProvider(object: NSString(string: repo.id))
                            provider.suggestedName = repo.id
                            return provider
                        }
                        .onDrop(of: [.text], delegate: DragReorderDelegate(item: repo, items: ordered, move: self.move))
                }
            }
            .padding(.vertical, 4)
        }
        .frame(minHeight: 260)
    }

    private func sorted(_ repos: [RepositoryViewModel]) -> [RepositoryViewModel] {
        repos.sorted { lhs, rhs in
            switch (lhs.sortOrder, rhs.sortOrder) {
            case let (left?, right?): left < right
            case (.none, .some): false
            case (.some, .none): true
            default: lhs.title < rhs.title
            }
        }
    }

    private func moveStep(repo: RepositoryViewModel, in ordered: [RepositoryViewModel], direction: Int) {
        guard let currentIndex = ordered.firstIndex(of: repo) else { return }
        let maxIndex = max(ordered.count - 1, 0)
        let target = max(0, min(maxIndex, currentIndex + direction))
        guard target != currentIndex else { return }
        self.move(IndexSet(integer: currentIndex), target > currentIndex ? target + 1 : target)
    }
}

private struct DragReorderDelegate: DropDelegate {
    let item: RepositoryViewModel
    let items: [RepositoryViewModel]
    let move: (IndexSet, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
        guard let dragging = itemBeingDragged(info: info),
              let from = items.firstIndex(of: dragging),
              let to = items.firstIndex(of: item),
              from != to else { return }
        self.move(IndexSet(integer: from), to > from ? to + 1 : to)
    }

    func performDrop(info: DropInfo) -> Bool { true }

    private func itemBeingDragged(info: DropInfo) -> RepositoryViewModel? {
        for provider in info.itemProviders(for: [.text]) {
            if let id = provider.suggestedName, let found = items.first(where: { $0.id == id }) { return found }
        }
        return nil
    }
}
