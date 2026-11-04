@testable import AntennaPod
import PodcastCore
import XCTest

/// Settings → Queue → Enqueue location (Android prefEnqueueLocation) on the real PodcastStore.
@MainActor
final class EnqueueLocationStoreTests: PlaybackFixtureTestCase {
    private func ep(_ n: String) -> PodcastEpisode {
        PodcastEpisode(id: "enq-\(n)-\(UUID().uuidString.prefix(6))", title: n, downloadUrl: "https://example.invalid/\(n).mp3",
                       mimeType: "audio/mpeg", durationSeconds: 60)
    }

    func testDefaultAndBackup() throws {
        var old = settings.backupSnapshot()
        old.enqueueLocation = nil
        settings.applyBackupSnapshot(old)
        XCTAssertEqual(settings.enqueueLocation, .back, "Android default Back")
        settings.enqueueLocation = .afterCurrentlyPlaying
        let snap = try JSONDecoder().decode(AppSettingsBackupSnapshot.self, from: JSONEncoder().encode(settings.backupSnapshot()))
        settings.enqueueLocation = .front
        settings.applyBackupSnapshot(snap)
        XCTAssertEqual(settings.enqueueLocation, .afterCurrentlyPlaying)
    }

    func testBackAppends() {
        settings.enqueueLocation = .back
        let x = ep("x")
        store.enqueue(x)
        XCTAssertEqual(store.queue.last?.id, x.id)
    }

    func testFrontInsertsAtHeadAndBatchKeepsOrder() {
        settings.enqueueLocation = .front
        let x = ep("x"), y = ep("y"), z = ep("z")
        store.enqueue(x)
        XCTAssertEqual(store.queue.first?.id, x.id)
        store.enqueue([y, z])
        XCTAssertEqual(store.queue.prefix(3).map(\.id), [y.id, z.id, x.id])
    }

    func testAfterCurrentlyPlayingInsertsBehindThePlayingEpisode() async throws {
        settings.enqueueLocation = .afterCurrentlyPlaying
        XCTAssertTrue(playback.play(episode: episodes[0]))
        try await waitFor("playing", timeout: 8) { self.playback.isPlaying }
        let x = ep("x"), y = ep("y")
        store.enqueue([x, y])
        XCTAssertEqual(store.queue.map(\.id), [episodes[0].id, x.id, y.id, episodes[1].id, episodes[2].id])
        // Continuous playback picks the newly added episode next.
        XCTAssertEqual(store.nextQueueEpisode(after: episodes[0].id)?.id, x.id)
    }

    func testRandomStaysInTheQueueWithoutDuplicates() {
        settings.enqueueLocation = .random
        let x = ep("x")
        store.enqueue(x)
        store.enqueue(x)
        XCTAssertEqual(store.queue.filter { $0.id == x.id }.count, 1)
        XCTAssertEqual(store.queue.count, episodes.count + 1)
    }

    func testPlayNextIgnoresEnqueueLocation() {
        settings.enqueueLocation = .back
        let x = ep("x")
        store.playNext(x, currentlyPlayingId: nil)
        XCTAssertEqual(store.queue.first?.id, x.id)
    }
}
