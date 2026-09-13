# Native TV design decisions

Recorded from Jordan’s review, September 8, 2026. Apply these rules to subsequent UI work.

- The sidebar or tab bar identifies the current page. Do not repeat the page name as a large title, another section header, and an explanatory subtitle. Settings should not say Playback twice above playback controls.
- Keep short section names where they distinguish content, such as Subtitles, Audio language, or Installed. Keep field labels, validation, and explanations that help the user make a meaningful choice. Remove generic introductions and descriptions that merely restate the page’s purpose.
- Browse must use Home’s actual presentation and interaction implementation. Share the background/scrim, pinned header, row viewport, remote focus, poster buttons, and end-of-row See All tile. Filters are the additional control row, with anchored native menus.
- The hero stays above the scrolling rows. Do not approximate it with a second full-page ScrollView, a different gradient, or an arbitrary hero frame.
- Inputs use native tvOS input and focus styling without extra glass containers. Put related submit actions beside their input; Add-ons Install belongs beside Manifest URL.
- Liquid Glass is appropriate for navigation and controls. Readability and reachable remote focus take precedence over translucency.

## Playback — approved and implemented

Retain AVPlayer and MPV because their format capabilities differ. Both movie players and Live TV use the same readable, fixed-size bottom Settings panel: Audio, Subtitles, Playback, Details. Select changes a tab; moving focus alone does not rebuild it. Back closes the drawer before exiting playback. Both engines use PlayerChrome; AVPlayer renders through AVPlayerLayer and MPV through its Metal layer. Neither renderer owns a separate transport interface. System-only sound enhancements are not advertised as app controls.

Playback offers supported speed, timing, episode and source controls. Live TV puts Previous/Next channel, Go Live, Favorite and Guide there. Stream information is available in Details, without separate pause or diagnostics overlays. MPV publishes changed values only, coalesces diagnostic requests and samples details at most once per second while visible. Native and live diagnostics also stop when Details is closed. These changes reduce unnecessary work; Apple TV hardware profiling is still required to quantify performance.

## Browse and detail follow-up

The filter row belongs outside the catalog's lazy scrolling container, directly beneath the pinned hero. It must remain visible and reachable after scrolling down and returning, including with large posters. Its width and leading alignment must participate in the remote focus section.

Detail pages use a wide backdrop without a separate poster layer or portrait-poster fallback. Keep poster artwork for cards and playback metadata.

Jordan asked whether Home and Browse should merge. Recommended direction: one Home entry with All / Movies / Shows; All retains personal rows such as Continue Watching and collections. This navigation change remains a discussion decision; the current fix preserves both entries.

## Player appearance reference

Jordan's manual playback review prefers the clean native AVKit transport and rejects the boxy MPV transport. The shared Settings drawer alone did not unify the transport appearance. Use one actual controls view, with native-style layout and remote behavior, across every engine; preserve per-stream engine selection for compatibility. MPV uses circular Settings, Subtitles and Audio actions above a timeline with time labels underneath, over a full-width bottom fade. Both movie engines receive the content title and episode information. Settings content sits over a full-width bottom fade, without a rectangular wrapper. Glass belongs to the compact buttons and tabs; the panel keeps its dimensions across tabs and long lists scroll. Up enters the action row; Down returns to the timeline and retains contextual skip/next actions when available. Back hides MPV transport before exiting playback. Preserve every supported playback function when changing appearance or interaction.

Playback validation must include the real Continue Watching → stream picker → player presentation. A direct-root fixture alone cannot verify that native menus hand off correctly to the shared Settings panel through nested full-screen covers. Keep coverage for repeated opening/closing, remote play/pause and seeking, and direct audio/subtitle access.

Pause follows native AVKit: reveal the title, available content information and timeline, and retain them while paused unless the user explicitly hides controls. Detailed stream statistics remain behind Details. The action row contains Settings, Subtitles and Audio; do not add a second Play/Pause button beside the timeline's status indicator. Select on the timeline and the remote Play/Pause key preserve playback control. Drive visibility from playback state as well as input callbacks so engine-originated pauses reveal the same UI.

## Single player interface — September 12, 2026

Reference reviewed: youngchris29-art/NuvioTV native/design/screenshots/player.png and NuvioMobile tvos-shared-extraction at 243da21. The screenshot uses a slim timeline over a bottom fade. The original implementation still has separate native AVKit transport and MPV transport/pause information, so copying it verbatim would preserve the reported inconsistency.

PlayerChrome now owns video focus, title and episode information, the timeline, Audio/Subtitles/Settings actions, pause visibility, auto-hide and Back handling for every playback path. Settings opens Playback directly; Audio and Subtitles open their respective tabs directly. Select commits a tab. Back closes Settings, then hides transport, then exits. No extra Play/Pause button is added beside the timeline status indicator. Engine diagnostics stay inside Details. Live TV supplies channel actions through the same settings content slot and uses live/DVR timing.

AVPlayerSurface uses AVPlayerLayer rather than a disabled AVPlayerViewController: the controller still handled remote events with its controls hidden. AVPlayerTransportAdapter translates native transport state and commands; MPV publishes through the same PlayerPlaybackState. Pause remains visible until playback resumes or the viewer hides controls. Track and timing adapters, source/episode orchestration, resume/scrobbling and remuxing remain engine responsibilities.

Apple documents subtitle display for custom AVPlayerLayer players: https://developer.apple.com/documentation/avfoundation/selecting-subtitles-and-alternative-audio-tracks . Native-only sound processing previously exposed through AVKit's private transport UI is not exposed by this custom interface. Do not leave instructions pointing to those removed controls.

Follow-up: the settings content area is 1640 × 460 points for every tab and every engine. The Audio/Subtitles/Playback/Details tab row remains pinned while content scrolls below it. Details has a visible scroll indicator and focus highlights on diagnostic rows. Live TV groups Previous/Go Live/Next separately from Favorite/Guide, with a compact channel identity above the controls. The same grouping is used by both engines.

Jordan’s latest preference keeps Settings opening on Playback, rather than Audio. Direct Audio and Subtitles buttons still open their own tabs.

Validation covers identical native/MPV pause-and-seek behavior, direct track buttons, repeated nested player presentation, Live TV channel/guide actions, fixed tab-row geometry, long subtitle lists and timing, and scrolling Details to the final row and back. Hidden transport buttons are removed from the view tree; changing opacity alone left glass controls exposed to tvOS focus and accessibility. Focus is assigned after controls mount. A static title is checked for accessibility visibility rather than hit testing, since it is not an interactive control.

## Account, continuity and loading pass — 2026-09-12

- Keep account entry compact, with phone approval first, native email/password fields and a visible Manage Profiles action. Prefer the active profile when reopening the picker. Guest/account identity must be clear.
- Add-ons belongs in Settings → Content Sources, not the main navigation. Its input and Install button remain inline. Back returns to Settings; the page must not own another navigation stack or intercept Back for the app sidebar.
- Home and Browse must budget the entire focused card, including captions and focus reach. Medium cards are no longer exempt when that complete frame is taller than the viewport. Cap oversized posters only after accounting for the hero's available compression. Shelf positions survive lazy-row recycling within the current profile session.
- Browse filters remain pinned. Returning Up must reach a usable native filter, with Select opening that filter. Native Menu focus is represented by an unnamed hosting view in accessibility, so test the focus frame and actual opening rather than only the AX button's `hasFocus` or visibility.
- Player loading uses the title logo/artwork and a text fallback throughout routing, native preparation and either engine's buffering. Respect Reduce Motion. Pass logos/backdrops through Details and Continue Watching rather than relying on the metadata repository surviving navigation.
- Player Details keeps a fixed panel size; the title and full synopsis are part of the remote focus graph. Long descriptions are divided into short focusable sections so neither end can become unreachable. Settings still opens Playback.
- Resume positions use the existing profile-scoped watch-progress repository. Both engines now enable its Nuvio upload path, including final saves. Engine fallback passes its current position explicitly. Synthetic test playback must not write account watch history.
- Live TV publishes channels before programme-guide completion, loads up to three sources concurrently, and caches encrypted channel/guide snapshots by profile and source fingerprint. Fresh snapshots are reused for 15 minutes; stale snapshots can paint while refreshing, and expire after seven days. Source edits/removal invalidate the cache. Sources and favorites remain device-local: the shared Nuvio backend has no compatible Live TV model.
- Successful stream probes are cached in memory for five minutes, keyed by URL and request headers, bounded to 32 entries. Failures are not cached. Artwork already uses decoded-memory and disk caches; Settings → Advanced can clear artwork without clearing account data or saved playback positions.
- Shared Nuvio repositories remain authoritative for supported profiles, libraries, add-ons and preferences. Do not invent remote storage fields for local-only TV features or upload playlist credentials into unrelated account settings.

## Profile picker — September 13, 2026

The account pass was too subtle on Who’s Watching. The launch gate now has a quiet Nuvio wordmark, one heading, larger circular portraits and a soft wash of the focused profile’s color. Keep Add Profile and Manage Profiles together below the portrait row. Management must be visually explicit: change the heading and show pencil badges and Edit Profile captions. Remove PRIMARY pills, stars and generic sync descriptions from the launch gate. Preserve cloud avatars, profile selection, PIN checks and account sync. Six profiles must fit with room for the native focus lift; keep caption heights equal. Respect Reduce Motion when changing the background color.

## Loading motion and discovery discussion — September 13, 2026

Keep the player’s loading title stationary: no repeating opacity pulse, bounce or layout movement when a logo replaces text. Use a fixed title slot, reuse cached artwork during engine handoff and preserve it across buffering events.

Jordan likes Home’s expandable presentation. Proposed, not yet approved: combine Browse and Search into one Search destination using the shared Home presentation for discovery, with compact filters and an explicit search field. Preserve browsing position when a query is cleared. Keep Home’s personal rows and recommendations. Do not remove a tab until the navigation decision is approved.

## Combined Search — approved September 13, 2026

Browse and Search are one Search destination, immediately after Home in tabs and sidebar. Keep Home unchanged. Search’s empty-query surface reuses MediaBrowseView/HomeView with an explicit native text field and the existing Movies/Shows, Genre, Catalog and Sort menus in one pinned row. Selecting Search does not open the keyboard. A committed query shows a deduplicated results grid with full type, genre, catalog and sort filters; Clear Search restores the same discovery view and filters. Keep discovery mounted for scroll restoration, disable hidden focus and accessibility, and cover its trailer while results are shown. Keep the synced Hide Discover preference and recent-search management.

Search refinement: keep the contextual backdrop/title, remove its separate hero CTA and carousel dots, stop automatic hero paging and limit the synopsis to two lines. Results retain the full type/genre/catalog/sort filter row and Reset; genres filter the metadata provided by the catalogs. History is a native glass button with a visible focus state. Keep native root navigation visible and reachable; hide it for immersive pushed content and explicit sidebar mode.

## Settings audit and organization — September 13, 2026

Keep common controls visible and longer groups expandable within the selected sidebar page. Each expanded control must remain its own native List row; never nest provider toggles inside a shared VStack row. Avoid repeating the sidebar title in the pane. Keep API key, plugin and badge URL inputs inline with their action; reject empty/whitespace submissions, keep failed-install URLs available for retry, and prevent simultaneous installs. Put Library & Sync beside account services. Keep diagnostic controls inside an explicit Diagnostics disclosure.

Subtitle appearance must apply to native AVPlayer playback as well as MPV. Reapply native text rules when the item changes (including channel changes and remux retries) and when shared preferences update. Preview size, color, background, bold and outline accurately. Bitmap subtitles keep their encoded appearance and platform accessibility preferences may override native text styling. Compatibility buffer/renderer options must state their scope; retain the bounded native remux and live buffers.

- Remote Setup follows the same quiet settings hierarchy: category navigation, inline inputs/actions, and readable status. Browser edits are drafts until TV approval; saved means repository operations finished, including async imports. Keep failed drafts retryable and reject stale snapshots before applying.

## Content-page hierarchy — approved September 13, 2026

Keep the cinematic artwork and prominent playback actions. Year/runtime/rating use a quiet inline facts row; only the age rating gets a small outline. Show a short parental advisory beside it. All series use one native season menu beside Episodes, including Specials, rather than switching between poster selectors and pill rows. Preserve episode artwork, watched state, stream routing, and the fixed-height focused synopsis.

Keep the top synopsis short; put the complete description and credits in a wider About column below episodes/cast, with a narrower Parental Guide column alongside it. Guide categories and labelled severities use plain rows and subtle separators. Both columns participate in the same page scroll. Long reading blocks take remote focus with a small leading line and no pill/scale treatment; they must not use section-top anchoring that prevents reading down and back up. Missing columns collapse naturally, and empty sections stay hidden.

Validation: the isolated content-page UI test passes on tvOS 27 for season selection, Specials, returning from episodes, reading long descriptions down/up, and crossing the About/Parental Guide columns. Device build passed and installed with app data preserved.
