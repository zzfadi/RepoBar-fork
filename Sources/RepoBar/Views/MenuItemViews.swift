import RepoBarCore
import SwiftUI

private struct MenuItemHighlightedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var menuItemHighlighted: Bool {
        get { self[MenuItemHighlightedKey.self] }
        set { self[MenuItemHighlightedKey.self] = newValue }
    }
}

struct RepoMenuCardView: View {
    let repo: RepositoryViewModel
    let isPinned: Bool
    let showHeatmap: Bool
    let heatmapSpan: HeatmapSpan
    let accentTone: AccentTone
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: self.verticalSpacing) {
                self.header
                self.stats
                self.activity
                self.errorOrLimit
                self.heatmap
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(self.repo.title)
                        .font(.headline)
                        .lineLimit(1)
                    if self.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    }
                }
                if let release = repo.latestRelease {
                    Text("Latest • \(release) • \(self.repo.latestReleaseDate ?? "")")
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var stats: some View {
        HStack(spacing: 10) {
            MenuCIBadge(status: self.repo.ciStatus, runCount: self.repo.ciRunCount)
            MenuStatBadge(label: "Issues", value: self.repo.issues)
            MenuStatBadge(label: "PRs", value: self.repo.pulls)
            if let visitors = repo.trafficVisitors {
                MenuStatBadge(label: "Visitors", value: visitors)
            }
            if let cloners = repo.trafficCloners {
                MenuStatBadge(label: "Cloners", value: cloners)
            }
        }
    }

    @ViewBuilder
    private var activity: some View {
        if let activity = repo.activityLine {
            Label(activity, systemImage: "text.bubble")
                .font(.caption)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var errorOrLimit: some View {
        if let error = repo.error {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(error)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(MenuHighlightStyle.error(self.isHighlighted))
            }
        } else if let limit = repo.rateLimitedUntil {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .foregroundStyle(.yellow)
                Text("Rate limited until \(RelativeFormatter.string(from: limit, relativeTo: Date()))")
                    .font(.caption)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            }
        }
    }

    @ViewBuilder
    private var heatmap: some View {
        if self.showHeatmap, !self.repo.heatmap.isEmpty {
            let filtered = HeatmapFilter.filter(self.repo.heatmap, span: self.heatmapSpan)
            HeatmapView(cells: filtered, accentTone: self.accentTone)
        }
    }

    private var verticalSpacing: CGFloat { 1 }
}

struct MenuStatBadge: View {
    let label: String
    let value: Int
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        Text("\(self.label) \(self.value)")
            .font(.caption2)
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
    }
}

struct MenuCIBadge: View {
    let status: CIStatus
    let runCount: Int?
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(self.color)
                .frame(width: 6, height: 6)
            Text("CI")
                .font(.caption2)
            if let runCount {
                Text("\(runCount)")
                    .font(.caption2).bold()
            }
        }
        .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
    }

    private var color: Color {
        switch self.status {
        case .passing: .green
        case .failing: .red
        case .pending: .yellow
        case .unknown: .gray
        }
    }
}

struct MenuLoggedOutView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.exclam")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Sign in to see your repositories")
                .font(.headline)
            Text("Connect your GitHub account to load pins and activity.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }
}

struct MenuEmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No repositories yet")
                .font(.headline)
            Text("Pin a repository to see activity here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

struct RateLimitBanner: View {
    let reset: Date
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.fill")
                .foregroundStyle(.orange)
            Text("Rate limit resets \(RelativeFormatter.string(from: self.reset, relativeTo: Date()))")
                .lineLimit(2)
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rate limit reset: \(RelativeFormatter.string(from: self.reset, relativeTo: Date()))")
    }
}

struct ErrorBanner: View {
    let message: String
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(self.message)
                .lineLimit(2)
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(MenuHighlightStyle.error(self.isHighlighted))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(self.message)")
    }
}

enum MenuHighlightStyle {
    static let selectionText = Color(nsColor: .selectedMenuItemTextColor)
    static let normalPrimaryText = Color(nsColor: .controlTextColor)
    static let normalSecondaryText = Color(nsColor: .secondaryLabelColor)

    static func primary(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : self.normalPrimaryText
    }

    static func secondary(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : self.normalSecondaryText
    }

    static func error(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : Color(nsColor: .systemRed)
    }

    static func selectionBackground(_ highlighted: Bool) -> Color {
        highlighted ? Color(nsColor: .selectedContentBackgroundColor) : .clear
    }
}
