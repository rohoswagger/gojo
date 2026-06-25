import AppKit

@MainActor
final class WindowActionExecutor {
    static let shared = WindowActionExecutor()

    private let provider = FocusedWindowProvider()
    private let calculator = WindowGeometryCalculator()
    private let history = WindowHistoryStore()

    private init() {}

    func refreshFocusedWindow(
        screenUUID: String?,
        state: WindowPowerState,
        promptIfNeeded: Bool = false
    ) async {
        let notchScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        do {
            let window = try await provider.focusedWindow(for: notchScreen, promptIfNeeded: promptIfNeeded)
            state.isAccessibilityAuthorized = true
            state.setFocusedWindow(window)
            await refreshWindowList(state: state, focusedWindow: window, screen: notchScreen)
        } catch FocusedWindowProvider.ProviderError.permissionMissing {
            state.setPermissionMissing()
        } catch FocusedWindowProvider.ProviderError.noFocusedWindowOnScreen {
            state.setNoWindow()
            await refreshWindowList(state: state, focusedWindow: nil, screen: notchScreen)
        } catch {
            state.setNoWindow()
            await refreshWindowList(state: state, focusedWindow: nil, screen: notchScreen)
        }
    }

    private func refreshWindowList(
        state: WindowPowerState,
        focusedWindow: FocusedWindow?,
        screen: NSScreen?
    ) async {
        guard let screen = screen ?? focusedWindow?.screen ?? NSScreen.main else {
            state.windows = []
            state.focusedWindowID = nil
            return
        }

        // CGWindowList doesn't require AX permission — use the main-app path for enumeration.
        // (Snap + raise still go through the XPC helper since those DO require AX.)
        let fresh = provider.enumerateWindows(on: screen)
        let freshByID = Dictionary(uniqueKeysWithValues: fresh.map { ($0.id, $0) })

        // Preserve stable ordering: keep existing windows in their current slots,
        // append newly-seen windows at the end, drop ones that have disappeared.
        var merged: [WindowSummary] = []
        var seen: Set<String> = []
        for old in state.windows {
            if let updated = freshByID[old.id] {
                merged.append(updated)
                seen.insert(old.id)
            }
        }
        for window in fresh where !seen.contains(window.id) {
            merged.append(window)
        }

        if state.windows != merged {
            state.windows = merged
        }

        // Preserve any valid user selection. Only auto-pick when the current selection
        // is missing or no longer exists in the enumeration.
        let currentSelectionValid = state.focusedWindowID
            .flatMap { id in merged.first { $0.id == id } } != nil

        if !currentSelectionValid {
            if let focusedWindow,
               let match = merged.first(where: { summary in
                   if let wid = focusedWindow.windowID, summary.windowID == wid { return true }
                   return summary.pid == focusedWindow.pid && summary.appName == focusedWindow.appName
               }) {
                state.focusedWindowID = match.id
            } else {
                state.focusedWindowID = merged.first?.id
            }
        }
    }

    /// Visually selects `summary` in the stage strip — no AX raise. Snap chips operate on this target.
    func focus(_ summary: WindowSummary, screenUUID: String?, state: WindowPowerState) async {
        state.focusedWindowID = summary.id
        state.appName = summary.appName
        state.title = summary.appName
        state.windowTitle = summary.title
        state.lastAction = summary.currentAction
        state.preview = summary.currentAction.map(WindowLayoutPreview.init(action:)) ?? .neutral
        state.statusKind = .idle
    }

    func execute(
        _ action: WindowAction,
        target: WindowSummary? = nil,
        screenUUID: String?,
        state: WindowPowerState
    ) async {
        let notchScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }

        // Cross-app target path: snap a specific window via the XPC helper (which has AX permission).
        if let target {
            await executeOnTarget(action, target: target, notchScreen: notchScreen, state: state)
            return
        }

        // Focused-window path (no explicit target): keeps existing keyboard-shortcut behavior.
        do {
            let window = try await provider.focusedWindow(for: notchScreen, promptIfNeeded: true)

            if action == .zoom {
                let success = await XPCHelperClient.shared.performZoom(pid: window.pid, windowID: window.windowID).success
                if success {
                    state.lastAction = .zoom
                    state.preview = .zoom
                    state.statusKind = .success
                    await refreshWindowList(state: state, focusedWindow: nil, screen: notchScreen)
                } else {
                    state.setFailure("Cannot reset \(window.appName)", detail: "macOS would not zoom this window.")
                }
                return
            }

            if action == .maximize,
               let entry = history.entry(for: window),
               entry.lastAction == .maximize {
                let restoreFrame = calculator.clampedRestoreFrame(entry.restoreFrame, for: window.screen)
                guard await provider.setFrame(restoreFrame, for: window) else {
                    state.setFailure("Previous position unavailable", detail: "macOS would not restore this window.")
                    return
                }
                history.clear(for: window)
                state.setSuccess(action: action, window: window, restored: true)
                return
            }

            history.ensureRestoreFrame(for: window, action: action)
            let targetFrame = calculator.targetFrame(for: action, window: window)
            guard await provider.setFrame(targetFrame, for: window) else {
                state.setFailure("This window cannot be resized", detail: "Some windows cannot be moved by Gojo.")
                return
            }

            history.updateLastAction(action, for: window)

            let refreshedWindow = provider.resolveWindow(
                pid: window.pid,
                windowID: window.windowID,
                fallbackAppName: window.appName,
                fallbackTitle: window.title
            ) ?? window
            let constrained = !refreshedWindow.normalFrame.approximatelyEquals(targetFrame, tolerance: 4)
            state.setSuccess(action: action, window: refreshedWindow, constrained: constrained)
            await refreshWindowList(state: state, focusedWindow: refreshedWindow, screen: notchScreen)
        } catch FocusedWindowProvider.ProviderError.permissionMissing {
            gojoDebug("executor: caught permissionMissing")
            state.setPermissionMissing()
        } catch FocusedWindowProvider.ProviderError.noFocusedWindowOnScreen {
            gojoDebug("executor: caught noFocusedWindowOnScreen → setNoWindow")
            state.setNoWindow()
        } catch FocusedWindowProvider.ProviderError.noFocusedWindow {
            gojoDebug("executor: caught noFocusedWindow → setNoWindow")
            state.setNoWindow()
        } catch {
            gojoDebug("executor: caught \(error)")
            state.setFailure("Window unavailable", detail: "Focus a normal app window, then try again.")
        }
    }

    private func executeOnTarget(
        _ action: WindowAction,
        target: WindowSummary,
        notchScreen: NSScreen?,
        state: WindowPowerState
    ) async {
        // Bring the target to front via the helper (which has AX), so the user sees the window appear.
        _ = await XPCHelperClient.shared.raiseWindow(pid: target.pid, windowID: target.windowID)
        NSRunningApplication(processIdentifier: target.pid)?.activate(options: [])

        // Display the target window lands on; also where we judge the resulting position.
        let targetScreen = NSScreen.screen(containing: target.normalFrame) ?? notchScreen ?? NSScreen.main
        guard let targetScreen else {
            state.setFailure("Cannot move \(target.appName)", detail: "No usable display.")
            return
        }

        let requestedFrame: CGRect?
        let result: WindowFrameResult
        if action == .zoom {
            requestedFrame = nil
            result = await XPCHelperClient.shared.performZoom(pid: target.pid, windowID: target.windowID)
        } else {
            let frame = WindowFrameCalculator.targetFrame(for: action, in: targetScreen.visibleFrame)
            requestedFrame = frame
            result = await XPCHelperClient.shared.setWindowFrame(frame, pid: target.pid, windowID: target.windowID)
        }

        guard result.success else {
            state.setFailure(
                "Cannot \(action == .zoom ? "reset" : "move") \(target.appName)",
                detail: "macOS would not \(action == .zoom ? "zoom" : "move") this window."
            )
            return
        }

        // The helper read the actual resulting frame back from AX, so we know the
        // true position immediately — no CGWindowList re-enumeration race, no sleep.
        // If a window was constrained (couldn't reach the requested size), the
        // read-back reflects where it actually ended up.
        let actualFrame = result.resultingFrame ?? requestedFrame ?? target.normalFrame
        let actualAction = WindowFrameCalculator.matchingAction(for: actualFrame, in: targetScreen.visibleFrame)
        let constrained = requestedFrame.map { !actualFrame.approximatelyEquals($0, tolerance: 4) } ?? false

        state.appName = target.appName
        state.title = target.appName
        state.windowTitle = target.title
        state.lastAction = actualAction ?? action
        state.preview = WindowLayoutPreview(action: action)
        state.statusKind = constrained ? .warning : .success

        // Patch the moved window's stage-strip summary in place with the ground-truth
        // frame so the identity row and chip highlight update on this first click —
        // the values come from AX, not a lagging re-enumeration.
        if let index = state.windows.firstIndex(where: { $0.id == target.id }) {
            let old = state.windows[index]
            state.windows[index] = WindowSummary(
                id: old.id,
                pid: old.pid,
                windowID: old.windowID,
                appName: old.appName,
                bundleIdentifier: old.bundleIdentifier,
                icon: old.icon,
                title: old.title,
                normalFrame: actualFrame,
                currentAction: actualAction
            )
        }
    }

    private func enumerateWindowsViaHelper(on screen: NSScreen) async -> [WindowSummary] {
        let dicts = await XPCHelperClient.shared.enumerateWindows(screenUUID: screen.displayUUID)
        guard !dicts.isEmpty else { return [] }
        let targetUUID = screen.displayUUID
        let visibleFrame = screen.visibleFrame
        var seen: Set<String> = []

        return dicts.compactMap { dict -> WindowSummary? in
            guard let pid = (dict["pid"] as? NSNumber)?.int32Value else { return nil }
            let windowID = (dict["windowID"] as? NSNumber).map { CGWindowID(truncating: $0) }
            let appName = dict["appName"] as? String ?? "App"
            let bundleIdentifier = (dict["bundleIdentifier"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let normalFrame = (dict["normalFrame"] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero

            // Helper returns windows from all displays; filter to this screen.
            if let uuid = targetUUID,
               NSScreen.screen(containing: normalFrame)?.displayUUID != uuid {
                return nil
            }

            let id = windowID.map { "win-\($0)" } ?? "pid-\(pid)-\(Int(normalFrame.origin.x))-\(Int(normalFrame.origin.y))"
            guard seen.insert(id).inserted else { return nil }

            return WindowSummary(
                id: id,
                pid: pid,
                windowID: windowID,
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                icon: NSRunningApplication(processIdentifier: pid)?.icon,
                title: nil,
                normalFrame: normalFrame,
                currentAction: WindowFrameCalculator.matchingAction(for: normalFrame, in: visibleFrame)
            )
        }
    }
}

/// Resolves which notch `WindowPowerState` shortcuts and drag handlers should target.
@MainActor
enum WindowPowerSession {
    static func contextForMouseLocation() -> (screenUUID: String?, state: WindowPowerState) {
        // NSApp.delegate is SwiftUI's adaptor wrapper, not our AppDelegate — the
        // direct cast always fails under @NSApplicationDelegateAdaptor. Use the
        // explicit shared reference, keeping the cast as a belt-and-braces fallback.
        guard let delegate = AppDelegate.shared ?? (NSApp.delegate as? AppDelegate) else {
            gojoDebug("contextForMouseLocation: AppDelegate unavailable → global fallback")
            return (nil, WindowPowerState.shared)
        }
        let viewModel = delegate.viewModelForCurrentMouseLocation()
        return (viewModel.screenUUID, viewModel.windowPowerState)
    }
}
