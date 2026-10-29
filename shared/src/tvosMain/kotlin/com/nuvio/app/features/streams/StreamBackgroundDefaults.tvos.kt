package com.nuvio.app.features.streams

// Decision D1 (2026-10-25): the cinematic picker is on for every tvOS profile that never set
// "Source Background"; Settings › Sources flips it back to Normal.
actual object StreamBackgroundDefaults {
    actual val platformDefault: StreamBackgroundMode = StreamBackgroundMode.Cinematic
}
