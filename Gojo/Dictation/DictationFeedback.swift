import AppKit

enum DictationFeedbackEvent: Equatable, Sendable {
    case ready, delivered, savedForCopying, cancelled, empty, failed
}

@MainActor
enum DictationFeedback {
    static func play(_ event: DictationFeedbackEvent) {
        let name: NSSound.Name
        switch event {
        case .ready: name = "Tink"
        case .delivered: name = "Pop"
        case .savedForCopying: name = "Glass"
        case .cancelled, .empty: name = "Tink"
        case .failed: name = "Morse"
        }
        guard let available = NSSound(named: name), let sound = available.copy() as? NSSound else { return }
        sound.volume = 0.12
        sound.play()
    }
}
