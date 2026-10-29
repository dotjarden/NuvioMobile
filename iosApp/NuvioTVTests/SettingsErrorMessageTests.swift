import XCTest
@testable import NuvioTV

final class SettingsErrorMessageTests: XCTestCase {
    func testSettingsErrorsKeepActionableMessagesWithoutTransportDump() {
        XCTAssertEqual(SettingsErrorMessage.readable("  Invalid API key.  ", fallback: "Try again."), "Invalid API key.")
        XCTAssertEqual(SettingsErrorMessage.readable("Exception in http request: Error Domain=NSURLErrorDomain UserInfo=...", fallback: "Check the URL."), "Check the URL.")
        XCTAssertEqual(SettingsErrorMessage.readable(String(repeating: "x", count: 300), fallback: "Try again."), "Try again.")
    }
}
