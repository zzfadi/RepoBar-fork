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

        if let local = repo.localStatus {
            menu.addItem(.separator())
            let stateView = LocalRepoStateMenuView(
                status: local,
                onSync: { [weak target] in target?.syncLocalRepo(local) },
                onRebase: { [weak target] in target?.rebaseLocalRepo(local) },
                onReset: { [weak target] in target?.resetLocalRepo(local) }
            )
            menu.addItem(self.viewItem(for: stateView, enabled: true))
            menu.addItem(self.actionItem(
                title: "Open in Finder",
                action: #selector(StatusBarMenuManager.openLocalFinder(_:)),
                represented: local.path,
                systemImage: "folder"
            ))
            menu.addItem(self.actionItem(
                title: "Open in Terminal",
                action: #selector(StatusBarMenuManager.openLocalTerminal(_:)),
                represented: local.path,
                systemImage: "terminal"
            ))
            menu.addItem(.separator())
            menu.addItem(self.localBranchesSubmenuItem(for: local, fullName: repo.title))
            menu.addItem(self.localWorktreesSubmenuItem(for: local, fullName: repo.title))
            menu.addItem(.separator())
        } else {
            menu.addItem(.separator())
            menu.addItem(self.actionItem(
                title: "Checkout Repo",
                action: #selector(self.target.checkoutRepoFromMenu),
                represented: repo.title,
                systemImage: "arrow.down.to.line"
            ))
            menu.addItem(.separator())
        }

        let commitCount = self.target.cachedRecentCommitCount(fullName: repo.title)
        menu.addItem(self.recentListSubmenuItem(RecentListConfig(
            title: "Commits",
            systemImage: "arrow.turn.down.right",
            fullName: repo.title,
            kind: .commits,
            openTitle: "Open Commits",
            openAction: #selector(self.target.openCommits),
            badgeText: commitCount.flatMap { $0 > 0 ? StatValueFormatter.compact($0) : nil }
        )))
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

        let events = Array(repo.activityEvents.prefix(AppLimits.RepoActivity.limit))
        let activityPreview = Array(events.prefix(AppLimits.RepoActivity.previewLimit))
        if activityPreview.isEmpty == false {
            menu.addItem(.separator())
            menu.addItem(self.infoItem("Activity"))
            activityPreview.forEach { menu.addItem(self.activityMenuItem(for: $0)) }
            if events.count > activityPreview.count {
                menu.addItem(self.repoActivityMoreMenuItem(events: events))
            }
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

    private func localBranchesSubmenuItem(for local: LocalRepoStatus, fullName: String) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self.target
        self.target.registerLocalBranchMenu(submenu, repoPath: local.path, fullName: fullName, localStatus: local)
        submenu.addItem(self.actionItem(
            title: "Create Branch…",
            action: #selector(self.target.createLocalBranch),
            represented: local.path,
            systemImage: "plus"
        ))
        submenu.addItem(.separator())
        submenu.addItem(self.loadingItem())

        let row = RecentListSubmenuRowView(
            title: "Switch Branch",
            systemImage: "point.topleft.down.curvedto.point.bottomright.up",
            badgeText: nil,
            detailText: local.branch == "detached" ? "Detached" : local.branch
        )
        return self.viewItem(for: row, enabled: true, highlightable: true, submenu: submenu)
    }

    private func localWorktreesSubmenuItem(for local: LocalRepoStatus, fullName: String) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self.target
        self.target.registerLocalWorktreeMenu(submenu, repoPath: local.path, fullName: fullName)
        submenu.addItem(self.actionItem(
            title: "Create Worktree…",
            action: #selector(self.target.createLocalWorktree),
            represented: local.path,
            systemImage: "plus"
        ))
        submenu.addItem(.separator())
        submenu.addItem(self.loadingItem())

        let row = RecentListSubmenuRowView(
            title: "Switch Worktree",
            systemImage: "square.stack.3d.down.right",
            badgeText: nil,
            detailText: local.worktreeName
        )
        return self.viewItem(for: row, enabled: true, highlightable: true, submenu: submenu)
    }

    private func loadingItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
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
            items.append(self.infoMessageItem(error))
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

    private func repoActivityMoreMenuItem(events: [ActivityEvent]) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        events.forEach { submenu.addItem(self.activityMenuItem(for: $0)) }
        let item = NSMenuItem(title: "More Activity…", action: nil, keyEquivalent: "")
        item.submenu = submenu
        if let image = self.cachedSystemImage(named: "ellipsis") {
            item.image = image
        }
        return item
    }
}
