<h1 align="center">
  <br>
  <img src="./Gojo/Assets.xcassets/AppIcon.appiconset/mac256.png" alt="Gojo" width="128">
  <br>
  Gojo
  <br>
</h1>

<p align="center">
  <em>Turn the MacBook notch into a control surface for everything you actually use.</em>
</p>

<p align="center">
  <a href="https://github.com/rohoswagger/gojo/releases/latest"><img src="https://img.shields.io/github/v/release/rohoswagger/gojo?display_name=tag&sort=semver&label=release" alt="Latest release"></a>
  <a href="https://github.com/rohoswagger/gojo/actions/workflows/build.yml"><img src="https://github.com/rohoswagger/gojo/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14+">
</p>

---

Gojo expands the dead space around your MacBook's notch into a focused, tab-driven HUD. Music, clipboard history, a drag-and-drop file shelf, window management, night shift, and more — all accessed by hovering the notch.

## Features

### Window snapping

Stage strip of on-screen apps with real app icons, a live monitor preview, and six snap actions (left / right / top / bottom halves, fill, zoom). Cross-app: click any window, snap it. Every chip surfaces its keyboard shortcut underneath.

<p align="center"><img src="./web/public/screenshots/windows-tab.png" alt="Windows tab" width="640"></p>

### Music

Now-playing surface that follows whatever's playing — Apple Music, Spotify, browser audio. Scrubs, switches, and renders artwork in the notch's album-art slot.

<p align="center"><img src="./web/public/screenshots/music.png" alt="Music tab" width="640"></p>

### Clipboard history

Recent clipboard items, browsable from the notch. Pin entries, search, paste back into the focused app. Automatically excludes password managers.

<!-- <p align="center"><img src="./web/public/screenshots/clipboard.png" alt="Clipboard tab" width="640"></p> -->

### Dictation

Choose a speech model in **Settings > Dictation**, then click **Download**. Gojo never downloads a model by itself. Hold **Control+Option**, speak, and release either key to type into the field you selected. While holding both keys, press **Space** to lock voice mode on, then release the keys and keep talking. Press **Control+Option**, then **Space** again to finish.

Open **Voice controls** from Dictation settings or the notch waveform button. The small floating capsule remembers where you drag it on each display. Voice mode keeps listening between phrases and follows the focused field at each phrase boundary. Click the waveform to pause, the play icon to resume, the checkmark to finish, or the cross to cancel. Hover for tooltips. The pause setting offers 0.6, 0.9, or 1.5 seconds. There is no automatic voice-session timeout. Sleep and screen lock cancel recording.

Pause detection uses microphone volume. Sustained background noise can delay a phrase boundary, and very quiet speech can be missed. If Gojo cannot keep up with queued phrases, it stops with an error rather than silently skipping speech.

Parakeet Unified handles English with punctuation and capitalization. Parakeet v3 covers 25 European languages. Whisper Small and Whisper Large v3 are English options. Downloaded models recognize speech on this Mac. Optional S1-mini cleanup and vocabulary replacements also run locally. Selecting **OpenRouter** instead sends audio to the configured cloud model and requires an API key.

Gojo refuses password fields. Each completed phrase stays tied to its captured field while processing. If the field changes or cannot be verified, voice mode keeps the text available for copying instead of redirecting it. The Control and Option shortcut is fixed so it is always easy to remember.

### Drag-and-drop shelf

Drop files into the notch from anywhere; pick them up later from any other app. Lightweight staging without a Finder tab open.

<!-- <p align="center"><img src="./web/public/screenshots/shelf.png" alt="Shelf tab" width="640"></p> -->

### Night shift

f.lux-style color temperature control built into the notch. Schedule-based transitions, location-aware sunset detection, and manual pause.

### Calendar & Reminders

Next-up events and reminders glanceable when the notch opens. Per-calendar and per-list toggling.

### Webcam mirror

Quick selfie view for camera-positioning before a call.

<!-- <p align="center"><img src="./web/public/screenshots/webcam.png" alt="Webcam mirror" width="640"></p> -->

### Battery

Battery percentage and power status notifications in the notch.

### First-run onboarding

A guided first launch opens with an animated aperture welcome, walks you through the optional permissions and your music source, and finishes with a hello flourish in the notch itself.

## Install

> Requires macOS 14 Sonoma or later. Apple Silicon and Intel both supported.

### Latest release

1. Download **Gojo-x.y.z.dmg** from the [latest release](https://github.com/rohoswagger/gojo/releases/latest).
2. Open the DMG and drag **Gojo.app** into **Applications**.
3. Open Gojo from **Applications**.

Official Gojo releases are signed with a Developer ID certificate and notarized by Apple, so they open normally with macOS Gatekeeper enabled.

Updates after that are delivered automatically via [Sparkle](https://sparkle-project.org/).

### Build from source

```bash
git clone https://github.com/rohoswagger/gojo.git
cd gojo
make run
```

`make run` builds the Debug app, stops any existing dev process, and launches it. Other useful targets:

| Command | Effect |
|---------|--------|
| `make build` | Build only |
| `make stop` | Kill running dev instances |
| `make restart` | Stop + build + launch |
| `make clean` | Remove `.build/` artifacts |

You can also open `Gojo.xcodeproj` in Xcode and run normally.

### Releasing

Maintainers cut signed, notarized releases from a local machine with a single command:

```bash
make release VERSION=1.0.0       # build → sign → notarize → DMG → Sparkle-sign → appcast → GitHub Release
make release-dry VERSION=1.0.0   # same, but stop before publishing
```

See [RELEASING.md](./RELEASING.md) for one-time setup (signing certificate, App Store Connect API key, Sparkle keys, GitHub Pages) and the full cut-a-release checklist.

## Permissions

Gojo asks for a few macOS permissions on first use of the relevant feature:

| Permission | Why |
|------------|-----|
| **Accessibility** | Required for the window manager — read and resize windows of other apps via AX. |
| **Microphone** | Required only while local dictation is listening. Audio is processed on-device and is not uploaded. |
| **Apple Events** | Reading the now-playing track from Music/Spotify. |
| **Camera** | Optional, for the webcam mirror. |
| **Calendar & Reminders** | Optional, for displaying upcoming events and reminders. |

Permissions are granted via **System Settings → Privacy & Security**. The `GojoXPCHelper` XPC service is the process that holds the Accessibility grant — Gojo proxies AX-trusted work through it.

## Keyboard shortcuts

Defaults — all rebindable in **Settings → Shortcuts**.

### Global

| Action | Shortcut |
|--------|----------|
| Open clipboard history panel | ⇧⌘C |
| Toggle notch open | ⇧⌘I |
| Toggle sneak peek | ⇧⌘H |
| Push to talk | Hold ⌃⌥ |
| Lock / finish voice mode | ⌃⌥ then Space |

### Window manager

| Action | Shortcut |
|--------|----------|
| Snap to left half | ⌃⌥← |
| Snap to right half | ⌃⌥→ |
| Snap to top half | ⌃⌥↑ |
| Snap to bottom half | ⌃⌥↓ |
| Maximize (fill) | ⌃⌥↩ |
| Zoom (default size) | ⌃⌥Z |

## Architecture

Gojo is two targets that talk over XPC:

- **`Gojo.app`** — the SwiftUI host app. Owns the notch window, the views, music/clipboard/shelf/webcam managers, and most of the UI logic.
- **`GojoXPCHelper.xpc`** — bundled XPC service. Holds the Accessibility authorization and performs AX-trusted operations (window enumeration, raise, frame set, zoom). Isolating AX in a separate process makes the trust model cleaner and lets the main app run without elevated permissions.

Auto-update is provided by Sparkle via the appcast at `https://trygojo.com/appcast.xml` (EdDSA-signed updates).

## Troubleshooting

**Window snaps aren't moving the right window**
Open **System Settings → Privacy & Security → Accessibility**, make sure **Gojo** is checked. The window manager talks through the helper, which needs AX trust.

**Clipboard history isn't capturing**
Gojo only sees changes while it's running. Launch Gojo first, then copy. If you toggle **Launch at login** in Settings, history starts being captured at boot.

**Dictation does not start**
Open **System Settings > Privacy & Security** and allow microphone access for Gojo. Accessibility access is also required to insert text into other apps. Then open **Settings > Dictation**, download a model, and choose it before using the shortcut.

**Notch doesn't show on a connected display**
Settings → General → Display lets you pick which screen Gojo lives on, and whether to mirror it across all displays.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md). Issues and PRs welcome — please search existing issues first.

## Security

See [SECURITY.md](./SECURITY.md) for the responsible-disclosure flow.

## License

Gojo is licensed under the [GNU General Public License v3.0](./LICENSE).

- Third-party licenses — [THIRD_PARTY_LICENSES](./THIRD_PARTY_LICENSES)
- Provenance — [NOTICE.md](./NOTICE.md)

## Acknowledgments

Built on Sparkle, WhisperKit, FluidAudio, KeyboardShortcuts, Defaults, swift-collections, Lottie, Pow, SkyLightWindow, MacroVisionKit, AsyncXPCConnection, swiftui-introspect, and LaunchAtLogin.
