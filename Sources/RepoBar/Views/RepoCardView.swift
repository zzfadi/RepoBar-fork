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
            StatusDot(status: self.repo.ciStatus)
            StatBadge(text: "Issues", value: self.repo.issues)
            StatBadge(text: "PRs", value: self.repo.pulls)
            if let visitors = repo.trafficVisitors { StatBadge(text: "Visitors", value: visitors) }
            if let cloners = repo.trafficCloners { StatBadge(text: "Cloners", value: cloners) }
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
        if !self.repo.heatmap.isEmpty {
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
}

struct StatusDot: View {
    let status: CIStatus
    var body: some View {
        Circle()
            .fill(self.color)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color.black.opacity(0.05), lineWidth: 0.5))
            .help(self.helpText)
    }

    private var color: Color {
        switch self.status {
        case .passing: .green
        case .failing: .red
        case .pending: .yellow
        case .unknown: .gray
        }
    }

    private var helpText: String {
        switch self.status {
        case .passing: "CI passing"
        case .failing: "CI failing"
        case .pending: "CI pending"
        case .unknown: "CI unknown"
        }
    }
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
