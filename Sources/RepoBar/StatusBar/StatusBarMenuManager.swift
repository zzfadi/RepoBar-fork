import AppKit
import MenuBarExtraAccess
import SwiftUI

#if !SWIFT_PACKAGE
    extension NSStatusBarButton {
        override open func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            highlight(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
                guard let self else { return }
                highlight(AppDelegateState.shared?.statusBarController?.menuManager.customWindow?
                    .isWindowVisible ?? false)
            }
        }
    }
#endif

@MainActor
final class StatusBarMenuManager: NSObject, NSMenuDelegate {
    private enum MenuState { case none, customWindow, contextMenu }

    var customWindow: CustomMenuWindow?
    private weak var statusBarButton: NSStatusBarButton?
    private weak var currentStatusItem: NSStatusItem?
    private var menuState: MenuState = .none
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Left click

    func toggleCustomWindow(relativeTo button: NSStatusBarButton) {
        if let window = customWindow, window.isWindowVisible {
            self.hideCustomWindow()
        } else {
            self.showCustomWindow(relativeTo: button)
        }
    }

    func showCustomWindow(relativeTo button: NSStatusBarButton) {
        self.updateMenuState(.customWindow, button: button)

        let mainView = MenuContentView()
            .environmentObject(self.appState.session)
            .environmentObject(self.appState)

        self.customWindow?.hide()
        self.customWindow = CustomMenuWindow(contentView: CustomMenuContainer { mainView })

        self.customWindow?.onHide = { [weak self] in
            self?.statusBarButton?.highlight(false)
            Task { @MainActor in self?.updateMenuState(.none) }
        }

        self.customWindow?.show(relativeTo: button)
        self.statusBarButton?.highlight(true)
    }

    func hideCustomWindow() {
        self.customWindow?.hide()
        self.updateMenuState(.none)
    }

    // MARK: - Right click

    func showContextMenu(for button: NSStatusBarButton, statusItem: NSStatusItem) {
        self.hideCustomWindow()
        self.currentStatusItem = statusItem
        button.state = .on
        self.updateMenuState(.contextMenu, button: button)

        let menu = NSMenu()
        menu.delegate = self

        // Login state
        let accountTitle: String
        switch self.appState.session.account {
        case .loggedOut: accountTitle = "Not signed in"
        case .loggingIn: accountTitle = "Signing in…"
        case let .loggedIn(user):
            let host = user.host.host ?? "github.com"
            accountTitle = "Signed in as \(user.username)@\(host)"
        }
        let accountItem = NSMenuItem(title: accountTitle, action: nil, keyEquivalent: "")
        accountItem.isEnabled = false
        menu.addItem(accountItem)

        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "Refresh now", action: #selector(self.refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(self.openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        let updateItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(self.checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)

        let logoutItem = NSMenuItem(title: "Log out", action: #selector(self.logOut), keyEquivalent: "")
        logoutItem.target = self
        menu.addItem(logoutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit RepoBar", action: #selector(self.quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    // MARK: - Menu actions

    @objc private func refreshNow() {
        self.appState.refreshScheduler.forceRefresh()
    }

    @objc private func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        NotificationCenter.default.post(name: .repobarOpenSettings, object: nil)
    }

    @objc private func checkForUpdates() {
        SparkleController.shared.checkForUpdates()
    }

    @objc private func logOut() {
        Task { @MainActor in
            await self.appState.auth.logout()
            self.appState.session.account = .loggedOut
            self.appState.session.repositories = []
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - State

    private func updateMenuState(_ newState: MenuState, button: NSStatusBarButton? = nil) {
        self.menuState = newState
        if let button { self.statusBarButton = button }
        if newState == .none { self.statusBarButton?.state = .off }
    }

    func menuDidClose(_: NSMenu) {
        self.updateMenuState(.none)
        self.statusBarButton?.state = .off
        self.currentStatusItem?.menu = nil
    }
}

// Helper to access delegate in the NSStatusBarButton extension
final class AppDelegateState {
    @MainActor static let shared = AppDelegateState()
    weak var statusBarController: StatusBarController?
}
