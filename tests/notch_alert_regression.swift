import Foundation
import SwiftUI

var failures = 0

func assertCondition(_ condition: Bool, _ message: String) {
    if !condition {
        FileHandle.standardError.write("Assertion failed: \(message)\n".data(using: .utf8)!)
        failures += 1
    }
}

func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        FileHandle.standardError.write(
            "Assertion failed: \(message). Expected \(rhs), got \(lhs)\n".data(using: .utf8)!
        )
        failures += 1
    }
}

@main
struct NotchAlertRegressionRunner {
    static func main() {
        // Identity is per-post: the coordinator's auto-hide compares ids so a newer
        // alert cancels its predecessor's expiry instead of being dismissed by it.
        let first = NotchAlert(source: .dictation, severity: .error, message: "Gojo did not hear anything.")
        let second = NotchAlert(source: .dictation, severity: .error, message: "Gojo did not hear anything.")
        assertCondition(first.id != second.id, "each posted alert must carry a distinct id")

        // Equality deliberately ignores id so a repeated failure re-posts without the
        // view animating a change it cannot see.
        assertEqual(first, second, "alerts with identical content should compare equal")

        assertCondition(
            first != NotchAlert(source: .dictation, severity: .warning, message: "Gojo did not hear anything."),
            "severity must participate in equality"
        )
        assertCondition(
            first != NotchAlert(source: .dictation, severity: .error, message: "Other failure"),
            "message must participate in equality"
        )
        assertCondition(
            first != NotchAlert(
                source: .dictation,
                severity: .error,
                message: "Gojo did not hear anything.",
                hint: "Try again shortly"
            ),
            "hint must participate in equality"
        )

        // The warm-block path posts a hint; every severity needs a distinct glyph so
        // the banner reads differently at a glance.
        let symbols = Set([
            NotchAlert.Severity.error.symbol,
            NotchAlert.Severity.warning.symbol,
            NotchAlert.Severity.info.symbol,
        ])
        assertEqual(symbols.count, 3, "each severity should map to its own SF Symbol")
        assertCondition(
            !NotchAlert.Severity.error.symbol.isEmpty,
            "severity symbols must be non-empty so the banner never renders a blank glyph"
        )

        // The banner reserves fixed side widths; a zero/negative value would collapse
        // the layout around the physical notch cutout.
        assertCondition(NotchAlertView.sideWidth > 0, "banner side width must be positive")

        if failures == 0 {
            print("notch-alert-regression-pass")
        } else {
            FileHandle.standardError.write(
                "notch-alert-regression-fail (\(failures))\n".data(using: .utf8)!
            )
            exit(1)
        }
    }
}
