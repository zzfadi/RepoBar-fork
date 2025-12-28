import Foundation
@testable import RepoBarCore
import Testing

struct EventLabelTests {
    @Test
    func pullRequestEventHasReadableTitle() {
        let event = RepoEvent(
            type: "PullRequestEvent",
            actor: EventActor(login: "octo", avatarUrl: nil),
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
}
