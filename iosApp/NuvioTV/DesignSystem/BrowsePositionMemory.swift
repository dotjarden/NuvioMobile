import SwiftUI

/// Owned by each Home/Browse surface. Keeps a shelf's place when lazy rows are recycled, without
/// observing every focus change at the app root. Destroyed when the user leaves their profile.
final class BrowsePositionMemory {
    private var items: [String: String] = [:]
    func remember(_ item: String, in row: String) {
        if items.count >= 100, items[row] == nil, let first = items.keys.first { items[first] = nil }
        items[row] = item
    }
    func item(in row: String) -> String? { items[row] }
}
private struct BrowsePositionMemoryKey: EnvironmentKey {
    static let defaultValue: BrowsePositionMemory? = nil
}
extension EnvironmentValues {
    var browsePositionMemory: BrowsePositionMemory? {
        get { self[BrowsePositionMemoryKey.self] }
        set { self[BrowsePositionMemoryKey.self] = newValue }
    }
}
