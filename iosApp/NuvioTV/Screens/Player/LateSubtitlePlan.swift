import Foundation

/// P4 (B17): add-on subtitles that arrive after the native master was first served. Pure: the
/// rendition merge (indices and names) and the rebuild decision.
nonisolated enum LateSubtitlePlan {
    enum Action: Equatable {
        /// Nothing new.
        case none
        /// Publish the late renditions as panel rows; the item is rebuilt on the first pick of one.
        case publishOnly
        /// Rebuild the item now so the named late DEFAULT rendition shows.
        case autoRebuild(name: String)
    }

    /// `existing` unchanged, followed by renditions for the `late` files whose URL is not already
    /// served. Indices continue from `max(existing index) + 1`; names are unique against every
    /// existing name with the " 2" suffix rule.
    static func merge(existing: [SubtitleRendition], late: [SubtitleFile]) -> [SubtitleRendition] {
        let servedURLs = Set(existing.compactMap { $0.sourceURL?.absoluteString })
        let fresh = SubtitleVTT.renditions(from: late.filter { !servedURLs.contains($0.url) })
        guard !fresh.isEmpty else { return existing }
        var seenNames = Set(existing.map(\.name))
        var next = (existing.map(\.index).max() ?? -1) + 1
        var out = existing
        for r in fresh {
            var name = r.name
            if !seenNames.insert(name).inserted {
                var n = 2
                while !seenNames.insert("\(r.name) \(n)").inserted { n += 1 }
                name = "\(r.name) \(n)"
            }
            out.append(SubtitleRendition(index: next, name: name, language: r.language, source: r.source,
                                         forced: r.forced, hearingImpaired: r.hearingImpaired))
            next += 1
        }
        return out
    }

    /// `.autoRebuild` only when the viewer has not touched the subtitle selection, nothing is
    /// showing, no rebuild has happened this session and a late rendition is DEFAULT in `flags`
    /// (parallel to `late`). Otherwise `.publishOnly` (`.none` with no late renditions).
    static func decide(late: [SubtitleRendition], flags: [SubtitleRenditionFlags], selectionShowing: Bool,
                       legibleTouched: Bool, rebuildsUsed: Int) -> Action {
        guard !late.isEmpty else { return .none }
        guard !legibleTouched, !selectionShowing, rebuildsUsed == 0,
              let i = flags.indices.first(where: { flags[$0].isDefault && $0 < late.count }) else { return .publishOnly }
        return .autoRebuild(name: late[i].name)
    }
}
