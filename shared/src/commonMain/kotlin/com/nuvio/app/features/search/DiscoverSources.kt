package com.nuvio.app.features.search

import com.nuvio.app.features.addons.AddonCatalog
import com.nuvio.app.features.addons.AddonExtraProperty
import com.nuvio.app.features.addons.ManagedAddon
import com.nuvio.app.features.addons.enabledAddons
import com.nuvio.app.features.catalog.supportsPagination

// Search & Discover batch 2026-10-06 (C5): the Discover catalog list, read-only, for the tvOS stage
// Discover page. The helpers below moved here from SearchRepository.kt unchanged (now `internal`);
// SearchRepository's own Discover feed still calls them, so both surfaces list the same catalogs
// under the same keys and share the persisted selection.

/// One Discover selection: a type, a catalog of that type, and its genre (null = all / none).
data class DiscoverSelection(
    val type: String,
    val catalogKey: String,
    val genre: String?,
)

object DiscoverSources {
    /// Every Discover-capable catalog across the enabled add-ons with a loaded manifest, in add-on
    /// then manifest order. Pure: no state, no network. tvOS recomputes it on each
    /// `AddonRepository.uiState` emission.
    fun options(addons: List<ManagedAddon>): List<DiscoverCatalogOption> =
        buildDiscoverSources(addons.enabledAddons().filter { addon -> addon.manifest != null })

    /// Distinct catalog types, in option order.
    fun types(options: List<DiscoverCatalogOption>): List<String> =
        options.map { option -> option.type }.distinct()

    /// The persisted catalog (the same `discover_catalog_key` Search's Discover uses) when it is
    /// still offered, else the first option; null when there are no options. The genre is the
    /// catalog's resolved default: the per-catalog genre memory (plan C4) plugs in here.
    fun restoreSelection(options: List<DiscoverCatalogOption>): DiscoverSelection? {
        val preferredKey = DiscoverSelectionStorage.loadCatalogKey()
        // The genre remembered for the catalog that will actually be restored.
        val restored = restoreSelection(options, preferredKey, preferredGenre = null) ?: return null
        return restoreSelection(
            options = options,
            preferredCatalogKey = preferredKey,
            preferredGenre = DiscoverSelectionStorage.loadGenre(restored.catalogKey),
        )
    }

    /// Persists the catalog key (shared with Search's Discover) and that catalog's genre
    /// (null clears it).
    fun saveSelection(catalogKey: String, genre: String?) {
        val key = catalogKey.trim()
        if (key.isEmpty()) return
        DiscoverSelectionStorage.saveCatalogKey(key)
        DiscoverSelectionStorage.saveGenre(key, genre)
    }

    /// FEAT-73 (Steven rc4): the catalog the grid-first Discover page opens on. A persisted
    /// explicit pick (`discover_catalog_key`) wins when it is still offered for [type]; otherwise
    /// [gridDefaultCatalog]'s rule over the type's options. [type] null = the first option's type.
    fun gridDefaultCatalog(options: List<DiscoverCatalogOption>, type: String?): DiscoverCatalogOption? =
        gridDefaultCatalog(options, type, DiscoverSelectionStorage.loadCatalogKey())

    /// Pure half of the grid default (FEAT-73). Among [type]'s options: the persisted pick, else
    /// the first with genres where the genre is optional (the grid opens on "All"), else the first
    /// with genres, else the first. Null when the type has no options.
    fun gridDefaultCatalog(
        options: List<DiscoverCatalogOption>,
        type: String?,
        preferredCatalogKey: String?,
    ): DiscoverCatalogOption? {
        val resolvedType = type ?: options.firstOrNull()?.type ?: return null
        val candidates = options.filter { option -> option.type == resolvedType }
        if (candidates.isEmpty()) return null
        val preferred = preferredCatalogKey?.trim()?.takeIf { it.isNotEmpty() }
        candidates.firstOrNull { option -> option.key == preferred }?.let { return it }
        return candidates.firstOrNull { option -> option.genreOptions.isNotEmpty() && !option.genreRequired }
            ?: candidates.firstOrNull { option -> option.genreOptions.isNotEmpty() }
            ?: candidates.first()
    }

    /// FEAT-73: the genre a catalog's grid opens on: the per-catalog memory (C4) when the catalog
    /// still offers it, else its default (null = "All" for an optional genre, the first genre for a
    /// required one).
    fun gridGenre(option: DiscoverCatalogOption): String? =
        option.resolveGenreSelection(DiscoverSelectionStorage.loadGenre(option.key))

    /// FEAT-73: persists a grid pick: the catalog key (shared with Search's Discover and the
    /// Browse rows) and that catalog's genre (null clears it, "All").
    fun saveGridSelection(option: DiscoverCatalogOption, genre: String?) {
        saveSelection(option.key, option.resolveGenreSelection(genre))
    }

    /// Pure half of [restoreSelection], for tests and for the C4 genre hook.
    internal fun restoreSelection(
        options: List<DiscoverCatalogOption>,
        preferredCatalogKey: String?,
        preferredGenre: String?,
    ): DiscoverSelection? {
        val catalog = resolveDiscoverCatalog(
            sources = options,
            preferredCatalogKey = preferredCatalogKey?.trim()?.takeIf { it.isNotEmpty() },
            currentCatalogKey = null,
        ) ?: return null
        return DiscoverSelection(
            type = catalog.type,
            catalogKey = catalog.key,
            genre = catalog.resolveGenreSelection(preferredGenre),
        )
    }
}

internal fun buildDiscoverSources(addons: List<ManagedAddon>): List<DiscoverCatalogOption> =
    addons.mapNotNull { addon ->
        val manifest = addon.manifest ?: return@mapNotNull null
        addon to manifest
    }.flatMap { (addon, manifest) ->
        manifest.catalogs
            .filter { catalog -> catalog.supportsDiscover() }
            .map { catalog ->
                val genreExtra = catalog.genreExtra()
                DiscoverCatalogOption(
                    key = "${manifest.id}:${catalog.type}:${catalog.id}",
                    addonName = addon.displayTitle,
                    manifestUrl = addon.manifestUrl,
                    type = catalog.type,
                    catalogId = catalog.id,
                    catalogName = catalog.name,
                    genreOptions = genreExtra?.options.orEmpty(),
                    genreRequired = genreExtra?.isRequired == true,
                    supportsPagination = catalog.supportsPagination(),
                )
            }
    }

internal fun AddonCatalog.supportsDiscover(): Boolean {
    if (extra.any { property -> property.name == "search" && property.isRequired }) {
        return false
    }

    return extra.none { property ->
        when (property.name) {
            "genre" -> property.isRequired && property.options.isEmpty()
            "skip" -> false
            "search" -> false
            else -> property.isRequired
        }
    }
}

internal fun AddonCatalog.genreExtra(): AddonExtraProperty? =
    extra.firstOrNull { property -> property.name == "genre" }

internal fun DiscoverCatalogOption.resolveGenreSelection(requestedGenre: String?): String? =
    when {
        genreOptions.isEmpty() -> null
        requestedGenre != null && genreOptions.contains(requestedGenre) -> requestedGenre
        genreRequired -> genreOptions.firstOrNull()
        else -> null
    }
