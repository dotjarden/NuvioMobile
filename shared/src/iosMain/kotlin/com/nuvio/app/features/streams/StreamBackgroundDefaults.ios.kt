package com.nuvio.app.features.streams

// First file in iosMain: the default hierarchy template already creates the source set (appleMain
// is its parent, shared with tvosMain). Upstream's phone default stays Normal.
actual object StreamBackgroundDefaults {
    actual val platformDefault: StreamBackgroundMode = StreamBackgroundMode.Normal
}
