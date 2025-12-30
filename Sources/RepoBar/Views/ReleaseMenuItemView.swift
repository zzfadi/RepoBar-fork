import Kingfisher
import RepoBarCore
import SwiftUI

struct ReleaseMenuItemView: View {
    let release: RepoReleaseSummary
    let onOpen: () -> Void
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            self.avatar

            VStack(alignment: .leading, spacing: 4) {
                Text(self.release.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(self.release.tag)
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)

                    if let author = self.release.authorLogin, author.isEmpty == false {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .lineLimit(1)
                    }

                    Text(RelativeFormatter.string(from: self.release.publishedAt, relativeTo: Date()))
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    if self.release.isPrerelease {
                        PrereleasePillView(isHighlighted: self.isHighlighted)
                    }

                    if self.release.assetCount > 0 {
                        MenuStatBadge(label: nil, value: self.release.assetCount, systemImage: "shippingbox")
                    }

                    if self.release.downloadCount > 0 {
                        MenuStatBadge(label: nil, value: self.release.downloadCount, systemImage: "arrow.down.circle")
                    }
                }
            }
            Spacer(minLength: 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { self.onOpen() }
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = self.release.authorAvatarURL {
            KFImage(url)
                .placeholder { self.avatarPlaceholder }
                .resizable()
                .scaledToFill()
                .frame(width: 20, height: 20)
                .clipShape(Circle())
        } else {
            self.avatarPlaceholder
                .frame(width: 20, height: 20)
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color(nsColor: .separatorColor))
            .overlay(
                Image(systemName: "tag.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PrereleasePillView: View {
    let isHighlighted: Bool

    var body: some View {
        Text("Pre")
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(self.isHighlighted ? .white.opacity(0.95) : Color(nsColor: .systemPurple))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(self.isHighlighted ? .white.opacity(0.16) : Color(nsColor: .systemPurple).opacity(0.14))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(self.isHighlighted ? .white.opacity(0.30) : Color(nsColor: .systemPurple).opacity(0.55), lineWidth: 1)
            )
    }
}
