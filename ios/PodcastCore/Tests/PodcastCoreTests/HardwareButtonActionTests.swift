import XCTest
@testable import PodcastCore

final class HardwareButtonActionTests: XCTestCase {
    func testDefaultsAndResolve() {
        XCTAssertEqual(HardwareButtonAction.defaultForward, .fastForward)
        XCTAssertEqual(HardwareButtonAction.defaultPrevious, .rewind)
        XCTAssertEqual(HardwareButtonAction.allCases.count, 4, "Android offers four actions")
        XCTAssertEqual(HardwareButtonAction.resolve("skipEpisode", default: .fastForward), .skipEpisode)
        XCTAssertEqual(HardwareButtonAction.resolve("bogus", default: .rewind), .rewind)
        XCTAssertEqual(HardwareButtonAction.resolve(nil, default: .fastForward), .fastForward)
    }
}
