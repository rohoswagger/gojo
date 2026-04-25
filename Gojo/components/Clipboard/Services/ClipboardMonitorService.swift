import AppKit

struct ClipboardCapture {
    let content: String
    let sourceAppName: String?
    let sourceBundleID: String?
    let fingerprint: String
}

final class ClipboardMonitorService {
    static let shared = ClipboardMonitorService()

    var onCapture: ((ClipboardCapture) -> Void)?

    private let queue = DispatchQueue(label: "rohoswagger.gojo.clipboard-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastChangeCount = NSPasteboard.general.changeCount

    private init() {}

    func start() {
        guard timer == nil else { return }
        syncChangeCountToCurrentPasteboard()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + .milliseconds(250),
            repeating: .milliseconds(250),
            leeway: .milliseconds(75)
        )
        timer.setEventHandler { [weak self] in
            self?.pollPasteboard()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func syncChangeCountToCurrentPasteboard() {
        queue.sync {
            lastChangeCount = NSPasteboard.general.changeCount
        }
    }

    private func pollPasteboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount

        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        guard let capture = extractCapture(from: pasteboard) else { return }
        Task { @MainActor [weak self] in
            self?.onCapture?(capture)
        }
    }

    private func extractCapture(from pasteboard: NSPasteboard) -> ClipboardCapture? {
        guard let text = pasteboard.string(forType: .string),
              !text.isEmpty else {
            return nil
        }

        let sourceApp = NSWorkspace.shared.frontmostApplication
        return ClipboardCapture(
            content: text,
            sourceAppName: sourceApp?.localizedName,
            sourceBundleID: sourceApp?.bundleIdentifier,
            fingerprint: text
        )
    }
}
