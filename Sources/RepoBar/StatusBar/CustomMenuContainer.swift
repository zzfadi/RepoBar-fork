import SwiftUI

struct CustomMenuContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1))
            self.content()
                .padding(16)
        }
        .frame(minWidth: 420, maxWidth: 520, minHeight: 300)
        .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
    }
}
