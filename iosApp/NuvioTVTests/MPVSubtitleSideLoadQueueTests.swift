import XCTest
@testable import NuvioTV

/// The mpv queue stall (Batch E device pass 2026-10-18): 112 add-on subtitles loaded as
/// synchronous `sub-add` commands held `eventQueue` for minutes. The queue now issues them one at
/// a time, asynchronously; these pin its order, its single load in flight and its walk policy.
final class MPVSubtitleSideLoadQueueTests: XCTestCase {
    private typealias Job = MPVSubtitleSideLoadQueue.Job

    private func job(_ name: String, rank: Int? = nil) -> Job {
        Job(source: "https://subs.example/\(name).srt", title: name, lang: "x", rank: rank)
    }

    func testPreferredJobsGoAheadOfPlainOnesAndKeepArrivalOrder() {
        var q = MPVSubtitleSideLoadQueue()
        q.enqueue(job("p1"))
        q.enqueue(job("e1", rank: 0))
        q.enqueue(job("p2"))
        q.enqueue(job("e2", rank: 0))
        XCTAssertEqual(q.pending.map(\.title), ["e1", "e2", "p1", "p2"])
    }

    func testPreferredJobsSortByLanguageRank() {
        var q = MPVSubtitleSideLoadQueue()
        q.enqueue(job("fr1", rank: 1))
        q.enqueue(job("plain"))
        q.enqueue(job("en1", rank: 0))
        q.enqueue(job("fr2", rank: 1))
        q.enqueue(job("en2", rank: 0))
        XCTAssertEqual(q.pending.map(\.title), ["en1", "en2", "fr1", "fr2", "plain"])
    }

    func testPreferredPendingTracksInFlightAndQueuedJobs() {
        var q = MPVSubtitleSideLoadQueue()
        q.enqueue(job("plain"))
        XCTAssertFalse(q.hasPreferredPending)
        let plain = q.start(now: 0)!
        q.enqueue(job("en", rank: 0))
        XCTAssertTrue(q.hasPreferredPending, "queued behind a plain load already in flight")
        _ = q.finish(replyId: plain.id, now: 1)
        let en = q.start(now: 1)!
        XCTAssertEqual(en.job.title, "en")
        XCTAssertTrue(q.hasPreferredPending, "in flight")
        _ = q.finish(replyId: en.id, now: 2)
        XCTAssertFalse(q.hasPreferredPending)
    }

    func testEnqueueAfterTheQueueEmptied() {
        var q = MPVSubtitleSideLoadQueue()
        q.enqueue(job("a"))
        let a = q.start(now: 0)!
        XCTAssertEqual(q.finish(replyId: a.id, now: 1)?.walkTracks, true)
        XCTAssertFalse(q.isActive)
        q.enqueue(job("b"))
        XCTAssertTrue(q.isActive)
        let b = q.start(now: 2)!
        XCTAssertEqual(b.job.title, "b")
        XCTAssertEqual(q.finish(replyId: b.id, now: 3)?.walkTracks, true)
    }

    func testOneLoadInFlightAtATime() {
        var q = MPVSubtitleSideLoadQueue()
        q.enqueue(job("a"))
        q.enqueue(job("b"))
        let first = q.start(now: 0)
        XCTAssertEqual(first?.job.title, "a")
        XCTAssertNil(q.start(now: 0), "a second load must wait for the first reply")
        XCTAssertNotNil(q.finish(replyId: first!.id, now: 1.2))
        XCTAssertEqual(q.start(now: 1.2)?.job.title, "b")
    }

    func testReplyIdsAreTaggedAndUnique() {
        var q = MPVSubtitleSideLoadQueue()
        q.enqueue(job("a"))
        q.enqueue(job("b"))
        let a = q.start(now: 0)!
        _ = q.finish(replyId: a.id, now: 0)
        let b = q.start(now: 0)!
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertTrue(MPVSubtitleSideLoadQueue.isReply(a.id))
        XCTAssertTrue(MPVSubtitleSideLoadQueue.isReply(b.id))
        // Observation ids (1...11) and other small userdata never read as side-load replies.
        XCTAssertFalse(MPVSubtitleSideLoadQueue.isReply(7))
        XCTAssertFalse(MPVSubtitleSideLoadQueue.isReply(0))
    }

    func testStaleOrForeignReplyIsIgnored() {
        var q = MPVSubtitleSideLoadQueue()
        q.enqueue(job("a"))
        let a = q.start(now: 0)!
        XCTAssertNil(q.finish(replyId: a.id &+ 1, now: 1))
        XCTAssertNotNil(q.inFlight)
        XCTAssertNotNil(q.finish(replyId: a.id, now: 1))
        XCTAssertNil(q.finish(replyId: a.id, now: 2), "a reply is consumed once")
    }

    func testAbandonFreesTheSlot() {
        var q = MPVSubtitleSideLoadQueue()
        q.enqueue(job("a"))
        q.enqueue(job("b"))
        _ = q.start(now: 0)
        q.abandonInFlight()
        XCTAssertEqual(q.start(now: 0)?.job.title, "b")
    }

    func testWalkPolicy() {
        var q = MPVSubtitleSideLoadQueue()
        q.enqueue(job("pref", rank: 0))
        for i in 0..<12 { q.enqueue(job("plain\(i)")) }
        var walks: [Bool] = []
        while let next = q.start(now: 0) {
            walks.append(q.finish(replyId: next.id, now: 1)!.walkTracks)
        }
        // Load 1 is preferred; loads 10 and the last (13, queue empty) walk; the rest do not.
        XCTAssertEqual(walks.count, 13)
        XCTAssertEqual(walks.enumerated().filter(\.element).map { $0.offset + 1 }, [1, 10, 13])
        XCTAssertFalse(q.isActive)
    }

    func testFinishReportsDuration() {
        var q = MPVSubtitleSideLoadQueue()
        q.enqueue(job("a"))
        let a = q.start(now: 10)!
        XCTAssertEqual(q.finish(replyId: a.id, now: 11.25)?.tookSec ?? 0, 1.25, accuracy: 0.0001)
    }

    // MARK: - Auto-select gate

    private func decide(_ match: Int64?, final: Bool = false, forcedOnly: Bool = false,
                        preferredPending: Bool = false, active: Bool = false,
                        noTargets: Bool = false) -> MPVSubtitleAutoSelectGate.Decision {
        MPVSubtitleAutoSelectGate.decide(matchId: match, matchIsFinal: final, forcedOnly: forcedOnly,
                                         preferredLoadsPending: preferredPending, sideLoadActive: active,
                                         noTargets: noTargets)
    }

    func testGateSelectsAFinalMatchAtOnce() {
        XCTAssertEqual(decide(5, final: true, preferredPending: true, active: true), .select(5))
    }

    /// Review r1 P2: an embedded track in the second language must not win while the top
    /// language's add-on files are still loading.
    func testGateHoldsANonFinalMatchWhilePreferredFilesLoad() {
        XCTAssertEqual(decide(5, preferredPending: true, active: true), .wait)
        XCTAssertEqual(decide(5, preferredPending: false, active: true), .select(5),
                       "only non-preferred files left: they cannot beat the match")
    }

    func testGateWaitsForLoadsWithoutAMatch() {
        XCTAssertEqual(decide(nil, active: true), .wait)
        XCTAssertEqual(decide(nil, active: false), .done)
    }

    func testGateForcedOnlyTurnsSubtitlesOffAndKeepsWatching() {
        XCTAssertEqual(decide(nil, forcedOnly: true, active: true), .off(final: false))
        XCTAssertEqual(decide(nil, forcedOnly: true, active: false), .off(final: true))
        XCTAssertEqual(decide(7, final: true, forcedOnly: true, active: true), .select(7),
                       "a forced track arriving later is still picked")
    }

    /// BUG-171: "No subtitles" (empty plan) turns mpv's own fallback pick off on the first walk,
    /// whatever is still loading.
    func testGateNoTargetsTurnsSubtitlesOffAtOnce() {
        XCTAssertEqual(decide(nil, noTargets: true), .off(final: true))
        XCTAssertEqual(decide(nil, preferredPending: true, active: true, noTargets: true), .off(final: true),
                       "no file arriving later can match an empty target list")
        XCTAssertEqual(decide(3, final: true, active: true, noTargets: true), .off(final: true),
                       "a stray match never turns subtitles on with no target language")
    }
}
