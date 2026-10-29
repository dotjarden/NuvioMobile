import Foundation
import SharedCore

/// Polish batch D4: one labelled run of rows in the source list. Built in
/// `StreamsViewModel.apply(_:)`, never in a body. Plain values only (W3-16 F1).
/// A presentation grouping over the same row values and keys as `StreamsViewModel.groups`.
struct StreamListSection: Identifiable, Equatable {
    /// "tier|<StreamTier.name>" or "addon|<addonId>".
    let id: String
    /// "4K" ... "SD", the localized "Other", or the add-on's name.
    let title: String
    /// Rows in this section (tier mode); nil in add-on mode (today's label has no count).
    let count: Int?
    /// Add-on mode only: the add-on is still answering (today's "Fetching..." spinner). Always false for tiers.
    let isLoading: Bool
    /// Tier mode: always. Add-on mode: only under "All" (today's rule).
    let showsLabel: Bool
    let rows: [StreamRowModel]

    static func build(groups: [StreamsViewModel.Group], mode: StreamGroupingMode,
                      selectedFilter: String?) -> [StreamListSection] {
        if mode == .addon {
            return groups.map { group in
                StreamListSection(id: "addon|\(group.id)", title: group.addonName, count: nil,
                                  isLoading: group.isLoading, showsLabel: selectedFilter == nil,
                                  rows: group.rows)
            }
        }
        let rows = groups.flatMap(\.rows)
        guard !rows.isEmpty else { return [] }
        let buckets = StreamTierGrouping.shared.groupIndices(
            resolutions: rows.map { KotlinInt(int: Int32($0.resolution ?? 0)) })
        return buckets.map { bucket in
            let bucketRows = bucket.indices.map { rows[$0.intValue] }
            return StreamListSection(id: "tier|\(bucket.tier.name)",
                                     title: StreamTierLabel.text(for: bucket.tier),
                                     count: bucketRows.count, isLoading: false, showsLabel: true,
                                     rows: bucketRows)
        }
    }
}

/// The tier label the list draws. Verbatim format names; only "Other" is a word.
enum StreamTierLabel {
    static func text(for tier: StreamTier) -> String {
        tier == .other ? String(localized: "Other") : tier.label
    }
}
