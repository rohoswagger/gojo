//
//  AltTabHotKeyMonitor.swift
//  Gojo
//
//  Global CGEvent tap that drives the per-display window switcher. Mirrors the
//  proven in-process tap setup in MediaKeyInterceptor. While enabled with the
//  Command modifier it disables the native ⌘-Tab application switcher via the
//  private CGS symbolic-hotkey API.
//

import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import Defaults

// Private SkyLight API used to enable/disable the system application switcher.
@_silgen_name("CGSSetSymbolicHotKeyEnabled")
private func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ isEnabled: Bool) -> Int32

// The macOS application-switcher symbolic hotkeys: 35 = ⌘-Tab (forward),
// 36 = ⌘-Shift-Tab (reverse). Same values AltTab (lwouis) uses.
private let kAppSwitcherForwardHotKey: Int32 = 35
private let kAppSwitcherReverseHotKey: Int32 = 36

@MainActor
final class AltTabHotKeyMonitor {
    static let shared = AltTabHotKeyMonitor()

    private let kVKTab: Int64 = 48
    private let kVKEscape: Int64 = 53

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // True only while *we* have disabled the native ⌘-Tab switcher, so restore
    // re-enables exactly what we turned off and never clobbers a switcher the
    // user (or another tool) disabled themselves.
    private var didDisableNativeSwitcher = false

    // Cached settings, refreshed on start(). The event tap fires for every
    // keystroke system-wide, so we keep Defaults lookups out of handleEvent.
    // AltTabManager restarts the monitor whenever these keys change.
    private var enabled = false
    private var modifier: AltTabModifierKey = .command
    private var reverseWithShift = true

    private init() {}

    // MARK: - Event Tap

    /// Idempotent: safe to call when already running. Re-reads settings and
    /// re-applies the native-switcher state, so changing the trigger modifier
    /// while enabled takes effect without a manual restart.
    func start(promptIfNeeded: Bool = false) async {
        guard Defaults[.altTabEnabled] else {
            stop()
            return
        }
        refreshSettingsCache()

        if eventTap == nil {
            let authorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
            if !authorized {
                if promptIfNeeded {
                    let granted = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
                    guard granted else { return }
                } else {
                    return
                }
            }
            createEventTap()
            guard eventTap != nil else { return }
        }

        applyNativeSwitcherState()
    }

    private func createEventTap() {
        let mask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue))
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, cgEvent, userInfo in
                guard let userInfo else { return Unmanaged.passRetained(cgEvent) }
                let monitor = Unmanaged<AltTabHotKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handleEvent(type: type, cgEvent)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        guard let eventTap else { return }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func refreshSettingsCache() {
        enabled = Defaults[.altTabEnabled]
        modifier = Defaults[.altTabModifier]
        reverseWithShift = Defaults[.altTabReverseWithShift]
    }

    func stop() {
        enabled = false
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        restoreNativeSwitcher()
    }

    // MARK: - Native switcher

    /// Disables the native ⌘-Tab switcher when our trigger is Command, and
    /// restores it otherwise — so toggling the modifier while enabled leaves the
    /// system in the right state in both directions.
    private func applyNativeSwitcherState() {
        if modifier == .command {
            _ = CGSSetSymbolicHotKeyEnabled(kAppSwitcherForwardHotKey, false)
            _ = CGSSetSymbolicHotKeyEnabled(kAppSwitcherReverseHotKey, false)
            didDisableNativeSwitcher = true
        } else {
            restoreNativeSwitcher()
        }
    }

    /// Re-enables the native ⌘-Tab switcher, but only if *we* disabled it. MUST
    /// run on stop and on app termination — the symbolic-hotkey change persists
    /// system-wide, so leaving it disabled would rob the user of ⌘-Tab until they
    /// log out. The guard keeps us from re-enabling a switcher the user disabled
    /// themselves.
    func restoreNativeSwitcher() {
        guard didDisableNativeSwitcher else { return }
        _ = CGSSetSymbolicHotKeyEnabled(kAppSwitcherForwardHotKey, true)
        _ = CGSSetSymbolicHotKeyEnabled(kAppSwitcherReverseHotKey, true)
        didDisableNativeSwitcher = false
    }

    // MARK: - Event Handling

    // The tap's run-loop source is on the main run loop (see createEventTap), so
    // this callback always fires on the main thread. It's `nonisolated` so the
    // @convention(c) tap callback can call it, and the whole body runs inside
    // `assumeIsolated` to safely touch this MainActor-isolated type's cached
    // settings and the manager.
    nonisolated private func handleEvent(type: CGEventType, _ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        MainActor.assumeIsolated {
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
                return Unmanaged.passRetained(cgEvent)
            }

            guard enabled else {
                return Unmanaged.passRetained(cgEvent)
            }

            let modMask: CGEventFlags = modifier == .command
                ? .maskCommand
                : (modifier == .option ? .maskAlternate : .maskControl)
            let flags = cgEvent.flags
            let modifierDown = flags.contains(modMask)

            let consumed: Bool

            switch type {
            case .flagsChanged:
                if AltTabManager.shared.session != nil && !modifierDown {
                    AltTabManager.shared.commit()
                }
                consumed = false

            case .keyDown:
                let keycode = cgEvent.getIntegerValueField(.keyboardEventKeycode)
                if keycode == kVKTab && modifierDown {
                    let reverse = flags.contains(.maskShift) && reverseWithShift
                    AltTabManager.shared.handleTrigger(reverse: reverse)
                    consumed = true
                } else if keycode == kVKEscape {
                    let open = AltTabManager.shared.session != nil
                    if open { AltTabManager.shared.cancel() }
                    consumed = open
                } else {
                    consumed = false
                }

            default:
                consumed = false
            }

            return consumed ? nil : Unmanaged.passRetained(cgEvent)
        }
    }
}
