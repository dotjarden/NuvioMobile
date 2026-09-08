# Native TV design decisions

Recorded from Jordan’s review, September 8, 2026. Apply these rules to subsequent UI work.

- The sidebar or tab bar identifies the current page. Do not repeat the page name as a large title, another section header, and an explanatory subtitle. Settings should not say Playback twice above playback controls.
- Keep short section names where they distinguish content, such as Subtitles, Audio language, or Installed. Keep field labels, validation, and explanations that help the user make a meaningful choice. Remove generic introductions and descriptions that merely restate the page’s purpose.
- Browse must use Home’s actual presentation and interaction implementation. Share the background/scrim, pinned header, row viewport, remote focus, poster buttons, and end-of-row See All tile. Filters are the additional control row, with anchored native menus.
- The hero stays above the scrolling rows. Do not approximate it with a second full-page ScrollView, a different gradient, or an arbitrary hero frame.
- Inputs use native tvOS input and focus styling without extra glass containers. Put related submit actions beside their input; Add-ons Install belongs beside Manifest URL.
- Liquid Glass is appropriate for navigation and controls. Readability and reachable remote focus take precedence over translucency.

## Playback discussion — proposal, not implemented

Retain both decoding engines because their format and playback capabilities differ. Give them a common bottom control organization: Audio, Subtitles, Playback, Details. Show only supported actions. Live TV adds channel navigation, Guide, Favorites, and Go Live in the same location. Detailed information remains available on demand rather than competing with transport controls.

Use the existing PlayerTopPanelModel and native/MPV adapters as the starting point for shared presentation state. AVKit owns native transport; MPV requires equivalent custom transport. Matching layout and remote grammar is feasible, but native AVKit’s internal controls cannot simply be transplanted into MPV.

Before implementation, agree the common layout with Jordan. Profile the information-heavy MPV UI on an actual Apple TV. Current code polls cached state every 0.5 seconds, republishes duration/state, and rebuilds information through the adapter; expensive diagnostics already run off-main but can be requested while any panel is open. These are investigation targets, not a measured diagnosis. Separate playback work from visible UI updates, deduplicate unchanged values, and sample diagnostics only while Details needs them. Preserve seek, track selection, HDR routing, and live playback behavior.
