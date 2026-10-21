import XCTest
import SharedCore
@testable import NuvioTV

/// FEAT-84 (GitHub #10 item 4): the language pickers' lists, built from the shared
/// `AvailableLanguageOptionCodes` (see `LanguageOptions`). The pure builder takes an injected
/// locale, so the English and French orders are checked without changing the host's language.
final class LanguageOptionsTests: XCTestCase {
    private let en = Locale(identifier: "en_US")
    private let fr = Locale(identifier: "fr")
    private let compareOptions: String.CompareOptions = [.caseInsensitive, .numeric, .widthInsensitive, .forcedOrdering]

    private var allLists: [(name: String, codes: [String])] {
        [
            ("audio", LanguageOptions.audioCodes),
            ("subtitle", LanguageOptions.subtitleCodes),
            ("tmdb", LanguageOptions.tmdbMetadataCodes),
            ("fallbackAudio", LanguageOptions.fallbackAudioCodes),
            ("fallbackSubtitle", LanguageOptions.fallbackSubtitleCodes),
        ]
    }

    // MARK: The shared list

    func testSharedListIs78TagsWithFourRegionalOnes() {
        let tags = LanguageOptions.sharedTags
        XCTAssertEqual(tags.count, 78)
        XCTAssertEqual(tags.filter { !$0.contains("-") }.count, 74)
        XCTAssertEqual(Set(tags.filter { $0.contains("-") }), ["zh-CN", "zh-TW", "pt-BR", "es-419"])
        XCTAssertEqual(LanguageOptions.languages.count, 78)
        XCTAssertEqual(LanguageOptions.bareLanguages.count, 74)
    }

    // MARK: Sentinels and sizes

    func testEachPickerPinsItsSentinelsFirstInOrder() {
        XCTAssertEqual(Array(LanguageOptions.audioCodes.prefix(2)), ["device", "original"])
        XCTAssertEqual(Array(LanguageOptions.subtitleCodes.prefix(2)), ["none", "device"])
        XCTAssertEqual(Array(LanguageOptions.tmdbMetadataCodes.prefix(1)), ["device"])
        XCTAssertEqual(Array(LanguageOptions.fallbackAudioCodes.prefix(2)), ["", "original"])
        XCTAssertEqual(Array(LanguageOptions.fallbackSubtitleCodes.prefix(1)), [""])
        // The sentinels are the shared constants.
        XCTAssertEqual(LanguageOptions.audioCodes[0], AudioLanguageOption.shared.DEVICE)
        XCTAssertEqual(LanguageOptions.audioCodes[1], AudioLanguageOption.shared.ORIGINAL)
        XCTAssertEqual(LanguageOptions.subtitleCodes[0], SubtitleLanguageOption.shared.NONE)
    }

    func testListSizes() {
        XCTAssertEqual(LanguageOptions.audioCodes.count, 80)
        XCTAssertEqual(LanguageOptions.subtitleCodes.count, 80)
        XCTAssertEqual(LanguageOptions.tmdbMetadataCodes.count, 75)
        XCTAssertEqual(LanguageOptions.fallbackAudioCodes.count, 80)
        XCTAssertEqual(LanguageOptions.fallbackSubtitleCodes.count, 79)
    }

    func testNoDuplicateCodes() {
        for list in allLists {
            XCTAssertEqual(Set(list.codes).count, list.codes.count, list.name)
        }
    }

    func testSentinelsAppearOnlyOnTop() {
        let sentinels: Set<String> = ["", "device", "original", "none", "default", "forced"]
        XCTAssertTrue(LanguageOptions.languages.allSatisfy { !sentinels.contains($0.code) })
    }

    // MARK: Codes are the stored form

    /// The shared setters store `normalizeLanguageCode(...)`; an option whose code is not a fixed
    /// point would never show as selected.
    func testEveryTrackOptionCodeIsAFixedPointOfNormalize() {
        let codes = Set(LanguageOptions.audioCodes + LanguageOptions.subtitleCodes
            + LanguageOptions.fallbackAudioCodes + LanguageOptions.fallbackSubtitleCodes)
        for code in codes where !code.isEmpty {
            XCTAssertEqual(PlayerLanguagePreferencesKt.normalizeLanguageCode(language: code), code, code)
        }
    }

    func testRegionalTagsAreOfferedInTheirStoredForm() {
        for code in ["pt-br", "zh-cn", "zh-tw", "es-419"] {
            XCTAssertTrue(LanguageOptions.audioCodes.contains(code), code)
            XCTAssertTrue(LanguageOptions.subtitleCodes.contains(code), code)
        }
        XCTAssertFalse(LanguageOptions.audioCodes.contains("pt-BR"))
    }

    // MARK: Labels and order

    func testEnglishOrderAfrikaansFirstZuluLast() {
        let langs = LanguageOptions.buildLanguages(tags: LanguageOptions.sharedTags, locale: en)
        XCTAssertEqual(langs.first?.code, "af")
        XCTAssertEqual(langs.first?.name, "Afrikaans")
        XCTAssertEqual(langs.last?.code, "zu")
        XCTAssertEqual(langs.last?.name, "Zulu")
        assertSorted(langs, locale: en)
    }

    func testFrenchLabelsAreCapitalisedAndFrenchCollated() {
        let langs = LanguageOptions.buildLanguages(tags: LanguageOptions.sharedTags, locale: fr)
        for option in langs {
            let first = String(option.name.prefix(1))
            XCTAssertEqual(first, first.uppercased(with: fr), "\(option.code) → \(option.name)")
        }
        XCTAssertEqual(langs.first { $0.code == "en" }?.name, "Anglais")
        assertSorted(langs, locale: fr)
        // French collation, not code-point order: "Géorgien" (ka) sorts before "Grec" (el); a raw
        // `<` puts the accented "é" after "r".
        let ka = langs.firstIndex { $0.code == "ka" }
        let el = langs.firstIndex { $0.code == "el" }
        XCTAssertNotNil(ka)
        XCTAssertNotNil(el)
        if let ka, let el { XCTAssertLessThan(ka, el, "\(langs[ka].name) vs \(langs[el].name)") }
    }

    func testEveryCodeGetsALabel() {
        for locale in [en, fr] {
            for option in LanguageOptions.buildLanguages(tags: LanguageOptions.sharedTags, locale: locale) {
                XCTAssertFalse(option.name.isEmpty, option.code)
                // A real language name, not the tag echoed back.
                XCTAssertNotEqual(option.name.lowercased(), option.code, "\(locale.identifier): \(option.code)")
            }
        }
        for list in allLists {
            for code in list.codes {
                XCTAssertNotNil(LanguageOptions.names[code], "\(list.name): \(code)")
                XCTAssertFalse(LanguageOptions.name(forCode: code).isEmpty, "\(list.name): \(code)")
            }
        }
    }

    func testChineseScriptsAreLabelledApart() {
        let langs = LanguageOptions.buildLanguages(tags: LanguageOptions.sharedTags, locale: en)
        let zh = langs.first { $0.code == "zh" }?.name
        let hans = langs.first { $0.code == "zh-cn" }?.name
        let hant = langs.first { $0.code == "zh-tw" }?.name
        XCTAssertEqual(LanguageOptions.displayName(forTag: "zh-CN", locale: en), en.localizedString(forIdentifier: "zh-Hans"))
        XCTAssertEqual(LanguageOptions.displayName(forTag: "zh-TW", locale: en), en.localizedString(forIdentifier: "zh-Hant"))
        XCTAssertEqual(Set([zh, hans, hant].compactMap { $0 }).count, 3, "\(String(describing: zh)) / \(String(describing: hans)) / \(String(describing: hant))")
        XCTAssertTrue(hans?.contains("Chinese") == true && hant?.contains("Chinese") == true)
    }

    func testSentinelAndSyncedLabels() {
        XCTAssertEqual(LanguageOptions.name(forCode: ""), String(localized: "None"))
        XCTAssertEqual(LanguageOptions.name(forCode: "none"), String(localized: "Off"))
        XCTAssertEqual(LanguageOptions.name(forCode: "device"), String(localized: "Device"))
        XCTAssertEqual(LanguageOptions.name(forCode: "original"), String(localized: "Original"))
        // Values mobile can sync that tvOS offers no row for: labelled, not shown raw.
        XCTAssertEqual(LanguageOptions.name(forCode: "default"), String(localized: "Default"))
        XCTAssertEqual(LanguageOptions.name(forCode: "forced"), String(localized: "Forced"))
    }

    func testKeepingCurrentInsertsAnUnlistedValueAfterTheSentinels() {
        let base = LanguageOptions.audioCodes
        XCTAssertEqual(LanguageOptions.codes(base, keeping: "en", pinned: 2), base)
        let withDefault = LanguageOptions.codes(base, keeping: "default", pinned: 2)
        XCTAssertEqual(withDefault.count, base.count + 1)
        XCTAssertEqual(Array(withDefault.prefix(3)), ["device", "original", "default"])
        XCTAssertEqual(LanguageOptions.codes(["a"], keeping: "b", pinned: 5), ["a", "b"])
    }

    // MARK: TMDB

    /// TMDB takes the bare codes only: the readback keeps the primary subtag
    /// (`SettingsViewModel.tmdbLanguageSelection`), so every option must round-trip through it.
    func testTmdbTakesTheBareCodesOnly() {
        let languages = Array(LanguageOptions.tmdbMetadataCodes.dropFirst())
        XCTAssertEqual(languages.sorted(), LanguageOptions.sharedTags.filter { !$0.contains("-") }.sorted())
        for code in languages {
            XCTAssertFalse(code.contains("-"), code)
            XCTAssertEqual(String(code.split(separator: "-").first ?? Substring(code)), code)
        }
    }

    // MARK: Local tables

    /// The Sources pane's Library / Watch Progress Source pickers still label through
    /// `name(forCode:in:)` with their own tables.
    func testNameForCodeInTableStillServesSourcesLabels() {
        let table: [(name: String, code: String)] = [("Nuvio Library", "local"), ("Trakt", "trakt")]
        XCTAssertEqual(LanguageOptions.name(forCode: "trakt", in: table), "Trakt")
        XCTAssertEqual(LanguageOptions.name(forCode: "local", in: table), "Nuvio Library")
        XCTAssertEqual(LanguageOptions.name(forCode: "unknown", in: table), "unknown")
    }

    // MARK: Helpers

    private func assertSorted(_ options: [(name: String, code: String)], locale: Locale, file: StaticString = #filePath, line: UInt = #line) {
        for (a, b) in zip(options, options.dropFirst()) {
            XCTAssertNotEqual(
                a.name.compare(b.name, options: compareOptions, locale: locale), .orderedDescending,
                "\(a.name) before \(b.name)", file: file, line: line
            )
        }
    }
}
