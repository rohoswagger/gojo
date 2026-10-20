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
  <a href="https://trygojo.com/downloads/">Official signed download</a>
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

Recent clipboard items, browsable from the notch. Pin entries, search, paste back into the focused app. Skips clipboard items marked private by supported password managers. Other copied text, including unmarked secrets, can enter history.

<!-- <p align="center"><img src="./web/public/screenshots/clipboard.png" alt="Clipboard tab" width="640"></p> -->

### Dictation

Choose a speech model in **Settings > Dictation**, then click **Download**. Gojo never downloads a model by itself. Hold **Control+Option**, speak, and release either key to type into the field you selected. While holding both keys, press **Space** to lock voice mode on, then release the keys and keep talking. Press **Control+Option**, then **Space** again to finish. Recording pauses any media that is playing and resumes it when the mic stops, including on cancel or a voice-mode pause. Media that was already paused stays paused.

Open **Voice controls** from Dictation settings or the notch waveform button. The small floating capsule remembers where you drag it on each display. You can record without selecting a text field. If no editable destination is selected, insertion fails, or the app cannot confirm receipt, a popover shows the full transcript. Click the capsule's center to reopen it. Use **Copy** to copy the text or **Discard** to remove it. Saved text stays available until you discard it, including across new sessions and canceling. Password fields and missing permissions still block recording. Voice mode keeps listening between phrases and follows the focused field at each phrase boundary. Click the waveform to pause, the play icon to resume, the checkmark to finish, or the cross to cancel. Hover for tooltips. The pause setting offers 0.6, 0.9, or 1.5 seconds. There is no automatic voice-session timeout. Sleep and screen lock cancel recording.

Pause detection uses microphone volume. Sustained background noise can delay a phrase boundary, and very quiet speech can be missed. If Gojo cannot keep up with queued phrases, it stops with an error rather than silently skipping speech.

Parakeet Unified handles English with punctuation and capitalization. Parakeet v3 covers 25 European languages. Whisper Small and Whisper Large v3 are English options. Downloaded models recognize speech on this Mac without an API key or cloud fallback. Optional S1-mini cleanup and vocabulary replacements also run locally. Selecting **OpenRouter** instead sends audio to the configured cloud model and requires an API key.

Add names, code symbols, or jargon under **Settings > Dictation > Vocabulary**. A word on its own is enough: no spoken alias is required. Whisper models use saved words as recognition hints, Parakeet models don't support hints yet, and every model preserves a word's exact spelling. S1-mini does not receive the vocabulary as a prompt. **Learn from my corrections** is on by default: after you make the same similar-spelling fix twice in a readable text field within about 30 seconds of dictating, Gojo adds a local replacement you can edit or delete. Apps that don't expose their text are skipped, and Gojo does not log keystrokes or save full documents.

Use **Import file…** to append words from a UTF-8 JSON, CSV, or text file up to 1 MiB. Existing words and aliases stay. Gojo skips duplicates and invalid terms, then reports how many words fit within the 250-entry limit. Use **Paste list…** for one word or phrase per line.

JSON accepts a string array such as `["Kubernetes", "PostgreSQL"]`, objects such as `[{"word":"Kubernetes"}]`, or a `{"words":["Kubernetes"]}` wrapper. CSV accepts words in each cell, such as `Kubernetes,PostgreSQL`. A first-row `word`, `words`, or `term` header selects that column and ignores metadata columns. To import the literal word `word` first, use JSON or text. Text files keep one word or phrase per line, with commas and quotes treated literally.

For a text file or **Paste list…**, enter:

```text
Kubernetes
PostgreSQL
```

Gojo refuses password fields. In voice mode, a phrase targeting a password field stops recording without transcribing or saving that phrase. Previously accepted phrases finish normally. Each completed phrase stays tied to its captured field while processing. If the field changes or cannot be verified, voice mode keeps the text available for copying instead of redirecting it. The Control and Option shortcut is fixed so it is always easy to remember.

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

> Requires macOS 14 Sonoma or later. The current signed download is for Apple Silicon Macs. Intel support is not verified for the published build.

### Latest release

1. Download **Gojo.dmg** from the [official download page](https://trygojo.com/downloads/).
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

`make run` builds and signs the Debug app, checks its signature and embedded helper, then runs a nonprompting helper handshake before launching. It uses LaunchServices with the explicit app path and defaults to the lifetime development license override. It refuses to launch while another Gojo instance is running and reports that instance's PID and path.

The helper accepts clients signed with an Apple-issued certificate for Gojo's team, `L6U44C67P5`. Install a valid development or Developer ID Application certificate and its private key for that team. The build discovers a matching identity automatically. To select one explicitly, set `GOJO_SIGNING_IDENTITY` to its SHA-1 or exact certificate name:

```bash
GOJO_SIGNING_IDENTITY='Developer ID Application: Your Name (L6U44C67P5)' make run
```

Missing or incompatible signing credentials stop the build with a diagnostic. Unsigned builds can check compilation by invoking `xcodebuild` directly with `CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO`; their helper connection and supported launch will fail signing validation.

Other useful targets:

| Command | Effect |
|---------|--------|
| `make build` | Build and verify app/helper signatures |
| `make stop` | Stop this build's app and bundled helper/media processes |
| `make restart` | Stop this build, then build and launch |
| `make clean` | Remove `.build/` artifacts |

You can also open `Gojo.xcodeproj` in Xcode and run normally.

For Xcode runs, select a signing certificate for team `L6U44C67P5` for both the app and helper targets. Ad-hoc signing fails the helper's caller requirement. These checks can also run directly:

```bash
python3 -B scripts/dev.py preflight /absolute/path/to/Gojo.app
python3 -B scripts/dev.py handshake /absolute/path/to/Debug/Gojo.app --timeout 15
python3 -B scripts/dev.py stop /absolute/path/to/Debug/Gojo.app
python3 -B tests/dev_signing_regression.py --app /absolute/path/to/signed/Gojo.app
```

The handshake launches a dedicated instance through LaunchServices, checks a nonce-matched typed helper reply on stdout, and cleans up its private temporary files and probe process. It never creates or reads the app's container. The probe accepts no output path and exits before normal app startup, including licensing and permission initialization. It does not request Accessibility or microphone access. A successful handshake can report `accessibilityAuthorized: false`; grant that permission separately when using a feature that needs it. Debug and Release builds both support signature preflight and the handshake probe.

The stop command matches the resolved app path, rechecks each process's path and start time before signaling, and uses bounded termination waits. Installed copies and other development builds remain running.

### Releasing

Maintainers cut signed, notarized releases from a local machine with a single command:

```bash
make release VERSION=1.0.0       # build → sign → notarize → DMG → Sparkle-sign → appcast → GitHub Release
make release-dry VERSION=1.0.0   # same, but stop before publishing
```

See [RELEASING.md](./RELEASING.md) for one-time setup (signing certificate, App Store Connect API key, Sparkle keys, Cloudflare R2) and the full cut-a-release checklist.

## Permissions

Gojo asks for a few macOS permissions on first use of the relevant feature:

| Permission | Why |
|------------|-----|
| **Accessibility** | Required for the window manager — read and resize windows of other apps via AX. |
| **Microphone** | Required for dictation. Local models process audio on-device; optional cloud mode sends audio to your selected provider. |
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

Auto-update is provided by Sparkle via the appcast at `https://updates.trygojo.com/appcast.xml` (EdDSA-signed updates).

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
