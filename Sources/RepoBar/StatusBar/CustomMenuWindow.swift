import AppKit
import SwiftUI

/// Lightweight floating window used for the rich left-click view.
@MainActor
final class CustomMenuWindow: NSWindow {
    private var hostingView: NSHostingView<AnyView>?
    private var eventMonitor: Any?
    private weak var statusBarButton: NSStatusBarButton?
    var onShow: (() -> Void)?
    var onHide: (() -> Void)?

    init(contentView: some View) {
        let view = AnyView(contentView)
        let hosting = NSHostingView(rootView: view)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        self.hostingView = hosting
        self.contentView = hosting
    }

    func show(relativeTo button: NSStatusBarButton) {
        self.statusBarButton = button
        guard let window = button.window, window.screen != nil else { return }

        self.hostingView?.layoutSubtreeIfNeeded()
        let fittingSize = self.hostingView?.fittingSize ?? NSSize(width: 420, height: 380)
        let width = min(max(380, fittingSize.width), 520)
        let height = min(max(220, fittingSize.height), 620)
        self.setContentSize(NSSize(width: width, height: height))

        let buttonFrame = window.convertToScreen(button.frame)
        let windowSize = frameRect(forContentRect: NSRect(origin: .zero, size: NSSize(width: width, height: height))).size
        let origin = NSPoint(
            x: buttonFrame.midX - windowSize.width / 2,
            y: buttonFrame.minY - windowSize.height - 8
        )
        setFrame(NSRect(origin: origin, size: windowSize), display: true)
        orderFrontRegardless()
        makeKey()
        self.onShow?()
        NSApp.activate(ignoringOtherApps: true)
        self.startEventMonitoring()
    }

    func hide() {
        orderOut(nil)
        self.stopEventMonitoring()
        self.onHide?()
    }

    var isWindowVisible: Bool {
        isVisible
    }

    override func resignKey() {
        super.resignKey()
        self.hide()
    }

    deinit {
        MainActor.assumeIsolated {
            self.stopEventMonitoring()
        }
    }

    // MARK: - Event monitoring

    private func startEventMonitoring() {
        self.stopEventMonitoring()
        guard self.isVisible else { return }

        self.eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let mouseLocation = NSEvent.mouseLocation

                // Allow re-clicking the status bar button to dismiss.
                if let button = self.statusBarButton,
                   let buttonWindow = button.window
                {
                    let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
                    if buttonFrame.contains(mouseLocation) {
                        self.hide()
                        return
                    }
                }

                // Dismiss when clicking outside the window frame.
                if !self.frame.contains(mouseLocation) {
                    self.hide()
                }
            }
        }
    }

    private func stopEventMonitoring() {
        if let monitor = self.eventMonitor {
            NSEvent.removeMonitor(monitor)
            self.eventMonitor = nil
        }
    }
}
