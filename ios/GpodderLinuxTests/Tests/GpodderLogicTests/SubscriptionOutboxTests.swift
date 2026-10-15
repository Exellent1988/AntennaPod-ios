import XCTest
import PodcastCore
@testable import GpodderLogic

/// Real app GpodderSubscriptionOutbox (symlinked): persistence across restarts, confirm only
/// drops what was sent.
final class SubscriptionOutboxTests: XCTestCase {
    var file: URL!
    override func setUp() { file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json") }
    override func tearDown() { try? FileManager.default.removeItem(at: file) }

    func testSurvivesRestartAndClearsOnlyOnConfirm() {
        var o: GpodderSubscriptionOutbox? = GpodderSubscriptionOutbox(fileURL: file)
        o!.record(["https://a.example/f", "http://old.example/f"])
        let sent = o!.snapshot
        o = nil
        let r = GpodderSubscriptionOutbox(fileURL: file)
        XCTAssertEqual(r.snapshot, sent)
        r.record(["https://b.example/f"])
        r.confirm(sent)
        XCTAssertEqual(GpodderSubscriptionOutbox(fileURL: file).snapshot.entries, [["https://b.example/f"]])
        r.cancel(["http://B.example/f/"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "empty queue removes the file")
    }

    func testAbsorbingPullPersistsServerSpelling() {
        let o = GpodderSubscriptionOutbox(fileURL: file)
        o.record(["https://a.example/f"])
        XCTAssertEqual(o.absorbingPull(["http://a.example/f/", "https://c.example/x"]), ["https://c.example/x"])
        XCTAssertEqual(GpodderSubscriptionOutbox(fileURL: file).snapshot.entries, [["https://a.example/f", "http://a.example/f/"]])
        o.clear()
        XCTAssertTrue(GpodderSubscriptionOutbox(fileURL: file).snapshot.isEmpty)
    }
}
