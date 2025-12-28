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
    let onOpen: (() -> Void)?
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
        .contentShape(Rectangle())
        .onTapGesture {
            self.onOpen?()
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(MenuCIBadge.dotColor(for: self.repo.ciStatus, isLightAppearance: self.isLightAppearance))
                    .frame(width: 6, height: 6)
                Text(self.repo.title)
                    .font(.subheadline)
                    .fontWeight(.regular)
                    .lineLimit(1)
                if let lastPushAge = self.repo.lastPushAge {
                    Text("• \(lastPushAge)")
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                }
                if self.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                }
            }
            Spacer(minLength: 6)
            if let release = repo.latestRelease {
                let date = self.repo.latestReleaseDate ?? ""
                Text(date.isEmpty ? release : "\(release) • \(date)")
                    .font(.system(size: 10))
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    @ViewBuilder
    private var stats: some View {
        HStack(spacing: 12) {
            MenuStatBadge(label: "Issues", value: self.repo.issues, systemImage: "exclamationmark.circle")
            MenuStatBadge(label: "PRs", value: self.repo.pulls, systemImage: "arrow.triangle.branch")
            MenuStatBadge(label: nil, value: self.repo.stars, systemImage: "star")
            MenuStatBadge(label: "Forks", value: self.repo.forks, systemImage: "tuningfork")
        }
    }

    @ViewBuilder
    private var activity: some View {
        if let activity = repo.activityLine {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(activity, systemImage: "text.bubble")
                    .font(.caption)
                    .lineLimit(2)
                    .layoutPriority(1)
                Spacer(minLength: 6)
                if let age = self.repo.latestActivityAge {
                    Text(age)
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
        }
    }

    @ViewBuilder
    private var errorOrLimit: some View {
        if let error = repo.error {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(self.warningColor)
                Text(error)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(MenuHighlightStyle.error(self.isHighlighted))
            }
        } else if let limit = repo.rateLimitedUntil {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .foregroundStyle(self.warningColor)
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

    private var isLightAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }

    private var warningColor: Color {
        self.isLightAppearance ? Color(nsColor: .systemOrange) : Color(nsColor: .systemYellow)
    }
}

struct MenuStatBadge: View {
    let label: String?
    let valueText: String
    let systemImage: String?
    @Environment(\.menuItemHighlighted) private var isHighlighted

    init(label: String?, value: Int, systemImage: String? = nil) {
        self.label = label
        self.valueText = "\(value)"
        self.systemImage = systemImage
    }

    init(label: String?, valueText: String, systemImage: String? = nil) {
        self.label = label
        self.valueText = valueText
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(self.label.map { "\($0) \(self.valueText)" } ?? self.valueText)
                .font(.caption2)
        }
        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
    }
}

struct MenuPaddedSeparatorView: View {
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    init(horizontalPadding: CGFloat = 10, verticalPadding: CGFloat = 6) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .padding(.horizontal, self.horizontalPadding)
            .padding(.vertical, self.verticalPadding)
    }
}

struct ActivityMenuItemView: View {
    let event: ActivityEvent
    let symbolName: String
    let onOpen: () -> Void
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: self.symbolName)
                .font(.caption)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            self.avatar
            Text(self.labelText)
                .font(.caption)
                .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                .lineLimit(2)
            Spacer(minLength: 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { self.onOpen() }
    }

    private var labelText: String {
        let when = RelativeFormatter.string(from: self.event.date, relativeTo: Date())
        return "\(when) • \(self.event.actor): \(self.event.title)"
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = self.event.actorAvatarURL {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Color(nsColor: .separatorColor))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    )
            }
            .frame(width: 16, height: 16)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Color(nsColor: .separatorColor))
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                )
                .frame(width: 16, height: 16)
        }
    }
}

struct MenuCIBadge: View {
    let status: CIStatus
    let runCount: Int?
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(spacing: 2) {
            Circle()
                .fill(self.color)
                .frame(width: 6, height: 6)
            if let runCount {
                Text("\(runCount)")
                    .font(.caption2).bold()
            }
        }
        .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
    }

    private var color: Color {
        Self.dotColor(for: self.status, isLightAppearance: self.isLightAppearance)
    }

    private var isLightAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }

    static func dotColor(for status: CIStatus, isLightAppearance: Bool) -> Color {
        let base: NSColor = switch status {
        case .passing: .systemGreen
        case .failing: .systemRed
        case .pending: .systemYellow
        case .unknown: .tertiaryLabelColor
        }
        let alpha: CGFloat = isLightAppearance ? 0.45 : 0.85
        let adjusted = base.withAlphaComponent(alpha)
        return Color(nsColor: adjusted)
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
        HStack(spacing: 6) {
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
        HStack(spacing: 6) {
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
        highlighted
            ? Color(nsColor: .selectedMenuItemTextColor).opacity(0.86)
            : self.normalSecondaryText
    }

    static func error(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : Color(nsColor: .systemRed)
    }

    static func selectionBackground(_ highlighted: Bool) -> Color {
        highlighted ? Color(nsColor: .selectedContentBackgroundColor) : .clear
    }
}

struct MenuRepoFiltersView: View {
    @Bindable var session: Session

    var body: some View {
        HStack(spacing: 1) {
            Picker("Filter", selection: self.$session.menuRepoSelection) {
                ForEach(MenuRepoSelection.allCases, id: \.self) { selection in
                    Text(selection.label).tag(selection)
                }
            }
            .labelsHidden()
            .font(.caption2)
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .fixedSize()

            Spacer(minLength: 0)
            Picker("Sort", selection: self.$session.settings.menuSortKey) {
                ForEach(RepositorySortKey.menuCases, id: \.self) { sortKey in
                    Label(sortKey.menuLabel, systemImage: sortKey.menuSymbolName)
                        .tag(sortKey)
                }
            }
            .labelsHidden()
            .font(.caption2)
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: self.session.settings.menuSortKey) { _, _ in
            NotificationCenter.default.post(name: .menuFiltersDidChange, object: nil)
        }
        .onChange(of: self.session.menuRepoSelection) { _, _ in
            NotificationCenter.default.post(name: .menuFiltersDidChange, object: nil)
        }
    }
}
