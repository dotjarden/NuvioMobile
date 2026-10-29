import AVFoundation
import AVKit
import XCTest
@testable import NuvioTV

/// P4 (A6-native): chapter times on the native timeline and the system bar's markers.
final class NativeChapterMarkersTests: XCTestCase {
    func testSecondsSubtractTheKeyframeOrigin() {
        XCTAssertEqual(NativeChapterMarkers.seconds(start: 90000, tbNum: 1, tbDen: 1000, originSec: 0), 90.0, accuracy: 1e-9)
        XCTAssertEqual(NativeChapterMarkers.seconds(start: 90000, tbNum: 1, tbDen: 1000, originSec: 1.0), 89.0, accuracy: 1e-9)
        XCTAssertEqual(NativeChapterMarkers.seconds(start: 90000, tbNum: 1, tbDen: 1000, originSec: 0.083), 89.917, accuracy: 1e-9)
    }

    func testGroups() throws {
        let chapters = [TransportChapter(title: "Opening", sec: 0), TransportChapter(title: "", sec: 90),
                        TransportChapter(title: "Act Two", sec: 240)]
        let groups = NativeChapterMarkers.groups(chapters, durationSec: 600)
        XCTAssertEqual(groups.count, 1)
        XCTAssertNil(groups[0].title)
        let markers = groups[0].timedNavigationMarkers ?? []
        XCTAssertEqual(markers.count, 3)
        XCTAssertEqual(markers[0].timeRange.end.seconds, 90, accuracy: 0.001)
        XCTAssertEqual(markers[1].timeRange.start.seconds, 90, accuracy: 0.001)
        XCTAssertEqual(markers[1].timeRange.end.seconds, 240, accuracy: 0.001)
        XCTAssertEqual(markers[2].timeRange.end.seconds, 600, accuracy: 0.001)
        XCTAssertEqual(markers[1].items.first?.value as? String, String(localized: "Chapter 2"))
        XCTAssertEqual(markers[0].items.first?.value as? String, "Opening")
    }

    func testEmpty() {
        XCTAssertTrue(NativeChapterMarkers.groups([], durationSec: 600).isEmpty)
    }
}
