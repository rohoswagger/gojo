struct AccessibilityAuthorizationFlowPolicy {
    static func shouldComplete(
        wasAuthorizedAtStart: Bool,
        isAuthorizedNow: Bool,
        acceptedDrag: Bool,
        observedUnauthorized: Bool
    ) -> Bool {
        isAuthorizedNow
            && (!wasAuthorizedAtStart || acceptedDrag || observedUnauthorized)
    }
}
