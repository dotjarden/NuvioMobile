# Remote Setup settings audit — September 13, 2026

Scope: the embedded LAN web interface opened from Settings → Advanced → Remote Setup. Audited every existing control and the approval/application path. This update preserves the remote editor's scope (add-ons, Home rows, metadata keys, badge imports); it does not expose all TV-only playback/account settings to the browser.

| Area | Findings and changes |
| --- | --- |
| Add-ons | Validate/normalize HTTP, HTTPS, Stremio and host-only inputs; reject duplicates. Stage toggles, removal and ordering. Await new installs before applying the complete order and enabled state. Keep existing providers when a replacement fails. Detect repository writes blocked by inherited profile settings. |
| Home rows | Stage visibility and order. Apply only to rows the browser edited, keeping newly installed catalogs' defaults. Read current repository state when applying. |
| Metadata keys | Send only entered, trimmed keys; saved credentials are never returned by the server. Masked fields have labelled Show/Hide actions. Existing shared setters persist keys and enable enrichment/ratings. This does not certify entered credentials with external providers. |
| Badge packs | Validate URLs, block duplicates and the shared three-pack limit; preserve pending imports on failure. Await the shared import result instead of dropping errors. Installed-pack activation/removal remains in TV Settings, as before. |
| Submission | Distinct pending, applying, confirmed, failed and rejected states. Freeze form edits while a request is pending. Send only changed sections. Read the latest repository state before approval and completion (Flow callbacks can lag); refresh after completion, preserve failed edits for retry, show short actionable errors and retain declined drafts. |
| Concurrent edits | Snapshot revision checked on submission and again on TV approval. Only one request may be pending/applying. New sessions clear old snapshots; pairing token remains required on every route. |
| Presentation | Three category destinations; metadata disclosure; flat rows; inline input/actions; readable footer and discard dialog; system type; dark/light appearance. Keyboard-visible focus, labelled switches, disabled boundary arrows and restored focus after reordering. Responsive 390px layout has no horizontal overflow. |

## Validation

- Six `RemoteSetupServerTests` pass on the tvOS 27 simulator, including real localhost server requests: approval waits for application, import failure propagation, token enforcement, conflict rejection, input validation, new provider order/disabled state, failed replacement preservation, and inherited-profile failure reporting.
- Browser fixture serves the exact Swift-embedded HTML with fake settings only. Checked invalid URLs, Stremio normalization, keyboard submission, ordering, row visibility, masked key reveal, omitted unchanged keys, disabled pending edits, decline recovery, failure retry, success refresh, badge duplicates, discard/cancel, and desktop layout.
- Phone layout inspected in a 390 × 844 viewport frame; document width and scroll width both 390px. The in-app browser's viewport override did not take effect, so the fixture uses an actual narrow browsing context.
- Browser interactions use fake providers/keys. No real account credentials, provider installs/removals, or watch-history changes are used as test probes. Production application continues through the existing shared repositories and sync paths.

The fixture is local-only and opt-in: `python3 scripts/tests/remote_setup_fixture.py`. See its docstring for failure/approval modes.
