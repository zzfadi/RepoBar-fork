import AppKit
import RepoBarCore
import SwiftUI

extension StatusBarMenuBuilder {
    func makeRepoSubmenu(for repo: RepositoryDisplayModel, isPinned: Bool) -> NSMenu {
        let signpost = self.signposter.beginInterval("makeRepoSubmenu")
        defer { self.signposter.endInterval("makeRepoSubmenu", signpost) }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self.target
        let settings = self.appState.session.settings

        let openRow = RecentListSubmenuRowView(
            title: "Open \(repo.title)",
            systemImage: "folder",
            badgeText: nil,
            onOpen: { [weak target] in
                target?.openRepoFromMenu(fullName: repo.title)
            }
        )
        menu.addItem(self.viewItem(for: openRow, enabled: true, highlightable: true))

        menu.addItem(self.recentListSubmenuItem(RecentListConfig(
            title: "Issues",
            systemImage: "exclamationmark.circle",
            fullName: repo.title,
            kind: .issues,
            openTitle: "Open Issues",
            openAction: #selector(self.target.openIssues),
            badgeText: repo.issues > 0 ? StatValueFormatter.compact(repo.issues) : nil
        )))
        menu.addItem(self.recentListSubmenuItem(RecentListConfig(
            title: "Pull Requests",
            systemImage: "arrow.triangle.branch",
            fullName: repo.title,
            kind: .pullRequests,
            openTitle: "Open Pull Requests",
            openAction: #selector(self.target.openPulls),
            badgeText: repo.pulls > 0 ? StatValueFormatter.compact(repo.pulls) : nil
        )))
        let cachedReleaseCount = self.target.cachedRecentListCount(fullName: repo.title, kind: .releases)
        menu.addItem(self.recentListSubmenuItem(RecentListConfig(
            title: "Releases",
            systemImage: "tag",
            fullName: repo.title,
            kind: .releases,
            openTitle: "Open Releases",
            openAction: #selector(self.target.openReleases),
            badgeText: cachedReleaseCount.flatMap { $0 > 0 ? String($0) : nil }
        )))
        let runBadge = repo.ciRunCount.flatMap { $0 > 0 ? String($0) : nil }
        menu.addItem(self.recentListSubmenuItem(RecentListConfig(
            title: "CI Runs",
            systemImage: "bolt",
            fullName: repo.title,
            kind: .ciRuns,
            openTitle: "Open Actions",
            openAction: #selector(self.target.openActions),
            badgeText: runBadge
        )))
        let cachedDiscussionCount = self.target.cachedRecentListCount(fullName: repo.title, kind: .discussions)
        menu.addItem(self.recentListSubmenuItem(RecentListConfig(
            title: "Discussions",
            systemImage: "bubble.left.and.bubble.right",
            fullName: repo.title,
            kind: .discussions,
            openTitle: "Open Discussions",
            openAction: #selector(self.target.openDiscussions),
            badgeText: cachedDiscussionCount.flatMap { $0 > 0 ? String($0) : nil }
        )))
        let cachedTagCount = self.target.cachedRecentListCount(fullName: repo.title, kind: .tags)
        menu.addItem(self.recentListSubmenuItem(RecentListConfig(
            title: "Tags",
            systemImage: "tag",
            fullName: repo.title,
            kind: .tags,
            openTitle: "Open Tags",
            openAction: #selector(self.target.openTags),
            badgeText: cachedTagCount.flatMap { $0 > 0 ? String($0) : nil }
        )))
        let cachedBranchCount = self.target.cachedRecentListCount(fullName: repo.title, kind: .branches)
        menu.addItem(self.recentListSubmenuItem(RecentListConfig(
            title: "Branches",
            systemImage: "point.topleft.down.curvedto.point.bottomright.up",
            fullName: repo.title,
            kind: .branches,
            openTitle: "Open Branches",
            openAction: #selector(self.target.openBranches),
            badgeText: cachedBranchCount.flatMap { $0 > 0 ? String($0) : nil }
        )))
        let cachedContributorCount = self.target.cachedRecentListCount(fullName: repo.title, kind: .contributors)
        menu.addItem(self.recentListSubmenuItem(RecentListConfig(
            title: "Contributors",
            systemImage: "person.2",
            fullName: repo.title,
            kind: .contributors,
            openTitle: "Open Contributors",
            openAction: #selector(self.target.openContributors),
            badgeText: cachedContributorCount.flatMap { $0 > 0 ? String($0) : nil }
        )))

        if repo.activityURL != nil {
            menu.addItem(self.actionItem(
                title: "Open Activity",
                action: #selector(self.target.openActivity),
                represented: repo.title,
                systemImage: "clock.arrow.circlepath"
            ))
        }
        if let local = repo.localStatus {
            menu.addItem(self.actionItem(
                title: "Open in Finder",
                action: #selector(self.target.openLocalFinder),
                represented: local.path,
                systemImage: "folder"
            ))
            menu.addItem(self.actionItem(
                title: "Open in Terminal",
                action: #selector(self.target.openLocalTerminal),
                represented: local.path,
                systemImage: "terminal"
            ))
        }

        if settings.heatmap.display == .submenu, !repo.heatmap.isEmpty {
            let filtered = HeatmapFilter.filter(repo.heatmap, range: self.appState.session.heatmapRange)
            let heatmap = VStack(spacing: 4) {
                HeatmapView(
                    cells: filtered,
                    accentTone: settings.appearance.accentTone,
                    height: MenuStyle.heatmapSubmenuHeight
                )
                HeatmapAxisLabelsView(range: self.appState.session.heatmapRange, foregroundStyle: Color.secondary)
            }
            .padding(.horizontal, MenuStyle.cardHorizontalPadding)
            .padding(.vertical, MenuStyle.cardVerticalPadding)
            menu.addItem(.separator())
            menu.addItem(self.viewItem(for: heatmap, enabled: false))
        }

        let events = Array(repo.activityEvents.prefix(10))
        if events.isEmpty == false {
            menu.addItem(.separator())
            menu.addItem(self.infoItem("Activity"))
            events.forEach { menu.addItem(self.repoActivityItem(for: $0)) }
        }

        let detailItems = self.repoDetailItems(for: repo)
        if !detailItems.isEmpty {
            menu.addItem(.separator())
            menu.addItem(self.infoItem("Details"))
            detailItems.forEach { menu.addItem($0) }
        }

        menu.addItem(.separator())

        if isPinned {
            menu.addItem(self.actionItem(
                title: "Unpin",
                action: #selector(self.target.unpinRepo),
                represented: repo.title,
                systemImage: "pin.slash"
            ))
        } else {
            menu.addItem(self.actionItem(
                title: "Pin",
                action: #selector(self.target.pinRepo),
                represented: repo.title,
                systemImage: "pin"
            ))
        }
        menu.addItem(self.actionItem(
            title: "Hide",
            action: #selector(self.target.hideRepo),
            represented: repo.title,
            systemImage: "eye.slash"
        ))

        if isPinned {
            let pins = self.appState.session.settings.repoList.pinnedRepositories
            if let index = pins.firstIndex(of: repo.title) {
                let moveUp = self.actionItem(
                    title: "Move Up",
                    action: #selector(self.target.moveRepoUp),
                    represented: repo.title,
                    systemImage: "arrow.up"
                )
                moveUp.isEnabled = index > 0
                let moveDown = self.actionItem(
                    title: "Move Down",
                    action: #selector(self.target.moveRepoDown),
                    represented: repo.title,
                    systemImage: "arrow.down"
                )
                moveDown.isEnabled = index < pins.count - 1
                menu.addItem(.separator())
                menu.addItem(moveUp)
                menu.addItem(moveDown)
            }
        }

        return menu
    }

    private struct RecentListConfig {
        let title: String
        let systemImage: String
        let fullName: String
        let kind: RepoRecentMenuKind
        let openTitle: String
        let openAction: Selector
        let badgeText: String?
    }

    private func recentListSubmenuItem(_ config: RecentListConfig) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self.target
        self.target.registerRecentListMenu(
            submenu,
            context: RepoRecentMenuContext(fullName: config.fullName, kind: config.kind)
        )

        submenu.addItem(self.actionItem(
            title: config.openTitle,
            action: config.openAction,
            represented: config.fullName,
            systemImage: config.systemImage
        ))
        submenu.addItem(.separator())
        let loading = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
        loading.isEnabled = false
        submenu.addItem(loading)

        let row = RecentListSubmenuRowView(
            title: config.title,
            systemImage: config.systemImage,
            badgeText: config.badgeText
        )
        return self.viewItem(for: row, enabled: true, highlightable: true, submenu: submenu)
    }

    private func repoDetailItems(for repo: RepositoryDisplayModel) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if let error = repo.error, RepositoryErrorClassifier.isNonCriticalMenuWarning(error) {
            items.append(self.infoItem(error))
        }
        if let local = repo.localStatus {
            items.append(self.infoItem("Branch: \(local.branch)"))
            items.append(self.infoItem("Sync: \(local.syncDetail)"))
        }
        if let visitors = repo.trafficVisitors {
            items.append(self.infoItem("Visitors (14d): \(visitors)"))
        }
        if let cloners = repo.trafficCloners {
            items.append(self.infoItem("Cloners (14d): \(cloners)"))
        }
        return items
    }

    private func repoActivityItem(for event: ActivityEvent) -> NSMenuItem {
        let view = ActivityMenuItemView(event: event, symbolName: self.activitySymbolName(for: event)) { [weak target] in
            target?.open(url: event.url)
        }
        return self.viewItem(for: view, enabled: true, highlightable: true)
    }

    private func activitySymbolName(for event: ActivityEvent) -> String {
        guard let type = event.eventTypeEnum else { return "clock" }
        switch type {
        case .pullRequest: return "arrow.triangle.branch"
        case .pullRequestReview: return "checkmark.bubble"
        case .pullRequestReviewComment: return "text.bubble"
        case .pullRequestReviewThread: return "text.bubble"
        case .issueComment: return "text.bubble"
        case .issues: return "exclamationmark.circle"
        case .push: return "arrow.up.circle"
        case .release: return "tag"
        case .watch: return "star"
        case .fork: return "doc.on.doc"
        case .create: return "plus"
        case .delete: return "trash"
        case .member: return "person.badge.plus"
        case .public: return "globe"
        case .gollum: return "book"
        case .commitComment: return "text.bubble"
        case .discussion: return "bubble.left.and.bubble.right"
        case .sponsorship: return "heart"
        }
    }
}
