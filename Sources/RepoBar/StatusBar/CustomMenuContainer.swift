import SwiftUI

struct CustomMenuContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.8))
            self.content()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(minWidth: 360, maxWidth: 440, minHeight: 260)
        .shadow(color: .black.opacity(0.12), radius: 18, y: 12)
    }
}
