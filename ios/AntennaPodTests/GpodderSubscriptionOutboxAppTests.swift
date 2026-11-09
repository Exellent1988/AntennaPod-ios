import XCTest
import PodcastCore
@testable import AntennaPod

/// Local unsubscribe → gpodder remove queue (Android SynchronizationQueue removed feeds).
/// Matching / pull filtering / upload rules are covered on Linux (PodcastCore
/// PendingSubscriptionRemovalsTests, GpodderLinuxTests); this checks the store hook.
@MainActor
final class GpodderSubscriptionOutboxAppTests: XCTestCase {
    private var file: URL!
    override func setUp() async throws {
        file = FileManager.default.temporaryDirectory.appendingPathComponent("gso-\(UUID().uuidString).json")
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: file) }

    private func feed(_ tag: String) -> PodcastFeed {
        var f = PodcastFeed(
            id: UUID(), title: "F \(tag)", feedUrl: "https://example.com/\(tag).xml", siteLink: nil, imageUrl: nil,
            descriptionText: "", author: nil, language: nil, fundingUrl: nil, fundingLabel: nil, categories: [],
            isLocked: false, lockedOwner: nil, podcastGuid: nil, episodes: [])
        f.alternateUrls = ["http://old.example.com/\(tag)"]
        return f
    }

    func testUserUnsubscribeQueuesAllUrlsOnlyWhenLoggedInAndNotForServerRemoves() {
        let store = PodcastStore()
        let savedFeeds = store.feeds, savedOutbox = store.gpodderSubscriptionOutbox
        let savedRecording = store.isGpodderActionRecordingEnabled
        defer { store.feeds = savedFeeds; store.gpodderSubscriptionOutbox = savedOutbox; store.isGpodderActionRecordingEnabled = savedRecording }
        let outbox = GpodderSubscriptionOutbox(fileURL: file)
        store.gpodderSubscriptionOutbox = outbox
        var loggedIn = false
        store.isGpodderActionRecordingEnabled = { loggedIn }

        let a = feed("a-\(UUID().uuidString)"), b = feed("b-\(UUID().uuidString)"), c = feed("c-\(UUID().uuidString)")
        store.feeds += [a, b, c]
        store.unsubscribe(a)
        XCTAssertTrue(outbox.snapshot.isEmpty, "not logged in: nothing queued")

        loggedIn = true
        store.unsubscribe(b)
        XCTAssertEqual(outbox.snapshot.entries, [b.allUrls])
        store.unsubscribe(c, recordForSync: false) // gpodder applying a server remove
        XCTAssertEqual(outbox.snapshot.entries.count, 1)
        XCTAssertEqual(GpodderSubscriptionOutbox(fileURL: file).snapshot.entries, [b.allUrls], "persisted")
        XCTAssertFalse(store.feeds.contains { $0.id == b.id })
    }
}
