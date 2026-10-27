import SwiftUI
import SharedCore

/// W3-16 (BUG-207, F1): one stream row, `Equatable` over its `StreamRowModel` (the closures are not
/// compared, see `StreamPickerView.streamRowView`). Reads NOTHING from the picker: not the focus
/// state, not the resolve spinner, not the rejected set — the model carries them.
///
/// BUG-16's expansion (a focused row shows its whole release name) reads the row style's
/// `\.settingsRowIsFocused` inside `StreamRowDescription`, so a focus move re-evaluates that one
/// leaf, never the row or its siblings.
struct StreamRowView: View, Equatable {
    let model: StreamRowModel
    let onSelect: () -> Void
    let onBuiltIn: () -> Void
    let onExternal: (String) -> Void
    /// Review r1 P2-3: called once the description's dwell has grown the focused row and it has
    /// laid out (the picker scrolls it back on screen). Not compared, like the other closures.
    var onExpanded: () -> Void = {}

    nonisolated static func == (lhs: StreamRowView, rhs: StreamRowView) -> Bool {
        lhs.model == rhs.model
    }

    var body: some View {
        #if DEBUG
        let _ = HomeBodyCounter.tick("StreamRow")
        #endif
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if model.hasBadgeRow && model.badgesOnTop {
                        StreamRowBadges(badges: model.badges, sizeBytes: model.sizeBytes)
                    }
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(model.title)
                            .font(Theme.Font.body)
                            .rowTextColor()
                            .lineLimit(2)
                        if model.isResolving {
                            ProgressView().scaleEffect(0.7)
                        }
                    }
                    if let description = model.description {
                        StreamRowDescription(text: description, onExpanded: onExpanded)
                    }
                    if model.hasBadgeRow && !model.badgesOnTop {
                        StreamRowBadges(badges: model.badges, sizeBytes: model.sizeBytes)
                    }
                    // Batch D U2: the add-on gave only a YouTube video id — the row plays after an
                    // on-device resolve (the spinner above), so say where the video comes from.
                    if model.isYouTube {
                        Text(verbatim: "YouTube")
                            .font(Theme.Font.caption)
                            .rowTextColor(secondary: true)
                    }
                    // Orivio batch item 2: this link failed recently for this title, so the
                    // automatic pickers skip it. Still selectable by hand.
                    if model.failedRecently {
                        Text("Failed recently")
                            .font(Theme.Font.caption)
                            .rowTextColor(secondary: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if model.showsAddonColumn {
                    StreamRowAddonColumn(name: model.addonName, logo: model.addonLogo)
                }
            }
            .padding(Theme.Spacing.md)
        }
        // `.settingsRow` (platter-free, soft white highlight + accent ring) replaces the system
        // `.glass` style: Liquid Glass's focus platter goes near-white, which made this row's
        // title text (statically `textPrimary`, near-white) unreadable on focus.
        .buttonStyle(.settingsRow)
        // P3.2: a 12 pt card on `surface` at rest so the row reads inside the panel (upstream mobile
        // white 5 %, Android TV #1A1A1A). Drawn BEHIND the style: focus keeps `.settingsRow`'s white
        // platter and lift on top (the native-List pass is a separate debt, not this batch).
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Palette.surface)
        )
        .accessibilityIdentifier("stream_picker_row")
        // FEAT-5: long-press → the OTHER player(s). With the built-in default, the menu offers
        // the installed external players; with an external default (plain Select already hands
        // off) it inverts to offer "Play in NuvioTV Player" plus any non-default externals. The
        // modifier is skipped entirely when no external player is installed, so the long-press
        // stays inert rather than opening an empty menu.
        .modifier(ExternalPlayMenu(
            players: model.players,
            defaultPlayerId: model.defaultPlayerId,
            onExternal: onExternal,
            onBuiltIn: onBuiltIn
        ))
    }
}

/// The release name under a row's title: 3 lines while browsing, the whole name on the focused row.
///
/// BUG-16 (final form): release names are dot/underscore-separated with no break points, so no
/// fixed cap fits all of them ("works for some links but not all" — the reporter, on the 3-line
/// beta.7 fix); expanding the row under focus guarantees the name you're actually reading is never
/// truncated, without a marquee and without inflating every row in the list.
///
/// W3-16 (BUG-207, F2): the expansion used to follow focus at once, so every Down/Up changed two
/// rows' heights while the engine scrolled a lazy stack on estimated heights. It now waits for a
/// dwell (`StreamRowDescription.dwell`): a browsing move changes no height at all. The collapse on
/// losing focus is immediate (derived from focus), and neither direction animates.
///
/// Review r1 P2-3: once grown, the row calls `onExpanded` (the picker's minimal `scrollTo`), so a
/// row near the bottom edge does not leave the end of its name below the fold.
private struct StreamRowDescription: View {
    let text: String
    let onExpanded: () -> Void
    /// ~0.5 s of the row holding focus before it grows.
    static let dwell: Duration = .milliseconds(500)
    /// After the grow, one frame or so for the taller row to lay out before the reveal is asked for:
    /// a `scrollTo` issued in the same update would measure the row at its 3-line height.
    static let revealDelay: Duration = .milliseconds(20)

    @Environment(\.settingsRowIsFocused) private var focused
    @State private var dwelled = false

    var body: some View {
        Text(text)
            .font(Theme.Font.caption)
            .rowTextColor(secondary: true)
            .lineLimit(focused && dwelled ? nil : 3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .task(id: focused) {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                guard focused else {
                    withTransaction(transaction) { dwelled = false }
                    return
                }
                try? await Task.sleep(for: Self.dwell)
                guard !Task.isCancelled else { return }
                withTransaction(transaction) { dwelled = true }
                // Review r1 P2-3: reveal the grown row once it has laid out. Focus leaving in the
                // meantime cancels this task (its id is `focused`), so a departed row never scrolls.
                try? await Task.sleep(for: Self.revealDelay)
                guard !Task.isCancelled else { return }
                onExpanded()
            }
    }
}

/// BUG-16: the badge row of a stream row — `ViewThatFits` over a ladder of candidates.
private struct StreamRowBadges: View {
    let badges: [StreamBadgeInfo]
    let sizeBytes: Int64?

    var body: some View {
        // BUG-16: this used to be one plain HStack with up to 8 badge chips (each up to
        // `StreamBadgeMetrics.maxImageWidth` = 180pt for image-based community badge packs) plus
        // the size chip — none of them width-flexible. An HStack whose children are all
        // non-shrinking ignores the width it's offered and reports the full sum of its children
        // back to its parent instead. That inflated "ideal" width bubbled up through the
        // title/description VStack and the row's outer HStack, widening the *whole row* — and
        // since every row shares one LazyVStack, effectively the whole list — past the screen.
        // The addon-logo column and the tail end of the badges/size chip then rendered off the
        // trailing edge, which is what testers saw as "no space left" for title/size/seeders.
        //
        // Fix: hand `ViewThatFits` a ladder of candidates from "every badge" down to "just an
        // overflow count", widest first. It measures each against the width actually left over
        // once title/description and the addon-logo column have claimed theirs, and renders the
        // first one that fits — so this row can never again demand more width than it's given.
        // The size chip is pinned first in every candidate since it's core metadata (like
        // seeders), not decoration, and every candidate shares the same fixed container height,
        // so switching between them never changes the row's height class.
        let displayBadges = Array(badges.prefix(8))
        let hiddenBeyondCap = max(0, badges.count - 8)
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: displayBadges.count, through: 0, by: -1)), id: \.self) { visible in
                variant(
                    displayBadges: displayBadges,
                    visibleCount: visible,
                    hiddenCount: (displayBadges.count - visible) + hiddenBeyondCap
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One `ViewThatFits` candidate: the size chip (if any) + the first `visibleCount` badges + a
    /// non-focusable "+N" overflow chip for everything else. `hiddenCount` folds in both badges
    /// dropped by this candidate and any beyond the 8-badge display cap, so the count the user sees
    /// is always accurate.
    private func variant(displayBadges: [StreamBadgeInfo], visibleCount: Int, hiddenCount: Int) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let sizeBytes {
                StreamFileSizeChip(bytes: sizeBytes)
            }
            ForEach(Array(displayBadges.prefix(visibleCount).enumerated()), id: \.offset) { _, badge in
                StreamBadgeChipView(badge: badge)
            }
            if hiddenCount > 0 {
                BadgeOverflowChip(count: hiddenCount)
            }
        }
    }
}

/// The trailing add-on column of a row: logo (when it has one) over the add-on's name.
private struct StreamRowAddonColumn: View {
    let name: String
    let logo: String?

    var body: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            if let logo, let url = URL(string: logo) {
                // Cached + downsampled: the same logo repeats on every row of a group, and the
                // uncached `AsyncImage` refetched and re-decoded it as each row was realized.
                // Clear while loading and on failure, like the old AsyncImage: add-on logos often
                // 404, and a shimmer or grey film tile on every row of the group is noise.
                CachedAsyncImage(url: url, contentMode: .fit, decodeSize: .points(width: 44, height: 44),
                                 loading: { Color.clear }, failure: { Color.clear })
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text(name)
                .font(Theme.Font.caption)
                .rowTextColor(secondary: true)
                .lineLimit(1)
        }
        .frame(width: 150)
    }
}

/// Attaches the "play somewhere else" context menu only when at least one supported external
/// player is installed (FEAT-5). A conditional modifier rather than an inline `.contextMenu` so
/// the no-players case adds NOTHING to the row — an empty context menu would still swallow the
/// long-press and show a blank platter, which reads as broken.
///
/// The menu always offers the destinations plain Select does NOT: with the built-in player as
/// default it lists the external players; with an external default it lists "Play in NuvioTV
/// Player" first (the escape hatch back) plus any other installed externals. The default player
/// itself is omitted — Select already goes there, and a menu entry duplicating Select reads as
/// two different actions.
private struct ExternalPlayMenu: ViewModifier {
    let players: [StreamRowPlayer]
    /// The validated default external player id, or nil when the built-in player is default.
    let defaultPlayerId: String?
    /// Called with the chosen player's `id`.
    let onExternal: (String) -> Void
    let onBuiltIn: () -> Void

    func body(content: Content) -> some View {
        if players.isEmpty {
            content
        } else {
            content.contextMenu {
                if defaultPlayerId != nil {
                    Button {
                        onBuiltIn()
                    } label: {
                        Label("Play in NuvioTV Player", systemImage: "play.tv")
                    }
                }
                ForEach(players.filter { $0.id != defaultPlayerId }, id: \.id) { player in
                    Button {
                        onExternal(player.id)
                    } label: {
                        Label("Open in \(player.name)", systemImage: "arrow.up.forward.app")
                    }
                }
            }
        }
    }
}
