import RepoBarCore
import SwiftUI
import AppKit

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
    let showsSeparator: Bool
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
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            if self.showsSeparator {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 1)
                    .padding(.leading, 10)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(self.repo.title)
                        .font(.subheadline)
                        .fontWeight(.regular)
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
        HStack(spacing: 12) {
            MenuCIBadge(status: self.repo.ciStatus, runCount: nil)
            MenuStatBadge(label: "Issues", value: self.repo.issues)
            MenuStatBadge(label: "PRs", value: self.repo.pulls)
            MenuStatBadge(label: "Visitors", valueText: self.repo.trafficVisitors.map(String.init) ?? "--")
            MenuStatBadge(label: "Cloners", valueText: self.repo.trafficCloners.map(String.init) ?? "--")
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
            HeatmapView(cells: filtered, accentTone: self.accentTone, height: 44)
        }
    }

    private var verticalSpacing: CGFloat { 4 }
}

struct MenuStatBadge: View {
    let label: String
    let valueText: String
    @Environment(\.menuItemHighlighted) private var isHighlighted

    init(label: String, value: Int) {
        self.label = label
        self.valueText = "\(value)"
    }

    init(label: String, valueText: String) {
        self.label = label
        self.valueText = valueText
    }

    var body: some View {
        Text("\(self.label) \(self.valueText)")
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
        let base: NSColor = switch self.status {
        case .passing: .systemGreen
        case .failing: .systemRed
        case .pending: .systemYellow
        case .unknown: .tertiaryLabelColor
        }
        let adjusted = self.isLightAppearance ? base.withAlphaComponent(0.6) : base
        return Color(nsColor: adjusted)
    }

    private var isLightAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
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
    let title: String
    let subtitle: String

    init(
        title: String = "No repositories yet",
        subtitle: String = "Pin a repository to see activity here."
    ) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(self.title)
                .font(.headline)
            Text(self.subtitle)
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

struct MenuRepoFiltersView: View {
    @EnvironmentObject var session: Session

    var body: some View {
        HStack(spacing: 8) {
            Picker("Scope", selection: self.$session.menuRepoScope) {
                ForEach(MenuRepoScope.allCases, id: \.self) { scope in
                    Text(scope.label).tag(scope)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .fixedSize()

            Spacer(minLength: 8)

            Picker("Filter", selection: self.$session.menuRepoFilter) {
                ForEach(MenuRepoFilter.allCases, id: \.self) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: self.session.menuRepoScope) { _, _ in
            NotificationCenter.default.post(name: .menuFiltersDidChange, object: nil)
        }
        .onChange(of: self.session.menuRepoFilter) { _, _ in
            NotificationCenter.default.post(name: .menuFiltersDidChange, object: nil)
        }
    }
}
