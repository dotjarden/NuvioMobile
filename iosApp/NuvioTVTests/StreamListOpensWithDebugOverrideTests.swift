import XCTest
import SharedCore
@testable import NuvioTV

/// Direction C D9: `-debug.sourceListOpensWith FULL|BEST` pins the stream picker's opening body for a
/// UI-leg launch. Parsing is pure; `mode(_:)` reads only in DEBUG and never writes.
final class StreamListOpensWithDebugOverrideTests: XCTestCase {

    func testDebugKeyName() {
        XCTAssertEqual(StreamListOpensWithDebugOverride.debugKey, "debug.sourceListOpensWith")
    }

    func testParseAcceptsTheTwoSpellingsTrimmedInAnyCase() {
        XCTAssertEqual(StreamListOpensWithDebugOverride.parse("FULL"), .fullList)
        XCTAssertEqual(StreamListOpensWithDebugOverride.parse("full"), .fullList)
        XCTAssertEqual(StreamListOpensWithDebugOverride.parse(" Full_List "), .fullList)
        XCTAssertEqual(StreamListOpensWithDebugOverride.parse("BEST"), .bestPick)
        XCTAssertEqual(StreamListOpensWithDebugOverride.parse("best_pick"), .bestPick)
    }

    func testParseRejectsEverythingElse() {
        XCTAssertNil(StreamListOpensWithDebugOverride.parse(nil))
        XCTAssertNil(StreamListOpensWithDebugOverride.parse(""))
        XCTAssertNil(StreamListOpensWithDebugOverride.parse("  "))
        XCTAssertNil(StreamListOpensWithDebugOverride.parse("tiers"))
    }

    func testModeReadsOnlyWhenPresentAndOnlyInDebug() throws {
        let suite = "StreamListOpensWithDebugOverrideTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(StreamListOpensWithDebugOverride.mode(defaults), "absent: the stored setting decides")
        defaults.set("FULL", forKey: StreamListOpensWithDebugOverride.debugKey)
        #if DEBUG
        XCTAssertEqual(StreamListOpensWithDebugOverride.mode(defaults), .fullList)
        defaults.set("garbage", forKey: StreamListOpensWithDebugOverride.debugKey)
        XCTAssertNil(StreamListOpensWithDebugOverride.mode(defaults), "unknown: the stored setting decides")
        #else
        XCTAssertNil(StreamListOpensWithDebugOverride.mode(defaults))
        #endif
    }
}
