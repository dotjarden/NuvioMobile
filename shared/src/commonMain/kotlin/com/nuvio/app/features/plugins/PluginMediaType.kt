package com.nuvio.app.features.plugins

/**
 * Restores the declared episodic type for a JS plugin after [normalizePluginType] has mapped
 * `series` to `tv` (upstream NuvioTV 8b60bdfe1). A plugin that declares `series` and receives
 * an episode request gets `series`; legacy `tv`-only plugins keep `tv`.
 */
internal fun jsPluginMediaType(
    mediaType: String,
    supportedTypes: List<String>,
    season: Int?,
    episode: Int?,
): String = if (
    mediaType.equals("tv", ignoreCase = true) && season != null && episode != null &&
    supportedTypes.any { it.equals("series", ignoreCase = true) }
) {
    "series"
} else {
    mediaType
}
