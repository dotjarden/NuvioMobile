import XCTest
import SharedCore
@testable import NuvioTV

/// Stream picker A, P5: the per-add-on filter survives the Kotlin/Swift bridge. `selectFilter` on
/// the shared `StreamsRepository` singleton lands in its `uiState` StateFlow, whose `value_` the
/// view model reads in Swift as `Any?` (cast to `StreamsUiState`).
@MainActor
final class StreamsRepositoryFilterRoundTripTests: XCTestCase {

    override func tearDown() {
        // The repository is a process-wide singleton: leave no filter behind for other tests.
        StreamsRepository.shared.selectFilter(addonId: nil)
        super.tearDown()
    }

    private func currentState() -> StreamsUiState? {
        StreamsRepository.shared.uiState.value_ as? StreamsUiState
    }

    func testSelectFilterRoundTripsThroughTheSharedRepository() {
        StreamsRepository.shared.selectFilter(addonId: "addon:test")
        let selected = currentState()
        XCTAssertNotNil(selected, "uiState.value did not bridge to StreamsUiState")
        XCTAssertEqual(selected?.selectedFilter, "addon:test")

        StreamsRepository.shared.selectFilter(addonId: nil)
        let cleared = currentState()
        XCTAssertNotNil(cleared, "uiState.value did not bridge to StreamsUiState")
        XCTAssertNil(cleared?.selectedFilter)
    }
}
