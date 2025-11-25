import SwiftUI

struct ContributionHeaderView: View {
    let username: String?
    @EnvironmentObject var session: Session
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let username {
            VStack(alignment: .leading, spacing: 8) {
                if self.session.contributionHeatmap.isEmpty {
                    self.placeholderOverlay
                } else {
                    let filtered = HeatmapFilter.filter(self.session.contributionHeatmap, span: self.session.settings.heatmapSpan)
                    HeatmapView(cells: filtered, accentTone: self.session.settings.accentTone)
                        .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 120, alignment: .leading)
                        .accessibilityLabel("Contribution graph for \(username)")
                }
            }
            .task {
                await self.appState.loadContributionHeatmapIfNeeded(for: username)
            }
        }
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
}
