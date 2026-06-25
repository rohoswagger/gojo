# Gojo

macOS notch utility app — turns the MacBook notch into a control surface for music, clipboard, window management, file shelf, and more.

## Build

```bash
make build        # Debug build
make run          # Build + launch
make clean        # Remove .build/ artifacts
```

Or open `Gojo.xcodeproj` in Xcode and run the `Gojo` scheme.

> Code signing requires the `L6U44C67P5` team certificate. For unsigned local builds, pass `CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO` to xcodebuild.

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
