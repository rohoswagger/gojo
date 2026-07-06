//
//  LicenseManager.swift
//  Gojo
//
//  Trial and license state for the paid distribution. Licenses are issued by
//  the Gojo licensing service (Stripe-backed Cloudflare Worker) and delivered
//  as Ed25519-signed tokens the app verifies offline.
//

import CryptoKit
import Foundation
import IOKit
import SwiftUI

enum LicensePlan: String, Codable {
    case lifetime
    case monthly

    var displayName: String {
        switch self {
        case .lifetime: return "Lifetime"
        case .monthly: return "Subscription"
        }
    }
}

enum LicenseState: Equatable {
    case trial(daysRemaining: Int)
    case licensed(plan: LicensePlan)
    case locked(reason: String)
}

enum LicenseConfig {
    // The deployed gojo-license Worker. Override for local testing with:
    //   defaults write <bundle-id> licenseServerURL http://localhost:8787
    static var serverBaseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "licenseServerURL"),
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://gojo-license.rohoswagger.workers.dev")!
    }

    // Raw Ed25519 public key matching the Worker's ED_PRIVATE_KEY.
    static let publicKeyBase64 = "n0QJXkS73SlMR/dGLUWWD5CG0PB4lWsfU6WhuhsH4QY="

    static let purchaseURL = URL(string: "https://rohoswagger.github.io/gojo/#buy")!
    static let trialDays = 3
    // If the server is unreachable, a previously-valid license keeps working
    // this long past its token expiry before the app locks.
    static let offlineGraceDays = 14
}

struct LicenseToken: Codable {
    let v: Int
    let key: String
    let machineId: String
    let plan: LicensePlan
    let iat: TimeInterval
    let exp: TimeInterval
}

struct LicenseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    @Published private(set) var state: LicenseState = .trial(daysRemaining: LicenseConfig.trialDays)
    @Published private(set) var licenseKeyMasked: String?

    var isLocked: Bool {
        if case .locked = state { return true }
        return false
    }

    private init() {
        evaluate()
        Task { await revalidationLoop() }
    }

    // MARK: - State evaluation

    func evaluate() {
        if let tokenString = Keychain.getString(.licenseToken),
           let token = Self.verify(tokenString) {
            licenseKeyMasked = Self.mask(token.key)
            let now = Date().timeIntervalSince1970
            let graceEnd = token.exp + TimeInterval(LicenseConfig.offlineGraceDays * 86_400)
            if now < graceEnd {
                state = .licensed(plan: token.plan)
            } else {
                state = .locked(reason: "Your license needs to be revalidated.")
            }
            return
        }

        licenseKeyMasked = nil
        let trialStart: Date
        if let stored = Keychain.getString(.trialStart), let epoch = TimeInterval(stored) {
            trialStart = Date(timeIntervalSince1970: epoch)
        } else {
            trialStart = Date()
            Keychain.setString(String(trialStart.timeIntervalSince1970), for: .trialStart)
        }

        let elapsedDays = Int(Date().timeIntervalSince(trialStart) / 86_400)
        let remaining = LicenseConfig.trialDays - elapsedDays
        if remaining > 0 {
            state = .trial(daysRemaining: remaining)
        } else {
            state = .locked(reason: "Your \(LicenseConfig.trialDays)-day free trial has ended.")
        }
    }

    // MARK: - Server calls

    func activate(key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { throw LicenseError(message: "Enter a license key.") }
        let token = try await request(path: "/v1/activate", licenseKey: trimmed)
        Keychain.setString(trimmed, for: .licenseKey)
        Keychain.setString(token, for: .licenseToken)
        evaluate()
    }

    func deactivate() async {
        if let key = Keychain.getString(.licenseKey) {
            _ = try? await request(path: "/v1/deactivate", licenseKey: key)
        }
        Keychain.delete(.licenseKey)
        Keychain.delete(.licenseToken)
        evaluate()
    }

    /// Refresh the signed token from the server. A definitive server rejection
    /// (revoked, canceled, unknown key) locks the app; network failures keep
    /// the current state and rely on the offline grace window.
    func refresh() async {
        guard let key = Keychain.getString(.licenseKey) else { return }
        do {
            let token = try await request(path: "/v1/validate", licenseKey: key)
            Keychain.setString(token, for: .licenseToken)
            evaluate()
        } catch let error as LicenseError {
            Keychain.delete(.licenseToken)
            state = .locked(reason: error.message)
        } catch {
            // Offline or server unavailable — grace window applies.
        }
    }

    private func revalidationLoop() async {
        while true {
            if Keychain.getString(.licenseKey) != nil,
               let tokenString = Keychain.getString(.licenseToken),
               let token = Self.verify(tokenString) {
                // Refresh once under half the token's 90-day lifetime remains
                // (lifetime plans), or daily-ish for subscription tokens.
                let secondsLeft = token.exp - Date().timeIntervalSince1970
                if token.plan == .monthly || secondsLeft < 45 * 86_400 {
                    await refresh()
                }
            } else if Keychain.getString(.licenseKey) != nil {
                await refresh()
            }
            try? await Task.sleep(for: .seconds(12 * 3600))
        }
    }

    private func request(path: String, licenseKey: String) async throws -> String {
        var req = URLRequest(url: LicenseConfig.serverBaseURL.appending(path: path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        req.httpBody = try JSONEncoder().encode([
            "licenseKey": licenseKey,
            "machineId": Self.machineID,
            "appVersion": appVersion,
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw error  // plain network error, not a LicenseError
        }

        struct ServerResponse: Codable {
            let token: String?
            let error: String?
        }
        let decoded = try? JSONDecoder().decode(ServerResponse.self, from: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LicenseError(message: decoded?.error ?? "The license server rejected the request.")
        }
        guard let token = decoded?.token, Self.verify(token) != nil else {
            throw LicenseError(message: "The license server returned an invalid token.")
        }
        return token
    }

    // MARK: - Token verification

    static func verify(_ tokenString: String) -> LicenseToken? {
        let parts = tokenString.split(separator: ".")
        guard parts.count == 2,
              let payload = Data(base64URLEncoded: String(parts[0])),
              let signature = Data(base64URLEncoded: String(parts[1])),
              let keyData = Data(base64Encoded: LicenseConfig.publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              publicKey.isValidSignature(signature, for: payload),
              let token = try? JSONDecoder().decode(LicenseToken.self, from: payload),
              token.machineId == machineID
        else { return nil }
        return token
    }

    // MARK: - Machine identity

    static let machineID: String = {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        guard service != 0,
              let uuid = IORegistryEntryCreateCFProperty(
                service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0
              )?.takeRetainedValue() as? String
        else { return "unknown-machine" }
        let digest = SHA256.hash(data: Data(uuid.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }()

    private static func mask(_ key: String) -> String {
        let suffix = key.split(separator: "-").last.map(String.init) ?? ""
        return "GOJO-••••-••••-••••-\(suffix)"
    }
}

// MARK: - Keychain storage

/// License data lives in the Keychain (not Defaults) so the trial clock and
/// activation survive app reinstalls.
private enum Keychain {
    enum Key: String {
        case trialStart = "gojo.trialStart"
        case licenseKey = "gojo.licenseKey"
        case licenseToken = "gojo.licenseToken"
    }

    private static let service = "GojoLicense"

    static func getString(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setString(_ value: String, for key: Key) {
        delete(key)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func delete(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private extension Data {
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        self.init(base64Encoded: base64)
    }
}
