import Foundation

/// FEAT-65 (Steven, beta.19-rc3 follow-up 2026-10-08: the app should open straight into his
/// profile): "Open Last Profile at Launch". The shared `ProfileRepository` has carried upstream's
/// `rememberLastProfileEnabled` flag (persisted in the profile payload, beside
/// `hasEverSelectedProfile` and the stored active index) all along; tvOS simply never read it.
///
/// The rule is upstream's `rememberedStartupProfile` in
/// `composeApp/src/commonMain/kotlin/com/nuvio/app/App.kt`, copied exactly: the flag is on, a
/// profile has been chosen on this install before, the stored active profile still exists, and it
/// has no PIN (a PIN profile always shows the picker, which asks for the PIN). Upstream also
/// auto-enters a lone non-PIN profile whatever the flag says (`enterProfileGate`'s `size == 1`
/// branch); that is a separate, older upstream behaviour the tvOS picker has never had, and it is
/// deliberately NOT ported here: with the flag off (the default) tvOS keeps its picker exactly as
/// before.
///
/// tvOS adds one term upstream gets from its gate state machine: the auto-enter fires at most once
/// per process (`alreadyFiredThisLaunch`). "Switch Profile" returns to the picker and must stay
/// there, and a sign-out followed by a sign-in in the same session must never jump into a profile.
/// The decision is pure so `ProfileAutoEnterTests` can pin the table; `ContentView` feeds it.
nonisolated enum ProfileAutoEnter {
    static func decision(enabled: Bool,
                         everSelected: Bool,
                         activeProfileExists: Bool,
                         pinEnabled: Bool,
                         alreadyFiredThisLaunch: Bool) -> Bool {
        enabled && everSelected && activeProfileExists && !pinEnabled && !alreadyFiredThisLaunch
    }

    /// DEBUG harness knob (`BatchARailProfileUITests`): `-debug.rememberLastProfile YES|NO`
    /// overrides the stored flag for this launch's decision only, in memory, never persisted, so a
    /// UI leg cannot leave the fixture's profile payload changed. nil when absent (or in Release).
    static func debugEnabledOverride(_ defaults: UserDefaults = .standard) -> Bool? {
        #if DEBUG
        guard defaults.object(forKey: debugKey) != nil else { return nil }
        return defaults.bool(forKey: debugKey)
        #else
        return nil
        #endif
    }

    static let debugKey = "debug.rememberLastProfile"
}
