import AppKit
import RepoBarCore
import SwiftUI

struct ContributionHeaderView: View {
    let username: String
    let displayName: String
    @Bindable var session: Session
    let appState: AppState
    @State private var isLoading: Bool
    @State private var failed: Bool
    @Environment(\.menuItemHighlighted) private var isHighlighted

    init(
        username: String,
        displayName: String,
        session: Session,
        appState: AppState
    ) {
        self.username = username
        self.displayName = displayName
        self.session = session
        self.appState = appState
        let hasHeatmap = session.contributionUser == username && !session.contributionHeatmap.isEmpty
        _isLoading = State(initialValue: !hasHeatmap)
        _failed = State(initialValue: false)
    }

    var body: some View {
        Button {
            self.openProfile()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Contributions · \(self.displayName) · last \(self.session.settings.heatmap.span.label)")
                    .font(.caption2)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                self.content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
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

    @ViewBuilder
    private var content: some View {
        if !self.session.hasLoadedRepositories, !self.hasCachedHeatmap {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 52, alignment: .center)
        } else if self.isLoading, !self.hasCachedHeatmap {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 52, alignment: .center)
        } else if self.failed {
            VStack(spacing: 6) {
                Text(self.session.contributionError ?? "Unable to load contributions right now.")
                    .font(.caption)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    self.appState.clearContributionCache()
                    Task { await self.appState.loadContributionHeatmapIfNeeded(for: self.username) }
                }
                .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
        } else {
            let filtered = HeatmapFilter.filter(self.session.contributionHeatmap, range: self.session.heatmapRange)
            VStack(spacing: 4) {
                HeatmapView(cells: filtered, accentTone: self.session.settings.appearance.accentTone, height: Self.graphHeight)
                HeatmapAxisLabelsView(
                    range: self.session.heatmapRange,
                    foregroundStyle: MenuHighlightStyle.secondary(self.isHighlighted)
                )
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Contribution graph for \(self.username)")
        }
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

    private static let graphHeight: CGFloat = 48
}
