import Foundation

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fputs("Assertion failed: \(message). Expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

@main
struct AccessibilityAuthorizationFlowRegressionRunner {
    static func main() {
        assertEqual(
            AccessibilityAuthorizationFlowPolicy.shouldComplete(
                wasAuthorizedAtStart: true,
                isAuthorizedNow: true,
                acceptedDrag: false,
                observedUnauthorized: false
            ),
            false,
            "a pre-existing grant must not skip the draggable menu flow"
        )
        assertEqual(
            AccessibilityAuthorizationFlowPolicy.shouldComplete(
                wasAuthorizedAtStart: true,
                isAuthorizedNow: true,
                acceptedDrag: true,
                observedUnauthorized: false
            ),
            true,
            "an accepted drag may confirm an existing grant"
        )
        assertEqual(
            AccessibilityAuthorizationFlowPolicy.shouldComplete(
                wasAuthorizedAtStart: false,
                isAuthorizedNow: true,
                acceptedDrag: false,
                observedUnauthorized: false
            ),
            true,
            "a newly granted permission should complete without requiring a drag callback"
        )
        assertEqual(
            AccessibilityAuthorizationFlowPolicy.shouldComplete(
                wasAuthorizedAtStart: false,
                isAuthorizedNow: false,
                acceptedDrag: true,
                observedUnauthorized: true
            ),
            false,
            "a drag alone must not claim authorization"
        )
        assertEqual(
            AccessibilityAuthorizationFlowPolicy.shouldComplete(
                wasAuthorizedAtStart: true,
                isAuthorizedNow: true,
                acceptedDrag: false,
                observedUnauthorized: true
            ),
            true,
            "revoking and regranting permission should complete the flow"
        )
        print("accessibility-authorization-flow-regression-pass")
    }
}
