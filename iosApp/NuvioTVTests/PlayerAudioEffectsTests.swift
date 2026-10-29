import XCTest
@testable import NuvioTV

final class PlayerAudioEffectsTests: XCTestCase {
    func testVolumePercent() {
        XCTAssertEqual(PlayerAudioEffects.volumePercent(boostDb: 0), 100, accuracy: 0.001)
        XCTAssertEqual(PlayerAudioEffects.volumePercent(boostDb: 6), 199.53, accuracy: 0.01)
        XCTAssertEqual(PlayerAudioEffects.volumePercent(boostDb: 10), 316.23, accuracy: 0.01)
        XCTAssertLessThanOrEqual(PlayerAudioEffects.volumePercent(boostDb: 10), Double(PlayerAudioEffects.volumeMax))
    }

    func testClampBoost() {
        XCTAssertEqual(PlayerAudioEffects.clampBoost(-2), 0)
        XCTAssertEqual(PlayerAudioEffects.clampBoost(5), 4)
        XCTAssertEqual(PlayerAudioEffects.clampBoost(12), 10)
        XCTAssertEqual(PlayerAudioEffects.clampBoost(6), 6)
    }

    func testAfOffIsEmpty() {
        XCTAssertEqual(PlayerAudioEffects.afValue(mode: .off, channels: "5.1", channelCount: 6), "")
    }

    func testAfDialogueOnPlainFiveOneUsesPan() {
        let af = PlayerAudioEffects.afValue(mode: .dialogue, channels: "5.1", channelCount: 6)
        XCTAssertTrue(af.hasPrefix("@nuvio-dialogue:lavfi=[pan=5.1|"))
        XCTAssertTrue(af.contains("c2=1.5*c2"))
    }

    func testAfDialogueOnCentreLayoutWithTooFewChannelsFallsBack() {
        let af = PlayerAudioEffects.afValue(mode: .dialogue, channels: "5.1", channelCount: 2)
        XCTAssertFalse(af.contains("pan="))
        XCTAssertTrue(af.contains("equalizer"))
    }

    func testAfDialogueOnFiveOneSideUsesPan() {
        let af = PlayerAudioEffects.afValue(mode: .dialogue, channels: "5.1(side)", channelCount: 6)
        XCTAssertTrue(af.hasPrefix("@nuvio-dialogue:lavfi=[pan=5.1(side)|"))
        XCTAssertTrue(af.contains("c2=1.5*c2"))
        XCTAssertTrue(af.contains("c0=c0|c1=c1|"))
        XCTAssertTrue(af.hasSuffix("c5=c5]"))
    }

    func testAfDialogueOnSevenOne() {
        let af = PlayerAudioEffects.afValue(mode: .dialogue, channels: "7.1", channelCount: 8)
        XCTAssertTrue(af.contains("pan=7.1|"))
        XCTAssertTrue(af.hasSuffix("c7=c7]"))
    }

    func testAfDialogueOnStereoUsesEqualizer() {
        let af = PlayerAudioEffects.afValue(mode: .dialogue, channels: "stereo", channelCount: 2)
        XCTAssertEqual(af, "@nuvio-dialogue:lavfi=[equalizer=f=2500:t=q:w=1.0:g=4]")
    }

    func testAfDialogueOnNilLayoutUsesEqualizer() {
        let af = PlayerAudioEffects.afValue(mode: .dialogue, channels: nil, channelCount: 0)
        XCTAssertTrue(af.contains("equalizer"))
        XCTAssertFalse(af.contains("pan="))
    }

    func testStoredStateDefaults() {
        let suite = "PlayerAudioEffectsTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertEqual(PlayerAudioEffects.storedState(d), PlayerAudioEffectsState(boostDb: 0, mode: .off))
        d.set(6, forKey: PlayerTuning.boostDbKey)
        d.set("dialogue", forKey: PlayerTuning.audioModeKey)
        XCTAssertEqual(PlayerAudioEffects.storedState(d), PlayerAudioEffectsState(boostDb: 6, mode: .dialogue))
    }
}
