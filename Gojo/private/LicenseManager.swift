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
    // The deployed gojo-license Worker. Debug builds can point elsewhere with:
    //   defaults write <bundle-id> licenseServerURL http://localhost:8787
    static var serverBaseURL: URL {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "licenseServerURL"),
           let url = URL(string: override) {
            return url
        }
        #endif
        return URL(string: "https://gojo-license.rohoswagger.com")!
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

struct TrialToken: Codable {
    let v: Int
    let kind: String
    let machineId: String
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

    @Published private(set) var state: LicenseState = .trial(daysRemaining: LicenseConfig.trialDays) {
        didSet { Self.lockedFlag = isLocked }
    }
    @Published private(set) var licenseKeyMasked: String?
    /// For subscriptions: the end of the paid period (token exp minus the
    /// offline grace window). Nil for trial and lifetime licenses.
    @Published private(set) var paidThrough: Date?

    /// Mirror of `isLocked` readable from non-main-actor call sites
    /// (CGEvent tap callbacks). Only written on the main actor.
    nonisolated(unsafe) private(set) static var lockedFlag = false

    var isLocked: Bool {
        if case .locked = state { return true }
        return false
    }

    private init() {
        evaluate()
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--print-license-state") {
            print("license-state: \(state)")
            exit(0)
        }
        // Screenshot/QA hook: force a state without touching Keychain or network.
        if args.contains("--fake-monthly") {
            licenseKeyMasked = "GOJO-••••-••••-••••-DEMO"
            paidThrough = Date(timeIntervalSince1970: Date().timeIntervalSince1970 + 26 * 86_400)
            state = .licensed(plan: .monthly)
            return
        }
        #endif
        Task {
            await ensureTrialToken()
            await revalidationLoop()
        }
    }

    // MARK: - State evaluation

    func evaluate() {
        // Trial and grace math run on the latest wall clock this app has ever
        // seen, so winding the Mac's clock back can't extend either.
        let now = max(
            Date().timeIntervalSince1970,
            Keychain.getString(.lastSeenTime).flatMap(TimeInterval.init) ?? 0
        )
        Keychain.setString(String(now), for: .lastSeenTime)

        if let tokenString = Keychain.getString(.licenseToken),
           let token = Self.verify(tokenString) {
            licenseKeyMasked = Self.mask(token.key)
            paidThrough = token.plan == .monthly
                ? Date(timeIntervalSince1970: token.exp - TimeInterval(LicenseConfig.offlineGraceDays * 86_400))
                : nil
            let graceEnd = token.exp + TimeInterval(LicenseConfig.offlineGraceDays * 86_400)
            if now < graceEnd {
                state = .licensed(plan: token.plan)
            } else {
                state = .locked(reason: "Your license needs to be revalidated.")
            }
            return
        }

        licenseKeyMasked = nil
        paidThrough = nil

        // Trial expiry comes from the server-signed trial token when present
        // (authoritative and offline-verified, so wiping local state can't reset
        // it). Before that token has been fetched — first launch, or offline — a
        // local provisional start keeps the app usable. ensureTrialToken() fetches
        // the server token once and hardens this.
        let trialExp: TimeInterval
        if let trialString = Keychain.getString(.trialToken),
           let trial = Self.verifyTrial(trialString) {
            trialExp = trial.exp
        } else {
            let start: TimeInterval
            if let stored = Keychain.getString(.trialStart), let epoch = TimeInterval(stored) {
                start = epoch
            } else {
                start = now
                Keychain.setString(String(start), for: .trialStart)
            }
            trialExp = start + TimeInterval(LicenseConfig.trialDays * 86_400)
        }

        let secondsLeft = trialExp - now
        if secondsLeft > 0 {
            state = .trial(daysRemaining: max(1, Int(ceil(secondsLeft / 86_400))))
        } else {
            state = .locked(reason: "Your \(LicenseConfig.trialDays)-day free trial has ended.")
        }
    }

    /// One-time fetch of the server-signed trial token, only when this machine
    /// has no license and no token yet. The trial start is recorded server-side
    /// (keyed by machine id), so it survives a local wipe. Verified offline
    /// afterward — this never runs on notch open, only at launch.
    private func ensureTrialToken() async {
        guard Keychain.getString(.licenseKey) == nil,
              Keychain.getString(.trialToken) == nil else { return }
        var req = URLRequest(url: LicenseConfig.serverBaseURL.appending(path: "/v1/trial"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        req.httpBody = try? JSONEncoder().encode(["machineId": Self.machineID, "appVersion": appVersion])
        guard req.httpBody != nil else { return }
        struct TrialResponse: Codable { let token: String? }
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let token = (try? JSONDecoder().decode(TrialResponse.self, from: data))?.token,
              Self.verifyTrial(token) != nil
        else { return }  // offline or error: keep the local provisional trial, retry next launch
        Keychain.setString(token, for: .trialToken)
        evaluate()
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

    /// Fetch a Stripe customer-portal URL so subscribers can manage billing
    /// (update card, invoices, cancel — where the retention offer appears).
    func managePortalURL() async throws -> URL {
        guard let key = Keychain.getString(.licenseKey) else {
            throw LicenseError(message: "No license is active on this Mac.")
        }
        var req = URLRequest(url: LicenseConfig.serverBaseURL.appending(path: "/v1/portal"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["licenseKey": key])
        let (data, response) = try await URLSession.shared.data(for: req)
        struct PortalResponse: Codable {
            let url: String?
            let error: String?
        }
        let decoded = try? JSONDecoder().decode(PortalResponse.self, from: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let urlString = decoded?.url, let url = URL(string: urlString)
        else {
            throw LicenseError(message: decoded?.error ?? "Couldn't open the billing portal.")
        }
        return url
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
            // Reconcile a provisional (offline-started) trial to the server
            // token once connectivity returns. No-op once a token is stored.
            await ensureTrialToken()
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

    static func verifyTrial(_ tokenString: String) -> TrialToken? {
        let parts = tokenString.split(separator: ".")
        guard parts.count == 2,
              let payload = Data(base64URLEncoded: String(parts[0])),
              let signature = Data(base64URLEncoded: String(parts[1])),
              let keyData = Data(base64Encoded: LicenseConfig.publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              publicKey.isValidSignature(signature, for: payload),
              let token = try? JSONDecoder().decode(TrialToken.self, from: payload),
              token.kind == "trial",
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
        case trialToken = "gojo.trialToken"
        case licenseKey = "gojo.licenseKey"
        case licenseToken = "gojo.licenseToken"
        case lastSeenTime = "gojo.lastSeenTime"
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
