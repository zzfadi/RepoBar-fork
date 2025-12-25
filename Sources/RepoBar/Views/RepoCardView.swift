import RepoBarCore
import SwiftUI

struct RepoCardView: View {
    let repo: RepositoryViewModel
    let isPinned: Bool
    let unpin: () -> Void
    let hide: () -> Void
    let moveUp: (() -> Void)?
    let moveDown: (() -> Void)?
    @EnvironmentObject var session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: self.verticalSpacing) {
            self.header
            self.stats
            self.activity
            self.errorOrLimit
            self.heatmap
        }
        .padding(self.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { self.open(url: self.repoURL()) }
        .accessibilityAction(named: Text("Move down")) { self.moveDown?() }
        .accessibilityAction(named: Text("Move up")) { self.moveUp?() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(self.accessibilitySummary())
    }

    private func repoURL() -> URL {
        URL(string: "https://github.com/\(self.repo.title)")!
    }

    private func open(url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func accessibilitySummary() -> String {
        var parts: [String] = [self.repo.title]
        parts.append("CI \(self.repo.ciStatus)")
        parts.append("Issues \(self.repo.issues)")
        parts.append("Pull requests \(self.repo.pulls)")
        if let release = self.repo.latestReleaseDate {
            parts.append("Latest release \(release)")
        }
        if let activity = self.repo.activityLine {
            parts.append("Activity \(activity)")
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(self.repo.title)
                    .font(.headline)
                    .lineLimit(1)
                if let release = repo.latestRelease {
                    Text("Latest • \(release) • \(self.repo.latestReleaseDate ?? "")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                if self.isPinned { Button("Unpin", action: self.unpin) }
                Button("Hide", action: self.hide)
                Button("Open in GitHub") { self.open(url: self.repoURL()) }
                if let moveUp { Button("Move up", action: moveUp) }
                if let moveDown { Button("Move down", action: moveDown) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .symbolRenderingMode(.hierarchical)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var stats: some View {
        HStack(spacing: 10) {
            LinkBadge(
                text: "CI",
                valueText: self.repo.ciRunCount.map(String.init),
                color: self.ciColor,
                action: { self.open(url: self.actionsURL()) }
            )
            LinkBadge(
                text: "Issues",
                valueText: "\(self.repo.issues)",
                color: Color(nsColor: .windowBackgroundColor),
                action: { self.open(url: self.issuesURL()) }
            )
            LinkBadge(
                text: "PRs",
                valueText: "\(self.repo.pulls)",
                color: Color(nsColor: .windowBackgroundColor),
                action: { self.open(url: self.pullsURL()) }
            )
            if let visitors = repo.trafficVisitors {
                StatBadge(text: "Visitors", value: visitors)
            }
            if let cloners = repo.trafficCloners {
                StatBadge(text: "Cloners", value: cloners)
            }
        }
    }

    @ViewBuilder
    private var activity: some View {
        if let activity = repo.activityLine, let url = repo.activityURL {
            Button { self.open(url: url) } label: {
                Label(activity, systemImage: "text.bubble")
                    .font(.caption)
                    .lineLimit(2)
            }
            .buttonStyle(.link)
        }
    }

    @ViewBuilder
    private var errorOrLimit: some View {
        if let error = repo.error {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(error).font(.caption).lineLimit(2)
            }
        } else if let limit = repo.rateLimitedUntil {
            HStack(spacing: 6) {
                Image(systemName: "clock").foregroundStyle(.yellow)
                Text("Rate limited until \(RelativeFormatter.string(from: limit, relativeTo: Date()))")
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var heatmap: some View {
        if self.session.settings.showHeatmap, !self.repo.heatmap.isEmpty {
            let filtered = HeatmapFilter.filter(self.repo.heatmap, span: self.session.settings.heatmapSpan)
            HeatmapView(cells: filtered, accentTone: self.session.settings.accentTone)
        }
    }

    private var cardPadding: CGFloat {
        switch self.session.settings.cardDensity {
        case .comfortable: 14
        case .compact: 10
        }
    }

    private var verticalSpacing: CGFloat {
        switch self.session.settings.cardDensity {
        case .comfortable: 10
        case .compact: 8
        }
    }

    private var ciColor: Color {
        switch self.repo.ciStatus {
        case .passing: .green
        case .failing: .red
        case .pending: .yellow
        case .unknown: .gray
        }
    }

    private func issuesURL() -> URL {
        URL(string: "https://github.com/\(self.repo.title)/issues")!
    }

    private func pullsURL() -> URL {
        URL(string: "https://github.com/\(self.repo.title)/pulls")!
    }

    private func actionsURL() -> URL {
        URL(string: "https://github.com/\(self.repo.title)/actions")!
    }
}

private struct CIBadge: View {
    let status: CIStatus
    let runCount: Int?
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(self.color)
                .frame(width: 10, height: 10)
            Text("CI")
                .font(.caption).bold()
            if let runCount {
                Text("\(runCount)")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(self.color.opacity(0.18))
        .foregroundStyle(self.color)
        .clipShape(Capsule(style: .continuous))
        .help(self.helpText)
    }

    private var color: Color { .clear }
    private var helpText: String { "" }
}

struct StatBadge: View {
    let text: String
    let value: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(self.text)
                .font(.caption2)
            Text("\(self.value)")
                .font(.caption2).bold()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct LinkBadge: View {
    let text: String
    let valueText: String?
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 4) {
                Text(self.text)
                    .font(.caption2)
                if let valueText {
                    Text(valueText)
                        .font(.caption2).bold()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(self.color.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(self.color.opacity(0.35), lineWidth: 1)
            )
            .foregroundStyle(self.color == Color(nsColor: .windowBackgroundColor) ? .primary : self.color)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
