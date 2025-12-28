import AppKit
import RepoBarCore
import SwiftUI

struct ContributionHeaderView: View {
    let username: String
    let displayName: String
    @Bindable var session: Session
    let appState: AppState
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        if self.session.settings.showHeatmap {
            Button {
                self.openProfile()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Contributions · \(self.displayName) · last \(self.session.settings.heatmapSpan.label)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    self.content
                }
            }
            .buttonStyle(.plain)
            .task(id: self.session.hasLoadedRepositories) {
                guard self.session.hasLoadedRepositories else { return }
                let hasHeatmap = self.hasCachedHeatmap
                self.isLoading = !hasHeatmap
                self.failed = false
                await self.appState.loadContributionHeatmapIfNeeded(for: self.username)
                await MainActor.run {
                    self.isLoading = false
                    let hasData = self.hasCachedHeatmap
                    self.failed = !hasData && self.session.contributionError != nil
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !self.session.hasLoadedRepositories && !self.hasCachedHeatmap {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 52, alignment: .center)
        } else if self.isLoading && !self.hasCachedHeatmap {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 52, alignment: .center)
        } else if self.failed {
            VStack(spacing: 6) {
                Text(self.session.contributionError ?? "Unable to load contributions right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    self.appState.clearContributionCache()
                    Task { await self.appState.loadContributionHeatmapIfNeeded(for: self.username) }
                }
                .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
        } else {
            let filtered = HeatmapFilter.filter(self.session.contributionHeatmap, span: self.session.settings.heatmapSpan)
            VStack(spacing: 4) {
                HeatmapView(cells: filtered, accentTone: self.session.settings.accentTone, height: 48)
                    .frame(maxWidth: .infinity, alignment: .leading)
                self.axisLabels
            }
            .accessibilityLabel("Contribution graph for \(self.username)")
        }
    }

    private var axisLabels: some View {
        let now = Date()
        let start = Calendar.current.date(byAdding: .month, value: -self.session.settings.heatmapSpan.months, to: now) ?? now
        return HStack {
            Text(Self.axisFormatter.string(from: start))
            Spacer()
            Text(Self.axisFormatter.string(from: now))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func openProfile() {
        guard let url = profileURL else { return }
        NSWorkspace.shared.open(url)
    }

    private var profileURL: URL? {
        var host = self.session.settings.githubHost
        host.appendPathComponent(self.username)
        return host
    }

    private static let axisFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.2))
            .frame(height: 80)
            .accessibilityLabel("Contribution graph unavailable")
    }

    private var placeholderOverlay: some View {
            self.placeholder.overlay { ProgressView() }
    }

    private var hasCachedHeatmap: Bool {
        self.session.contributionUser == self.username && !self.session.contributionHeatmap.isEmpty
    }
}
