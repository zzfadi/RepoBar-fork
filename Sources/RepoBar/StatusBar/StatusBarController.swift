import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    let menuManager: StatusBarMenuManager
    private let iconController: StatusBarIconController
    private let appState: AppState
    private var updateTimer: Timer?

    init(appState: AppState) {
        self.appState = appState
        self.menuManager = StatusBarMenuManager(appState: appState)
        self.iconController = StatusBarIconController()
        super.init()
        AppDelegateState.shared.statusBarController = self
        self.setupStatusItem()
        self.startTimer()
    }

    private func setupStatusItem() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.imagePosition = .imageLeading
        button.action = #selector(self.handleClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setButtonType(.toggle)
        button.toolTip = "RepoBar"
        self.iconController.update(button: button, session: self.appState.session)
    }

    private func startTimer() {
        self.updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.iconController.update(button: self.statusItem?.button, session: self.appState.session)
            }
        }
        self.updateTimer?.fire()
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        _ = NSApp.currentEvent
        if let statusItem { self.menuManager.toggleMainMenu(relativeTo: sender, statusItem: statusItem) }
    }
}
