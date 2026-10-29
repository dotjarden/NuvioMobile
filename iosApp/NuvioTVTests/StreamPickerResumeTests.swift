import XCTest
@testable import NuvioTV

/// Stream picker A, P3.3: the resume pill's text decisions, pinned without a view host.
final class StreamPickerResumeTests: XCTestCase {

    func testPositionWinsOverFractionAndShowsHours() {
        XCTAssertEqual(
            StreamPickerResume.label(positionMs: 4_324_000, fraction: 0.4, startFromBeginning: false),
            "Resume from 1:12:04")
    }

    func testPositionUnderAnHourOmitsHours() {
        XCTAssertEqual(
            StreamPickerResume.label(positionMs: 724_000, fraction: 0.4, startFromBeginning: false),
            "Resume from 12:04")
    }

    func testFractionAloneShowsPercent() {
        XCTAssertEqual(
            StreamPickerResume.label(positionMs: nil, fraction: 0.4, startFromBeginning: false),
            "Resume from 40 %")
    }

    func testTinyOrCompleteFractionShowsNothing() {
        XCTAssertNil(StreamPickerResume.label(positionMs: nil, fraction: 0.004, startFromBeginning: false))
        XCTAssertNil(StreamPickerResume.label(positionMs: nil, fraction: 1.0, startFromBeginning: false))
    }

    func testPositionUnderOneSecondShowsNothing() {
        // The players' own gate: a resume needs more than 10 s in (review r1).
        XCTAssertNil(StreamPickerResume.label(positionMs: 5_000, fraction: nil, startFromBeginning: false))
        XCTAssertNil(StreamPickerResume.label(positionMs: 10_000, fraction: nil, startFromBeginning: false))
        XCTAssertEqual(StreamPickerResume.label(positionMs: 10_001, fraction: nil, startFromBeginning: false), "Resume from 0:10")
        XCTAssertNil(StreamPickerResume.label(positionMs: 0, fraction: 0, startFromBeginning: false))
    }

    func testStartOverHidesThePill() {
        XCTAssertNil(StreamPickerResume.label(positionMs: 4_324_000, fraction: 0.4, startFromBeginning: true))
    }

    func testTimeString() {
        XCTAssertEqual(StreamPickerResume.timeString(seconds: 0), "0:00")
        XCTAssertEqual(StreamPickerResume.timeString(seconds: 59.6), "1:00")
    }
}
