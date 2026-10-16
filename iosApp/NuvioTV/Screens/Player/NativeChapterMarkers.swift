import AVFoundation
import AVKit

/// One chapter as libavformat reports it, already mapped onto the native playlist timeline. Plain
/// and nonisolated so the remux worker can build it; the coordinator turns the list into
/// `TransportChapter`s through `PlayerChapters.parseIndexed`.
nonisolated struct RemuxChapter: Equatable, Sendable {
    let title: String
    let sec: Double
}

/// P4 (A6-native): chapter times and the system bar's navigation markers for the native engine.
enum NativeChapterMarkers {
    /// A chapter start (`start × num / den`) on the served timeline, whose zero is the first video
    /// keyframe (`originSec = boundaryTicks[0] × video time base`), not the container start. [C-4]
    nonisolated static func seconds(start: Int64, tbNum: Int32, tbDen: Int32, originSec: Double) -> Double {
        guard tbDen != 0 else { return -.infinity }
        return Double(start) * Double(tbNum) / Double(tbDen) - originSec
    }

    /// One untitled marker group (chapters must be the first group and carry no title, per
    /// `AVPlayerItem.navigationMarkerGroups`) with one timed group per chapter, each running to the
    /// next start (the last to the duration). Empty list → `[]`.
    static func groups(_ chapters: [TransportChapter], durationSec: Double) -> [AVNavigationMarkersGroup] {
        guard !chapters.isEmpty else { return [] }
        var markers: [AVTimedMetadataGroup] = []
        for (i, chapter) in chapters.enumerated() {
            let end = i + 1 < chapters.count ? chapters[i + 1].sec : max(durationSec, chapter.sec)
            let item = AVMutableMetadataItem()
            item.identifier = .commonIdentifierTitle
            item.value = PlayerChapters.displayTitle(chapter, index: i) as NSString
            item.extendedLanguageTag = "und"
            let range = CMTimeRange(start: CMTime(seconds: chapter.sec, preferredTimescale: 1000),
                                    end: CMTime(seconds: end, preferredTimescale: 1000))
            markers.append(AVTimedMetadataGroup(items: [item], timeRange: range))
        }
        return [AVNavigationMarkersGroup(title: nil, timedNavigationMarkers: markers)]
    }
}
