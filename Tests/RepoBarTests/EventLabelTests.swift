import Foundation
@testable import RepoBarCore
import Testing

struct EventLabelTests {
    @Test
    func pullRequestEventHasReadableTitle() {
        let event = RepoEvent(
            type: "PullRequestEvent",
            actor: EventActor(login: "octo", avatarUrl: nil),
            repo: nil,
            payload: EventPayload(action: nil, comment: nil, issue: nil, pullRequest: nil),
            createdAt: Date()
        )
        #expect(event.displayTitle == "Pull Request")
    }

    @Test
    func actionGetsAppendedToTitle() {
        let event = RepoEvent(
            type: "IssuesEvent",
            actor: EventActor(login: "octo", avatarUrl: nil),
            repo: nil,
            payload: EventPayload(action: "opened", comment: nil, issue: nil, pullRequest: nil),
            createdAt: Date()
        )
        #expect(event.displayTitle == "Issue opened")
    }

    @Test
    func unknownEventTypeFallsBackToReadableName() {
        let event = RepoEvent(
            type: "ProjectCardEvent",
            actor: EventActor(login: "octo", avatarUrl: nil),
            repo: nil,
            payload: EventPayload(action: nil, comment: nil, issue: nil, pullRequest: nil),
            createdAt: Date()
        )
        #expect(event.displayTitle == "Project Card")
    }

    @Test
    func activityEventUsesIssueTitleAndRepoFallback() {
        let event = RepoEvent(
            type: "IssuesEvent",
            actor: EventActor(login: "octo", avatarUrl: nil),
            repo: nil,
            payload: EventPayload(
                action: "opened",
                comment: nil,
                issue: EventIssue(title: "Fix it", number: 123, htmlUrl: URL(string: "https://example.com/issue/1")!),
                pullRequest: nil
            ),
            createdAt: Date()
        )
        let activity = event.activityEvent(owner: "steipete", name: "RepoBar")
        #expect(activity.title == "Issue opened #123: Fix it")
        #expect(activity.actor == "octo")
        #expect(activity.url.absoluteString == "https://example.com/issue/1")
    }

    @Test
    func activityEventUsesStargazerLinkForWatchEvents() {
        let event = RepoEvent(
            type: "WatchEvent",
            actor: EventActor(login: "octo", avatarUrl: nil),
            repo: nil,
            payload: EventPayload(action: nil, comment: nil, issue: nil, pullRequest: nil),
            createdAt: Date()
        )
        let activity = event.activityEvent(owner: "steipete", name: "RepoBar")
        #expect(activity.url.absoluteString == "https://github.com/steipete/RepoBar/stargazers")
    }

    @Test
    func activityEventUsesCommitLinkForPushEvents() {
        let event = RepoEvent(
            type: "PushEvent",
            actor: EventActor(login: "octo", avatarUrl: nil),
            repo: nil,
            payload: EventPayload(
                action: nil,
                comment: nil,
                issue: nil,
                pullRequest: nil,
                release: nil,
                forkee: nil,
                ref: nil,
                refType: nil,
                head: "abc123",
                commits: nil
            ),
            createdAt: Date()
        )
        let activity = event.activityEvent(owner: "steipete", name: "RepoBar")
        #expect(activity.url.absoluteString == "https://github.com/steipete/RepoBar/commit/abc123")
    }

    @Test
    func activityMetadataCapturesActionTargetAndLink() {
        let event = RepoEvent(
            type: "PullRequestEvent",
            actor: EventActor(login: "octo", avatarUrl: nil),
            repo: nil,
            payload: EventPayload(
                action: "closed",
                comment: nil,
                issue: nil,
                pullRequest: EventPullRequest(
                    title: "Ship it",
                    number: 42,
                    merged: true,
                    htmlUrl: URL(string: "https://example.com/pr/42")!
                )
            ),
            createdAt: Date()
        )
        let activity = event.activityEvent(owner: "steipete", name: "RepoBar")
        #expect(activity.metadata?.label == "PR merged #42: Ship it")
        #expect(activity.metadata?.deepLink?.absoluteString == "https://example.com/pr/42")
    }

    @Test
    func activityMetadataIncludesReleaseTag() {
        let event = RepoEvent(
            type: "ReleaseEvent",
            actor: EventActor(login: "octo", avatarUrl: nil),
            repo: nil,
            payload: EventPayload(
                action: "published",
                comment: nil,
                issue: nil,
                pullRequest: nil,
                release: EventRelease(
                    htmlUrl: URL(string: "https://example.com/releases/v1.0.0")!,
                    tagName: "v1.0.0",
                    name: nil
                )
            ),
            createdAt: Date()
        )
        let activity = event.activityEvent(owner: "steipete", name: "RepoBar")
        #expect(activity.metadata?.label == "Release published: v1.0.0")
    }

    @Test
    func activityMetadataFormatsForkTarget() {
        let event = RepoEvent(
            type: "ForkEvent",
            actor: EventActor(login: "octo", avatarUrl: nil),
            repo: nil,
            payload: EventPayload(
                action: nil,
                comment: nil,
                issue: nil,
                pullRequest: nil,
                release: nil,
                forkee: EventForkee(
                    htmlUrl: URL(string: "https://example.com/octo/fork")!,
                    fullName: "octo/fork"
                )
            ),
            createdAt: Date()
        )
        let activity = event.activityEvent(owner: "steipete", name: "RepoBar")
        #expect(activity.metadata?.label == "Forked → octo/fork")
    }
}
