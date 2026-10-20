//
//  FullscreenMediaDetection.swift
//  Gojo
//
//  Created by Richard Kunkli on 06/09/2024.
//

import AppKit
import Foundation
import Combine
import MacroVisionKit

@MainActor
final class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()
    
    @Published var fullscreenStatus: [String: Bool] = [:]
    
    private var monitorTask: Task<Void, Never>?
    private var windowMonitorTask: Task<Void, Never>?
    private var fullscreenSpaces: [MacroVisionKit.FullScreenMonitor.SpaceInfo] = []
    
    private init() {
        startMonitoring()
    }
    
    deinit {
        monitorTask?.cancel()
        windowMonitorTask?.cancel()
    }
    
    private func startMonitoring() {
        windowMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refreshStatus()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        monitorTask = Task { @MainActor in
            let stream = await FullScreenMonitor.shared.spaceChanges()
            for await spaces in stream {
                updateStatus(with: spaces)
            }
        }
    }
    
    private func updateStatus(with spaces: [MacroVisionKit.FullScreenMonitor.SpaceInfo]) {
        fullscreenSpaces = spaces
        refreshStatus()
    }

    private func refreshStatus() {
        var newStatus: [String: Bool] = [:]
        for space in fullscreenSpaces {
            if let uuid = space.screenUUID {
                newStatus[uuid] = true
            }
        }

        if let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            let windows = windowInfo.compactMap { WindowTargetWindowSnapshot(cgWindowInfo: $0) }
                .filter { WindowTargetResolver.isTopLevelWindow($0, ownPID: ProcessInfo.processInfo.processIdentifier) }
            let appKitWindowFrames = windows.map { $0.bounds.gojoScreenFlipped }
            let appKitScreenFrames = NSScreen.screens.map(\.frame)
            for (uuid, screen) in NSScreen.screensByUUID {
                guard let index = NotchAutoHidePolicy.topWindowIndex(
                    appKitWindowFrames: appKitWindowFrames,
                    appKitScreenFrames: appKitScreenFrames,
                    targetAppKitScreenFrame: screen.frame
                ) else { continue }
                if NotchAutoHidePolicy.coversFullHeight(
                    appKitWindowFrame: appKitWindowFrames[index],
                    appKitScreenFrame: screen.frame,
                    appKitVisibleFrame: screen.visibleFrame,
                    notchWidth: getClosedNotchSize(screenUUID: uuid).width
                ) {
                    newStatus[uuid] = true
                }
            }
        }

        if fullscreenStatus != newStatus {
            fullscreenStatus = newStatus
        }
    }
}
