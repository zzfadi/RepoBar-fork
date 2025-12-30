import Kingfisher
import RepoBarCore
import SwiftUI

struct PullRequestMenuItemView: View {
    let pullRequest: RepoPullRequestSummary
    let onOpen: () -> Void
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            self.avatar

            VStack(alignment: .leading, spacing: 4) {
                Text(self.pullRequest.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text("#\(self.pullRequest.number)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)

                    if let author = self.pullRequest.authorLogin, author.isEmpty == false {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .lineLimit(1)
                    }

                    Text(RelativeFormatter.string(from: self.pullRequest.updatedAt, relativeTo: Date()))
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    if self.pullRequest.isDraft {
                        DraftPillView(isHighlighted: self.isHighlighted)
                    }

                    if self.pullRequest.reviewCommentCount > 0 {
                        MenuStatBadge(label: nil, value: self.pullRequest.reviewCommentCount, systemImage: "checkmark.bubble")
                    }

                    if self.pullRequest.commentCount > 0 {
                        MenuStatBadge(label: nil, value: self.pullRequest.commentCount, systemImage: "text.bubble")
                    }
                }

                if let head = self.pullRequest.headRefName, let base = self.pullRequest.baseRefName, head.isEmpty == false, base.isEmpty == false {
                    Text("\(head) → \(base)")
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                }

                if self.pullRequest.labels.isEmpty == false {
                    MenuLabelChipsView(labels: self.pullRequest.labels)
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
        if let url = self.pullRequest.authorAvatarURL {
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
                Image(systemName: "person.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DraftPillView: View {
    let isHighlighted: Bool

    var body: some View {
        Text("Draft")
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(self.isHighlighted ? .white.opacity(0.95) : Color(nsColor: .systemOrange))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(self.isHighlighted ? .white.opacity(0.16) : Color(nsColor: .systemOrange).opacity(0.14))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(self.isHighlighted ? .white.opacity(0.30) : Color(nsColor: .systemOrange).opacity(0.55), lineWidth: 1)
            )
    }
}
