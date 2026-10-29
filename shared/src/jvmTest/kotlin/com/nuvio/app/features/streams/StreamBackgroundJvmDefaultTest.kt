package com.nuvio.app.features.streams

import kotlin.test.Test
import kotlin.test.assertEquals

/** The non-tvOS targets keep upstream's Normal default (decision D1 is tvOS-only). */
class StreamBackgroundJvmDefaultTest {
    @Test
    fun jvmDefaultsToNormal() {
        assertEquals(StreamBackgroundMode.Normal, StreamBackgroundDefaults.platformDefault)
    }
}
