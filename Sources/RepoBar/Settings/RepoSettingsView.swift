import SwiftUI

struct RepoSettingsView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var appState: AppState
    @State private var newRepoInput = ""
    @State private var newRepoVisibility: RepoVisibility = .pinned
    @State private var selection = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Manage which repositories are pinned in the menubar and which are hidden.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            RepoInputRow(
                placeholder: "owner/name",
                buttonTitle: "Add",
                text: self.$newRepoInput,
                onCommit: self.addNewRepo
            ) {
                Picker("Visibility", selection: self.$newRepoVisibility) {
                    ForEach([RepoVisibility.pinned, .hidden], id: \.id) { vis in
                        Text(vis.label).tag(vis)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            Table(self.rows, selection: self.$selection) {
                TableColumn("Repository") { row in
                    Text(row.name).lineLimit(1).truncationMode(.middle)
                }
                .width(min: 180, ideal: 240, max: .infinity)

                TableColumn("Visibility") { row in
                    Picker("", selection: Binding(
                        get: { row.visibility },
                        set: { newValue in Task { await self.set(row.name, to: newValue) } }
                    )) {
                        ForEach(RepoVisibility.allCases) { vis in
                            Text(vis.label).tag(vis)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140, alignment: .leading)
                }
                .width(min: 140, ideal: 160, max: 180)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .frame(minHeight: 240)
            .onDeleteCommand { self.deleteSelection() }
            .contextMenu(forSelectionType: String.self) { selection in
                Button("Pin") { Task { await self.bulkSet(selection, to: .pinned) } }
                Button("Hide") { Task { await self.bulkSet(selection, to: .hidden) } }
                Button("Set Visible") { Task { await self.bulkSet(selection, to: .visible) } }
            }

            HStack(spacing: 10) {
                Button {
                    self.deleteSelection()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .disabled(self.selection.isEmpty)

                Spacer()

                Button("Refresh Now") {
                    Task { await self.appState.refresh() }
                }
            }
        }
        .padding()
        .onAppear {
            Task { try? await self.appState.github.prefetchedRepositories() }
        }
    }

    private var rows: [RepoRow] {
        var out: [RepoRow] = []
        for (index, name) in self.session.settings.pinnedRepositories.enumerated() {
            out.append(RepoRow(name: name, visibility: .pinned, sortKey: index))
        }
        for name in self.session.settings.hiddenRepositories where !out.contains(where: { $0.name == name }) {
            out.append(RepoRow(name: name, visibility: .hidden, sortKey: Int.max))
        }
        return out.sorted { lhs, rhs in
            if lhs.sortKey != rhs.sortKey { return lhs.sortKey < rhs.sortKey }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func addNewRepo(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.newRepoInput = ""
        Task { await self.set(trimmed, to: self.newRepoVisibility) }
    }

    private func set(_ name: String, to visibility: RepoVisibility) async {
        await self.appState.setVisibility(for: name, to: visibility)
    }

    private func bulkSet(_ ids: Set<String>, to visibility: RepoVisibility) async {
        for id in ids {
            await self.set(id, to: visibility)
        }
        await MainActor.run { self.selection.removeAll() }
    }

    private func deleteSelection() {
        let ids = self.selection
        Task {
            await self.bulkSet(ids, to: .visible)
        }
    }
}

// MARK: - Autocomplete helper

private struct RepoRow: Identifiable, Hashable {
    var id: String { self.name }
    let name: String
    var visibility: RepoVisibility
    let sortKey: Int
}

private struct RepoInputRow<Accessory: View>: View {
    let placeholder: String
    let buttonTitle: String
    @Binding var text: String
    var onCommit: (String) -> Void
    var accessory: () -> Accessory

    @EnvironmentObject var appState: AppState
    @State private var suggestions: [Repository] = []
    @State private var isLoading = false
    @State private var showSuggestions = false
    @State private var selectedIndex: Int?
    @FocusState private var isFocused: Bool
    @State private var searchTask: Task<Void, Never>?

    private var trimmedText: String {
        self.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    ZStack(alignment: .trailing) {
                        TextField(self.placeholder, text: self.$text)
                            .textFieldStyle(.roundedBorder)
                            .focused(self.$isFocused)
                            .onChange(of: self.text) { _, _ in self.scheduleSearch() }
                            .onSubmit { self.commit() }
                            .onTapGesture {
                                self.showSuggestions = true
                                self.scheduleSearch(immediate: true)
                            }
                            .onMoveCommand(perform: self.handleMove)

                        if self.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 8)
                        }
                    }

                    self.accessory()

                    Button(self.buttonTitle) { self.commit() }
                        .disabled(self.trimmedText.isEmpty)
                }
            }

            if self.showSuggestions, !self.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(self.suggestions) { repo in
                        Button {
                            self.commit(repo.fullName)
                        } label: {
                            HStack {
                                Text(repo.fullName)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(repo.owner)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .background(self.isSelected(repo) ? Color.accentColor.opacity(0.12) : .clear)
                        .contentShape(Rectangle())

                        if repo.id != self.suggestions.last?.id {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: 420, alignment: .leading)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.2))
                )
                .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 4)
                .padding(.top, 36) // Drop below the text field row
                .zIndex(10)
            }
        }
        .onChange(of: self.isFocused) { _, newValue in
            if newValue {
                self.scheduleSearch(immediate: true)
            } else {
                self.hideSuggestionsSoon()
            }
        }
        .onDisappear { self.searchTask?.cancel() }
    }

    private func commit(_ value: String? = nil) {
        let trimmed = (value ?? self.trimmedText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.text = ""
        self.suggestions = []
        self.showSuggestions = false
        self.onCommit(trimmed)
    }

    private func scheduleSearch(immediate: Bool = false) {
        self.searchTask?.cancel()
        let query = self.text
        self.searchTask = Task {
            // Debounce to avoid hammering GitHub as the user types.
            if !immediate { try? await Task.sleep(nanoseconds: 450_000_000) }
            await self.loadSuggestions(query: query)
        }
    }

    private func loadSuggestions(query: String) async {
        await MainActor.run {
            self.isLoading = true
            self.showSuggestions = self.isFocused
        }
        defer {
            Task { @MainActor in self.isLoading = false }
        }

        do {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefetched = try? await self.appState.github.prefetchedRepositories()

            let localMatches: [Repository] = {
                guard let prefetched else { return [] }
                if trimmed.isEmpty { return Array(prefetched.prefix(8)) }
                return prefetched.filter { $0.fullName.localizedCaseInsensitiveContains(trimmed) }
            }()

            var merged = Array(localMatches.prefix(8))

            if trimmed.count >= 3 {
                let remote = try await self.appState.github.searchRepositories(matching: trimmed)
                merged = Self.merge(local: localMatches, remote: remote, limit: 8)
            }

            if merged.isEmpty, let prefetched {
                merged = Array(prefetched.prefix(8)) // Fallback to cached recents if nothing matches.
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.suggestions = merged
                if !merged.isEmpty {
                    let current = self.selectedIndex ?? 0
                    self.selectedIndex = max(0, min(current, merged.count - 1))
                }
                // Keep suggestions visible while typing even if focus flickers.
                self.showSuggestions = !self.suggestions.isEmpty && (self.isFocused || !self.trimmedText.isEmpty)
            }
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.suggestions = []
                self.showSuggestions = false
                self.selectedIndex = nil
            }
        }
    }

    private func hideSuggestionsSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.showSuggestions = false
            self.selectedIndex = nil
        }
    }

    private static func merge(local: [Repository], remote: [Repository], limit: Int) -> [Repository] {
        var seen = Set<String>()
        var out: [Repository] = []

        let appendUnique: (Repository) -> Void = { repo in
            let key = repo.fullName.lowercased()
            if !seen.contains(key), out.count < limit {
                seen.insert(key)
                out.append(repo)
            }
        }

        local.forEach(appendUnique)
        remote.forEach(appendUnique)
        return out
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        guard !self.suggestions.isEmpty else { return }
        switch direction {
        case .down:
            let next = (self.selectedIndex ?? -1) + 1
            self.selectedIndex = min(next, self.suggestions.count - 1)
        case .up:
            let prev = (self.selectedIndex ?? 0) - 1
            self.selectedIndex = max(prev, 0)
        default:
            break
        }
    }

    private func isSelected(_ repo: Repository) -> Bool {
        guard let idx = self.selectedIndex else { return false }
        return self.suggestions.indices.contains(idx) && self.suggestions[idx].id == repo.id
    }
}
