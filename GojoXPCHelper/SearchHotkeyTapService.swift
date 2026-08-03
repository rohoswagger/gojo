//
//  SearchHotkeyTapService.swift
//  GojoXPCHelper
//
//  Global CGEvent tap that intercepts ⌘Space before macOS's symbolic hotkey
//  handling can deliver it to Spotlight. This MUST live in the helper: the
//  main Gojo.app runs under the App Sandbox, and a sandboxed process cannot
//  create a global keyboard event tap even when Accessibility-trusted —
//  CGEvent.tapCreate silently returns nil there. This helper is unsandboxed
//  and holds the Accessibility grant, so the tap is created here instead.
//
//  Since NSXPCListener.service() vends a *new* GojoXPCHelper instance per
//  incoming connection, the tap's lifecycle is owned by this process-wide
//  singleton rather than by any single exported object.
//
//  On a match, the event is consumed and the toggle is broadcast to the main
//  app via DistributedNotificationCenter — the simplest channel from an
//  unsandboxed XPC helper to a sandboxed app that doesn't have a reverse XPC
//  callback wired up (the sandboxed app CAN observe distributed notifications).
//
//  Threading: a CFMachPort run loop source only delivers events on a thread
//  whose CFRunLoop is actually being run. `NSXPCListener.service().resume()`
//  never runs a Foundation/CF run loop on the main thread — incoming XPC
//  messages are dispatched onto libdispatch worker threads instead — so a
//  tap source added on whichever thread happened to handle the
//  `startSearchHotkeyInterception` call would sit on a run loop that's never
//  pumped and would silently never fire. To fix this the tap owns a
//  dedicated, long-lived thread that we explicitly spin up with
//  `CFRunLoopRun()`.
//

import Foundation
import ApplicationServices
import CoreGraphics
import os.log

enum SearchHotkeyDistributedNotification {
    static let toggleName = Notification.Name("rohoswagger.gojo.searchHotkeyToggle")
}

final class SearchHotkeyTapService {
    static let shared = SearchHotkeyTapService()

    // All of the following are shared between the caller's thread (start/stop)
    // and the dedicated tap thread, and are only ever touched under `stateLock`.
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    // Set by stop() (even when it snapshots nil tap/source/run loop state,
    // e.g. stop() lands while the tap thread is still slowly creating the
    // tap). Checked by runTapThread immediately after it publishes
    // eventTap/runLoopSource/tapRunLoop and before it parks in
    // CFRunLoopRun(), so a stop() that raced tap creation still tears the
    // tap down instead of leaving an unstoppable thread parked forever.
    // Cleared at the top of start().
    private var stopRequested = false
    // The per-start authentication token supplied by the caller (see
    // `start(token:)`), echoed into the toggle notification's userInfo so the
    // app-side observer can ignore notifications from other same-user
    // processes. Set by start() on the caller's thread, read by handleEvent
    // on the tap thread, so it goes through `stateLock` like the rest of the
    // cross-thread state above.
    private var activeToken: String?
    private let stateLock = NSLock()

    // Touched ONLY from the tap thread's run loop callback, which is
    // strictly single-threaded, so these need no locking.
    private var suppressingRepeat = false
    private var lastConsumedLogTime: Date?
    private var lastReenableLogTime: Date?
    private let logThrottleInterval: TimeInterval = 1.0

    private let log = OSLog(subsystem: "rohoswagger.gojo.helper", category: "search-hotkey")

    private init() {}

    var isActive: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return eventTap != nil
    }

    private final class TapCreationResult {
        var succeeded = false
    }

    /// Idempotent: safe to call when already running, and safe to call again
    /// after a prior `stop()` (start -> stop -> start). Spawns a dedicated
    /// "SearchHotkeyTap" thread that owns the tap's run loop for the lifetime
    /// of the tap, and blocks (with a short timeout) until that thread reports
    /// whether tap creation actually succeeded, so the return value here
    /// remains truthful for the XPC reply.
    @discardableResult
    func start(token: String) -> Bool {
        stateLock.lock()
        stopRequested = false
        activeToken = token
        if eventTap != nil {
            stateLock.unlock()
            return true
        }
        guard tapThread == nil else {
            os_log("start(): a tap thread is already starting/running, refusing double-start", log: log, type: .error)
            stateLock.unlock()
            return false
        }
        stateLock.unlock()

        guard AXIsProcessTrusted() else {
            os_log("start(): helper is not Accessibility-trusted, refusing to create tap", log: log, type: .error)
            return false
        }

        let readySemaphore = DispatchSemaphore(value: 0)
        let result = TapCreationResult()

        let thread = Thread { [weak self] in
            self?.runTapThread(result: result, readySemaphore: readySemaphore)
        }
        thread.name = "SearchHotkeyTap"
        thread.qualityOfService = .userInteractive

        stateLock.lock()
        tapThread = thread
        stateLock.unlock()

        thread.start()

        // If this times out, `tapThread` is left set (not cleared here) and
        // `stopRequested` is left however it was (false, since we just reset
        // it above and no stop() has run yet). That's the consistent state a
        // later stop()/start() pair recovers from: stop() will see no
        // eventTap/source/runLoop yet, set stopRequested, and poll for
        // tapThread to clear; runTapThread — whenever tap creation actually
        // finishes — will see stopRequested set and tear itself down instead
        // of parking, clearing tapThread in the process.
        guard readySemaphore.wait(timeout: .now() + 2.0) == .success else {
            os_log("start(): timed out waiting for tap thread to report status", log: log, type: .error)
            return false
        }

        return result.succeeded
    }

    /// Body of the dedicated tap thread. Creates the tap, adds its run loop
    /// source to *this* thread's run loop, then parks the thread in
    /// `CFRunLoopRun()` so events are actually delivered. Returns once
    /// `stop()` calls `CFRunLoopStop` on the stored run loop.
    private func runTapThread(result: TapCreationResult, readySemaphore: DispatchSemaphore) {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, cgEvent, userInfo in
                guard let userInfo else { return Unmanaged.passRetained(cgEvent) }
                let service = Unmanaged<SearchHotkeyTapService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handleEvent(type: type, cgEvent)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        guard let tap else {
            os_log("start(): CGEvent.tapCreate returned nil", log: log, type: .error)
            result.succeeded = false
            stateLock.lock()
            tapThread = nil
            stateLock.unlock()
            readySemaphore.signal()
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let runLoop = CFRunLoopGetCurrent()
        if let source {
            CFRunLoopAddSource(runLoop, source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)

        stateLock.lock()
        eventTap = tap
        runLoopSource = source
        tapRunLoop = runLoop
        let shouldTearDownImmediately = stopRequested
        stateLock.unlock()

        #if DEBUG
        os_log("start(): event tap created and enabled on dedicated thread", log: log, type: .default)
        #endif
        result.succeeded = true
        readySemaphore.signal()

        // stop() raced tap creation and gave up waiting for us before we
        // published eventTap/runLoopSource/tapRunLoop above. Tear the tap
        // down right here instead of parking in CFRunLoopRun() forever with
        // no owner left to stop it.
        if shouldTearDownImmediately {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            if let source {
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
            }
            stateLock.lock()
            eventTap = nil
            runLoopSource = nil
            tapThread = nil
            tapRunLoop = nil
            stateLock.unlock()
            return
        }

        // Parks this thread until stop() calls CFRunLoopStop(runLoop).
        CFRunLoopRun()

        stateLock.lock()
        tapThread = nil
        tapRunLoop = nil
        stateLock.unlock()
    }

    /// Invalidates the tap, removes its source, and stops the dedicated
    /// thread's run loop (letting the thread exit). `CFRunLoopStop` is
    /// thread-safe, so this may be called from any thread. Blocks briefly
    /// until the tap thread has actually finished, so an immediate
    /// `start()` afterwards is safe.
    func stop() {
        stateLock.lock()
        let tap = eventTap
        let source = runLoopSource
        let runLoop = tapRunLoop
        eventTap = nil
        runLoopSource = nil
        // Set unconditionally, even when the snapshot above is nil (tap
        // creation still in flight on the tap thread) — runTapThread checks
        // this before parking so that race doesn't leak an unstoppable tap.
        stopRequested = true
        stateLock.unlock()

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source, let runLoop {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
        }

        // Wait for the tap thread to actually exit CFRunLoopRun() and clear
        // itself out, so a subsequent start() doesn't race the double-start
        // guard against a thread that's still tearing down.
        let deadline = Date().addingTimeInterval(1.0)
        while true {
            stateLock.lock()
            let threadStillRunning = tapThread != nil
            stateLock.unlock()
            guard threadStillRunning, Date() < deadline else { break }
            Thread.sleep(forTimeInterval: 0.005)
        }
    }

    private func handleEvent(type: CGEventType, _ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stateLock.lock()
            let tap = eventTap
            stateLock.unlock()
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                if type == .tapDisabledByTimeout {
                    logThrottled(&lastReenableLogTime, "tapDisabledByTimeout: re-enabled event tap")
                }
            }
            return Unmanaged.passRetained(cgEvent)
        }

        guard type == .keyDown else {
            return Unmanaged.passRetained(cgEvent)
        }

        let keycode = cgEvent.getIntegerValueField(.keyboardEventKeycode)
        let isCommandSpace = SearchHotkeyMatch.isCommandSpace(keyCode: keycode, flags: cgEvent.flags)

        guard isCommandSpace else {
            suppressingRepeat = false
            return Unmanaged.passRetained(cgEvent)
        }

        let isRepeat = cgEvent.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isRepeat && suppressingRepeat {
            return nil
        }

        suppressingRepeat = true
        stateLock.lock()
        let token = activeToken
        stateLock.unlock()
        DistributedNotificationCenter.default().postNotificationName(
            SearchHotkeyDistributedNotification.toggleName,
            object: nil,
            userInfo: token.map { ["token": $0] },
            deliverImmediately: true
        )
        logThrottled(&lastConsumedLogTime, "match: consumed cmd+space, notifying app")
        return nil
    }

    /// Only called from the tap thread's single-threaded run loop callback,
    /// so `lastTime` needs no synchronization. DEBUG-only: fires on every
    /// re-enable/match, which would otherwise spam release logs on every
    /// ⌘Space.
    private func logThrottled(_ lastTime: inout Date?, _ message: String) {
        #if DEBUG
        let now = Date()
        if let lastTime, now.timeIntervalSince(lastTime) < logThrottleInterval {
            return
        }
        lastTime = now
        os_log("%{public}@", log: log, type: .default, message)
        #endif
    }
}
