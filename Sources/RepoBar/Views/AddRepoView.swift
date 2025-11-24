import SwiftUI

struct AddRepoView: View {
    @Binding var isPresented: Bool
    var onSelect: (Repository) -> Void
    @State private var query = ""
    @State private var results: [Repository] = []
    @State private var isLoading = false

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pin a repository")
                .font(.headline)
            TextField("owner/name", text: self.$query)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    Task { await self.search() }
                }
            if self.isLoading {
                ProgressView().padding(.vertical, 8)
            }
            List(self.results) { repo in
                Button {
                    self.onSelect(repo)
                    self.isPresented = false
                } label: {
                    VStack(alignment: .leading) {
                        Text(repo.fullName).bold()
                        if let release = repo.latestRelease {
                            Text("Latest: \(release.name)").font(.caption)
                        } else {
                            Text("Issues: \(repo.openIssues) • Owner: \(repo.owner)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            HStack {
                Spacer()
                Button("Cancel") { self.isPresented = false }
            }
        }
        .padding(16)
        .frame(width: 380, height: 420)
        .onAppear { Task { await self.searchDefault() } }
    }

    private func searchDefault() async { await self.search() }

    private func search() async {
        self.isLoading = true
        defer { self.isLoading = false }
        do {
            let trimmed = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
            let repos: [Repository] = if trimmed.isEmpty {
                try await self.appState.github.recentRepositories(limit: 10)
            } else {
                try await self.appState.github.searchRepositories(matching: trimmed)
            }
            await MainActor.run { self.results = repos }
        } catch {
            // Ignored; UI stays empty
        }
    }
}
