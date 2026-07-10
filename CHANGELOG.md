# Changelog

All notable changes to Gojo will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/rohoswagger/gojo/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/rohoswagger/gojo/releases/tag/v1.0.2
[1.0.1]: https://github.com/rohoswagger/gojo/releases/tag/v1.0.1
[1.0.0]: https://github.com/rohoswagger/gojo/releases/tag/v1.0.0
