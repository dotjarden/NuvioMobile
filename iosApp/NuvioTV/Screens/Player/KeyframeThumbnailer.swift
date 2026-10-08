import CoreGraphics
import Foundation
import Libavcodec
import Libavformat
import Libavutil
import Libswscale

/// The FFmpeg surface the P3 keyframe thumbnailer relies on (critique C11): `Libswscale` imports
/// in this MPVKit build (swscale 9, FFmpeg 8.1). `sws_scale_frame` is deliberately not used in P3:
/// its colour-managed path could tone-map a second time on top of `HDRThumbnailToneMap`.
nonisolated enum ThumbFFmpegSurface {
    /// `swscale <major>.<minor>.<micro> test_transfer(pq,in)=<n>`, logged once per process.
    static let versionLine: String = {
        let v = swscale_version()
        let pq = sws_test_transfer(AVCOL_TRC_SMPTE2084, 0)
        return "swscale \(v >> 16).\((v >> 8) & 0xFF).\(v & 0xFF) test_transfer(pq,in)=\(pq)"
    }()
}
