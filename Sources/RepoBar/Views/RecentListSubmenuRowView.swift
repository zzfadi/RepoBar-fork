import SwiftUI

struct RecentListSubmenuRowView: View {
    let title: String
    let systemImage: String
    let badgeText: String?

    private let iconColumnWidth: CGFloat = 18
    private let iconBaselineOffset: CGFloat = 1

    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: self.systemImage)
                .symbolRenderingMode(.hierarchical)
                .font(.caption)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .frame(width: self.iconColumnWidth, alignment: .center)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    dimensions[VerticalAlignment.center] + self.iconBaselineOffset
                }

            Text(self.title)
                .font(.system(size: 14))
                .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let badgeText {
                Text(badgeText)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(self.badgeForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(self.badgeBackground, in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(self.badgeBorder, lineWidth: 1)
                    }
                    .padding(.trailing, 16)
                    .accessibilityLabel(Text("Count \(badgeText)"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var badgeBackground: Color {
        if self.isHighlighted {
            return Color.white.opacity(self.colorScheme == .dark ? 0.22 : 0.18)
        }
        if self.colorScheme == .dark {
            return Color.white.opacity(0.08)
        }
        return Color.black.opacity(0.12)
    }

    private var badgeBorder: Color {
        if self.isHighlighted {
            return Color.white.opacity(self.colorScheme == .dark ? 0.22 : 0.28)
        }
        if self.colorScheme == .dark {
            return Color.white.opacity(0.10)
        }
        return Color.black.opacity(0.18)
    }

    private var badgeForeground: Color {
        self.isHighlighted ? MenuHighlightStyle.selectionText : MenuHighlightStyle.primary(false)
    }
}
