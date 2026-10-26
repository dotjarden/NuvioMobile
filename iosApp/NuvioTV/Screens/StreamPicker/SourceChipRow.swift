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

    /// P5 device pass: programmatic scrolling by id (`ScrollViewReader.scrollTo`, then
    /// `.scrollPosition(id:)`) centred the selected chip on the tvOS 26.5 simulator and never on
    /// the Living Room box (tvOS 27.2), where only focus-driven scrolling moved the row. The Home
    /// rows scroll that box by OFFSET (`ScrollPosition.scrollTo(x:)`), so the row does the same:
    /// each chip reports its frame in the content space, the viewport its width, and a step
    /// scrolls to the offset that centres the selected chip, clamped to the content.
    @State private var position = ScrollPosition()
    @State private var chipFrames: [String: CGRect] = [:]
    @State private var viewportWidth: CGFloat = 0

    var body: some View {
        // Review r1 (P2): a Left/Right on the list moves the selection without focusing a chip, so
        // the row scrolls the selected chip into view itself.
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
                .coordinateSpace(name: Self.contentSpace)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { geo in
            Color.clear.onChange(of: geo.size.width, initial: true) { _, width in
                viewportWidth = width
            }
        })
        .onPreferenceChange(ChipFrameKey.self) { chipFrames = $0 }
        // The chip lifts on focus; don't crop the lift (FilterPills guidance).
        .scrollClipDisabled()
        .scrollPosition($position)
        .onChange(of: selected, initial: true) { _, selected in
            // The chip frames are laid out in the same update as the selection: scroll on the next
            // runloop, centred rather than merely "in view" (a step onto the last chip once left it
            // cut at the panel edge, P4 device pass).
            let key = selected.map(Self.key(for:)) ?? Self.allKey
            DispatchQueue.main.async { scrollToChip(key) }
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
        .background(GeometryReader { geo in
            Color.clear.preference(key: ChipFrameKey.self, value: [key: geo.frame(in: .named(Self.contentSpace))])
        })
        .prefersDefaultFocus(isActive, in: namespace)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    nonisolated static let contentSpace = "stream_picker_chip_row.content"

    /// The offset that centres `key` in the viewport, clamped to the content; nothing before the
    /// frames and the viewport are known (the next selection change tries again).
    nonisolated static func scrollOffset(for key: String, frames: [String: CGRect], viewportWidth: CGFloat,
                                         trailingInset: CGFloat = 0) -> CGFloat? {
        guard viewportWidth > 0, let frame = frames[key] else { return nil }
        // The frames are in the padded content's space: the trailing padding lies past the last
        // chip's edge and is part of what can scroll into view.
        let contentWidth = (frames.values.map(\.maxX).max() ?? 0) + trailingInset
        let maxOffset = max(contentWidth - viewportWidth, 0)
        return min(max(frame.midX - viewportWidth / 2, 0), maxOffset)
    }

    private func scrollToChip(_ key: String) {
        guard let x = Self.scrollOffset(for: key, frames: chipFrames, viewportWidth: viewportWidth,
                                        trailingInset: Theme.Spacing.xs) else { return }
        withAnimation(.easeOut(duration: 0.2)) { position.scrollTo(x: x) }
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
        // P5 review r1 Q2: no count while loading, and none on a failed chip with nothing listable
        // (it reads "failed" to VoiceOver and sits on the error tint for the linger); "Comet · 0"
        // stays for an add-on that answered with nothing.
        guard !chip.isLoading, !(chip.hasError && chip.count == 0) else { return chip.name }
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

/// The chips' frames in the row's content space, keyed by chip key (`SourceChipRow.scrollToChip`).
private struct ChipFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
