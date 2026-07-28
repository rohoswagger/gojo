import ApplicationServices
@preconcurrency import CoreGraphics
import Foundation
import os

@MainActor
final class DictationModifierHotKeyMonitor {
    static let shared = DictationModifierHotKeyMonitor()

    private let logger = Logger(
        subsystem: "rohoswagger.gojo.dictation",
        category: "shortcut"
    )
    private let activationDelay: Duration = .milliseconds(75)

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activationTask: Task<Void, Never>?
    private var machine = DictationModifierShortcutStateMachine(
        mode: DictationActivationMode.saved()
    )
    private var isStarting = false
    private var startGeneration: UInt = 0

    private init() {}

    var activationMode: DictationActivationMode {
        machine.mode
    }

    var isMonitoring: Bool {
        eventTap != nil
    }

    func setActivationMode(_ mode: DictationActivationMode) {
        mode.save()
        let action = machine.setMode(mode)
        if action != .none {
            activationTask?.cancel()
            activationTask = nil
        }
        apply(action)
    }

    func cancelCurrentSession() {
        resetShortcutState()
    }

    func start(promptIfNeeded: Bool = false) async {
        guard eventTap == nil, !isStarting else { return }
        isStarting = true
        startGeneration &+= 1
        let generation = startGeneration
        defer { isStarting = false }

        let authorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        guard startGeneration == generation else { return }
        if !authorized {
            guard promptIfNeeded else {
                logger.error("monitor start failed: accessibility permission missing")
                return
            }
            let granted = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
            guard startGeneration == generation else { return }
            guard granted else {
                logger.error("monitor start failed: accessibility permission denied")
                return
            }
        }

        guard eventTap == nil, startGeneration == generation else { return }
        createEventTap()
    }

    func stop() {
        startGeneration &+= 1
        resetShortcutState()

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func createEventTap() {
        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue)
                | (1 << CGEventType.keyDown.rawValue)
        )
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<DictationModifierHotKeyMonitor>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        guard let eventTap else {
            logger.error("monitor start failed: event tap unavailable")
            return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        logger.notice("monitor started chord=control+option")
    }

    nonisolated private func handle(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        MainActor.assumeIsolated {
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                resetShortcutState()
                if let eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            switch type {
            case .flagsChanged:
                let flags = event.flags
                let controlDown = flags.contains(.maskControl)
                let optionDown = flags.contains(.maskAlternate)
                let disallowedFlags: CGEventFlags = [.maskCommand, .maskShift, .maskSecondaryFn]
                let hasDisallowedModifiers = !flags.intersection(disallowedFlags).isEmpty
                let exactChord = controlDown
                    && optionDown
                    && !hasDisallowedModifiers
                apply(machine.handle(.flagsChanged(
                    isExactChord: exactChord,
                    anyTriggerModifierDown: controlDown || optionDown,
                    hasDisallowedModifiers: hasDisallowedModifiers
                )))

            case .keyDown:
                apply(machine.handle(.keyDown))

            default:
                break
            }

            return Unmanaged.passRetained(event)
        }
    }

    private func apply(_ action: DictationModifierShortcutStateMachine.Action) {
        switch action {
        case .none:
            break

        case .scheduleActivation:
            logger.debug("event=arming chord=control+option")
            activationTask?.cancel()
            let delay = activationDelay
            activationTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                guard let self else { return }
                self.activationTask = nil
                self.apply(self.machine.handle(.activationDelayElapsed))
            }

        case .cancelScheduledActivation:
            logger.debug("event=disarmed chord=control+option")
            activationTask?.cancel()
            activationTask = nil

        case .beginDictation:
            logger.notice("event=keyDown chord=control+option mode=\(self.machine.mode.rawValue, privacy: .public)")
            GojoDictationService.sendShortcutEvent(.keyDown)

        case .finishDictation:
            logger.notice("event=keyUp chord=control+option mode=\(self.machine.mode.rawValue, privacy: .public)")
            GojoDictationService.sendShortcutEvent(.keyUp)

        case .cancelDictation:
            logger.notice("event=cancel chord=control+option")
            GojoDictationService.sendShortcutEvent(.cancel)
        }
    }

    private func resetShortcutState() {
        let action = machine.reset()
        activationTask?.cancel()
        activationTask = nil
        apply(action)
    }
}
