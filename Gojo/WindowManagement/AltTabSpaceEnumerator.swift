//
//  AltTabSpaceEnumerator.swift
//  Gojo
//
//  Cross-Space window discovery for the per-display window switcher.
//
//  The standard CGWindowList enumeration (FocusedWindowProvider) uses
//  `.optionOnScreenOnly`, which only returns windows on each display's
//  *currently active* Space. Fullscreen apps — and windows parked on other
//  Spaces of a display — each live in their own Space, so they're invisible to
//  that path. This enumerator uses the private CoreGraphics/SkyLight Spaces API
//  to list every window assigned to a display's Spaces (fullscreen included),
//  so the switcher can offer them too.
//
//  This is purely additive: callers union these results with the on-screen
//  enumeration, so if the private API ever returns nothing we simply fall back
//  to today's behavior.
//

import AppKit

private typealias CGSConnectionID = UInt

@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> CGSConnectionID

// Both are CoreGraphics "Copy" functions (caller owns the +1 result), so they
// return `Unmanaged` and we balance the retain with `takeRetainedValue()`.
// Declaring them as a plain `CFArray` return would leak one array per call.
@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> Unmanaged<CFArray>?

@_silgen_name("CGSCopyWindowsWithOptionsAndTags")
private func CGSCopyWindowsWithOptionsAndTags(
    _ cid: CGSConnectionID,
    _ owner: UInt32,
    _ spaces: CFArray,
    _ options: UInt32,
    _ setTags: UnsafeMutablePointer<UInt64>,
    _ clearTags: UnsafeMutablePointer<UInt64>
) -> Unmanaged<CFArray>?

enum AltTabSpaceEnumerator {
    /// Window IDs (front-to-back) assigned to every Space of the given screen,
    /// across all Spaces — including fullscreen Spaces.
    @MainActor
    static func windowIDs(on screen: NSScreen) -> [CGWindowID] {
        let cid = _CGSDefaultConnection()
        guard let displays = CGSCopyManagedDisplaySpaces(cid)?.takeRetainedValue() as? [[String: Any]] else { return [] }

        let targetUUID = screen.displayUUID
        let isMainScreen = (screen == NSScreen.main)

        var spaceIDs: [Int] = []
        for display in displays {
            let identifier = display["Display Identifier"] as? String
            // The main display is sometimes reported as "Main" rather than its UUID.
            let matches = (identifier != nil && identifier == targetUUID)
                || (isMainScreen && identifier == "Main")
            guard matches else { continue }

            let spaces = display["Spaces"] as? [[String: Any]] ?? []
            spaceIDs.append(contentsOf: spaces.compactMap(Self.spaceID(from:)))
        }

        guard !spaceIDs.isEmpty else { return [] }

        var setTags: UInt64 = 0
        var clearTags: UInt64 = 0
        // owner 0 + options 2: every window assigned to the listed Spaces, in
        // z-order. Matches AltTab's cross-Space enumeration.
        let windows = CGSCopyWindowsWithOptionsAndTags(
            cid, 0, spaceIDs as CFArray, 2, &setTags, &clearTags
        )?.takeRetainedValue() as? [CGWindowID] ?? []
        return windows
    }

    /// Turn raw cross-Space window IDs into switcher items, applying the same
    /// top-level/app filters the on-screen enumeration uses so the two lists are
    /// consistent.
    ///
    /// Note: `CGWindowListCreateDescriptionFromArray` does NOT work for these
    /// cross-Space IDs (it only describes on-screen windows and rejects the
    /// bridged CFNumber array). Instead we pull the full window list once — which
    /// does include off-screen/other-Space windows — and index it by number.
    @MainActor
    static func items(on screen: NSScreen) -> [AltTabItem] {
        let ids = windowIDs(on: screen)
        guard !ids.isEmpty,
              let all = CGWindowListCopyWindowInfo([], kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        var infoByNumber: [CGWindowID: [String: Any]] = [:]
        for info in all {
            if let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value {
                infoByNumber[CGWindowID(number)] = info
            }
        }

        let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        var seen = Set<CGWindowID>()
        var items: [AltTabItem] = []

        for wid in ids {
            guard let info = infoByNumber[wid],
                  let snapshot = WindowTargetWindowSnapshot(cgWindowInfo: info),
                  let windowID = snapshot.windowID,
                  WindowTargetResolver.isTopLevelWindow(snapshot, ownPID: ownPID),
                  snapshot.bounds.width >= 200, snapshot.bounds.height >= 120,
                  let app = NSRunningApplication(processIdentifier: snapshot.pid),
                  app.activationPolicy == .regular,
                  !app.isTerminated,
                  seen.insert(windowID).inserted
            else { continue }

            items.append(
                AltTabItem(
                    id: "win-\(windowID)",
                    pid: snapshot.pid,
                    windowID: windowID,
                    appName: app.localizedName ?? snapshot.ownerName ?? "App",
                    title: nil,
                    icon: app.icon
                )
            )
        }
        return items
    }

    private static func spaceID(from space: [String: Any]) -> Int? {
        if let id = space["ManagedSpaceID"] as? Int { return id }
        if let id = space["id64"] as? Int { return id }
        if let id = space["ID"] as? Int { return id }
        return nil
    }
}
