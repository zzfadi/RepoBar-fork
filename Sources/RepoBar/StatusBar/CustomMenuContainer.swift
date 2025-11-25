import SwiftUI

struct CustomMenuContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.9))
            self.content()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(minWidth: 360, maxWidth: 460)
        .shadow(color: .black.opacity(0.14), radius: 18, y: 12)
    }
}
