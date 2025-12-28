import AppKit
import SwiftUI

@MainActor
final class AddRepoWindowController {
    private let appState: AppState
    private var window: NSWindow?

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        if self.window == nil {
            let rootView = AddRepoPanelView(appState: self.appState) { [weak self] in
                self?.window?.close()
            }
            let hosting = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable]
            window.title = "Add Repository"
            window.level = .floating
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct AddRepoPanelView: View {
    let appState: AppState
    let onClose: () -> Void
    @State private var isPresented = true

    var body: some View {
        AddRepoView(isPresented: self.$isPresented) { repo in
            Task { await self.appState.addPinned(repo.fullName) }
        }
        .environmentObject(self.appState)
        .environmentObject(self.appState.session)
        .onChange(of: self.isPresented) { _, newValue in
            if !newValue {
                self.onClose()
            }
        }
    }
}
