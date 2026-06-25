//
//  AltTabModels.swift
//  Gojo
//
//  Value types for the per-display window switcher (alt-tab).
//

import AppKit

struct AltTabItem: Identifiable, Equatable {
    let id: String
    let pid: pid_t
    let windowID: CGWindowID?
    let appName: String
    var title: String?
    let icon: NSImage?

    /// Window title when known, otherwise the app name.
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return appName
    }

    static func == (lhs: AltTabItem, rhs: AltTabItem) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.appName == rhs.appName
    }
}

struct AltTabSession: Equatable {
    var items: [AltTabItem]
    var selectedIndex: Int
    let screenUUID: String?

    var selectedItem: AltTabItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }
}
