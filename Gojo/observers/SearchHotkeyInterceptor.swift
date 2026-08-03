//
//  SearchHotkeyInterceptor.swift
//  Gojo
//
//  Thin client for the ⌘Space Spotlight override. The actual CGEvent tap is
//  created in GojoXPCHelper (see SearchHotkeyTapService there), not here:
//  Gojo.app runs under the App Sandbox, and a sandboxed process cannot create
//  a global keyboard event tap — CGEvent.tapCreate silently returns nil even
//  when Accessibility is granted. Only the unsandboxed, Accessibility-trusted
//  helper can install the tap.
//
//  This class asks the helper to start/stop that tap and observes the
//  distributed notification the helper posts when it sees a ⌘Space match, then
//  toggles the search panel on the main thread.
//

import Foundation
import AppKit
import Defaults
import os

private let searchHotkeyLogger = Logger(
    subsystem: "rohoswagger.gojo.search",
    category: "hotkey-interceptor"
)

@MainActor
final class SearchHotkeyInterceptor {
    static let shared = SearchHotkeyInterceptor()

    /// True once the helper confirms its event tap is active. Exposed so
    /// settings UI can show a "needs Accessibility" affordance when the
    /// override is on but the helper couldn't create the tap.
    private(set) var isActive = false

    private var observer: NSObjectProtocol?
    private var startTask: Task<Void, Never>?

    /// The per-start token most recently handed to the helper. The toggle
    /// notification's userInfo is compared against this before acting on it,
    /// so a same-user process posting the (unauthenticated) distributed
    /// notification name can't trigger the toggle.
    private var activeToken: String?

    private init() {}

    // MARK: - Lifecycle

    /// Idempotent: safe to call when already running.
    func start(promptIfNeeded: Bool = false) async {
        #if DEBUG
        searchHotkeyLogger.notice("start() called: searchEnabled=\(Defaults[.searchEnabled], privacy: .public) overrideCommandSpace=\(Defaults[.searchOverrideCommandSpace], privacy: .public) promptIfNeeded=\(promptIfNeeded, privacy: .public) AXIsProcessTrusted(mainApp)=\(AXIsProcessTrusted(), privacy: .public)")
        #endif

        guard Defaults[.searchEnabled], Defaults[.searchOverrideCommandSpace] else {
            stop()
            return
        }

        registerObserverIfNeeded()

        let authorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        #if DEBUG
        searchHotkeyLogger.notice("XPCHelperClient.isAccessibilityAuthorized() (helper process) = \(authorized, privacy: .public)")
        #endif
        if !authorized {
            if promptIfNeeded {
                let granted = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
                #if DEBUG
                searchHotkeyLogger.notice("ensureAccessibilityAuthorization(promptIfNeeded: true) = \(granted, privacy: .public)")
                #endif
                guard granted else { return }
            } else {
                #if DEBUG
                searchHotkeyLogger.notice("not authorized and promptIfNeeded=false, bailing out before asking helper to start the tap")
                #endif
                return
            }
        }

        let token = UUID().uuidString
        activeToken = token
        let active = await XPCHelperClient.shared.startSearchHotkeyInterception(token: token)
        #if DEBUG
        searchHotkeyLogger.notice("helper startSearchHotkeyInterception() = \(active, privacy: .public)")
        #endif
        isActive = active
    }

    func stop() {
        XPCHelperClient.shared.stopSearchHotkeyInterception()
        isActive = false
        activeToken = nil
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
            self.observer = nil
        }
    }

    // MARK: - Distributed notification

    private func registerObserverIfNeeded() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: SearchHotkeyDistributedNotification.toggleName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let receivedToken = notification.userInfo?["token"] as? String
            Task { @MainActor in
                guard let activeToken = self.activeToken, receivedToken == activeToken else {
                    #if DEBUG
                    searchHotkeyLogger.notice("ignoring ⌘Space toggle notification: token mismatch")
                    #endif
                    return
                }
                #if DEBUG
                searchHotkeyLogger.notice("received ⌘Space toggle notification from helper")
                #endif
                guard Defaults[.searchEnabled], Defaults[.searchOverrideCommandSpace] else { return }
                SearchPanelController.shared.toggle()
            }
        }
    }
}

/// Mirrors the name declared in GojoXPCHelper/SearchHotkeyTapService.swift.
/// Kept in sync manually since the two targets don't share that file.
enum SearchHotkeyDistributedNotification {
    static let toggleName = Notification.Name("rohoswagger.gojo.searchHotkeyToggle")
}
