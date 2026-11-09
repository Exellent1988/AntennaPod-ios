import XCTest
@testable import AntennaPod

final class DownloadHistoryTests: XCTestCase {
    private func entry(_ i: Int, ok: Bool = true) -> DownloadHistoryEntry {
        DownloadHistoryEntry(episodeId: "e\(i)", episodeTitle: "Ep \(i)", feedTitle: "Feed",
                             succeeded: ok, message: ok ? nil : "HTTP 404", byteSize: ok ? 1234 : nil,
                             timestampEpochMs: Int64(i))
    }

    func testAppendIsNewestFirstAndCapped() {
        var list: [DownloadHistoryEntry] = []
        for i in 0..<(DownloadHistoryLog.capacity + 20) { list = DownloadHistoryLog.appending(entry(i), to: list) }
        XCTAssertEqual(list.count, DownloadHistoryLog.capacity)
        XCTAssertEqual(list.first?.episodeId, "e\(DownloadHistoryLog.capacity + 19)")
    }

    func testPersistenceRoundTripKeepsSuccessesAndFailures() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dl-history-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let items = [entry(2, ok: false), entry(1)]
        DownloadHistoryLog.save(items, to: url)
        let loaded = DownloadHistoryLog.load(from: url)
        XCTAssertEqual(loaded, items)
        XCTAssertEqual(loaded.first?.message, "HTTP 404")
        XCTAssertEqual(loaded.last?.byteSize, 1234)
        DownloadHistoryLog.save([], to: url)
        XCTAssertTrue(DownloadHistoryLog.load(from: url).isEmpty)
    }
}
