import SwiftUI

/// One source chip's facts: the add-on of a shared `AddonStreamGroup`, its listable count, and
/// its fetch state. Built in `StreamsViewModel.apply(_:)` from every group of the fan-out
/// (listable or not), so a chip exists for an add-on while it loads and when it fails.
nonisolated struct SourceChip: Equatable, Identifiable {
    /// The add-on's group id (`AddonStreamGroup.addonId`), the value `selectFilter` takes.
    let id: String
    let name: String
    /// Listable streams (after the picker's playability filter).
    let count: Int
    let isLoading: Bool
    /// The shared group's `error` (P0.2): the add-on answered with a failure. nil otherwise.
    let error: String?

    var hasError: Bool { !(error ?? "").isEmpty }
}

/// Stream picker A, P2 (`docs/stream-picker-addons-plan-2026-10-25.md` §2): the source chips above
/// the list. A refresh chip, "All", then one chip per add-on in the shared group order
/// (`StreamAutoPlaySelector.orderAddonStreams`, which follows the installed add-on order).
///
/// States (Android TV `StreamScreen`): loading → label at 0.6 with a small spinner and no count;
/// error → an error-tinted fill, dropped 1.6 s after the fan-out finishes unless the add-on also
/// returned streams (`chipsToDrop`); selected → the accent fill from `.chip(selected:)`. The accent
/// is the only brand colour on the screen (HIG contract).
///
/// Focus: the row is its own focus section and scope; the selected chip prefers default focus so
/// Up from the first row lands on it. Select on a chip keeps focus on the chip. Left/Right on the
/// LIST (rows are full width, so the focus engine has no target and `onMoveCommand` sees the
/// press) step the selection with wrap (`step`), throttled to `moveRepeatInterval`.
struct SourceChipRow: View {
    let chips: [SourceChip]
    /// The selected add-on id; nil is "All".
    let selected: String?
    /// Any add-on still loading: spins the refresh glyph.
    let anyLoading: Bool
    let focus: FocusState<String?>.Binding
    let namespace: Namespace.ID
    let onSelect: (String?) -> Void
    let onRefresh: () -> Void

    nonisolated static let allKey = "chip:all"
    nonisolated static let refreshKey = "chip:refresh"
    nonisolated static func key(for addonId: String) -> String { "chip:\(addonId)" }

    /// Android TV's D-pad repeat throttle for Left/Right on the list.
    nonisolated static let moveRepeatInterval: TimeInterval = 0.112
    /// How long an error chip with no streams stays after the fan-out finished.
    nonisolated static let errorChipLinger: TimeInterval = 1.6

    var body: some View {
        // Review r1 (P2): a Left/Right on the list moves the selection without focusing a chip, so
        // the row scrolls the selected chip into view itself.
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.sm) {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(Theme.Font.meta)
                            .symbolEffect(.rotate, isActive: anyLoading)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, Theme.Spacing.xs)
                    }
                    .buttonStyle(.chip)
                    .focused(focus, equals: Self.refreshKey)
                    .id(Self.refreshKey)
                    .accessibilityLabel(Text("Refresh sources"))
                    .accessibilityIdentifier("stream_picker_chip_refresh")

                    chip(title: String(localized: "All"), key: Self.allKey, isActive: selected == nil,
                         isLoading: false, hasError: false,
                         accessibilityLabel: String(localized: "All sources"),
                         identifier: "stream_picker_chip_all") {
                        onSelect(nil)
                    }

                    // Review r1 (P2): identified by position, never by the add-on id, which carries
                    // the manifest URL (and with it a debrid config) into XCUITest dumps.
                    ForEach(Array(chips.enumerated()), id: \.element.id) { index, item in
                        chip(title: Self.label(for: item), key: Self.key(for: item.id), isActive: selected == item.id,
                             isLoading: item.isLoading, hasError: item.hasError,
                             accessibilityLabel: Self.accessibilityLabel(for: item),
                             identifier: "stream_picker_chip_\(index)") {
                            onSelect(item.id)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.xs)
            }
            // The chip lifts on focus; don't crop the lift (FilterPills guidance).
            .scrollClipDisabled()
            .onChange(of: selected, initial: true) { _, selected in
                proxy.scrollTo(selected.map(Self.key(for:)) ?? Self.allKey)
            }
        }
        .focusSection()
        .focusScope(namespace)
        .accessibilityIdentifier("stream_picker_chip_row")
    }

    @ViewBuilder
    private func chip(title: String, key: String, isActive: Bool, isLoading: Bool, hasError: Bool,
                      accessibilityLabel: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(title)
                    .lineLimit(1)
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 18, height: 18)
                }
            }
            .font(Theme.Font.meta)
            .opacity(isLoading ? 0.6 : 1)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
        }
        .buttonStyle(.chip(selected: isActive, tint: hasError ? Theme.Palette.error.opacity(0.12) : nil))
        .focused(focus, equals: key)
        .id(key)
        .prefersDefaultFocus(isActive, in: namespace)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    /// "Comet, 6 sources" / "Comet, loading" / "Comet, failed": the middle dot of `label(for:)` is
    /// not for VoiceOver.
    nonisolated static func accessibilityLabel(for chip: SourceChip) -> String {
        if chip.isLoading { return String(localized: "\(chip.name), loading") }
        if chip.hasError && chip.count == 0 { return String(localized: "\(chip.name), failed") }
        if chip.count == 1 { return String(localized: "\(chip.name), 1 source") }
        return String(localized: "\(chip.name), \(chip.count) sources")
    }

    /// "Comet · 6"; the count is left out while the add-on is still loading.
    nonisolated static func label(for chip: SourceChip) -> String {
        guard !chip.isLoading else { return chip.name }
        return "\(chip.name) \u{00B7} \(chip.count)"
    }

    /// `nonisolated`: compared inside the nonisolated `step`, so the conformance must not inherit
    /// the view's main-actor isolation (an error in Swift 6 mode).
    nonisolated enum StepDirection: Equatable { case previous, next }

    /// The selection after one Left (`.previous`) or Right (`.next`) on the list, over the order
    /// [All, chips…] with wrap at both ends. `nil` is "All". A selection that is no longer in
    /// `chipIds` (its chip was dropped) steps from "All".
    nonisolated static func step(from selected: String?, chipIds: [String], direction: StepDirection) -> String? {
        let order: [String?] = [nil] + chipIds.map { Optional($0) }
        guard order.count > 1 else { return nil }
        let current = order.firstIndex(where: { $0 == selected }) ?? 0
        let offset = direction == .next ? 1 : -1
        let next = (current + offset + order.count) % order.count
        return order[next]
    }

    /// The error chips to remove once the fan-out has finished: an add-on that failed AND returned
    /// nothing listable. A failed add-on with streams keeps its chip (and its tint).
    nonisolated static func chipsToDrop(_ chips: [SourceChip]) -> Set<String> {
        Set(chips.filter { $0.hasError && $0.count == 0 }.map(\.id))
    }
}
