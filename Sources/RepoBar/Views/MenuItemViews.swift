import AppKit
import NukeUI
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
    let repo: RepositoryDisplayModel
    let isPinned: Bool
    let showsSeparator: Bool
    let showHeatmap: Bool
    let heatmapRange: HeatmapRange
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
                    .fill(MenuCIBadge.dotColor(
                        for: self.repo.ciStatus,
                        isLightAppearance: self.isLightAppearance,
                        isHighlighted: self.isHighlighted
                    ))
                    .frame(width: 6, height: 6)
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
            Spacer(minLength: 6)
            if let releaseLine = repo.releaseLine {
                Text(releaseLine)
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
            ForEach(self.repo.stats) { stat in
                MenuStatBadge(label: stat.label, value: stat.value, systemImage: stat.systemImage)
            }
        }
    }

    @ViewBuilder
    private var activity: some View {
        if let activity = repo.activityLine {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(activity, systemImage: "text.bubble")
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let age = self.repo.latestActivityAge {
                    Text(age)
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                        .layoutPriority(1)
                        .frame(minWidth: 56, alignment: .trailing)
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
            let filtered = HeatmapFilter.filter(self.repo.heatmap, range: self.heatmapRange)
            HeatmapView(cells: filtered, accentTone: self.accentTone, height: 48)
        }
    }

    private var verticalSpacing: CGFloat { 6 }

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
    private static let iconWidth: CGFloat = 12

    init(label: String?, value: Int, systemImage: String? = nil) {
        self.label = label
        self.valueText = StatValueFormatter.compact(value)
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
                    .frame(width: Self.iconWidth, alignment: .center)
            }
            if let label {
                Text(label)
                    .font(.caption2)
            }
            Text(self.valueText)
                .font(.caption2)
                .monospacedDigit()
                .lineLimit(1)
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
            LazyImage(url: url, transaction: Transaction(animation: nil)) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    self.avatarPlaceholder
                }
            }
            .frame(width: 16, height: 16)
            .clipShape(Circle())
        } else {
            self.avatarPlaceholder
                .frame(width: 16, height: 16)
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color(nsColor: .separatorColor))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        Self.dotColor(for: self.status, isLightAppearance: self.isLightAppearance, isHighlighted: self.isHighlighted)
    }

    private var isLightAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }

    static func dotColor(for status: CIStatus, isLightAppearance: Bool, isHighlighted: Bool) -> Color {
        let base: NSColor = switch status {
        case .passing:
            isLightAppearance
                ? NSColor(srgbRed: 0.12, green: 0.55, blue: 0.24, alpha: 1)
                : NSColor(srgbRed: 0.23, green: 0.8, blue: 0.4, alpha: 1)
        case .failing:
            .systemRed
        case .pending:
            isLightAppearance
                ? NSColor(srgbRed: 0.0, green: 0.45, blue: 0.9, alpha: 1)
                : NSColor(srgbRed: 0.2, green: 0.65, blue: 1.0, alpha: 1)
        case .unknown:
            .tertiaryLabelColor
        }
        let alpha: CGFloat = isHighlighted ? 1.0 : (isLightAppearance ? 0.8 : 0.9)
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
            .font(.subheadline)
            .pickerStyle(.segmented)
            .controlSize(.small)
            .fixedSize()

            Spacer(minLength: 2)
            Picker("Sort", selection: self.$session.settings.menuSortKey) {
                ForEach(RepositorySortKey.menuCases, id: \.self) { sortKey in
                    Label(sortKey.menuLabel, systemImage: sortKey.menuSymbolName)
                        .labelStyle(.iconOnly)
                        .accessibilityLabel(sortKey.menuLabel)
                        .tag(sortKey)
                }
            }
            .labelsHidden()
            .font(.subheadline)
            .pickerStyle(.segmented)
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: self.session.settings.menuSortKey) { _, _ in
            NotificationCenter.default.post(name: .menuFiltersDidChange, object: nil)
        }
        .onChange(of: self.session.menuRepoSelection) { _, _ in
            NotificationCenter.default.post(name: .menuFiltersDidChange, object: nil)
        }
    }
}
