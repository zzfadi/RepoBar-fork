import AppKit
import RepoBarCore
import SwiftUI

struct ContributionHeaderView: View {
    let username: String
    let displayName: String
    @Bindable var session: Session
    let appState: AppState
    @State private var isLoading: Bool
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
    }

    var body: some View {
        if !self.hasCachedHeatmap, !self.isLoading {
            EmptyView()
        } else {
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
                await self.appState.loadContributionHeatmapIfNeeded(for: self.username)
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let filtered = HeatmapFilter.filter(self.session.contributionHeatmap, range: self.session.heatmapRange)
        let hasHeatmap = self.hasCachedHeatmap
        let showProgress = (self.session.hasLoadedRepositories == false || self.isLoading) && !hasHeatmap

        ZStack {
            VStack(spacing: 4) {
                HeatmapView(
                    cells: filtered,
                    accentTone: self.session.settings.appearance.accentTone,
                    height: Self.graphHeight
                )
                HeatmapAxisLabelsView(
                    range: self.session.heatmapRange,
                    foregroundStyle: MenuHighlightStyle.secondary(self.isHighlighted)
                )
            }
            .frame(maxWidth: .infinity)
            .opacity(hasHeatmap ? 1 : 0)

            if showProgress {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(hasHeatmap ? "Contribution graph for \(self.username)" : "Contribution graph loading")
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
