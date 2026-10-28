import Foundation

/// Direction C D5: one section of the `.tiers` body: a `StreamListSection` folded to its preview.
nonisolated struct StreamTierPreviewSection: Equatable, Identifiable {
    static let previewCount = 2
    /// = `StreamListSection.id` ("tier|FHD", "addon|<id>").
    let id: String
    let title: String
    let count: Int?
    let isLoading: Bool
    let showsLabel: Bool
    /// The first `previewCount` rows in list order, or every row when expanded or when count <= 2.
    let visibleRows: [StreamRowModel]
    /// rows.count - visibleRows.count; 0 means no "more" row.
    let hiddenCount: Int
    /// The key of the first hidden row (the row that takes the "more" row's place on expand).
    let firstHiddenKey: String?
    let isExpanded: Bool
    /// The "more" row's focus key and scroll id. Carries the section id, which in Add-on mode
    /// carries the add-on id (a manifest URL): never log it (`focusProbeName` prints "more").
    var moreFocusKey: String { "more:" + id }
}

/// Direction C: the `.tiers` body as one flat, lazily realized list (the LazyVStack's children).
nonisolated enum StreamTiersItem: Equatable, Identifiable {
    case card(StreamBestPickModel)
    case alternatives([StreamAlternativeModel])
    /// Drawn only when `section.showsLabel`.
    case header(StreamTierPreviewSection)
    case row(StreamRowModel, sectionId: String)
    case more(StreamTierPreviewSection)

    var id: String {
        switch self {
        case .card: return StreamBestPickModel.focusKey
        case .alternatives: return "alternatives"
        case .header(let s): return "header|" + s.id
        case .row(let r, _): return r.key
        case .more(let s): return s.moreFocusKey
        }
    }
}

/// The row keys the card and pills show (after the upgrade gate). All nil = no card, no pills.
nonisolated struct StreamBestPickSelection: Equatable {
    var bestKey: String?
    var fhdKey: String?
    var directKey: String?
    static let none = StreamBestPickSelection()
}

/// Direction C D3 "at most one swap per add-on answer", and the plan's named fallback.
nonisolated enum StreamBestPickUpgradePolicy: Equatable {
    /// Default: the card may change when another add-on has answered, when the fan-out settles,
    /// and freely after it settled.
    case perAnswer
    /// Risks fallback: the card is frozen on the first eligible stream and upgraded once, when the
    /// fan-out settles.
    case onCompletion
}

nonisolated struct StreamBestPickAnchor: Equatable {
    var selection: StreamBestPickSelection
    var answered: Int
    var settled: Bool
    var filter: String?
}

/// The upgrade gate (spec §4.7): decides whether a fresh pick replaces the one on screen.
nonisolated enum StreamBestPickGate {
    static func resolve(previous: StreamBestPickAnchor?, fresh: StreamBestPickSelection,
                        eligibleKeys: Set<String>, availableKeys: Set<String>,
                        answered: Int, settled: Bool, filter: String?,
                        policy: StreamBestPickUpgradePolicy) -> StreamBestPickAnchor {
        func anchor(_ selection: StreamBestPickSelection) -> StreamBestPickAnchor {
            StreamBestPickAnchor(selection: selection, answered: answered, settled: settled, filter: filter)
        }
        // 1: first pick, or a different filter (a different list).
        guard let previous, previous.filter == filter else { return anchor(fresh) }
        // 2: nothing was shown yet.
        guard let shownKey = previous.selection.bestKey else { return anchor(fresh) }
        // 3: the shown stream is gone, rejected or no longer eligible.
        guard eligibleKeys.contains(shownKey) else { return anchor(fresh) }
        // 4 / 5: an upgrade moment.
        switch policy {
        case .perAnswer:
            if answered > previous.answered || settled { return anchor(fresh) }
        case .onCompletion:
            if settled { return anchor(fresh) }
        }
        // 6: hold; the pills drop out when their stream is gone.
        var held = previous.selection
        if let key = held.fhdKey, !availableKeys.contains(key) { held.fhdKey = nil }
        if let key = held.directKey, !availableKeys.contains(key) { held.directKey = nil }
        return anchor(held)
    }
}

/// Direction C D1/D7: what the source panel's body shows, built in `StreamsViewModel.apply(_:)`
/// (and on the three body actions), never in a body. Equatable: an equal rebuild is not published.
nonisolated struct StreamPickerBodyModel: Equatable {
    var mode: StreamPickerSourceContent = .list
    var card: StreamBestPickModel?
    var alternatives: [StreamAlternativeModel] = []
    var sections: [StreamTierPreviewSection] = []
    /// `.tiers` only: card, alternatives (one item, when non-empty), then per section: header
    /// (when showsLabel), visible rows, more (when hiddenCount > 0). Empty in `.list`.
    var items: [StreamTiersItem] = []
    /// Where list focus goes first. `.list`: the first row (= `firstRowKey`). `.tiers`: the card,
    /// else the first pill, else the first visible row, else nil.
    var firstFocusKey: String?
    /// `.tiers`: every focusable key in `items` (card, pills, visible rows, more rows). Empty in `.list`.
    var focusKeys: Set<String> = []

    @MainActor
    static func build(mode: StreamPickerSourceContent, sections: [StreamListSection],
                      firstRowKey: String?, selection: StreamBestPickSelection,
                      settled: Bool, expanded: Set<String>) -> StreamPickerBodyModel {
        guard mode == .tiers else {
            return StreamPickerBodyModel(mode: .list, firstFocusKey: firstRowKey)
        }
        let rows = sections.flatMap(\.rows)
        var rowsByKey: [String: StreamRowModel] = [:]
        for row in rows where rowsByKey[row.key] == nil { rowsByKey[row.key] = row }

        let card: StreamBestPickModel? = selection.bestKey.flatMap { rowsByKey[$0] }.map { row in
            StreamBestPickModel(rowKey: row.key, isSettled: settled,
                                headline: StreamPickerCopy.cardHeadline(row),
                                facts: StreamPickerCopy.cardFacts(row),
                                rankLine: StreamPickerCopy.rankLine(considered: rows.count),
                                considered: rows.count)
        }

        var alternatives: [StreamAlternativeModel] = []
        if !rows.isEmpty {
            if let row = selection.fhdKey.flatMap({ rowsByKey[$0] }) {
                alternatives.append(StreamAlternativeModel(
                    kind: .bestFhd, rowKey: row.key,
                    title: StreamPickerCopy.pillTitle(.bestFhd, row)))
            }
            if let row = selection.directKey.flatMap({ rowsByKey[$0] }) {
                alternatives.append(StreamAlternativeModel(
                    kind: .bestDirect, rowKey: row.key,
                    title: StreamPickerCopy.pillTitle(.bestDirect, row)))
            }
            alternatives.append(StreamAlternativeModel(
                kind: .showAll, rowKey: nil, title: StreamPickerCopy.showAllTitle(rows.count)))
        }

        let previews: [StreamTierPreviewSection] = sections.map { section in
            let isExpanded = expanded.contains(section.id)
            let visible = (isExpanded || section.rows.count <= StreamTierPreviewSection.previewCount)
                ? section.rows
                : Array(section.rows.prefix(StreamTierPreviewSection.previewCount))
            let hidden = section.rows.count - visible.count
            return StreamTierPreviewSection(
                id: section.id, title: section.title, count: section.count,
                isLoading: section.isLoading, showsLabel: section.showsLabel,
                visibleRows: visible, hiddenCount: hidden,
                firstHiddenKey: hidden > 0 ? section.rows[visible.count].key : nil,
                isExpanded: isExpanded)
        }

        var items: [StreamTiersItem] = []
        var focusKeys: Set<String> = []
        if let card {
            items.append(.card(card))
            focusKeys.insert(StreamBestPickModel.focusKey)
        }
        if !alternatives.isEmpty {
            items.append(.alternatives(alternatives))
            for alt in alternatives { focusKeys.insert(alt.focusKey) }
        }
        var firstRow: String?
        for section in previews {
            if section.showsLabel { items.append(.header(section)) }
            for row in section.visibleRows {
                items.append(.row(row, sectionId: section.id))
                focusKeys.insert(row.key)
                if firstRow == nil { firstRow = row.key }
            }
            if section.hiddenCount > 0 {
                items.append(.more(section))
                focusKeys.insert(section.moreFocusKey)
            }
        }
        let first = card != nil ? StreamBestPickModel.focusKey : (alternatives.first?.focusKey ?? firstRow)
        return StreamPickerBodyModel(mode: .tiers, card: card, alternatives: alternatives,
                                     sections: previews, items: items, firstFocusKey: first,
                                     focusKeys: focusKeys)
    }
}
