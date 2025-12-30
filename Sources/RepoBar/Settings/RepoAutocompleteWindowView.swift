import AppKit
import RepoBarCore
import SwiftUI

struct RepoAutocompleteWindowView: NSViewRepresentable {
    let suggestions: [Repository]
    @Binding var selectedIndex: Int
    let keyboardNavigating: Bool
    let onSelect: (String) -> Void
    let width: CGFloat
    @Binding var isShowing: Bool

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if self.isShowing, !self.suggestions.isEmpty {
            context.coordinator.showDropdown(
                on: nsView,
                suggestions: self.suggestions,
                selectedIndex: self.$selectedIndex,
                keyboardNavigating: self.keyboardNavigating,
                width: self.width
            )
        } else {
            context.coordinator.hideDropdown()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: self.onSelect, isShowing: self.$isShowing, selectedIndex: self.$selectedIndex)
    }

    @MainActor
    class Coordinator: NSObject {
        private var dropdownWindow: NSWindow?
        private var hostingView: NSHostingView<AnyView>?
        private let onSelect: (String) -> Void
        @Binding var isShowing: Bool
        @Binding var selectedIndex: Int
        private nonisolated(unsafe) var clickMonitor: Any?

        init(onSelect: @escaping (String) -> Void, isShowing: Binding<Bool>, selectedIndex: Binding<Int>) {
            self.onSelect = onSelect
            self._isShowing = isShowing
            self._selectedIndex = selectedIndex
            super.init()
        }

        deinit {
            if let monitor = clickMonitor {
                DispatchQueue.main.async {
                    NSEvent.removeMonitor(monitor)
                }
            }
        }

        @MainActor
        private func cleanupClickMonitor() {
            if let monitor = clickMonitor {
                NSEvent.removeMonitor(monitor)
                self.clickMonitor = nil
            }
        }

        @MainActor
        func showDropdown(
            on view: NSView,
            suggestions: [Repository],
            selectedIndex: Binding<Int>,
            keyboardNavigating: Bool,
            width: CGFloat
        ) {
            guard let parentWindow = view.window else { return }

            if self.dropdownWindow == nil {
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: width, height: 200),
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = true
                window.level = .floating
                window.isReleasedWhenClosed = false

                let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
                window.contentView = hostingView

                self.dropdownWindow = window
                self.hostingView = hostingView
            }

            guard let window = dropdownWindow,
                  let hostingView else { return }

            let resolvedWidth = max(240, width)
            let content = RepoAutocompleteListView(
                suggestions: suggestions,
                selectedIndex: selectedIndex,
                keyboardNavigating: keyboardNavigating
            ) { [weak self] fullName in
                self?.onSelect(fullName)
                self?.isShowing = false
            }
            .frame(width: resolvedWidth)
            .frame(maxHeight: 220)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )

            hostingView.rootView = AnyView(content)

            let viewFrame = view.convert(view.bounds, to: nil)
            let screenFrame = parentWindow.convertToScreen(viewFrame)
            let windowFrame = NSRect(
                x: screenFrame.minX,
                y: screenFrame.minY - 224,
                width: resolvedWidth,
                height: 220
            )
            window.setFrame(windowFrame, display: false)

            if window.parent == nil {
                parentWindow.addChildWindow(window, ordered: .above)
            }
            window.makeKeyAndOrderFront(nil)

            if self.clickMonitor == nil {
                self.clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    if event.window != window {
                        self?.isShowing = false
                    }
                    return event
                }
            }
        }

        @MainActor
        func hideDropdown() {
            self.cleanupClickMonitor()

            if let window = dropdownWindow {
                if let parent = window.parent {
                    parent.removeChildWindow(window)
                }
                window.orderOut(nil)
            }
        }
    }
}

private struct RepoAutocompleteListView: View {
    let suggestions: [Repository]
    @Binding var selectedIndex: Int
    let keyboardNavigating: Bool
    let onSelect: (String) -> Void
    @State private var mouseHoverTriggered = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(self.suggestions.enumerated()), id: \.element.id) { index, repo in
                        RepoAutocompleteRow(
                            repo: repo,
                            isSelected: index == self.selectedIndex
                        ) {
                            self.onSelect(repo.fullName)
                        }
                        .id(index)
                        .onHover { hovering in
                            if hovering {
                                self.mouseHoverTriggered = true
                                self.selectedIndex = index
                            }
                        }

                        if index < self.suggestions.count - 1 {
                            Divider()
                                .padding(.horizontal, 8)
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
            .onChange(of: self.selectedIndex) { _, newIndex in
                if newIndex >= 0, newIndex < self.suggestions.count, self.keyboardNavigating,
                   !self.mouseHoverTriggered {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
                self.mouseHoverTriggered = false
            }
        }
    }
}

private struct RepoAutocompleteRow: View {
    let repo: Repository
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: self.onTap) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(self.repo.fullName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(self.repo.owner)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(self.isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(
            HStack {
                if self.isSelected {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2)
                }
                Spacer()
            }
        )
    }
}
