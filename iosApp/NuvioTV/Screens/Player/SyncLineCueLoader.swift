import Foundation
import SharedCore

/// Sync Line (P5 B19): loads the cues of the selected external subtitle. Never sends stream headers
/// (the mpv credential guard exists for the same reason): add-on subtitle URLs are fetched bare.
nonisolated enum SyncLineCueLoader {
    /// `source`: an http(s) URL or an absolute file path (mpv's credential-case temp copy).
    static func load(source: String?, stripSdh: Bool = false) async -> [SubtitleSyncCue]? {
        guard let source, !source.isEmpty else { return nil }
        let data: Data?
        if source.hasPrefix("http://") || source.hasPrefix("https://") {
            guard let url = URL(string: source) else { return nil }
            data = await download(url)
        } else {
            let path = source.hasPrefix("file://") ? (URL(string: source)?.path ?? source) : source
            data = FileManager.default.contents(atPath: path)
        }
        let byteCount = data?.count ?? -1
        guard let data, !data.isEmpty, let text = normalized(data, stripSdh: stripSdh) else {
            print("[SyncLine] load failed source=\(Self.describe(source)) bytes=\(byteCount)")
            return nil
        }
        let cues = parse(text, sourceUrl: source)
        print("[SyncLine] loaded source=\(Self.describe(source)) bytes=\(byteCount) chars=\(text.count) cues=\(cues.count) first=\(cues.first?.startTimeMs ?? -1)ms last=\(cues.last?.startTimeMs ?? -1)ms head=\(String(text.prefix(40)).replacingOperators())")
        return cues
    }

    /// Native: the server's cached offset-zero VTT, else a download of the rendition's URL.
    static func load(vtt: String?, fallbackURL: URL?, stripSdh: Bool = false) async -> [SubtitleSyncCue]? {
        if let vtt, !vtt.isEmpty {
            return parse(vtt, sourceUrl: "sub.vtt")
        }
        guard let fallbackURL else { return nil }
        guard let data = await download(fallbackURL), !data.isEmpty,
              let text = normalized(data, stripSdh: stripSdh) else { return nil }
        return parse(text, sourceUrl: fallbackURL.absoluteString)
    }

    /// Same decoder as the native subtitle path: UTF-16 BOM, UTF-8, Windows-1252, then Latin-1.
    static func decode(_ data: Data) -> String? {
        SubtitleVTT.decode(data)
    }

    /// The text the screen renders: decoded, converted to WebVTT and SDH-stripped exactly as the
    /// native path does, so the list never shows a line the screen does not.
    /// Host + extension only: subtitle URLs carry add-on tokens.
    static func describe(_ source: String) -> String {
        if let u = URL(string: source), let host = u.host { return "\(host)/…\(u.pathExtension.isEmpty ? "" : "." + u.pathExtension)" }
        return "file…\(source.hasSuffix(".srt") || source.hasSuffix(".vtt") || source.hasSuffix(".ass") ? String(source.suffix(4)) : "")"
    }

    private static func normalized(_ data: Data, stripSdh: Bool) -> String? {
        SubtitleVTT.webVTT(from: data, stripSdh: stripSdh) ?? decode(data)
    }

    private static func parse(_ text: String, sourceUrl: String) -> [SubtitleSyncCue] {
        PlayerSubtitleCueParser.shared.parse(text: text, sourceUrl: sourceUrl)
    }

    private static func download(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return data
    }
}

private extension String {
    /// One line, no control characters, for the console.
    func replacingOperators() -> String {
        unicodeScalars.map { $0.value < 32 ? "·" : String($0) }.joined()
    }
}
