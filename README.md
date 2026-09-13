# NuvioMobile · dotjarden Apple TV fork

**Independent community fork maintained by [dotjarden](https://github.com/dotjarden).** Based on [youngchris29-art/NuvioTV](https://github.com/youngchris29-art/NuvioTV) and its [NuvioMobile tvOS branch](https://github.com/youngchris29-art/NuvioMobile/tree/tvos-shared-extraction), built on [NuvioMedia/NuvioMobile](https://github.com/NuvioMedia/NuvioMobile). Original authorship and copyright notices are preserved. This fork is not an official Nuvio release and is not endorsed by the upstream maintainers.

**Modification notice — September 13, 2026:** this distribution includes changes to the Apple TV interface, Live TV, playback controls, account flows, settings, and remote navigation. See [FORK_CHANGES.md](FORK_CHANGES.md), [NOTICE](NOTICE), and the Git history for dates, authors, and scope.

This repository contains the SwiftUI **NuvioTV** application and the shared Kotlin Multiplatform core used by [dotjarden/NuvioTV](https://github.com/dotjarden/NuvioTV). The inherited Android and iOS source remains in the repository; this fork's current development and validation focus on Apple TV.

## Build this version

Start from the [NuvioTV wrapper repository](https://github.com/dotjarden/NuvioTV) so the QuickJS tvOS patch and all pinned submodules are included:

```sh
git clone --recurse-submodules --branch main https://github.com/dotjarden/NuvioTV.git
cd NuvioTV
```

Follow its [build instructions](https://github.com/dotjarden/NuvioTV/blob/main/BUILDING.md). Build the **NuvioTV** Xcode scheme from `NuvioMobile/iosApp/iosApp.xcodeproj`. Downloadable fork builds, when published, belong to [dotjarden's releases](https://github.com/dotjarden/NuvioTV/releases).

## Fork changes

The maintained version adds Live TV, a revised Apple TV interface, combined Search/discovery filters, shared player controls, account/profile improvements, organized settings and Remote Setup, and navigation fixes. See [FORK_CHANGES.md](FORK_CHANGES.md) and the [project overview](https://github.com/dotjarden/NuvioTV#changes-in-this-fork).

`main` is this fork's maintained Apple TV version. `codex/native-tv-experience` is the ongoing development branch. The inherited `cmp-rewrite` and `tvos-shared-extraction` branches retain upstream context.

## Source layout

- `iosApp/NuvioTV/`: SwiftUI Apple TV screens and playback interface.
- `iosApp/NuvioTopShelf/`: Apple TV Top Shelf extension.
- `shared/`: UI-independent Kotlin `SharedCore` framework.
- `composeApp/`: inherited Android/iOS Compose application.
- `MPVKit/`: pinned playback dependency and its upstream licenses.
- `iosApp/Configuration/Version.xcconfig`: app version/build configuration.

## Credits and licenses

- **youngchris29-art**: [native Apple TV port](https://github.com/youngchris29-art/NuvioTV) and [tvOS shared-core extraction](https://github.com/youngchris29-art/NuvioMobile/tree/tvos-shared-extraction).
- **NuvioMedia and contributors**: [original NuvioMobile application](https://github.com/NuvioMedia/NuvioMobile), shared business logic, and the broader Nuvio ecosystem.
- **tapframe and contributors**: [earlier React Native NuvioTV](https://github.com/tapframe/NuvioTV).
- **MPVKit, libmpv, QuickJS, and other dependency authors**: playback/runtime components under their respective licenses.
- **dotjarden**: this community fork's maintenance and modifications, with individual authors preserved in Git history.

The inherited [GNU GPLv3 LICENSE](LICENSE) and copyright notices remain in place. [NOTICE](NOTICE) identifies the fork and upstream projects. Distributed builds must provide corresponding source, including the pinned submodules and required build scripts. This fork does not imply upstream endorsement.

For the official mobile project and its releases, visit [NuvioMedia/NuvioMobile](https://github.com/NuvioMedia/NuvioMobile).
