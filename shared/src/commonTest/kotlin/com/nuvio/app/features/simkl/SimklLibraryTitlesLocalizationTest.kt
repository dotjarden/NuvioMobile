package com.nuvio.app.features.simkl

import com.nuvio.app.core.i18n.LocalizedStrings
import com.nuvio.app.core.i18n.StringKey
import com.nuvio.app.core.i18n.StringProvider
import com.nuvio.app.features.mdblist.MdbListLibrarySnapshot
import com.nuvio.app.features.tracking.TrackingLibraryTabKind
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlin.test.Test
import kotlin.test.assertEquals

class SimklLibraryTitlesLocalizationTest {
    private val french = StringProvider { key, _ ->
        when (key) {
            StringKey.library_status_watching -> "En cours"
            StringKey.library_status_plan_to_watch -> "À regarder"
            StringKey.library_status_on_hold -> "En pause"
            StringKey.library_status_completed -> "Terminé"
            StringKey.library_status_dropped -> "Abandonné"
            StringKey.trakt_watchlist -> "Liste de suivi"
            else -> null
        }
    }

    private fun entry(status: SimklListStatus, id: Long) = SimklLibraryEntry(
        mediaType = SimklMediaType.SHOWS,
        status = status,
        show = SimklMedia(
            title = "Title $id",
            poster = "12/poster",
            year = 2020,
            ids = buildJsonObject {
                put("simkl", id)
                put("imdb", "tt$id")
            },
        ),
    )

    private fun projectedTitles(): Map<String, String> {
        val entries = simklLibraryStatusDefinitions.mapIndexed { index, definition ->
            entry(definition.status, 1000L + index)
        }
        return SimklSyncSnapshot(entries = entries)
            .toSimklLibraryProjection()
            .sections
            .associate { section -> section.type to section.displayTitle }
    }

    private inline fun withProvider(provider: StringProvider?, block: () -> Unit) {
        val previous = LocalizedStrings.provider
        LocalizedStrings.provider = provider
        try {
            block()
        } finally {
            LocalizedStrings.provider = previous
        }
    }

    @Test
    fun `section titles come out localized when a provider is installed`() {
        withProvider(french) {
            assertEquals(
                mapOf(
                    "simkl:status:watching" to "En cours",
                    "simkl:status:plantowatch" to "À regarder",
                    "simkl:status:hold" to "En pause",
                    "simkl:status:completed" to "Terminé",
                    "simkl:status:dropped" to "Abandonné",
                ),
                projectedTitles(),
            )
        }
    }

    @Test
    fun `section titles fall back to English with no provider`() {
        withProvider(null) {
            assertEquals(
                mapOf(
                    "simkl:status:watching" to "Watching",
                    "simkl:status:plantowatch" to "Plan to Watch",
                    "simkl:status:hold" to "On Hold",
                    "simkl:status:completed" to "Completed",
                    "simkl:status:dropped" to "Dropped",
                ),
                projectedTitles(),
            )
        }
    }

    @Test
    fun `status tabs and the MDBList watchlist tab follow the provider`() {
        withProvider(french) {
            assertEquals("En cours", simklLibraryStatusDefinition("simkl:status:watching")?.title)
            val watchlist = MdbListLibrarySnapshot().tabs()
                .single { tab -> tab.kind == TrackingLibraryTabKind.WATCHLIST }
            assertEquals("Liste de suivi", watchlist.title)
        }
        withProvider(null) {
            val watchlist = MdbListLibrarySnapshot().tabs()
                .single { tab -> tab.kind == TrackingLibraryTabKind.WATCHLIST }
            assertEquals("Watchlist", watchlist.title)
        }
    }
}
