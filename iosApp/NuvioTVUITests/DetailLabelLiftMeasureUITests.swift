import XCTest

/// BUG-200 (GitHub #9 item 1): measures the lift the Detail Cast avatar (140 pt circle) and the
/// studio/network chip (52 pt capsule) wear in the default cell (Accent Focus Ring off, zoom on):
/// the SYSTEM lift on the avatar (`DetailLabelLift` → `.systemLift`), and the chip's own manual
/// ×1.12 scale (`cardFocusButtonStyle(lift: .manual)` + `PlainLabelRing.smallLabelLift`).
///
/// The system `.hoverEffect(.highlight)` is render-only (AX frames never follow it), while the
/// chip's `.scaleEffect` does carry its probe's AX frame (×1.12 about the centre, sim 2026-10-21),
/// so the lift is read off screenshots, aligned on the centre of the layout boxes (which neither
/// lift moves) the DEBUG `-debug.cardGeometryProbe YES` probes
/// publish (`cast_artwork`, `company_artwork`). Same idea as test44's luma edge finder, two
/// oracles because the two labels differ:
///  - **Chip**: a white capsule on the dark page. From seeds inside the capsule's white padding the
///    walk runs outward while luma stays bright, so the measured box is the capsule's rendered
///    edge whatever the logo looks like. Focused (shot A) vs the same chip at rest after one Right
///    (shot B) gives the scale; a resting neighbour in shot A calibrates the walk against its own
///    layout box.
///  - **Avatar**: a photo, so no threshold works. Shot A has avatar 0 focused, shot B (after one
///    Right) has it at rest; the scale and vertical shift are the pair that best maps B's photo onto
///    A's (normalized cross-correlation inside the circle, coarse-to-fine search).
///
/// A measurement first: it records the numbers (attachments + `[BUG200]` log lines). Readings on
/// the tvOS 27 simulator, 2026-10-21, with both labels on `.systemLift`: avatar ×1.32 (22.6 pt per
/// side, symmetric, NCC 0.988), capsule ×1.19 (212 → 252 pt, 52 → 62 pt, symmetric). The capsule's
/// reading is over critique §2's ×1.15 ceiling (it overlaps a neighbour across the 16 pt gap), so
/// the chip moved to its own manual lift (×1.12); its leg guards the ×1.08 … ×1.13 window, a
/// symmetric rise and a clear neighbour, and the cast leg that the avatar lifts and clears its
/// neighbour. Chip reading on the manual lift (The Dark Knight, 4 chips, same day): 212 × 52 →
/// 237 × 58 pt (×1.118 / ×1.115, AX box ×1.120), rise = drop = 3.0 pt, 12.5 pt per side, 3.5 pt
/// clear of the resting neighbour; avatar re-measured ×1.3225, unchanged.
///
/// TMDB enrichment (cast links, logos) comes from `-tmdb_enabled_1 YES` in the argument domain:
/// read, never written, for the fixture's local profile.
final class DetailLabelLiftMeasureUITests: XCTestCase {

    let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    // MARK: - Helpers (trimmed file-private copies, the `DetailFocusReturnUITests` convention)

    private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

    private func press(_ button: XCUIRemote.Button, times: Int = 1, gap: TimeInterval = 0.8) {
        for _ in 0..<times {
            remote.press(button)
            pause(gap)
        }
    }

    private func attach(_ text: String, _ name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("[BUG200] \(name): \(text)")
    }

    private func attach(_ shot: XCUIScreenshot, _ name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Default cell: ring off, zoom on. Opens the title's Detail page straight from launch through
    /// the DEBUG `-debug.openDeepLink` hook (`RevampEvidenceTests`' route): no Home walk, so no
    /// Select ever lands on a Continue Watching card and starts playback on the fixture profile.
    private func launchToDetail(_ url: String) -> XCUIApplication {
        let app = XCUIApplication()
        // `-tmdb_enabled_1 YES`: TMDB enrichment (cast links, studio logos) through the argument
        // domain only — read, never written — for the fixture's local profile (index 1).
        app.launchArguments += ["-debug.openDeepLink", url, "-tmdb_enabled_1", "YES",
                                "-accent_focus_ring", "NO", "-no_zoom_on_focus", "NO",
                                "-debug.cardGeometryProbe", "YES", "-debug.detailFocusProbe", "YES",
                                "-debug.trailerProbe", "YES", "-debug.trailerForceNoTrailer", "YES"]
        app.launch()
        let chris = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chris")).firstMatch
        XCTAssertTrue(chris.waitForExistence(timeout: 90), "profile picker never appeared — is the sim session still signed in?")
        if chris.exists {
            // Default focus is the first profile; Left is a no-op there, Right would hit Add Profile.
            press(.left, times: 2, gap: 0.5)
            remote.press(.select)
        }
        pause(12)
        var waited: TimeInterval = 0
        while !app.staticTexts["Cast"].exists, waited < 14 {
            pause(1)
            waited += 1
        }
        pause(2)
        attach(XCUIScreen.main.screenshot(), "landing")
        return app
    }

    /// `debug_detail_focus` tokens.
    private func probe(_ app: XCUIApplication) -> (row: String, idx: String) {
        let label = app.staticTexts["debug_detail_focus"]
        let text = label.waitForExistence(timeout: 4) ? label.label : ""
        var tokens: [String: String] = [:]
        for part in text.split(separator: " ") {
            let kv = part.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { tokens[String(kv[0])] = String(kv[1]) }
        }
        return (tokens["row"] ?? "?", tokens["idx"] ?? "?")
    }

    /// The probe rows a failed walk passed through, for the route's attachment.
    private var walkTrail: [String] = []

    private func walkDown(to row: String, in app: XCUIApplication, maxPresses: Int = 16) -> Bool {
        walkTrail = []
        for _ in 0..<maxPresses {
            let p = probe(app)
            walkTrail.append("\(p.row)/\(p.idx)")
            if p.row == row { return true }
            press(.down)
        }
        return probe(app).row == row
    }

    /// Titles with TMDB studio logos and TMDB-linked cast (the deep links `RevampEvidenceTests` uses).
    private let titles = ["nuviotv://title?id=tt15239678&type=movie&name=Dune",
                          "nuviotv://title?id=tt0903747&type=series&name=Breaking%20Bad"]

    /// Titles for the chip leg, the most studio logos first: its neighbour check needs a second
    /// chip, and Dune (the cast leg's first title) shows one. Breaking Bad and Dune are fallbacks.
    private let chipTitles = ["nuviotv://title?id=tt0468569&type=movie&name=The%20Dark%20Knight",
                              "nuviotv://title?id=tt0903747&type=series&name=Breaking%20Bad",
                              "nuviotv://title?id=tt15239678&type=movie&name=Dune"]

    /// Distinct boxes carrying `identifier`, left to right. The probe can publish each one twice,
    /// and a focused chip's box is scaled about its centre, so boxes are told apart by centre.
    private func distinct(_ frames: [CGRect]) -> [CGRect] {
        var boxes: [CGRect] = []
        for box in frames where !boxes.contains(where: { abs($0.midX - box.midX) < 1 }) { boxes.append(box) }
        return boxes
    }

    /// Opens the chip titles until one has a focusable logo row with at least two chips; failing
    /// that, the first title that had one chip (relaunched if a later title was tried after it).
    private func openChipRow() -> XCUIApplication? {
        var single: String?
        for (index, url) in chipTitles.enumerated() {
            let app = launchToDetail(url)
            guard walkDown(to: "logos", in: app) else {
                attach("\(url) has no focusable logos row; trail=\(walkTrail)", "chip_route\(index)")
                continue
            }
            let count = distinct(namedFrames(app, "company_artwork")).count
            attach("\(url): \(count) chip(s)", "chip_route\(index)")
            if count >= 2 { return app }
            if single == nil { single = url }
            if index == chipTitles.count - 1, single == url { return app }
        }
        guard let single else { return nil }
        let app = launchToDetail(single)
        return walkDown(to: "logos", in: app) ? app : nil
    }

    /// Opens the titles' Detail pages until one has a focusable `row`.
    private func openDetail(withRow row: String) -> XCUIApplication? {
        for (index, url) in titles.enumerated() {
            let app = launchToDetail(url)
            if walkDown(to: row, in: app) { return app }
            attach(XCUIScreen.main.screenshot(), "route\(index)_\(row)")
            attach("\(url) has no focusable \(row) row; Cast heading=\(app.staticTexts["Cast"].exists) trail=\(walkTrail)", "route\(index)_\(row)")
        }
        return nil
    }

    /// Left, one press at a time, until the probe reads card 0 of `row` (never past it: Left from
    /// the first card of a row may leave the page for the navigation rail).
    private func parkOnFirstCard(of row: String, in app: XCUIApplication) -> Bool {
        for _ in 0..<12 {
            let p = probe(app)
            guard p.row == row else { return false }
            if p.idx == "0" { return true }
            press(.left, gap: 0.6)
        }
        return false
    }

    /// Every frame carrying `identifier`, left to right.
    private func namedFrames(_ app: XCUIApplication, _ identifier: String) -> [CGRect] {
        guard let root = try? app.snapshot() else { return [] }
        var out: [CGRect] = []
        func walk(_ node: XCUIElementSnapshot) {
            if node.identifier == identifier { out.append(node.frame) }
            node.children.forEach(walk)
        }
        walk(root)
        return out.sorted { $0.minX < $1.minX }
    }

    // MARK: - Pixels

    private struct LumaImage {
        let width: Int
        let height: Int
        let luma: [Double]
        /// Pixels per point.
        let scale: CGFloat

        init(_ shot: XCUIScreenshot, windowWidth: CGFloat) throws {
            guard let cg = shot.image.cgImage, windowWidth > 0 else { throw XCTSkip("screenshot has no CGImage") }
            let w = cg.width, h = cg.height
            var buffer = [UInt8](repeating: 0, count: w * h * 4)
            guard let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw XCTSkip("could not build a bitmap context") }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            var luma = [Double](repeating: 0, count: w * h)
            for i in 0..<(w * h) {
                luma[i] = (0.2126 * Double(buffer[i * 4]) + 0.7152 * Double(buffer[i * 4 + 1])
                    + 0.0722 * Double(buffer[i * 4 + 2])) / 255.0
            }
            self.width = w
            self.height = h
            self.luma = luma
            self.scale = CGFloat(w) / windowWidth
        }

        func at(_ x: Int, _ y: Int) -> Double {
            guard x >= 0, y >= 0, x < width, y < height else { return 0 }
            return luma[y * width + x]
        }

        /// Bilinear sample at pixel coordinates.
        func sample(_ x: Double, _ y: Double) -> Double {
            let x0 = Int(floor(x)), y0 = Int(floor(y))
            let fx = x - Double(x0), fy = y - Double(y0)
            let a = at(x0, y0), b = at(x0 + 1, y0), c = at(x0, y0 + 1), d = at(x0 + 1, y0 + 1)
            return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
        }
    }

    /// The bright (white capsule) box around a chip whose layout box is `frame`: walks outward from
    /// seeds inside the capsule's white padding while luma stays above `threshold`. Points.
    private func brightBox(_ image: LumaImage, frame: CGRect, threshold: Double = 0.55) -> CGRect? {
        let s = image.scale
        func px(_ v: CGFloat) -> Int { Int((v * s).rounded()) }
        let midX = px(frame.midX), midY = px(frame.midY)
        // Seeds: 4 pt inside the top/bottom padding (8 pt), 8 pt inside the side padding (16 pt).
        // A lift only grows the capsule outward, so a resting seed stays inside it; search a few
        // points toward the centre in case the lift also shifts it.
        func seed(_ x: Int, _ y: Int, dx: Int, dy: Int) -> (Int, Int)? {
            for k in 0..<Int(12 * s) {
                let sx = x + dx * k, sy = y + dy * k
                if image.at(sx, sy) > threshold { return (sx, sy) }
            }
            return nil
        }
        guard let top = seed(midX, px(frame.minY + 4), dx: 0, dy: 1),
              let bottom = seed(midX, px(frame.maxY - 4), dx: 0, dy: -1),
              let left = seed(px(frame.minX + 8), midY, dx: 1, dy: 0),
              let right = seed(px(frame.maxX - 8), midY, dx: -1, dy: 0) else { return nil }
        var y0 = top.1; while y0 > 0, image.at(top.0, y0 - 1) > threshold { y0 -= 1 }
        var y1 = bottom.1; while y1 < image.height - 1, image.at(bottom.0, y1 + 1) > threshold { y1 += 1 }
        var x0 = left.0; while x0 > 0, image.at(x0 - 1, left.1) > threshold { x0 -= 1 }
        var x1 = right.0; while x1 < image.width - 1, image.at(x1 + 1, right.1) > threshold { x1 += 1 }
        return CGRect(x: CGFloat(x0) / s, y: CGFloat(y0) / s,
                      width: CGFloat(x1 - x0 + 1) / s, height: CGFloat(y1 - y0 + 1) / s)
    }

    /// The (scale, dy) that best maps the RESTING avatar in `rest` onto the LIFTED one in `lifted`,
    /// both laid out at `frame` (points): lifted(p) ≈ rest(c + (p − c − (0, dy)) / scale). Scored by
    /// normalized cross-correlation over the inner 80 % of the lifted circle (clear of the edge and
    /// its shadow), so the highlight's brightness change does not bias it.
    private func avatarLift(lifted: LumaImage, rest: LumaImage, frame: CGRect) -> (scale: Double, dy: Double, ncc: Double) {
        let s = Double(lifted.scale)
        let cx = Double(frame.midX) * s, cy = Double(frame.midY) * s
        let r = Double(frame.width) / 2 * s
        func score(_ k: Double, _ dy: Double) -> Double {
            let radius = 0.8 * r
            let step = max(1, Int(radius / 40)) // ~5k samples
            var a: [Double] = [], b: [Double] = []
            var y = -radius
            while y <= radius {
                var x = -radius
                while x <= radius {
                    if x * x + y * y <= radius * radius {
                        let lx = cx + x, ly = cy + dy * s + y
                        a.append(lifted.sample(lx, ly))
                        b.append(rest.sample(cx + x / k, cy + y / k))
                    }
                    x += Double(step)
                }
                y += Double(step)
            }
            let n = Double(a.count)
            guard n > 10 else { return -1 }
            let ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
            var num = 0.0, da = 0.0, db = 0.0
            for i in 0..<a.count {
                let u = a[i] - ma, v = b[i] - mb
                num += u * v; da += u * u; db += v * v
            }
            return da > 0 && db > 0 ? num / (da * db).squareRoot() : -1
        }
        var best = (scale: 1.0, dy: 0.0, ncc: -2.0)
        for k in stride(from: 1.0, through: 1.5, by: 0.02) {
            for dy in stride(from: -16.0, through: 16.0, by: 2.0) {
                let v = score(k, dy)
                if v > best.ncc { best = (k, dy, v) }
            }
        }
        let coarse = best
        for k in stride(from: coarse.scale - 0.02, through: coarse.scale + 0.02, by: 0.0025) {
            for dy in stride(from: coarse.dy - 2, through: coarse.dy + 2, by: 0.5) {
                let v = score(k, dy)
                if v > best.ncc { best = (k, dy, v) }
            }
        }
        return best
    }

    // MARK: - Legs

    /// Studio/network chip, default cell: focused chip vs the same chip at rest. BUG-200: the chip
    /// draws its own ×1.12 manual lift there (no platter), so its capsule must grow inside the
    /// ×1.08 … ×1.13 window, about its own centre (rise == drop == `smallLabelRise`, 3.12 pt), and
    /// stay clear of its resting neighbour.
    func testChipManualLiftInDefaultCell() throws {
        guard let app = openChipRow() else {
            throw XCTSkip("no title on the route had a focusable studio/network logo row")
        }
        // Park on the leftmost chip so Right has somewhere to go.
        guard parkOnFirstCard(of: "logos", in: app) else {
            throw XCTSkip("could not park on the first logo chip (probe \(probe(app)))")
        }
        pause(1.5)
        let focusedIndex = Int(probe(app).idx) ?? 0
        let framesA = namedFrames(app, "company_artwork")
        let shotA = XCUIScreen.main.screenshot()
        attach(shotA, "200_chip_A_focused")
        // Off the chip: Right onto its neighbour, or Down off the row when it is the only one.
        press(.right)
        pause(1.5)
        var afterIndex = Int(probe(app).idx) ?? -1
        var movedOffRow = false
        if afterIndex == focusedIndex || probe(app).row != "logos" {
            press(.down)
            pause(2)
            movedOffRow = true
            afterIndex = -1
        }
        let framesB = namedFrames(app, "company_artwork")
        let shotB = XCUIScreen.main.screenshot()
        attach(shotB, "200_chip_B_rest")
        attach("framesA=\(framesA) framesB=\(framesB) focused=\(focusedIndex) after=\(afterIndex) movedOffRow=\(movedOffRow) probe=\(probe(app))", "200_chip_frames")
        guard focusedIndex < framesA.count, focusedIndex < framesB.count else {
            throw XCTSkip("focused chip index \(focusedIndex) has no company_artwork frame (\(framesA.count) chips)")
        }
        // Shot A's box is the FOCUSED chip's: its AX frame follows the `.scaleEffect`. Shot B's is
        // the resting layout box (read there: the page may scroll when focus leaves the row).
        let boxesA = distinct(framesA)
        let boxesB = distinct(framesB)
        guard focusedIndex < boxesA.count, focusedIndex < boxesB.count else {
            throw XCTSkip("focused chip index \(focusedIndex) has no distinct company_artwork box (\(boxesA.count) / \(boxesB.count))")
        }
        let frame = boxesA[focusedIndex]
        let frameB = boxesB[focusedIndex]
        let imageA = try LumaImage(shotA, windowWidth: app.frame.width)
        let imageB = try LumaImage(shotB, windowWidth: app.frame.width)
        guard let liftedRaw = brightBox(imageA, frame: frame), let restRaw = brightBox(imageB, frame: frameB) else {
            throw XCTSkip("the chip's white capsule was not found around \(frame) / \(frameB)")
        }
        // Both boxes in shot A's coordinates: shot B shifted by the scroll, measured on the box
        // CENTRES, which neither a centre scale nor the system lift moves.
        let lifted = liftedRaw
        let rest = restRaw.offsetBy(dx: frame.midX - frameB.midX, dy: frame.midY - frameB.midY)
        let restLayout = frameB.offsetBy(dx: frame.midX - frameB.midX, dy: frame.midY - frameB.midY)
        // The model's own reading: the AX box's growth (1 where AX ignores the lift).
        let axScale = frameB.width > 0 ? frame.width / frameB.width : 0
        // The resting neighbour to the right, in shot A.
        let neighbourBox = boxesA.first(where: { $0.minX > restLayout.maxX - 1 })
        let neighbourRest = neighbourBox.flatMap { brightBox(imageA, frame: $0) }
        let scaleW = lifted.width / rest.width
        let scaleH = lifted.height / rest.height
        let rise = rest.minY - lifted.minY
        let drop = lifted.maxY - rest.maxY
        let growLeft = rest.minX - lifted.minX
        let growRight = lifted.maxX - rest.maxX
        let clearance = neighbourRest.map { $0.minX - lifted.maxX }
        let neighbourText = "layout=\(neighbourBox.map(String.init(describing:)) ?? "none") measured=\(neighbourRest.map(String.init(describing:)) ?? "none")"
        let clearanceText = clearance.map { String(format: "%.2fpt", $0) } ?? "n/a"
        attach(String(format: "layout=%@ axFocused=%@ axScale=%.4f restMeasured=%@ liftedMeasured=%@ scaleW=%.4f scaleH=%.4f rise=%.2fpt drop=%.2fpt growLeft=%.2fpt growRight=%.2fpt chips=%ld neighbour(%@) clearance=%@",
                      "\(restLayout)", "\(frame)", axScale, "\(rest)", "\(lifted)", scaleW, scaleH, rise, drop,
                      growLeft, growRight, boxesA.count, neighbourText, clearanceText), "200_chip_lift")
        XCTAssertEqual(rest.height, restLayout.height, accuracy: 3, "the resting capsule should measure its own 52 pt layout height")
        XCTAssertEqual(rest.width, restLayout.width, accuracy: 3, "the resting capsule should measure its own layout width")
        // ×1.12 by construction (`smallLabelScaleCeiling`); the window allows for the edge walk's
        // antialiasing at the capsule's ends (±1 px on a 52 pt height is ±0.01).
        for (axis, scale) in [("width", scaleW), ("height", scaleH)] {
            XCTAssertLessThanOrEqual(scale, 1.13, "the studio chip's \(axis) lifts past ×1.13 in the default cell")
            XCTAssertGreaterThanOrEqual(scale, 1.08, "the studio chip's \(axis) lifts under ×1.08 in the default cell — the lift is missing or partial")
        }
        // About its own centre: the top rises as far as the bottom drops (≈ 3.12 pt), and nothing
        // shifts the capsule vertically beyond that rise.
        XCTAssertEqual(rise, drop, accuracy: 1.5, "the focused chip shifted vertically (rise \(rise) pt, drop \(drop) pt)")
        XCTAssertLessThanOrEqual(rise, 3.12 + 1.5, "the focused chip rose past its 3.12 pt small-label rise")
        XCTAssertEqual(growLeft, growRight, accuracy: 1.5, "the focused chip grew lopsided (left \(growLeft) pt, right \(growRight) pt)")
        if let clearance {
            XCTAssertGreaterThan(clearance, 0, "the lifted chip reaches its resting neighbour")
        }
    }

    /// Cast avatar, default cell: avatar 0 focused vs at rest, photo-matched.
    func testCastAvatarSystemLiftInDefaultCell() throws {
        guard let app = openDetail(withRow: "cast") else {
            throw XCTSkip("no title on the route had a tappable cast row")
        }
        guard parkOnFirstCard(of: "cast", in: app) else {
            throw XCTSkip("could not park on cast card 0 (probe \(probe(app)))")
        }
        pause(1.5)
        let first = probe(app)
        let framesA = namedFrames(app, "cast_artwork")
        let shotA = XCUIScreen.main.screenshot()
        attach(shotA, "200_cast_A_focused")
        press(.right)
        pause(1.5)
        let second = probe(app)
        let framesB = namedFrames(app, "cast_artwork")
        let shotB = XCUIScreen.main.screenshot()
        attach(shotB, "200_cast_B_rest")
        attach("framesA=\(framesA.prefix(4)) framesB=\(framesB.prefix(4)) idx \(first.idx)→\(second.idx)", "200_cast_frames")
        guard second.idx == "1", let frame = framesA.first, let frameB = framesB.first else {
            throw XCTSkip("focus did not move from cast 0 to cast 1, or no cast_artwork frame")
        }
        XCTAssertEqual(frame.minX, frameB.minX, accuracy: 1, "the cast row scrolled between the shots")
        XCTAssertEqual(frame.width, 140, accuracy: 1, "cast_artwork should be the 140 pt avatar")
        let imageA = try LumaImage(shotA, windowWidth: app.frame.width)
        let imageB = try LumaImage(shotB, windowWidth: app.frame.width)
        let fit = avatarLift(lifted: imageA, rest: imageB, frame: frame)
        // Control: the same match of B onto itself must find scale 1, dy 0.
        let control = avatarLift(lifted: imageB, rest: imageB, frame: frame)
        let radius = Double(frame.width) / 2
        let rise = radius * (fit.scale - 1) - fit.dy
        let bottomDrop = radius * (fit.scale - 1) + fit.dy
        attach(String(format: "layout=%@ scale=%.4f dy=%.2fpt ncc=%.4f rise=%.2fpt bottomDrop=%.2fpt growthPerSide=%.2fpt control(scale=%.4f dy=%.2f ncc=%.4f)",
                      "\(frame)", fit.scale, fit.dy, fit.ncc, rise, bottomDrop, radius * (fit.scale - 1),
                      control.scale, control.dy, control.ncc), "200_cast_lift")
        XCTAssertEqual(control.scale, 1, accuracy: 0.003, "the matcher's self-control drifted")
        XCTAssertGreaterThan(fit.ncc, 0.8, "the focused and resting photos did not match — the reading is noise")
        XCTAssertGreaterThan(fit.scale, 1.005, "the focused avatar did not lift at all in the default cell")
        // Distinct layout boxes (the probe can publish each one twice), left to right.
        var boxes: [CGRect] = []
        for box in framesA where !boxes.contains(where: { abs($0.minX - box.minX) < 1 }) { boxes.append(box) }
        if boxes.count > 1 {
            let gap = boxes[1].minX - boxes[0].maxX
            XCTAssertLessThan(radius * (fit.scale - 1), gap, "the lifted avatar reaches its neighbour (gap \(gap) pt)")
        }
    }
}
