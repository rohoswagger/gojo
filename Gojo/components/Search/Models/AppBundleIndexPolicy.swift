import Foundation

enum AppBundleIndexPolicy {
    static func shouldInclude(infoDictionary: [String: Any]?) -> Bool {
        guard let infoDictionary else { return true }
        return !isEnabled(infoDictionary["LSUIElement"])
            && !isEnabled(infoDictionary["LSBackgroundOnly"])
    }

    private static func isEnabled(_ value: Any?) -> Bool {
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            return ["1", "true", "yes"].contains(string.lowercased())
        }
        return false
    }
}
