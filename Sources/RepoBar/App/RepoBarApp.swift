import AppKit
import Kingfisher
import MenuBarExtraAccess
import OSLog
import RepoBarCore
import SwiftUI

@main
struct RepoBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate
    @State private var appState = AppState()
    @State private var isMenuPresented = false
    @State private var menuManager: StatusBarMenuManager?
    private let logger = Logger(subsystem: "com.steipete.repobar", category: "menu-state")

    @SceneBuilder
    var body: some Scene {
        MenuBarExtra {
            EmptyView()
        } label: {
            StatusItemLabelView(session: self.appState.session)
        }
        .menuBarExtraStyle(.menu)
        .menuBarExtraAccess(isPresented: self.$isMenuPresented) { item in
            self.logMenuEvent("menuBarExtraAccess statusItem=\(self.objectID(item)) menuManager=\(self.menuManager != nil)")
            if self.menuManager == nil {
                self.menuManager = StatusBarMenuManager(appState: self.appState)
            }
            self.menuManager?.attachMainMenu(to: item)
        }
        .onChange(of: self.isMenuPresented) { _, newValue in
            self.logMenuEvent("isMenuPresented=\(newValue)")
        }

        Settings {
            SettingsView(session: self.appState.session, appState: self.appState)
        }
        .defaultSize(width: 540, height: 420)
        .windowResizability(.contentSize)
    }

    private func logMenuEvent(_ message: String) {
        self.logger.info("\(message, privacy: .public)")
        Task { await DiagnosticsLogger.shared.message(message) }
    }

    private func objectID(_ object: AnyObject?) -> String {
        guard let object else { return "nil" }
        return String(ObjectIdentifier(object).hashValue)
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        guard ensureSingleInstance() else {
            NSApp.terminate(nil)
            return
        }
        configureImagePipeline()
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}

extension AppDelegate {
    /// Prevent multiple instances when LS UI flag is unavailable under SwiftPM.
    private func ensureSingleInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID && !$0.isEqual(NSRunningApplication.current)
        }
        return others.isEmpty
    }

    private func configureImagePipeline() {
        let cache = ImageCache(name: "RepoBarAvatars")
        cache.memoryStorage.config.totalCostLimit = 64 * 1024 * 1024
        cache.diskStorage.config.sizeLimit = 64 * 1024 * 1024
        KingfisherManager.shared.cache = cache
    }
}
