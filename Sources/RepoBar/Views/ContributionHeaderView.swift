import SwiftUI

struct ContributionHeaderView: View {
    let username: String
    @EnvironmentObject var session: Session
    @EnvironmentObject var appState: AppState
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        if self.session.settings.showHeatmap {
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .task {
                self.isLoading = true
                self.failed = false
                await self.appState.loadContributionHeatmapIfNeeded(for: username)
                await MainActor.run {
                    self.isLoading = false
                    self.failed = self.session.contributionHeatmap.isEmpty
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if self.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 120, alignment: .center)
        } else if self.failed {
            Text("Unable to load contributions right now.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
        } else {
            let filtered = HeatmapFilter.filter(self.session.contributionHeatmap, span: self.session.settings.heatmapSpan)
            HeatmapView(cells: filtered, accentTone: self.session.settings.accentTone)
                .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 120, alignment: .leading)
                .accessibilityLabel("Contribution graph for \(self.username)")
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
