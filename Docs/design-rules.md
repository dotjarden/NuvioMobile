# Native TV design decisions

Recorded from Jordan’s review, September 8, 2026. Apply these rules to subsequent UI work.

- The sidebar or tab bar identifies the current page. Do not repeat the page name as a large title, another section header, and an explanatory subtitle. Settings should not say Playback twice above playback controls.
- Keep short section names where they distinguish content, such as Subtitles, Audio language, or Installed. Keep field labels, validation, and explanations that help the user make a meaningful choice. Remove generic introductions and descriptions that merely restate the page’s purpose.
- Browse must use Home’s actual presentation and interaction implementation. Share the background/scrim, pinned header, row viewport, remote focus, poster buttons, and end-of-row See All tile. Filters are the additional control row, with anchored native menus.
- The hero stays above the scrolling rows. Do not approximate it with a second full-page ScrollView, a different gradient, or an arbitrary hero frame.
- Inputs use native tvOS input and focus styling without extra glass containers. Put related submit actions beside their input; Add-ons Install belongs beside Manifest URL.
- Liquid Glass is appropriate for navigation and controls. Readability and reachable remote focus take precedence over translucency.

## Playback — approved and implemented

Retain AVPlayer and MPV because their format capabilities differ. Both movie players and Live TV use the same opaque bottom Settings drawer: Audio, Subtitles, Playback, Details. Select changes a tab; moving focus alone does not rebuild it. Back closes the drawer before exiting playback. Native AVKit keeps system transport and sound enhancements; MPV supplies its own transport with the same Settings entry point.

Playback offers supported speed, timing, episode and source controls. Live TV puts Previous/Next channel, Go Live, Favorite and Guide there. Stream information is available in Details, without separate pause or diagnostics overlays. MPV publishes changed values only, coalesces diagnostic requests and samples details at most once per second while visible. Native and live diagnostics also stop when Details is closed. These changes reduce unnecessary work; Apple TV hardware profiling is still required to quantify performance.

## Browse and detail follow-up

The filter row belongs outside the catalog's lazy scrolling container, directly beneath the pinned hero. It must remain visible and reachable after scrolling down and returning, including with large posters. Its width and leading alignment must participate in the remote focus section.

Detail pages use a wide backdrop without a separate poster layer or portrait-poster fallback. Keep poster artwork for cards and playback metadata.

Jordan asked whether Home and Browse should merge. Recommended direction: one Home entry with All / Movies / Shows; All retains personal rows such as Continue Watching and collections. This navigation change remains a discussion decision; the current fix preserves both entries.
