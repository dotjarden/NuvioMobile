package com.nuvio.app.features.streams

/**
 * Stream picker A, P0.1: what happens to the per-add-on filter ([StreamsUiState.selectedFilter])
 * when `StreamsRepository.load` starts a request.
 *
 * tvOS wants the chip to survive a refresh of the SAME title (the refresh chip and the stale-link
 * retry both call `reload`) and to reset on a NEW title. The request token
 * (`StreamsRepository.requestToken`: type, id, season, episode, manual flag) already identifies
 * the title, so "same token" is the whole rule; `clear()` empties the token and therefore resets
 * too. A same-token load that is not skipped as unchanged is either a forced refresh or the
 * BUG-74 remap re-entry, and both should keep the chip.
 *
 * Gated on [StreamPresentationPlatform.selectedFilterSurvivesRefresh] (tvOS sets it at bootstrap)
 * so mobile's refresh keeps resetting to "All" as upstream wrote it.
 */
object StreamFilterRetention {

    /** The filter the new request starts with, before any group has been built. */
    fun carriedFilter(previous: StreamsUiState, requestToken: String): String? {
        if (!StreamPresentationPlatform.selectedFilterSurvivesRefresh) return null
        return previous.selectedFilter?.takeIf { previous.requestToken == requestToken }
    }

    /**
     * Once the fan-out's placeholder groups exist, a carried filter that names an add-on no longer
     * in the fan-out (disabled or removed between loads) is dropped, otherwise the picker would
     * filter down to nothing with no chip to show for it.
     */
    fun validated(filter: String?, groups: List<AddonStreamGroup>): String? =
        filter?.takeIf { id -> groups.any { it.addonId == id } }
}
