# Changelog

All notable changes to Gojo will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.5.0] — 2026-09-01

Dictation is more flexible, more reliable, and no longer limited to a short
list of compatible apps.

### Added

- **Optional OpenRouter transcription.** Use a supported cloud speech model
  with an API key stored in the macOS Keychain, or keep using the existing
  private, on-device models.
- **Private transcript cleanup.** Download S1-mini to remove filler, false
  starts, and accidental repetition entirely on this Mac.
- **Writing styles and vocabulary.** Choose Casual, Conversational, or Formal
  output and teach Gojo names, terms, and phrases that speech models commonly
  mishear.
- **Accessibility recovery from the menu bar.** Reopen the same drag-to-grant
  setup flow at any time from the Gojo menu.

### Changed

- **Dictation works across more apps.** Gojo now supports Accessibility-opaque
  editors without maintaining a per-app allowlist. It keeps insertion locked
  to the captured app and window, avoids the clipboard, and rechecks secure
  focused controls while adding text.
- **The Control–Option shortcut recovers more reliably.** Event-tap recovery,
  cancellation, replacement sessions, and first-use permission handling are
  more resilient across app activation, wake, and rapid retries.

### Fixed

- **Accessibility setup no longer completes before you can drag.** A previous
  grant can no longer make the menu-triggered recovery flow flash “You're all
  set” and immediately disappear.
- **Debug and Release builds package the cleanup runtime correctly.** The
  redundant llama framework embed phase that broke clean builds has been
  removed.

## [1.4.0] — 2026-08-17

Automatic updates now come from their own address, so they no longer depend on
the website being up.

### Changed

- **A dedicated home for updates.** Gojo checks `updates.trygojo.com` for new
  versions instead of the main site. The feed is served straight from storage, so
  a problem with the website can never stop updates from arriving.

### Note for 1.3.0 and earlier

Older versions look for updates at the previous address, which keeps working —
but they cannot be pointed at the new one after the fact. If you are on 1.3.0 or
earlier and updates are not appearing, download Gojo once from
[trygojo.com](https://downloads.trygojo.com/Gojo.dmg) and replace your copy. Your
licence key is unaffected and will activate as normal. This is a one-time step.

## [1.3.0] — 2026-08-16

Gojo has a new home: **trygojo.com**.

> **Update to 1.3.0 to keep your license working.** Licensing moved to the new
> domain and the old address has been retired, so earlier versions can no longer
> reach the licence server. Your licence key itself is unchanged and stays
> valid — but an un-updated copy will eventually ask you to revalidate and lock.
> If your copy has already locked, download Gojo once from
> [trygojo.com](https://downloads.trygojo.com/Gojo.dmg) and replace it; your
> existing key will activate as normal.

### Changed

- **New home on the web.** The Gojo site, downloads, and this changelog now live
  under `trygojo.com` instead of the old `rohoswagger.com` address.
- **Licensing and updates follow the move.** Licence checks and the automatic
  update feed point at the new domain. Nothing changes in how you use them.
- **Licence emails now come from `hi@trygojo.com`.** Add it to your contacts if
  your provider is strict about filtering.

## [1.2.0] — 2026-08-03

Search comes to Gojo. Press ⌘ Space and Gojo answers instead of Spotlight.

### Added

- **Search** — a Spotlight-style panel for your whole Mac. Press ⌘ Space (or ⌥ Space) to open it from anywhere: launch any installed app, find files by name, or type a calculation like `2*19` and copy the answer with a single keystroke. Results rank by how often and how recently you use them, so your everyday apps float to the top.
- **Replace Spotlight, reversibly.** Gojo takes over ⌘ Space without touching your system keyboard settings — turn it off in Settings → Search and Spotlight is instantly back. Requires the same Accessibility permission Gojo already uses for window management.
- **Built to grow.** Search is built on a provider system, so future result types (clipboard, actions, and more) plug into the same panel.

## [1.1.2] — 2026-08-02

Dictation fixes. If holding Control–Option seemed to do nothing, or your words never made it into the field, this release is for you.

### Fixed

- **Gojo now asks for Accessibility instead of going quiet.** Dictation listens for Control–Option through an event tap, which macOS only allows with Accessibility permission. Without it Gojo gave up silently — the shortcut simply did nothing, with no prompt and no explanation. It now asks for permission at launch.
- **Your first dictation no longer arrives too late to use.** The speech model was only loaded once you stopped speaking, so the very first transcript could take around 20 seconds to appear — long enough that if you had clicked anywhere else, Gojo discarded the text and told you that you had moved to another field. The model now loads while you speak.

Gojo still refuses to insert text if you move to a different field mid-dictation. That check is deliberate, and it keeps dictated text out of the wrong place.

## [1.1.1] — 2026-08-01

A repair release. Gojo itself is unchanged from 1.1.0 — this is the same app, signed correctly.

### Fixed

- **Automatic updates now work.** Every release up to and including 1.1.0 was signed with a malformed sandbox entitlement, which left Gojo unable to reach the helper services that install updates. Gojo could check for a new version but never finish installing one.

> **If you are already running 1.1.0 or earlier, please download Gojo once from [downloads.rohoswagger.com](https://downloads.rohoswagger.com/Gojo.dmg) and replace your copy.** The broken updater is the very thing this release fixes, so it cannot update itself. This is a one-time step — updates from 1.1.1 onward install on their own.

## [1.1.0] — 2026-07-31

Gojo can now type for you from the notch. Choose a local voice model, press Control–Option, speak, and Gojo inserts the final transcript into the field you selected.

### Added

- **Dictation** — pick a speech model in **Settings > Dictation**, download it explicitly, then hold or tap **Control–Option** to speak into the focused text field. Recognition stays on this Mac; Gojo does not use an API key or cloud transcription.
- **Voice models** — choose from Parakeet Unified, Parakeet v3, Whisper Small, and Whisper Large v3. Models can be downloaded, selected, and removed independently.
- **Insertion safety** — Gojo refuses password fields, validates the focused target before adding text, and cancels insertion if you move to another field while it is transcribing.

### Changed

- **Dictation settings** now show the activation mode, microphone and Accessibility status, model download size, installed models, and the current model.
- **Microphone permission copy** now explains exactly when Gojo uses the microphone and that audio is transcribed locally.
- **License settings** now preserve the local key when server-side deactivation fails and describe the available 1- and 3-Mac plans accurately.
- **Website** now presents Gojo as an all-in-one MacBook notch workspace with richer feature tours, real app screenshots, comparison pages, clearer pricing, and consistent custom-domain search metadata.

### Fixed

- **Window switching** — per-window recency is preserved across app activation, so quick switching keeps the expected window order.
- **Multiple displays** — the switcher now appears on the focused app's display and only includes eligible windows from that physical display, even when displays share a Space.
- **macOS 14 compatibility** — the bundled media adapter is now built for Gojo's advertised minimum system version.

## [1.0.2] — 2026-07-10

### Changed

- **Clipboard history** and the **calendar view** are now enabled by default on fresh installs.

### Fixed

- **Night shift** — the notch toggle now works even without a location set, assuming a 7 AM sunrise / 7 PM sunset. The first time you turn it on without a location, settings opens once so you can set one.
- **Window snapping** — the window strip now scrolls smoothly when you have many windows open, instead of hiding anything past the sixth. Edge fades and a peeking card show when there's more to scroll, and the focused window scrolls into view automatically.

## [1.0.1] — 2026-07-08

### Fixed

- **Onboarding** — the accessibility permission step is now a Codex-style drag-to-grant flow: drag the app icon straight into System Settings instead of hunting through panes.
- **Onboarding** — the setup flow now renders correctly in light mode, with a consistent look across every step.
- **Installer** — the DMG install window is redesigned to match the marketing site, and window chrome/layout issues on open are fixed.

## [1.0.0] — 2026-06-25

Meet Gojo — it turns the dead space around your MacBook's notch into a control surface for the things you reach for all day. Hover the notch and it opens; everything's a glance and a click away.

### What's inside

- **Music** — see and control whatever's playing (Apple Music, Spotify, browser audio) right in the notch: album art, scrubbing, and playback controls.
- **Window snapping** — a live strip of your open windows with one-click snapping (halves, fill, zoom) and keyboard shortcuts, across any app.
- **Clipboard history** — browse, search, pin, and paste your recent copies. Password managers are skipped automatically.
- **File shelf** — drag files into the notch from anywhere and pick them back up in any other app.
- **Night shift** — warm your screen on a schedule with location-aware sunset, down to a cozy 750K.
- **Calendar & reminders** — your next events and to-dos, glanceable the moment the notch opens.
- **Webcam mirror** — a quick mirror to check your framing before a call.
- **Battery** — charge level and power status, always in reach.
- **Guided setup** — a polished first launch that gets you going in seconds.
- **Automatic updates** — new versions install themselves; no re-downloading.

[Unreleased]: https://github.com/rohoswagger/gojo/compare/v1.4.0...HEAD
[1.4.0]: https://github.com/rohoswagger/gojo/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/rohoswagger/gojo/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/rohoswagger/gojo/compare/v1.1.2...v1.2.0
[1.1.2]: https://github.com/rohoswagger/gojo/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/rohoswagger/gojo/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/rohoswagger/gojo/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/rohoswagger/gojo/releases/tag/v1.0.2
[1.0.1]: https://github.com/rohoswagger/gojo/releases/tag/v1.0.1
[1.0.0]: https://github.com/rohoswagger/gojo/releases/tag/v1.0.0
