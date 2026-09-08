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

Home is unchanged. Movies and Shows now share Browse, with featured artwork and horizontal shelves. Its type, catalog, genre, and sort selectors use opaque remote-focusable selection panels. Catalog/genre filtering uses the shared paginated Discover service. A–Z and rating sorts apply to fetched pages; provider ordering remains the default. Search merges provider result rows into one deduplicated grid, keyed by content type and ID. Library adds title search and content-type filtering, preserving its existing profile-scoped sort and cloud source.

Live TV defaults to On now channel cards; the timed guide remains available through View. Categories are selected from a panel instead of a long chip row. Source setup is one opaque presentation with an inline editor, persistent field labels, adjacent action buttons, and visible validation. A source name is optional and defaults to the provider host. Source and programme presentations use solid backgrounds.

Validated on tvOS 27 simulator: type-selector round trip; source manager entry; invalid-source validation; save of a valid local provider; return to Live TV. Native screenshots reviewed for overlapping text and contrast. Device build succeeds. Home source was not modified.
