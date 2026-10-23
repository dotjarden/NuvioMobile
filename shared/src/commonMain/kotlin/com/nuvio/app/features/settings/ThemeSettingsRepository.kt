package com.nuvio.app.features.settings

import com.nuvio.app.core.ui.AppTheme
import com.nuvio.app.core.ui.NativeTabControllerProvider
import com.nuvio.app.core.ui.nativeAccentHex
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

object ThemeSettingsRepository {
    private val _selectedTheme = MutableStateFlow(AppTheme.WHITE)
    val selectedTheme: StateFlow<AppTheme> = _selectedTheme.asStateFlow()

    private val _amoledEnabled = MutableStateFlow(false)
    val amoledEnabled: StateFlow<Boolean> = _amoledEnabled.asStateFlow()

    private val _liquidGlassNativeTabBarEnabled = MutableStateFlow(false)
    val liquidGlassNativeTabBarEnabled: StateFlow<Boolean> = _liquidGlassNativeTabBarEnabled.asStateFlow()

    private val _selectedAppLanguage = MutableStateFlow(AppLanguage.DEVICE)
    val selectedAppLanguage: StateFlow<AppLanguage> = _selectedAppLanguage.asStateFlow()

    private val _navBarStyle = MutableStateFlow(NavBarStyle.ADAPTIVE)
    val navBarStyle: StateFlow<NavBarStyle> = _navBarStyle.asStateFlow()

    private var hasLoaded = false

    // DEBUG harness seam (harness-w4, 2026-10-23). See [setDebugAmoledEnabledOverride].
    private var debugAmoledEnabledOverrideValue: Boolean? = null

    fun ensureLoaded() {
        if (hasLoaded) return
        loadFromDisk()
    }

    /**
     * Synchronous read of the current theme name for Swift callers — the generic
     * `StateFlow<AppTheme>` bridges to Swift as an untyped protocol without a usable `value`
     * member, and tvOS's `AppThemeModel` must seed its initial `@Published` name from the STORED
     * theme at init (a hard-coded seed guaranteed a whole-tree `.id()` remount seconds after
     * every cold launch for any profile whose theme differed — the beta.15 "doubled hero" report).
     * Call `ensureLoaded()` first.
     */
    fun currentThemeName(): String = _selectedTheme.value.name

    fun onProfileChanged() {
        loadFromDisk()
    }

    fun clearLocalState() {
        hasLoaded = false
        _selectedTheme.value = AppTheme.WHITE
        _amoledEnabled.value = false
        _liquidGlassNativeTabBarEnabled.value = false
        NativeTabControllerProvider.controller.publishAccentColor(AppTheme.WHITE.nativeTabAccentHex())
        NativeTabControllerProvider.controller.publishLiquidGlassEnabled(false)
        _selectedAppLanguage.value = AppLanguage.DEVICE
        _navBarStyle.value = NavBarStyle.ADAPTIVE
    }

    private fun loadFromDisk() {
        hasLoaded = true
        val stored = ThemeSettingsStoreProvider.store.loadSelectedTheme()
        val theme = if (stored != null) {
            try {
                AppTheme.valueOf(stored)
            } catch (_: IllegalArgumentException) {
                AppTheme.WHITE
            }
        } else {
            AppTheme.WHITE
        }
        _selectedTheme.value = theme
        NativeTabControllerProvider.controller.publishAccentColor(theme.nativeTabAccentHex())
        // harness-w4: the DEBUG override (in memory only) is consulted before the persisted value.
        _amoledEnabled.value = debugAmoledEnabledOverrideValue
            ?: ThemeSettingsStoreProvider.store.loadAmoledEnabled()
            ?: false
        val liquidGlassEnabled = ThemeSettingsStoreProvider.store.loadLiquidGlassNativeTabBarEnabled() ?: false
        _liquidGlassNativeTabBarEnabled.value = liquidGlassEnabled
        NativeTabControllerProvider.controller.publishLiquidGlassEnabled(liquidGlassEnabled)
        val appLanguage = AppLanguage.fromCode(ThemeSettingsStoreProvider.store.loadSelectedAppLanguage())
        ThemeSettingsStoreProvider.store.applySelectedAppLanguage(appLanguage.code)
        _selectedAppLanguage.value = appLanguage
        _navBarStyle.value = NavBarStyle.fromKey(ThemeSettingsStoreProvider.store.loadNavBarStyle())
    }

    fun setTheme(theme: AppTheme) {
        ensureLoaded()
        if (_selectedTheme.value == theme) return
        _selectedTheme.value = theme
        ThemeSettingsStoreProvider.store.saveSelectedTheme(theme.name)
        NativeTabControllerProvider.controller.publishAccentColor(theme.nativeTabAccentHex())
    }

    /**
     * DEBUG harness seam (harness-w4, 2026-10-23), the twin of
     * [com.nuvio.app.features.tmdb.TmdbSettingsRepository.setDebugEnabledOverride]: when [value] is
     * non-null it stands in for the persisted `amoled_enabled` (OLED True Black) in [amoledEnabled],
     * for this process only (it survives profile switches, which reload from storage). It is never
     * written to the [ThemeSettingsStore], and the profile-settings sync export
     * ([ThemeSettingsStore.exportToSyncPayload]) reads storage, so the account's payload keeps the
     * persisted value. Only the tvOS app's DEBUG build calls this (`AmoledDebugOverride`,
     * `-debug.amoledEnabledOverride YES|NO`); Release never does. null clears it.
     */
    fun setDebugAmoledEnabledOverride(value: Boolean?) {
        if (debugAmoledEnabledOverrideValue == value) return
        debugAmoledEnabledOverrideValue = value
        if (hasLoaded) loadFromDisk()
    }

    /** The active DEBUG override of `amoled_enabled`, or null (see [setDebugAmoledEnabledOverride]). */
    fun currentDebugAmoledEnabledOverride(): Boolean? = debugAmoledEnabledOverrideValue

    fun setAmoled(enabled: Boolean) {
        ensureLoaded()
        if (_amoledEnabled.value == enabled) return
        _amoledEnabled.value = enabled
        ThemeSettingsStoreProvider.store.saveAmoledEnabled(enabled)
    }

    fun setLiquidGlassNativeTabBar(enabled: Boolean) {
        ensureLoaded()
        if (_liquidGlassNativeTabBarEnabled.value == enabled) return
        _liquidGlassNativeTabBarEnabled.value = enabled
        ThemeSettingsStoreProvider.store.saveLiquidGlassNativeTabBarEnabled(enabled)
        NativeTabControllerProvider.controller.publishLiquidGlassEnabled(enabled)
    }

    fun setAppLanguage(language: AppLanguage) {
        ensureLoaded()
        if (_selectedAppLanguage.value == language) return
        ThemeSettingsStoreProvider.store.saveSelectedAppLanguage(language.code)
        ThemeSettingsStoreProvider.store.applySelectedAppLanguage(language.code)
        _selectedAppLanguage.value = language
    }

    fun setNavBarStyle(style: NavBarStyle) {
        ensureLoaded()
        if (_navBarStyle.value == style) return
        _navBarStyle.value = style
        ThemeSettingsStoreProvider.store.saveNavBarStyle(style.key)
    }
}

private fun AppTheme.nativeTabAccentHex(): String =
    this.nativeAccentHex
