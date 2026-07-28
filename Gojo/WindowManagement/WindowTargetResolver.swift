import CoreGraphics
import Foundation

enum WindowTargetActivationPolicy: Equatable {
    case regular
    case accessory
    case prohibited
    case unknown
}

struct WindowTargetApplicationSnapshot: Equatable {
    let pid: pid_t
    let bundleIdentifier: String?
    let activationPolicy: WindowTargetActivationPolicy
    let isTerminated: Bool
}

struct WindowTargetWindowSnapshot: Equatable {
    let windowID: CGWindowID?
    let pid: pid_t
    let ownerName: String?
    let layer: Int
    let bounds: CGRect

    init(windowID: CGWindowID? = nil, pid: pid_t, ownerName: String?, layer: Int, bounds: CGRect) {
        self.windowID = windowID
        self.pid = pid
        self.ownerName = ownerName
        self.layer = layer
        self.bounds = bounds
    }

    init?(cgWindowInfo: [String: Any]) {
        guard let pid = WindowTargetResolver.pidValue(cgWindowInfo[kCGWindowOwnerPID as String]),
              let layer = WindowTargetResolver.intValue(cgWindowInfo[kCGWindowLayer as String]),
              let bounds = WindowTargetResolver.rectValue(cgWindowInfo[kCGWindowBounds as String]) else {
            return nil
        }

        self.init(
            windowID: WindowTargetResolver.cgWindowIDValue(cgWindowInfo[kCGWindowNumber as String]),
            pid: pid,
            ownerName: cgWindowInfo[kCGWindowOwnerName as String] as? String,
            layer: layer,
            bounds: bounds
        )
    }
}

struct DictationApplicationPasteTarget: Equatable, Sendable {
    let pid: pid_t
    let windowID: CGWindowID
}

enum WindowTargetResolver {
    static let guardedApplicationPasteBundleIDs: Set<String> = []

#if DEBUG
    static let guardedUnicodeTypingBundleIDs: Set<String> = [
        "com.openai.codex",
        "com.zarifpour.superconductor",
        "rohoswagger.gojo.UnicodeTypingE2EFixture",
    ]
#else
    static let guardedUnicodeTypingBundleIDs: Set<String> = [
        "com.openai.codex",
        "com.zarifpour.superconductor",
    ]
#endif

    static let axOpaqueDictationBundleIDs: Set<String> =
        guardedApplicationPasteBundleIDs.union(guardedUnicodeTypingBundleIDs)

    private static let excludedOwners: Set<String> = [
        "Dock",
        "WindowServer",
        "Notification Center",
        "Control Center",
        "Gojo"
    ]

    static func resolve(
        frontmost: WindowTargetApplicationSnapshot?,
        lastTarget: WindowTargetApplicationSnapshot?,
        topWindows: [WindowTargetWindowSnapshot],
        applicationsByPID: [pid_t: WindowTargetApplicationSnapshot],
        ownPID: pid_t,
        ownBundleID: String?
    ) -> pid_t? {
        resolve(
            frontmost: frontmost,
            lastTarget: lastTarget,
            topWindows: topWindows,
            applicationsByPID: applicationsByPID,
            ownPID: ownPID,
            excludedBundleIDs: Set([ownBundleID].compactMap { $0 })
        )
    }

    static func resolve(
        frontmost: WindowTargetApplicationSnapshot?,
        lastTarget: WindowTargetApplicationSnapshot?,
        topWindows: [WindowTargetWindowSnapshot],
        applicationsByPID: [pid_t: WindowTargetApplicationSnapshot],
        ownPID: pid_t,
        excludedBundleIDs: Set<String>
    ) -> pid_t? {
        if let frontmost, isTargetApplication(frontmost, ownPID: ownPID, excludedBundleIDs: excludedBundleIDs) {
            return frontmost.pid
        }

        if let lastTarget, isTargetApplication(lastTarget, ownPID: ownPID, excludedBundleIDs: excludedBundleIDs) {
            return lastTarget.pid
        }

        return topWindows.first { window in
            guard isTopLevelWindow(window, ownPID: ownPID),
                  let app = applicationsByPID[window.pid] else {
                return false
            }
            return isTargetApplication(app, ownPID: ownPID, excludedBundleIDs: excludedBundleIDs)
        }?.pid
    }

    static func isTargetApplication(
        _ app: WindowTargetApplicationSnapshot,
        ownPID: pid_t,
        ownBundleID: String?
    ) -> Bool {
        isTargetApplication(
            app,
            ownPID: ownPID,
            excludedBundleIDs: Set([ownBundleID].compactMap { $0 })
        )
    }

    static func isTargetApplication(
        _ app: WindowTargetApplicationSnapshot,
        ownPID: pid_t,
        excludedBundleIDs: Set<String>
    ) -> Bool {
        guard !app.isTerminated else { return false }
        guard app.pid != ownPID else { return false }
        if let bundleIdentifier = app.bundleIdentifier,
           excludedBundleIDs.contains(bundleIdentifier) {
            return false
        }
        return app.activationPolicy == .regular || app.activationPolicy == .accessory
    }

    static func isTopLevelWindow(_ window: WindowTargetWindowSnapshot, ownPID: pid_t) -> Bool {
        guard window.pid != ownPID else { return false }
        guard window.layer == 0 else { return false }
        guard window.bounds.width > 0, window.bounds.height > 0 else { return false }
        if let ownerName = window.ownerName, excludedOwners.contains(ownerName) {
            return false
        }
        return true
    }

    static func topmostApplicationPasteTarget(
        topWindows: [WindowTargetWindowSnapshot],
        applicationsByPID: [pid_t: WindowTargetApplicationSnapshot],
        ownPID: pid_t,
        excludedBundleIDs: Set<String>,
        allowedBundleIDs: Set<String>
    ) -> DictationApplicationPasteTarget? {
        for window in topWindows {
            guard isTopLevelWindow(window, ownPID: ownPID),
                  window.bounds.width >= 120,
                  window.bounds.height >= 80,
                  let windowID = window.windowID,
                  windowID != 0,
                  let application = applicationsByPID[window.pid],
                  isTargetApplication(
                      application,
                      ownPID: ownPID,
                      excludedBundleIDs: excludedBundleIDs
                  ) else {
                continue
            }
            guard let bundleIdentifier = application.bundleIdentifier,
                  allowedBundleIDs.contains(bundleIdentifier) else {
                return nil
            }
            return DictationApplicationPasteTarget(
                pid: window.pid,
                windowID: windowID
            )
        }
        return nil
    }

    static func shouldUsePreferredApplicationPasteTarget(
        preferredPID: pid_t?,
        focusedCandidatePIDs: [pid_t]
    ) -> Bool {
        guard let preferredPID, preferredPID != 0 else {
            return false
        }
        return !focusedCandidatePIDs.contains(preferredPID)
    }

    static func isCapturedWindowTopmost(
        targetPID: pid_t,
        targetWindowID: CGWindowID,
        topWindows: [WindowTargetWindowSnapshot],
        ownPID: pid_t
    ) -> Bool {
        let applicationWindows = topWindows.filter {
            $0.pid == targetPID && isTopLevelWindow($0, ownPID: ownPID)
        }
        guard let capturedIndex = applicationWindows.firstIndex(where: {
            $0.windowID == targetWindowID
        }) else {
            return false
        }

        return !applicationWindows[..<capturedIndex].contains {
            $0.bounds.width >= 120 && $0.bounds.height >= 80
        }
    }

    static func displayIndex(
        containing frame: CGRect,
        displayBounds: [CGRect]
    ) -> Int? {
        guard !frame.isNull, frame.width > 0, frame.height > 0 else {
            return nil
        }

        return displayBounds.enumerated().compactMap {
            index,
            bounds -> (index: Int, area: CGFloat)? in
            let intersection = bounds.intersection(frame)
            guard !intersection.isNull,
                  intersection.width > 0,
                  intersection.height > 0 else {
                return nil
            }
            return (
                index: index,
                area: intersection.width * intersection.height
            )
        }.max { lhs, rhs in
            lhs.area < rhs.area
        }?.index
    }

    static func windowID(
        containing controlFrame: CGRect,
        targetPID: pid_t,
        topWindows: [WindowTargetWindowSnapshot],
        ownPID: pid_t
    ) -> CGWindowID? {
        guard !controlFrame.isNull,
              controlFrame.width > 0,
              controlFrame.height > 0 else {
            return nil
        }

        return topWindows.compactMap {
            window -> (windowID: CGWindowID, area: CGFloat)? in
            guard window.pid == targetPID,
                  isTopLevelWindow(window, ownPID: ownPID),
                  let windowID = window.windowID else {
                return nil
            }
            let intersection = window.bounds.intersection(controlFrame)
            guard !intersection.isNull,
                  intersection.width > 0,
                  intersection.height > 0 else {
                return nil
            }
            return (
                windowID,
                intersection.width * intersection.height
            )
        }.max { lhs, rhs in
            lhs.area < rhs.area
        }?.windowID
    }

    static func pidValue(_ value: Any?) -> pid_t? {
        if let pid = value as? pid_t { return pid }
        if let number = value as? NSNumber { return pid_t(truncating: number) }
        if let int = value as? Int { return pid_t(int) }
        if let int32 = value as? Int32 { return pid_t(int32) }
        return nil
    }

    static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let int32 = value as? Int32 { return Int(int32) }
        return nil
    }

    static func cgWindowIDValue(_ value: Any?) -> CGWindowID? {
        if let windowID = value as? CGWindowID { return windowID }
        if let number = value as? NSNumber { return CGWindowID(truncating: number) }
        if let int = value as? Int { return CGWindowID(int) }
        if let uint32 = value as? UInt32 { return CGWindowID(uint32) }
        return nil
    }

    static func rectValue(_ value: Any?) -> CGRect? {
        if let rect = value as? CGRect { return rect }
        if let dictionary = value as? NSDictionary {
            return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
        }
        return nil
    }
}
