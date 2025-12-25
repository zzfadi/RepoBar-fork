import Foundation
import RepoBarCore

struct RepoRow {
    let repo: Repository
    let activityDate: Date?
    let activityLabel: String
    let activityLine: String
}

struct RepoOutput: Codable {
    let fullName: String
    let owner: String
    let name: String
    let repoUrl: URL
    let openIssues: Int
    let openPulls: Int
    let stars: Int
    let pushedAt: Date?
    let activityDate: Date?
    let activityTitle: String?
    let activityActor: String?
    let activityUrl: URL?
    let error: String?
}

struct StatusOutput: Codable {
    let authenticated: Bool
    let host: String?
    let expiresAt: Date?
    let expiresIn: String?
    let expired: Bool?
}

func prepareRows(repos: [Repository], now: Date = Date()) -> [RepoRow] {
    repos.map { repo in
        let activityDate = repo.activityDate
        let activityLabel = activityDate.map { RelativeFormatter.string(from: $0, relativeTo: now) } ?? "-"
        let activityLine = repo.activityLine(fallbackToPush: true) ?? "-"
        return RepoRow(repo: repo, activityDate: activityDate, activityLabel: activityLabel, activityLine: activityLine)
    }
}

func renderTable(
    _ rows: [RepoRow],
    useColor: Bool,
    includeURL: Bool,
    baseHost: URL
) {
    let activityHeader = "ACTIVITY"
    let issuesHeader = "ISSUES"
    let pullsHeader = "PR"
    let starsHeader = "STAR"
    let repoHeader = "REPO"
    let eventHeader = "EVENT"

    let issuesWidth = max(issuesHeader.count, rows.map { String($0.repo.openIssues).count }.max() ?? 1)
    let pullsWidth = max(pullsHeader.count, rows.map { String($0.repo.openPulls).count }.max() ?? 1)
    let starsWidth = max(starsHeader.count, rows.map { String($0.repo.stars).count }.max() ?? 1)
    let activityWidth = max(activityHeader.count, rows.map(\.activityLabel.count).max() ?? 1)

    let header = [
        padRight(activityHeader, to: activityWidth),
        padLeft(issuesHeader, to: issuesWidth),
        padLeft(pullsHeader, to: pullsWidth),
        padLeft(starsHeader, to: starsWidth),
        repoHeader,
        eventHeader
    ].joined(separator: "  ")
    print(useColor ? Ansi.bold.wrap(header) : header)

    for row in rows {
        let issues = padLeft(String(row.repo.openIssues), to: issuesWidth)
        let pulls = padLeft(String(row.repo.openPulls), to: pullsWidth)
        let stars = padLeft(String(row.repo.stars), to: starsWidth)
        let activity = padRight(row.activityLabel, to: activityWidth)
        let repoName = row.repo.fullName
        let repoURL = makeRepoURL(baseHost: baseHost, repo: row.repo)
        let repoLabel = formatRepoLabel(
            repoName: repoName,
            repoURL: repoURL,
            includeURL: includeURL,
            linkEnabled: Ansi.supportsLinks
        )
        let lineText = row.activityLine.singleLine
        let lineURL = row.repo.latestActivity?.url
        let line = formatEventLabel(
            text: lineText,
            url: lineURL,
            includeURL: includeURL,
            linkEnabled: Ansi.supportsLinks
        )

        let coloredActivity = useColor ? Ansi.gray.wrap(activity) : activity
        let coloredIssues = useColor ? (row.repo.openIssues > 0 ? Ansi.red.wrap(issues) : Ansi.gray.wrap(issues)) : issues
        let coloredPulls = useColor ? (row.repo.openPulls > 0 ? Ansi.magenta.wrap(pulls) : Ansi.gray.wrap(pulls)) : pulls
        let coloredStars = useColor ? (row.repo.stars > 0 ? Ansi.yellow.wrap(stars) : Ansi.gray.wrap(stars)) : stars
        let coloredRepo = useColor ? Ansi.cyan.wrap(repoLabel) : repoLabel
        let coloredLine = useColor && row.repo.error != nil ? Ansi.red.wrap(line) : line

        let output = [
            coloredActivity,
            coloredIssues,
            coloredPulls,
            coloredStars,
            coloredRepo,
            coloredLine
        ].joined(separator: "  ")
        print(output)

        if let error = row.repo.error {
            let message = "  ! \(error)"
            print(useColor ? Ansi.red.wrap(message) : message)
        }
    }
}

func renderJSON(_ rows: [RepoRow], baseHost: URL) throws {
    let items = rows.map { row in
        RepoOutput(
            fullName: row.repo.fullName,
            owner: row.repo.owner,
            name: row.repo.name,
            repoUrl: makeRepoURL(baseHost: baseHost, repo: row.repo),
            openIssues: row.repo.openIssues,
            openPulls: row.repo.openPulls,
            stars: row.repo.stars,
            pushedAt: row.repo.pushedAt,
            activityDate: row.activityDate,
            activityTitle: row.repo.latestActivity?.title,
            activityActor: row.repo.latestActivity?.actor,
            activityUrl: row.repo.latestActivity?.url,
            error: row.repo.error
        )
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(items)
    if let json = String(data: data, encoding: .utf8) {
        print(json)
    }
}

func padLeft(_ value: String, to width: Int) -> String {
    let pad = max(0, width - value.count)
    return String(repeating: " ", count: pad) + value
}

func padRight(_ value: String, to width: Int) -> String {
    let pad = max(0, width - value.count)
    return value + String(repeating: " ", count: pad)
}

func makeRepoURL(baseHost: URL, repo: Repository) -> URL {
    baseHost.appending(path: "/\(repo.owner)/\(repo.name)")
}

func formatRepoLabel(
    repoName: String,
    repoURL: URL,
    includeURL: Bool,
    linkEnabled: Bool
) -> String {
    includeURL ? formatURL(repoURL, linkEnabled: linkEnabled) : repoName
}

func formatEventLabel(
    text: String,
    url: URL?,
    includeURL: Bool,
    linkEnabled: Bool
) -> String {
    guard includeURL, let url else { return text }
    return formatURL(url, linkEnabled: linkEnabled)
}

func formatURL(_ url: URL, linkEnabled: Bool) -> String {
    if linkEnabled {
        return Ansi.link(url.absoluteString, url: url, enabled: true)
    }
    return url.absoluteString
}
