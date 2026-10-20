# Gojo

macOS notch utility app — turns the MacBook notch into a control surface for music, clipboard, window management, file shelf, and more.

## Build

```bash
make build        # Debug build
make run          # Build + launch
make clean        # Remove .build/ artifacts
```

Or open `Gojo.xcodeproj` in Xcode and run the `Gojo` scheme.

`make build` discovers a valid Apple signing identity for team `L6U44C67P5`, verifies it cryptographically, and signs both targets with it. Select a specific installed identity with `GOJO_SIGNING_IDENTITY` set to its SHA-1 or exact certificate name. An unavailable or incompatible identity fails the build; there is no unsigned fallback.

`make run` verifies the app against the helper's exact caller requirement, verifies the embedded helper, and runs a bounded, nonprompting helper handshake before launching the explicit app path through LaunchServices. It refuses to launch while another Gojo instance is running. The probe reads helper authorization without requesting it and exits before normal app initialization. Accessibility denial can be a successful handshake because transport readiness and OS authorization are separate.

Unsigned builds are for compile checks only. To compile without the team's certificate, invoke `xcodebuild` directly with `CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO`; the resulting app cannot pass the helper's caller validation or supported development launch.

```bash
python3 -B scripts/dev.py preflight /absolute/path/to/Gojo.app
python3 -B scripts/dev.py handshake /absolute/path/to/Debug/Gojo.app --timeout 15
python3 -B scripts/dev.py stop /absolute/path/to/Debug/Gojo.app
python3 -B tests/dev_signing_regression.py --app /absolute/path/to/signed/Gojo.app
```

Debug and Release artifacts support signature preflight and the nonprompting handshake probe. The probe runs before SwiftUI, licensing, and permission startup. It uses the versioned `GOJO_HELPER_HANDSHAKE_STDOUT_V1=1` flag and a UUID launch argument, returns one nonce-matched JSON line on stdout, and accepts no output path. The runner captures stdout in its own private temporary directory and never accesses the app container. Timeout cleanup checks the probe's exact executable, nonce, arguments, and start time before signaling. Do not weaken the helper's production caller requirement to support local builds.

`make stop` targets only this build's resolved executable and its bundled helper/media processes. It rechecks the process path and start time before TERM or KILL and leaves other installed or development copies running.

## Architecture

Two targets communicating over XPC:

- **`Gojo.app`** — SwiftUI host. Owns the notch window, all views, and managers (music, clipboard, shelf, webcam, brightness, volume, flux).
- **`GojoXPCHelper.xpc`** — Bundled XPC service. Holds Accessibility authorization and performs AX-trusted operations (window enumeration, raise, frame set, zoom).

### Key paths

| Path | Purpose |
|------|---------|
| `Gojo/GojoApp.swift` | App entry point, window creation, keyboard shortcuts, drag detection |
| `Gojo/ContentView.swift` | Main notch view — hover/tap/gesture handling, open/close logic |
| `Gojo/GojoViewCoordinator.swift` | Shared state coordinator — current view, sneak peek, HUD setup |
| `Gojo/models/GojoViewModel.swift` | Per-screen notch state (open/closed, sizing) |
| `Gojo/components/Settings/SettingsView.swift` | All settings panels |
| `Gojo/components/Onboarding/` | First-launch onboarding flow |
| `Gojo/components/Notch/` | Notch UI components (header, home view) |
| `Gojo/observers/MediaKeyInterceptor.swift` | CGEvent tap for HUD replacement |
| `Gojo/managers/` | Feature managers (music, brightness, volume, battery, flux) |
| `GojoXPCHelper/` | XPC helper source |
| `design/logo/` | Source SVGs and master PNG for the logo |

### Licensing in local builds

Debug builds honour a `GOJO_LICENSE` environment override:

```bash
GOJO_LICENSE=lifetime make run   # also: monthly | trial | trial:<days> | locked
```

`make run` defaults to `GOJO_LICENSE=lifetime`. When set, `LicenseManager` forces that state and **never touches the license
Keychain** — no reads, no writes, no migration. Use it for any local run: the
license lives in one shared Keychain item, so a dev build with a different
storage layout will otherwise migrate it and strand the installed app's
license. Release builds ignore the variable.

### Settings storage

User preferences use the `Defaults` library (`@Default` property wrapper). Keys are defined across model files. `@AppStorage` is used for a few legacy keys like `firstLaunch`.

### Notch lifecycle

1. Hover/tap/gesture/keyboard shortcut triggers `doOpen()` in ContentView
2. `GojoViewModel.open()` sets `notchState = .open` and resizes the notch window
3. Tabs switch via `GojoViewCoordinator.currentView`
4. Close triggers on hover-exit timeout or explicit close

## Testing

```bash
make test-window        # Window management regression
make test-window-ui     # Windows tab UI checks
make test-window-focus  # Focused-window provider checks
make test-flux          # Night shift regression
```

## Conventions

- SwiftUI throughout, targeting macOS 14+
- Feature managers are singletons (`*.shared`)
- The coordinator (`GojoViewCoordinator.shared`) is the central state hub
- Onboarding blocks notch interaction via `coordinator.firstLaunch` guards
- HUD replacement requires Accessibility authorization via the XPC helper
- GPLv3 licensed — preserve copyright headers and LICENSE when modifying
