import Foundation

/// BUG-187 (Steven rc9: "back from a cast member, focus goes back to Play"). The main fix keeps
/// the rows mounted across the reload (`DetailMetaAdoption`), so the focus engine can restore the
/// card itself. This is the fallback: the last card focus held in the Cast, Studios, Collection
/// and More Like This rows, re-applied after a pop with FEAT-79's rungs (`CollectionsUI`'s
/// `restoreClassicRowsFocus`) when the engine's own restoration does not land there.
///
/// A reference box held in `@State` with no published state: writing it on every Left/Right
/// never invalidates `DetailView`. The rows write it from their own focus state; `DetailView`
/// arms it when the page disappears and takes the armed target when it appears again.
@MainActor
final class DetailFocusMemory {
    /// The remembered row and card key (the cast/studio index, or the item id), nil when none.
    private(set) var row: DetailRowID?
    private(set) var key: String?
    private var armed = false
    /// Review r1: false from `arm()` (the page's `onDisappear`) until `takeArmedTarget()` (its
    /// `onAppear`). The focus engine can report Play in between (the pushed page's teardown, the
    /// pop's first layout), and that report must not disarm the restore it is about to need.
    private(set) var pageVisible = true
    private var generation = 0

    /// A card in a tracked row took focus. A nil key (focus left the row, which a push also does)
    /// keeps the last card: `clear()` is what forgets it.
    func note(row: DetailRowID, key: String?) {
        guard let key else { return }
        self.row = row
        self.key = key
    }

    /// Focus settled somewhere this box does not track (the hero, another row). A no-op while
    /// the page is not visible (review r1): a focus report between `arm()` and the next
    /// `takeArmedTarget()` belongs to the push/pop, not to the viewer.
    func clear() {
        guard pageVisible else { return }
        row = nil
        key = nil
        armed = false
    }

    /// The page is going away with a remembered card (a push from that card).
    func arm() {
        armed = row != nil && key != nil
        pageVisible = false
    }

    /// The armed target, once: a later appearance without a new push restores nothing. Called on
    /// every appearance, so it also marks the page visible again (armed or not).
    func takeArmedTarget() -> (row: DetailRowID, key: String)? {
        pageVisible = true
        guard armed, let row, let key else { return nil }
        armed = false
        return (row, key)
    }

    /// A new restore; any older one's pending rungs stand down.
    func beginRestore() -> Int {
        generation &+= 1
        return generation
    }

    func isCurrent(_ generation: Int) -> Bool { generation == self.generation }
}

/// BUG-187: a restore rung for a row that owns its own `FocusState` (Collection, More Like This).
/// `DetailView` sets it; the row applies it when `row` is its own.
struct DetailFocusRestoreRequest: Equatable {
    var row: DetailRowID?
    var key: String?
    var force: Bool
    var generation: Int

    static let none = DetailFocusRestoreRequest(row: nil, key: nil, force: false, generation: 0)
}

/// BUG-187: the pure halves of the fallback restore.
enum DetailFocusRestore {
    /// FEAT-79's rungs: two forced at once and after the first layout, then two late ones for the
    /// engine's own restoration (0.55–0.98 s late on hardware, Batch A).
    nonisolated static let rungs: [(delay: Double, force: Bool)] = [(0, true), (0.35, true), (0.8, false), (1.1, false)]
    /// When the request is retired, after the last rung.
    nonisolated static let retireDelay: Double = 1.3

    /// Rows that remember their card. Focus landing on any other row forgets it.
    nonisolated static func tracks(_ row: DetailRowID) -> Bool {
        switch row {
        case .cast, .logos, .collection, .moreLikeThis: true
        default: false
        }
    }

    /// Whether a rung moves focus. `current` is the row's focused card key (nil = focus is not in
    /// the row). A forced rung corrects any other card; a late rung only pulls focus back into a
    /// row it is not in at all (the engine put it on Play), never off a card in the row.
    nonisolated static func shouldApply(force: Bool, current: String?, target: String) -> Bool {
        force ? current != target : current == nil
    }
}

/// BUG-187: `-debug.detailFocusProbe YES` mounts the DEBUG `debug_detail_focus row= idx=` label
/// the UI leg reads (the tvOS 27 simulator never reports `hasFocus`). Launch-latched.
enum DetailFocusProbe {
    nonisolated static let enabled = UserDefaults.standard.bool(forKey: "debug.detailFocusProbe")
}
