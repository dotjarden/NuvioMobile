# Native Apple TV development build

This branch extends youngchris29-art's native tvOS port. It retains the existing Kotlin core, accounts, addons, library, debrid integrations, subtitles, and movie/episode playback.

## Added

- Native Movies and Shows catalog entry points, using the existing metadata and detail routes.
- The compact pinned Home presentation enabled by default on new installs; existing explicit preferences remain respected.
- A Live TV tab in both the system tab bar and the optional sidebar.
- M3U and Xtream source management with optional or automatically discovered XMLTV guides.
- Native SwiftUI glass controls, remote focus, channel search, categories, favorites, and recents.
- A three-hour programme grid with earlier/later navigation, plus a Now/Next channel list.
- Native AVPlayer live playback, channel switching, Go Live, retry, and MPV compatibility playback for transport streams or native playback failures.
- Profile-scoped Keychain storage for source configuration. Persisted favorite/recent identifiers are SHA-256 hashes; credential-bearing URLs never enter UserDefaults.
- Explicit live-session guards in both progress-recording implementations and MPV scrobbling/resume paths.

## Boundaries

Live TV is currently implemented in the native tvOS target. It does not add Live TV to the upstream mobile app or sync provider credentials to Nuvio Cloud. Existing addon catalogs remain accessible through the existing addon browsing paths; they are not automatically converted into XMLTV channels.

Provider credentials and streams are user supplied. M3U and Xtream are implemented; Stalker Portal, recording, catch-up, multiview, and a Live TV phone-setup extension are not implemented. Existing remote setup still supports the original addon/configuration workflows. XMLTV feeds must be plain XML (HTTP transfer compression is handled by URLSession); .xml.gz file archives are not currently unpacked.

Guide data is kept in memory, bounded to one day of history and seven days ahead. A refresh failure preserves previously loaded channels in the current session. Channels reload from the provider after relaunch; guide/channel disk caching is not implemented. Stream authorization and codec coverage depend on the provider and Apple TV hardware.

## Build

The app scheme is `NuvioTV` in `iosApp/iosApp.xcodeproj`. The code requires tvOS 26+ and was compiled using Xcode 26.6 and Xcode 27 beta. On a Mac with Xcode beta, prefix commands with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` if it is not the selected developer directory.

Initialize MPVKit with `git submodule update --init --recursive`. The outer wrapper's `scaffolding/build-quickjs-tvos.sh` builds the required local QuickJS package. Then build using Xcode, or run `scripts/build-development-ipa.sh` for an unsigned hardware build. The script does not publish a release. An unsigned IPA must be re-signed before installation. Top Shelf stays in source builds and is omitted from the sideload package.

## Checks

Parser checks:

```sh
xcrun swiftc iosApp/NuvioTV/LiveTV/LiveTVModels.swift tests/livetv/LiveTVParserChecks.swift -o /tmp/nuvio-parser-checks
/tmp/nuvio-parser-checks
```

Provider integration checks use the deterministic local server in `tests/livetv/provider_fixture.py` (port 8766), then compile and run `LiveTVProviderChecks.swift` with the models and service files. No personal account or provider is needed.

The dedicated `NuvioTVUITests` scheme contains `LiveTVExperienceTests`. It exercises the production Live TV screens with an isolated debug-only profile and local fixture. Use standard simulator signing so Keychain behavior can be tested. The test entry point is absent in Release builds and unused in normal Debug launches.

## Authentication configuration

Clean builds use the official public `https://api.nuvio.tv` endpoint and publishable client key documented in the outer repository's cloud API reference. `SUPABASE_URL` / `SUPABASE_ANON_KEY` and the equivalent `NUVIO_` variables still override defaults. A custom build endpoint without a key now fails during configuration instead of producing a broken login screen. Runtime self-hosted server selection is unchanged.

`AuthenticationConnectivityTests` is an opt-in integration test against the live official service. It creates a temporary anonymous pairing session and verifies that the native screen renders a QR code; it does not approve a pairing or authenticate a personal account. `tests/auth/AuthErrorChecks.swift` verifies readable error handling and removal of raw request diagnostics.

## September UX revision

Home is unchanged. Movies and Shows now share Browse, reusing Home's full-bleed backdrop and hero foreground above horizontal shelves. The hero area keeps a fixed height while filters load. Type, catalog, genre, and sort controls open native anchored menus. Catalog/genre filtering uses the shared paginated Discover service. A–Z and rating sorts apply to fetched pages; provider ordering remains the default. Search merges provider result rows into one deduplicated grid, keyed by content type and ID. Library adds title search and content-type filtering, preserving its existing profile-scoped sort and cloud source.

Live TV defaults to On now channel cards; the timed guide remains available through View. View and Category use anchored menus in a single toolbar alongside Refresh and Sources, with channel search underneath. Source setup is one opaque presentation with an inline editor, persistent field labels, adjacent action buttons, and visible validation. A source name is optional and defaults to the provider host. Source and programme presentations use solid backgrounds.

Settings uses an aligned category rail and detail list. Select opens a category; moving focus through categories preserves the current pane. Additional material and padding wrappers were removed from search, login, profile, source URL, API key, and numeric-filter fields so tvOS owns their input and focus appearance.

Validated on tvOS 27 simulator: anchored type-selector round trip; source manager entry; invalid-source validation; save of a valid local provider; return to Live TV; Settings category selection. Native screenshots reviewed for overlapping text and contrast. Signed device build succeeds. Home and Browse now share the same surface; Home retains its existing default content and controls.

## Live player control ownership

Removed the SwiftUI transport bar layered over AVKit and MPV. AVKit exposes the shared drawer through its native Settings menu; Playback contains previous/next channel, Go Live, favorite, and Channel guide. MPV uses the same drawer and actions. Channel guide opens the programme grid. Error recovery is a separate solid screen.

`testLivePlayerNativeMenuFocus` uses the synthetic HLS stream from `tests/livetv/run-player-fixture.sh` (ffmpeg and Python required, loopback port 8767). On tvOS 27 the test opens the native menu with Up/Select, switches channels, reopens it, and returns to the guide. This test passed with real HLS segment delivery. The movie-player tests also exercise MPV against a generated local two-audio-track, subtitled file.

## Shared Home surface and heading rules

Browse now supplies data and anchored filters to HomeView itself. It shares Home’s scrim, pinned geometry, focus dwell, CatalogRowView, end-of-row See All tile, and scroll settling. Filtered discovery uses the same horizontal catalog row and requests more pages near its end. Settings removes page-title duplication, retaining useful subgroup labels. Add-ons puts Install beside Manifest URL and removes its introductory block. See [design-rules.md](design-rules.md) for the user’s persistent hierarchy rules and the approved playback layout.

Verified on tvOS 27: Home/Browse hero-button vertical alignment, unchanged hero position after remote row navigation, trailing See All reachability, stable filter placement through type and genre changes and Reset, Settings selection without a duplicate title, and inline Add-ons field/action alignment. Signed Apple TV build passes. The shared bottom drawer is now implemented; see below.


## Pinned filters and common player drawer

Browse filters now stay outside HomeView's lazy rows, so row virtualization and scroll correction cannot remove them. The row viewport accounts for their reserved height. Opening content no longer mounts a separate poster over its wide background, and portrait posters are not used as a temporary backdrop.

AVPlayer movies, MPV movies, and Live TV share Audio / Subtitles / Playback / Details in a readable bottom drawer. Native menus finish dismissing before drawer presentation. Tabs and contents have aligned focus regions, and Back dismisses the drawer without exiting playback. Native system transport and audio enhancements remain available. Engine-specific timing, episode/source controls, and live actions are shown only where supported.

Diagnostics run only while Details is visible. MPV deduplicates state publications and coalesces requests, capped at one details sample per second. Old pause/diagnostic overlays and their timers were removed. Hardware smoothness has not been measured.

Validation for this update: tvOS 27 remote tests passed for repeated Browse scroll returns at Medium and Large poster sizes; type/genre/reset filters; pinned Home/Browse interaction and trailing See All; live channel switching and Guide; and both native and MPV movie drawers with actual audio/subtitle selection, speed changes, and Back preserving playback. Player media is synthetic and served on loopback by the fixture script. The physical-device target builds and signs successfully; hardware playback/performance validation remains outstanding.

All 14 pinned-row geometry unit tests pass, including the filter-reservation bounds. Final device build passes strict deep signature verification.

## Playback remote focus regression

Adding focusable transport buttons left MPV's progress bar without a focusable seek target, and returning first-responder status to the sibling UIKit renderer did not reliably restore directional input after the controls hid. The timeline is now one focusable, labelled accessibility control: Left/Right seek ten seconds and Select toggles playback. A SwiftUI video focus target owns remote input while controls are hidden. Down continues to prioritize next-episode/skip actions before opening Playback settings. Seek targets are clamped to the file's duration.

New remote regression tests check actual time changes, play/pause before and after dismissing Settings, seeking forward/back on the timeline, and seeking immediately after automatic control hiding without repeated seeks continuing after release. Native AVKit also passes post-drawer pause/resume and seek-position checks. These are simulator results, not physical-device verification.
