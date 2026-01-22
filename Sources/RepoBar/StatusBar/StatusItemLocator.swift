import AppKit

@MainActor
enum StatusItemLocator {
    static func locate() -> NSStatusItem? {
        let statusItemClassName: String
        if #available(macOS 26.0, *) {
            statusItemClassName = "NSSceneStatusItem"
        } else {
            statusItemClassName = "NSStatusItem"
        }

        return NSApp.windows
            .filter { $0.className.contains("NSStatusBarWindow") }
            .compactMap { $0.fetchStatusItem() }
            .first { $0.className == statusItemClassName }
    }
}

private extension NSWindow {
    /// When called on an NSStatusBarWindow instance, returns the associated status item.
    func fetchStatusItem() -> NSStatusItem? {
        value(forKey: "statusItem") as? NSStatusItem
            ?? Mirror(reflecting: self).descendant("statusItem") as? NSStatusItem
    }
}
