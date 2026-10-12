# Talkiie

Talkiie is a macOS dictation app: press a shortcut, speak, and the text appears at the cursor of the app you
are using. Speech recognition runs on your Mac (whisper.cpp with the Breeze-ASR-25 model). Your voice does
not leave the Mac.

This repository is the source code of the public Mac app distributed at <https://talkiie.yyt.app>, reduced to
what is needed to build and run it. It is published so that the privacy claims on
<https://talkiie.yyt.app/privacy.html> can be read in the code, not taken on trust.

## What is in this repository

| Path | What it is |
|---|---|
| `App/`, `AppPublic/` | The macOS app (SwiftUI / AppKit). `AppPublic/` holds what is specific to this edition. |
| `Sources/NaturalInputCore` | Dictation logic: recording, formatting, text insertion (synthetic key events), consent. No network APIs. |
| `Sources/NaturalInputEgress`, `Sources/NaturalInputEgressPublic` | The only places that describe a network destination: the update feed and the feedback web page. |
| `Sources/NaturalInputModelDownload` | First-run download of the speech model (the third and last network use). |
| `Sources/NaturalInputLocalASR` | On-device transcription; the only code that calls whisper.cpp. |
| `Sources/TalkiieOrb`, `Sources/TalkiieLicensing` | The recording animation; a stub of the paid-features module (see below). |
| `Vendor/whisper/` | whisper.cpp v1.8.4 with two small patches, prebuilt as a static xcframework (arm64). |
| `Assets/brand/menubar/carousel/` | The menu-bar animation frames the app bundles. |
| `release/releases-public.json` | Release notes, bundled in the app (the "What's new" window). |
| `project.yml`, `Package.swift`, `xcode/Package.resolved` | The Xcode project spec, the Swift package of the modules, and the pinned Sparkle revision. |
| `tools/build-public.sh` | Builds the app. `tools/sparkle-embed.sh` is a build phase it runs. |

## What the app connects to

| Destination | When | Why |
|---|---|---|
| `https://talkiie.yyt.app/appcast.xml` | Once a day (Sparkle) | Update check. Sparkle's system profile is turned off; the request carries only the standard headers, including a User-Agent with the app name, app version and Sparkle version (and, like any request, your IP address). |
| `https://models.talkiie.yyt.app/…` | First run, and when a newer model is offered | Downloads the speech model (about 2 GB, checked against SHA-256 hashes fixed in `Sources/NaturalInputModelDownload/ModelManifest.swift`). |
| `https://talkiie.yyt.app/feedback` | Only when you click "Report a problem" | Opened in your browser; the app itself sends nothing. |

There is no telemetry. You can watch this yourself with a network monitor (Little Snitch, LuLu, `nettop`).

## Building it yourself

Requirements:

- An Apple Silicon Mac. The app runs on macOS 14 (Sonoma) or later (`deploymentTarget` in `project.yml`).
- Xcode 26 (Swift 6) and its command line tools (`xcode-select --install` once, and open Xcode once to accept
  the license).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
- About 3 GB of free disk for the build, and network access the first time (Swift packages).

From a fresh clone:

```sh
tools/build-public.sh
```

It runs `xcodegen generate` (the Xcode project is generated from `project.yml`, not committed), then
`xcodebuild -scheme TalkiiePublic -configuration Release` with the package versions pinned in
`xcode/Package.resolved` (Sparkle 2.10.0 at a fixed revision), ad-hoc signed (no Apple developer account needed).
It then re-signs the app ad-hoc without the hardened runtime: an ad-hoc signature has no Team ID, and under the
hardened runtime macOS refuses to load the embedded Sparkle framework, so the app would quit at launch. The
official app is signed with a Developer ID and keeps the hardened runtime (`--keep-runtime` builds it that way,
but such a build does not start). The app is at `build/DerivedData/Build/Products/Release/TalkiiePublic.app`; the official app is the same bundle
renamed to `Talkiie.app`.

### First run

Copy `TalkiiePublic.app` to `/Applications` (or `~/Applications`) and open it:

1. The consent page explains what the app does; nothing is recorded before you accept.
2. macOS asks for **Microphone** and **Accessibility** (System Settings → Privacy & Security). Accessibility is
   what lets Talkiie type into other apps. **Input Monitoring** is requested only if you choose the fn key as
   the shortcut.
3. The app downloads the speech model: about 2.1 GB (two files, checked against fixed SHA-256 hashes),
   about 2.4 GB on disk after installation. Until it is ready, the shortcut does not record.

An ad-hoc signed build gets a new code signature every time you rebuild it, so macOS may ask for the
permissions again after a rebuild.

### A build of your own still talks to the official servers

A build from this repository carries the same Sparkle public key and the same addresses as the official app:

- **Updates**: a Release build checks `talkiie.yyt.app` and would replace itself with the official signed
  release. Debug builds never start the updater. To turn updates off in your own Release build, replace
  `SUPublicEDKey` in `AppPublic/Info.plist` with a value that is not a 32-byte Ed25519 key (the updater is then
  never created), or remove the launch check in `AppPublic/Updater.swift` (`checkForUpdatesInBackground()` in
  `start()`; `SUEnableAutomaticChecks` alone does not stop it). To use your own update source, change both
  `SUFeedURL` in `AppPublic/Info.plist` and `PublicUpdatePolicy.feedURL` / `downloadPrefix` in
  `Sources/NaturalInputEgressPublic/PublicUpdatePolicy.swift` (the updater refuses any other feed), and put your
  own key in `SUPublicEDKey`.
- **Speech model**: it downloads from `models.talkiie.yyt.app`. The addresses are fixed in the source on purpose
  (they are part of the privacy policy); a fork that hosts its own model changes `ModelManifest.swift`.

## What this repository does not show

- It does **not** prove that the official app was built from this exact source. Signing with the developer's
  certificate, Apple notarization and packaging are not in this repository, and Swift apps are not bit-for-bit
  reproducible (signatures, timestamps, paths).
- `Vendor/whisper/` is a prebuilt library. It is whisper.cpp v1.8.4 (<https://github.com/ggml-org/whisper.cpp>)
  with two patches, which `AppPublic/THIRD_PARTY_NOTICES.md` describes; the patches and the script that builds the
  library are not in this repository.
- **Comments**: the source files here have their comments removed (the developer's own copy keeps them).
  Apart from comments and blank lines, they are the same code the official app is compiled from: before
  publishing, every Swift file's parse tree (`swiftc -dump-parse`) and token stream, every script's parsed form
  and every configuration file's parsed contents are compared with the original, and any difference stops the
  export. Kept: `// swift-tools-version`, `#!` lines, and the copyright and licence notices of third-party code.
  Line numbers therefore differ from the official build (for example in crash reports).
- Tests, the developer's checks and tools (source lint, release checks, release and website scripts), design
  notes and decision records are not in this repository. Some identifiers and self-test messages still name
  them (`decisions/00NN`, selftests).
- **Paid features (Talkiie Plus)**: their implementation, their prices and how a purchase is verified are not
  here. In their place are stubs that keep every paid feature locked: `Sources/TalkiieLicensing/`,
  `AppPublic/PublicLicenseStub.swift`, `App/AuroraGlowPanel.swift`, `App/AuroraScreenSelection.swift`,
  `App/HUDGlass.swift`, `App/PaidFeatureCopy.swift`, `App/PlusThemeShots.swift`, `App/ThemeTrialPreview.swift`,
  `Sources/NaturalInputCore/HUDTheme+Copy.swift`, `Sources/NaturalInputCore/StartChime+Plus.swift`,
  `Sources/NaturalInputCore/StreamingTranscription+Speculation.swift` and `Sources/TalkiieOrb/AuroraGeometry.swift`. The official app does not offer Plus either,
  so a build from here behaves the same. The official app's `AppPublic/Info.plist` also has a `CFBundleURLTypes`
  entry that only the paid features use; this repository's copy leaves it out.
- A second, unpublished edition is built from the same shared code (the developer edition, 「開發版」;
  `Edition` switches between the two at compile time); its own files are not here. The About page
  of a Debug build shows 「開發版・不自動更新」 ("development build, no automatic updates").
- The app contains self-test modes (`--settings-selftest` and similar) used during development; they are compiled
  in and only run when started with those arguments.

## Name and icon

The Apache License 2.0 does not grant permission to use trade names, trademarks or product names (section 6).
"Talkiie", its icon and its wordmark are the project's trademarks and brand assets:

- They stay in this repository so that you can build the original app from source.
- You may redistribute the official, unmodified app as it is.
- A fork or any modified version must use a different name, a different icon and a different bundle identifier
  (`app.yyt.talkiie` is the official app's), and must not suggest that it is the official app or endorsed by
  its developer. This also keeps the fork's privacy permissions on a Mac apart from the official app's.

## Reporting problems

- Bugs and questions: the Issues tab of this repository. Pull requests are not merged at the moment.
- Security or privacy problems: see [SECURITY.md](SECURITY.md).

## License

Apache License 2.0, see [LICENSE](LICENSE). Third-party components and their licenses are listed in
[NOTICE](NOTICE). The name and icon are covered by "Name and icon" above, not by the code license.
