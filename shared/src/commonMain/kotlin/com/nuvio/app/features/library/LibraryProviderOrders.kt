package com.nuvio.app.features.library

import com.nuvio.app.features.tracking.TrackingLibrarySorter
import com.nuvio.app.features.tracking.TrackingProviderRegistry
import com.nuvio.app.features.tracking.providerId
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onStart

internal data class LibraryProviderOrders(
    val ranks: Map<String, Map<String, Int>> = emptyMap(),
    val failed: Boolean = false,
)

/**
 * Fork (tvOS, batch D review r1 F2): one list's slice of [LibraryProviderOrders], the shape Swift
 * watches through `LibraryRepository.observeProviderOrder`. [ranks] is null while the provider
 * order is unknown: still loading, no provider order for this sort, or the sorter failed
 * ([failed]); the projection then falls back to its local sort.
 */
data class LibraryProviderOrderResult(
    val ranks: Map<String, Int>?,
    val failed: Boolean,
)

internal fun LibraryProviderOrders.forList(listKey: String): LibraryProviderOrderResult =
    LibraryProviderOrderResult(ranks = ranks[listKey], failed = failed)

internal fun LibrarySourceMode.librarySorter(): TrackingLibrarySorter? =
    providerId?.let(TrackingProviderRegistry::libraryProvider)?.listSorter

internal fun observeLibraryProviderOrders(
    sorter: TrackingLibrarySorter?,
    listKeys: List<String>,
    sortOption: LibrarySortOption,
): Flow<LibraryProviderOrders> {
    if (sorter == null || listKeys.isEmpty()) return flowOf(LibraryProviderOrders())
    val observe: (String) -> Flow<List<String>?> = when (sortOption) {
        LibrarySortOption.ADDED_DESC, LibrarySortOption.ADDED_ASC ->
            { key -> sorter.observeAddedOrder(key, sortOption == LibrarySortOption.ADDED_DESC) }
        LibrarySortOption.RELEASED_DESC, LibrarySortOption.RELEASED_ASC ->
            { key -> sorter.observeReleaseOrder(key, sortOption == LibrarySortOption.RELEASED_DESC) }
        else -> return flowOf(LibraryProviderOrders())
    }
    return combine(listKeys.distinct().map { key ->
        observe(key).map { keys ->
            key to keys?.withIndex()?.associate { (index, item) -> item to index }
        }.onStart { emit(key to null) }
    }) { orders ->
        LibraryProviderOrders(orders.mapNotNull { (key, ranks) -> ranks?.let { key to it } }.toMap())
    }.catch { emit(LibraryProviderOrders(failed = true)) }.distinctUntilChanged()
}
