import AppKit
import Observation
import SwiftUI

@MainActor
protocol MenuItemMeasuring: AnyObject {
    func measuredHeight(width: CGFloat) -> CGFloat
}

@MainActor
protocol MenuItemHighlighting: AnyObject {
    func setHighlighted(_ highlighted: Bool)
}

@MainActor
@Observable
final class MenuItemHighlightState {
    var isHighlighted = false
}

struct MenuItemContainerView<Content: View>: View {
    @Bindable var highlightState: MenuItemHighlightState
    let showsSubmenuIndicator: Bool
    let content: Content

    init(
        highlightState: MenuItemHighlightState,
        showsSubmenuIndicator: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.highlightState = highlightState
        self.showsSubmenuIndicator = showsSubmenuIndicator
        self.content = content()
    }

    var body: some View {
        self.content
            .padding(.trailing, self.showsSubmenuIndicator ? MenuStyle.menuItemContainerTrailingPadding : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.menuItemHighlighted, self.highlightState.isHighlighted)
            .foregroundStyle(MenuHighlightStyle.primary(self.highlightState.isHighlighted))
            .background(alignment: .topLeading) {
                if self.highlightState.isHighlighted {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(MenuHighlightStyle.selectionBackground(true))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if self.showsSubmenuIndicator {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MenuHighlightStyle.secondary(self.highlightState.isHighlighted))
                        .padding(.top, 8)
                        .padding(.trailing, MenuStyle.menuItemContainerTrailingPadding)
                }
            }
    }
}

@MainActor
final class MenuItemHostingView: NSHostingView<AnyView>, MenuItemMeasuring, MenuItemHighlighting {
    private let highlightState: MenuItemHighlightState?

    override var allowsVibrancy: Bool { true }
    override var focusRingType: NSFocusRingType {
        get { MenuFocusRingStyle.type }
        set {}
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        guard self.frame.width > 0 else { return size }
        return NSSize(width: self.frame.width, height: size.height)
    }

    init(rootView: AnyView, highlightState: MenuItemHighlightState) {
        self.highlightState = highlightState
        super.init(rootView: rootView)
        if #available(macOS 13.0, *) {
            self.sizingOptions = [.minSize, .intrinsicContentSize]
        }
    }

    @MainActor
    required init(rootView: AnyView) {
        self.highlightState = nil
        super.init(rootView: rootView)
        if #available(macOS 13.0, *) {
            self.sizingOptions = [.minSize, .intrinsicContentSize]
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setHighlighted(_ highlighted: Bool) {
        self.highlightState?.isHighlighted = highlighted
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        if self.frame.width != width {
            self.frame = NSRect(origin: self.frame.origin, size: NSSize(width: width, height: 10))
        }
        let size = self.fittingSize
        return size.height
    }
}
