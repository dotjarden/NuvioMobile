# Fork modification record

## September 8–13, 2026 — dotjarden community fork

Based on youngchris29-art's native NuvioTV port and NuvioMobile tvOS branch,
with shared core and application lineage from NuvioMedia/NuvioMobile.
Upstream authors, commits, copyright notices, and GPLv3 license are retained.

Changes in this fork include:

- Native Apple TV presentation, glass controls, catalog shelves and focus behavior.
- Live TV sources, guide/favorites, channel cache and playback integration.
- Shared playback interface over AVPlayer and MPV, with playback information,
  track selection, timing, resume behavior and loading artwork.
- Combined Search/discovery and full filtering controls.
- Profiles, sign-in, account synchronization and continuity improvements.
- Organized TV settings, add-ons under Settings and browser Remote Setup.
- Content-page hierarchy, plain metadata, a single season menu and full synopsis.
- September 13: restore native navigation after returning to Home's pinned hero.
- September 13: prominent fork identity, upstream attribution, source/build
  documentation and credits in Settings → About.

The Git log records exact files, commit authors and dates. This record describes
fork modifications and does not claim authorship of the inherited application.
The preserved baseline for the original fork checkout is NuvioTV commit
`bd91451eedd1df195430b840732b6a709380184b`; its submodule records the matching
upstream NuvioMobile revision.
