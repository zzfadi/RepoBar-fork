import SwiftUI

struct RepoSettingsView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var appState: AppState
    @State private var pinnedInput = ""
    @State private var hiddenInput = ""

    var body: some View {
        Form {
            Section("Pinned repositories") {
                HStack {
                    TextField("owner/name", text: self.$pinnedInput)
                    Button("Add") { self.addPinned() }
                        .disabled(self.pinnedInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                List {
                    ForEach(self.session.settings.pinnedRepositories, id: \.self) { repo in
                        HStack {
                            Text(repo).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Remove") { Task { await self.appState.removePinned(repo) } }
                                .buttonStyle(.link)
                        }
                    }
                    .onDelete { indexes in
                        let toRemove = indexes.map { self.session.settings.pinnedRepositories[$0] }
                        Task { for repo in toRemove {
                            await self.appState.removePinned(repo)
                        } }
                    }
                }
                .frame(minHeight: 120)
            }

            Section("Hidden repositories") {
                HStack {
                    TextField("owner/name", text: self.$hiddenInput)
                    Button("Hide") { self.addHidden() }
                        .disabled(self.hiddenInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                List {
                    ForEach(self.session.settings.hiddenRepositories, id: \.self) { repo in
                        HStack {
                            Text(repo).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Unhide") { Task { await self.appState.unhide(repo) } }
                                .buttonStyle(.link)
                        }
                    }
                    .onDelete { indexes in
                        let toRemove = indexes.map { self.session.settings.hiddenRepositories[$0] }
                        Task { for repo in toRemove {
                            await self.appState.unhide(repo)
                        } }
                    }
                }
                .frame(minHeight: 120)
            }
        }
        .padding()
    }

    private func addPinned() {
        let trimmed = self.pinnedInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.pinnedInput = ""
        Task { await self.appState.addPinned(trimmed) }
    }

    private func addHidden() {
        let trimmed = self.hiddenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.hiddenInput = ""
        Task { await self.appState.hide(trimmed) }
    }
}
