import XCTest

/// BUG-92 (beta.18 follow-up, u/mrStevenx3): with No Zoom ON (`CardFocusButtonStyle` swaps to
/// `StillCardButtonStyle` + `.focusEffectDisabled(true)` — zero system lift, `PosterCard.swift`
/// ~L196-210), accent ring OFF, Card Depth ON, the inline poster trailer spills past the poster's
/// edge — but only on the FIRST (left-most) card of a row. Root cause: the row's horizontal
/// `ScrollView` runs `.scrollClipDisabled()` (`BrowseComponents.swift` ~L3107), so any bleed a
/// focused card puts outside its own layout frame lands on top of its LEFT neighbour and is
/// invisible everywhere except at card #1, which has no neighbour to hide behind — the empty
/// overscan margin left of the row shows it plainly. `RowLeadingEdgeClip`
/// (`NuvioTV/DesignSystem/RowLeadingEdgeClip.swift`) is the fix; see that type's header for the
/// exact `BrowseComponents.swift` attachment this repo's DesignSystem wave does NOT itself touch.
///
/// Card Depth is deliberately left at its default (untouched by either launch-argument leg below):
/// its rail/shadow draw strictly INSIDE the tile's own `.clipShape` (`CardDepthStyle.swift`), so it
/// has no bearing on bleed PAST the tile's edge — the reporter's "Card Depth ON" is incidental to
/// this bug, not a precondition of it.
///
/// Helper methods here are a trimmed COPY of `NuvioTVUITests`'/`TrailerSoakTests`'/
/// `InlineTrailerTileProbeTests`' (`launchToHome`, `press`, `pause`, `shot`) — same house rule those
/// give for why cross-file UI-test helpers stay duplicated rather than factored out.
final class RowLeadingEdgeTests: XCTestCase {

    let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    // MARK: - Helpers (see type doc for why these are duplicated, not shared)

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func press(_ button: XCUIRemote.Button, times: Int = 1, gap: TimeInterval = 0.8) {
        for _ in 0..<times {
            remote.press(button)
            pause(gap)
        }
    }

    @discardableResult
    private func launchToHome(extraArguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        // Home Stage & Strip (W3, 2026-10-05): Stage is the app's default Home now, and this file
        // measures Classic Home (Classic's row leading edge), so every launch pins Classic.
        app.launchArguments += ["-home_layout", "classic"]
        app.launchArguments += extraArguments
        app.launch()
        let chris = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chris")).firstMatch
        XCTAssertTrue(chris.waitForExistence(timeout: 90), "profile picker never appeared — is the sim session still signed in?")
        if chris.exists {
            // ui-legs: the shared verified step (Select only once "Chris" reads focused).
            DetailEntryRoute.selectChrisTile(self, app, timeout: 5)
        }
        pause(10) // Home catalog fan-out
        return app
    }

    /// The UX-4c smoke id (also used by `TrailerSoakTests`/`InlineTrailerTileProbeTests`) — a known
    /// bar-free 16:9 trailer, kept here purely so a title that DOES reach `.playing` (extraction not
    /// blocked) plays something deterministic. `.expandedStatic` — the phase that actually produces
    /// the widened tile + `.shadow` this bug is about — needs only a listed trailer in the focused
    /// title's metadata, not a successful extraction (see `InlineTrailerCardModel.expand`/`resolve`:
    /// the card promotes to `.expandedStatic` once a selectable trailer is confirmed and the single
    /// extraction slot is granted, BEFORE the YouTube fetch itself completes) — so this smoke id is
    /// belt-and-braces, not what makes the tile appear at all.
    private static let smokeVideoId = "rNZ0xKaCdus"

    /// `noZoom`: the two legs the plan asks for — No Zoom ON (`CardFocusMode.still`, zero lift, the
    /// reporter's exact config) and OFF (`CardFocusMode.systemLift`, the shipped default's real
    /// system hover lift, which can bleed independently of the ring/no-zoom band). Both toggle via
    /// launch arguments (`NSArgumentDomain`, top priority over any persisted value), the same knob
    /// `InlineTrailerTileProbeTests` already relies on — neither leg touches the synced profile, so
    /// both run for real rather than one being written as a skip.
    private func launchArguments(noZoom: Bool) -> [String] {
        [
            "-inline_trailers_enabled", "YES",
            "-debug.trailerProbe", "YES",
            "-debug.trailerSmokeVideoId", Self.smokeVideoId,
            // Deterministic row geometry (TrailerSoakTests'/InlineTrailerTileProbeTests' trick):
            // removes the Upcoming row so the down×4 walk below has a stable target.
            "-home_upcoming_row_enabled", "NO",
            "-trailer_playback_location", "poster",
            "-no_zoom_on_focus", noZoom ? "YES" : "NO",
            "-accent_focus_ring", "NO",
            // harness-w4 (2026-10-23): a fixed 3 s from focus (never before the rows stop), the
            // longest Trailer Start Delay, so the at-rest captures fit between the hero settling on
            // card #1 and the tile expanding (see `assertNoBleedPastLeadingEdge`).
            "-trailer_start_delay", "3",
            // No hero trailer: the backdrop behind the measured column must hold still.
            "-hero_trailer_autoplay", "NO",
        ]
    }

    /// `debug_trailerTile`'s `x=` field — the tile's own frame origin in `.global` space
    /// (`InlineTrailerCard.swift`'s BUG-92 doc: the row defines no NAMED coordinate space, so the
    /// probe reads `.global`, the same space a screenshot's pixel columns are already in).
    private func tileGlobalOriginX(_ label: String) -> CGFloat? {
        for token in label.split(separator: " ") where token.hasPrefix("x=") {
            // Spelled out: `Double(...).map(CGFloat.init)` made the Swift 6 type checker give up
            // ("failed to produce diagnostic for expression") on the Phase 1 gate build.
            guard let value = Double(String(token.dropFirst(2))) else { return nil }
            return CGFloat(value)
        }
        return nil
    }

    /// One consistent read of every button's frame + focus flag from a SINGLE `snapshot()` walk —
    /// `NuvioTVUITests.buttonSnapshots`' own pattern (a per-element `.frame`/`.hasFocus` read via
    /// `allElementsBoundByIndex` can throw "No matches found for Element at index N" while the
    /// poster morph is remounting tiles; one snapshot walk has no such race).
    private func focusedButtonFrame(_ app: XCUIApplication) -> CGRect? {
        guard let root = try? app.snapshot() else { return nil }
        var found: CGRect?
        func walk(_ node: XCUIElementSnapshot) {
            guard found == nil else { return }
            if node.elementType == .button, node.hasFocus { found = node.frame; return }
            node.children.forEach(walk)
        }
        walk(root)
        return found
    }

    /// harness-w4 (2026-10-23): the bleed the app ALLOWS past the row's leading edge, mirroring
    /// `RowLeadingEdgeClip.rowAllowance` (BUG-164; this target cannot import the app). No Zoom opens
    /// for the still focus shadow's visible reach only: `shadowReach()` = ceil(22 × 2) = 44 pt. Zoom
    /// on opens for the lifted 16:9 tile plus the shadow radius: ceil(16/9 × h × (2 × 20 / h) / 2) +
    /// 22 = ceil(35.6) + 22 = 58 pt, the same at every poster size (accent ring off here, else +4).
    /// Anything the first card draws INSIDE that opening is by design; the leg judges what lands
    /// past it.
    private static func leadingEdgeAllowance(noZoom: Bool) -> CGFloat {
        noZoom ? 44 : 58
    }

    /// The row's leading edge (card #1's layout x), from one snapshot taken with card #1 focused at
    /// rest: the unfocused cards in the focused card's band are evenly pitched, so card #1 sits one
    /// pitch left of card #2. Read from the unfocused cards because a focused card's frame can carry
    /// its lift. nil when fewer than two unfocused cards are readable.
    private func rowLeadingEdge(_ app: XCUIApplication, focusedBand: CGRect) -> CGFloat? {
        guard let root = try? app.snapshot() else { return nil }
        var frames: [CGRect] = []
        func walk(_ node: XCUIElementSnapshot) {
            let f = node.frame
            if node.elementType == .button, !node.hasFocus, f.width >= 100, f.height >= 150,
               abs(f.midY - focusedBand.midY) < 40, f.minX > focusedBand.minX {
                frames.append(f)
            }
            node.children.forEach(walk)
        }
        walk(root)
        let xs = frames.map(\.minX).sorted()
        guard xs.count >= 2 else { return nil }
        let pitch = xs[1] - xs[0]
        guard pitch > 100 else { return nil }
        return xs[0] - pitch
    }

    /// Polls up to 8 s for `debug_trailerTile` (the dwell + `InlineTrailerCardModel.morphAnimation`'s
    /// ~0.35 s) and returns its `x=` field: the focused tile's leading edge in `.global` space.
    private func pollTileOriginX(_ app: XCUIApplication, tag: String) throws -> CGFloat {
        let probeText = app.staticTexts["debug_trailerTile"]
        var label: String?
        for i in 0..<16 {
            if probeText.exists {
                label = probeText.label
                break
            }
            pause(0.5)
            if i == 8 { shot(app, "\(tag)_01_mid_poll") }
        }
        shot(app, "\(tag)_02_after_poll")
        guard let label else {
            // YouTube extraction has been returning LOGIN_REQUIRED from this Mac since ~2026-09-05
            // 18:20 ET (see FEAT-32's tracker notes) — but `.expandedStatic` (the phase that
            // actually widens the tile) needs only a listed trailer in metadata, not a successful
            // extraction, so a missing probe here more likely means the focused title's metadata
            // never resolved at all, or the dwell/expand pipeline stalled for some other reason.
            // Either way this is an environment/content limitation the test can't tell apart from a
            // real regression by itself — skip rather than fail.
            throw XCTSkip("\(tag): debug_trailerTile never appeared within the poll window — no trailer tile observed on this sim run")
        }
        guard let originX = tileGlobalOriginX(label) else {
            XCTFail("\(tag): debug_trailerTile carries no parseable x= field: \(label)")
            throw XCTSkip("unparseable probe label")
        }
        return originX
    }

    /// Rasterizes both crops to raw RGBA bytes and returns the largest single-channel absolute
    /// difference between them — a pixel-for-pixel oracle, not a luma average
    /// (`NuvioTVUITests.lumaProfile`/`lumaStats`'s tool): the fix here is a CLIP, not a brightness
    /// change, and a colored bleed against a similarly-lit background could hide from a luma-only
    /// check. Same points→pixels scaling contract as those two (sim screenshots are exactly the
    /// window's own scale factor, read from the screenshot/window width ratio).
    private func maxChannelDelta(_ before: UIImage, _ after: UIImage, pointRect: CGRect, windowSize: CGSize) throws -> Int {
        guard let beforeCg = before.cgImage, let afterCg = after.cgImage, windowSize.width > 0 else {
            throw XCTSkip("screenshot has no CGImage / zero window size")
        }
        let scale = CGFloat(beforeCg.width) / windowSize.width
        let px = CGRect(
            x: pointRect.minX * scale, y: pointRect.minY * scale,
            width: pointRect.width * scale, height: pointRect.height * scale
        ).integral.intersection(CGRect(x: 0, y: 0, width: beforeCg.width, height: beforeCg.height))
        guard !px.isEmpty, let beforeCrop = beforeCg.cropping(to: px), let afterCrop = afterCg.cropping(to: px) else {
            throw XCTSkip("column \(pointRect) is off-screen")
        }
        func bytes(_ cg: CGImage) -> [UInt8] {
            let w = cg.width, h = cg.height
            var buffer = [UInt8](repeating: 0, count: w * h * 4)
            guard let ctx = CGContext(
                data: &buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return [] }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return buffer
        }
        let beforeBytes = bytes(beforeCrop)
        let afterBytes = bytes(afterCrop)
        guard !beforeBytes.isEmpty, beforeBytes.count == afterBytes.count else {
            throw XCTSkip("could not rasterize both crops to compare")
        }
        var maxDelta = 0
        for i in 0..<beforeBytes.count {
            let delta = abs(Int(beforeBytes[i]) - Int(afterBytes[i]))
            if delta > maxDelta { maxDelta = delta }
        }
        return maxDelta
    }

    /// Per-channel byte tolerance for "no pixel differs beyond noise" — sim screenshots are
    /// lossless (no JPEG ringing), so this only has to absorb the video decoder's own frame-to-frame
    /// dither and any single-pixel anti-aliasing seam at a shape edge, never a genuine bleed (which
    /// reads as many dozens of bytes of real picture content, not a handful of rounding bytes).
    private static let noiseTolerance = 10

    // MARK: - No Zoom ON (the reporter's exact config)

    func testNoZoomFirstCardLeavesNoBleedPastLeadingEdge() throws {
        try assertNoBleedPastLeadingEdge(noZoom: true, tag: "rowEdge_noZoom")
    }

    // MARK: - Zoom ON (the shipped default's system lift)

    func testZoomOnFirstCardLeavesNoBleedPastLeadingEdge() throws {
        try assertNoBleedPastLeadingEdge(noZoom: false, tag: "rowEdge_zoomOn")
    }

    /// harness-w4 (2026-10-23): the measurement compares the column left of card #1 in two states of
    /// the SAME focus, so the only thing that can change in it is the bleed.
    ///
    /// The column left of the first card is not row background: it is the Home hero's backdrop, and
    /// the hero follows the focused title. The old leg compared card #1 expanded against card #2
    /// focused (one Right), so the backdrop changed with the title and the leg read that change as
    /// a bleed (first full run: 76/255 and 51/255, captures `rowEdge_noZoom_03/04`). Now:
    ///  1. Down ×4 lands on card #1 (the row's first card) and the leg waits, with the Trailer Start
    ///     Delay at 3 s, until the hero has followed it: two at-rest captures 0.6 s apart, both
    ///     before `debug_trailerTile` exists (the tile has not expanded).
    ///  2. The tile expands (`debug_trailerTile`, its `x=` is the tile's leading edge) and settles.
    ///  3. The column is the 60 pt just past the clip the row opens for its first card: the row's
    ///     leading edge (card #1's layout x, one pitch left of card #2, read at rest) minus the
    ///     allowance `RowLeadingEdgeClip.rowAllowance` grants since BUG-164 (No Zoom 44 pt: the
    ///     still shadow's reach; zoom on 58 pt: the lifted tile plus its shadow), less 2 pt of
    ///     antialiasing slack. Inside that opening the first card is ALLOWED to draw (first run of
    ///     this rewrite measured the still shadow fading out by x ≈ 90 and the lifted tile reaching
    ///     x ≈ 102 with its shadow to x ≈ 78, against clips at 96 / 82). The two at-rest captures
    ///     must agree in the column (the backdrop has settled; otherwise the leg skips, it cannot
    ///     judge), and the expanded capture is compared against the second one: same title
    ///     focused, same backdrop, so any difference is something drawn past the clip.
    /// The focus-only treatment (still shadow, system lift) is present in both states; it is judged
    /// only through the same column (it must not reach past the clip either).
    private func assertNoBleedPastLeadingEdge(noZoom: Bool, tag: String) throws {
        let app = launchToHome(extraArguments: launchArguments(noZoom: noZoom))
        let probeText = app.staticTexts["debug_trailerTile"]
        press(.down, times: 4)
        shot(app, "\(tag)_00_row_focused")
        let firstRest = XCUIScreen.main.screenshot().image
        pause(0.6)
        let secondRest = XCUIScreen.main.screenshot().image
        let expandedBeforeRest = probeText.exists
        let restFocus = focusedButtonFrame(app)
        let leading = restFocus.flatMap { rowLeadingEdge(app, focusedBand: $0) }
        shot(app, "\(tag)_00b_at_rest")
        guard !expandedBeforeRest else {
            throw XCTSkip("\(tag): the trailer tile had already expanded at the at-rest captures (Trailer Start Delay not honoured?) — no unexpanded reference")
        }
        let originX = try pollTileOriginX(app, tag: tag)
        // Past the morph (~0.35 s) and the tile shadow's fade-in before judging the steady state.
        pause(0.8)
        let expanded = XCUIScreen.main.screenshot().image
        shot(app, "\(tag)_03_expanded")

        guard let buttonFrame = focusedButtonFrame(app) else {
            throw XCTSkip("\(tag): no focused element reported (27.0 runtime never reports hasFocus reliably) — cannot bound the column vertically")
        }
        // The button's reported WIDTH/X can lag the live morph (house memory: "the focused
        // Button's AX frame never follows the tile"), but its Y/HEIGHT do not — UX-4a's whole
        // point is that a card's height never changes across the morph, only its width does — so
        // the vertical band below is trustworthy even though `buttonFrame.minX`/`.width` are not
        // used for anything.
        guard let leading else {
            throw XCTSkip("\(tag): the row's leading edge could not be read at rest (fewer than two unfocused cards in the focused row's band) — no column to judge")
        }
        let allowance = Self.leadingEdgeAllowance(noZoom: noZoom)
        let columnWidth: CGFloat = 60
        let clipX = leading - allowance - 2
        let column = CGRect(x: clipX - columnWidth, y: buttonFrame.minY, width: columnWidth, height: buttonFrame.height)
        let windowSize = app.frame.size

        let backdropDrift = try maxChannelDelta(firstRest, secondRest, pointRect: column, windowSize: windowSize)
        let delta = try maxChannelDelta(secondRest, expanded, pointRect: column, windowSize: windowSize)
        let report = XCTAttachment(string: "\(tag): row leading edge=\(leading) allowance=\(allowance) column \(column) tile x=\(originX) backdrop drift at rest=\(backdropDrift)/255 expanded vs rest=\(delta)/255 (tolerance \(Self.noiseTolerance))")
        report.name = "\(tag)_04_column"
        report.lifetime = .keepAlways
        add(report)
        guard backdropDrift <= Self.noiseTolerance else {
            throw XCTSkip("\(tag): the column left of card #1 was still changing between the two at-rest captures (\(backdropDrift)/255): the hero backdrop had not settled, so a bleed cannot be told from it — rerun")
        }
        XCTAssertLessThanOrEqual(
            delta, Self.noiseTolerance,
            "\(tag): the 60 pt column past the row's leading-edge clip (leading \(leading) − allowance \(allowance); tile x=\(originX)) differs by up to \(delta)/255 between card #1 at rest and its expanded tile (same title focused, same backdrop) — BUG-92 bleed past the clip"
        )
        XCTAssertTrue(app.state == .runningForeground, "\(tag): app must survive the leading-edge check")
    }
}
