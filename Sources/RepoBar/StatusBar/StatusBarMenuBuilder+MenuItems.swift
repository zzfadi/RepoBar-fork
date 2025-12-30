import AppKit
import SwiftUI

extension StatusBarMenuBuilder {
    func paddedSeparator() -> NSMenuItem {
        self.viewItem(for: MenuPaddedSeparatorView(), enabled: false)
    }

    func repoCardSeparator() -> NSMenuItem {
        self.viewItem(for: RepoCardSeparatorRowView(), enabled: false)
    }

    func repoMenuItem(for repo: RepositoryDisplayModel, isPinned: Bool) -> NSMenuItem {
        let card = RepoMenuCardView(
            repo: repo,
            isPinned: isPinned,
            showHeatmap: self.appState.session.settings.heatmap.display == .inline,
            heatmapRange: self.appState.session.heatmapRange,
            accentTone: self.appState.session.settings.appearance.accentTone,
            onOpen: { [weak target] in
                target?.openRepoFromMenu(fullName: repo.title)
            }
        )
        let submenu = self.repoSubmenu(for: repo, isPinned: isPinned)
        if let cached = self.repoMenuItemCache[repo.title], let view = cached.view as? MenuItemHostingView {
            view.updateHighlightableRootView(AnyView(card), showsSubmenuIndicator: true)
            cached.isEnabled = true
            cached.submenu = submenu
            cached.target = self.target
            cached.action = #selector(self.target.menuItemNoOp(_:))
            return cached
        }
        let item = self.viewItem(for: card, enabled: true, highlightable: true, submenu: submenu)
        self.repoMenuItemCache[repo.title] = item
        return item
    }

    func repoSubmenu(for repo: RepositoryDisplayModel, isPinned: Bool) -> NSMenu {
        let signature = RepoSubmenuSignature(
            repo: repo,
            settings: self.appState.session.settings,
            heatmapRange: self.appState.session.heatmapRange,
            recentCounts: RepoRecentCountSignature(
                releases: self.target.cachedRecentListCount(fullName: repo.title, kind: .releases),
                discussions: self.target.cachedRecentListCount(fullName: repo.title, kind: .discussions),
                tags: self.target.cachedRecentListCount(fullName: repo.title, kind: .tags),
                branches: self.target.cachedRecentListCount(fullName: repo.title, kind: .branches),
                contributors: self.target.cachedRecentListCount(fullName: repo.title, kind: .contributors)
            ),
            isPinned: isPinned
        )
        if let cached = self.repoSubmenuCache[repo.title], cached.signature == signature {
            return cached.menu
        }
        let menu = self.makeRepoSubmenu(for: repo, isPinned: isPinned)
        self.repoSubmenuCache[repo.title] = RepoSubmenuCacheEntry(menu: menu, signature: signature)
        return menu
    }

    func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    func actionItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        represented: Any? = nil,
        systemImage: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self.target
        if let represented { item.representedObject = represented }
        if let systemImage, let image = self.cachedSystemImage(named: systemImage) {
            item.image = image
        }
        return item
    }

    func cachedSystemImage(named name: String) -> NSImage? {
        let key = "\(name)|\(self.isLightAppearance ? "light" : "dark")"
        if let cached = self.systemImageCache[key] {
            return cached
        }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        image.size = NSSize(width: 14, height: 14)
        if name == "eye.slash", self.isLightAppearance {
            let config = NSImage.SymbolConfiguration(hierarchicalColor: .secondaryLabelColor)
            let tinted = image.withSymbolConfiguration(config)
            tinted?.isTemplate = false
            if let tinted {
                self.systemImageCache[key] = tinted
                return tinted
            }
        }
        image.isTemplate = true
        self.systemImageCache[key] = image
        return image
    }

    func viewItem(
        for content: some View,
        enabled: Bool,
        highlightable: Bool = false,
        submenu: NSMenu? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = enabled
        if highlightable {
            let highlightState = MenuItemHighlightState()
            let wrapped = MenuItemContainerView(
                highlightState: highlightState,
                showsSubmenuIndicator: submenu != nil
            ) {
                content
            }
            item.view = MenuItemHostingView(rootView: AnyView(wrapped), highlightState: highlightState)
        } else {
            item.view = MenuItemHostingView(rootView: AnyView(content))
        }
        item.submenu = submenu
        if submenu != nil {
            item.target = self.target
            item.action = #selector(self.target.menuItemNoOp(_:))
        }
        return item
    }
}
