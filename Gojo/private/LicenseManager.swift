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
    /// The full, unmasked license key from the Keychain — for copy-to-clipboard
    /// only. The UI keeps the key masked and never displays this.
    var fullLicenseKey: String? { Keychain.getString(.licenseKey) }
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
        guard Keychain.setStrings([.licenseKey: trimmed, .licenseToken: token]) else {
            // The license is valid and active for this session (the cache
            // holds it), but it won't survive a relaunch — tell the user
            // instead of silently reverting next launch.
            evaluate()
            throw LicenseError(
                message: "Your license was activated but couldn't be saved to the Keychain. It may need to be re-entered after restarting Gojo.")
        }
        evaluate()
    }

    func deactivate() async throws {
        guard let key = Keychain.getString(.licenseKey) else { return }

        var req = URLRequest(url: LicenseConfig.serverBaseURL.appending(path: "/v1/deactivate"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        req.httpBody = try JSONEncoder().encode([
            "licenseKey": key,
            "machineId": Self.machineID,
            "appVersion": appVersion,
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        struct DeactivateResponse: Codable { let error: String? }
        let decoded = try? JSONDecoder().decode(DeactivateResponse.self, from: data)
        guard let http = response as? HTTPURLResponse else {
            throw LicenseError(message: "The license server returned an invalid response.")
        }
        // A missing activation is already in the desired state, so deactivation
        // remains safe to retry after a timeout or interrupted response.
        guard (200..<300).contains(http.statusCode) || http.statusCode == 404 else {
            throw LicenseError(message: decoded?.error ?? "Couldn't deactivate this Mac.")
        }

        Keychain.delete(.licenseKey, .licenseToken)
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
///
/// All five values are consolidated into a single generic-password item
/// (account "gojo.license", JSON-encoded `[String: String]`) instead of five
/// separate items, so that on the legacy file-based keychain — which prompts
/// the user once per item the first time each is accessed — steady state is
/// at most ONE permission prompt per launch, and "Always Allow" on that one
/// prompt ends them for good. The exceptions are the launches that still
/// touch the old per-key items: the one-time five-item migration below, and
/// `mergeLeftovers` retrying an item that couldn't be read then.
///
/// Reads and writes prefer the data-protection keychain
/// (`kSecUseDataProtectionKeychain`), which is gated by entitlement rather
/// than the legacy keychain's per-binary ACL, so it never prompts at all.
/// That tier requires the app to be signed with a provisioning profile that
/// validates its entitlements (see TN3137); this app doesn't ship one yet,
/// so `dataProtectionAvailable` probes for that once with a throwaway write
/// and falls back to the legacy keychain, unchanged from the old behavior,
/// for the rest of the process's lifetime. Unsigned and profile-less builds
/// always fall back to legacy; once a profile is added, prompts disappear
/// entirely with no further code changes.
///
/// The blob is read once per process and cached in memory; every public
/// function operates on that cache and persists through `store(_:)`. Three
/// migration mechanisms run when the cache is first populated: a
/// legacy-keychain blob is moved into the DP keychain once DP becomes
/// available; if no blob exists at all, the old five-item per-key layout is
/// read and combined into the new blob; and `mergeLeftovers` folds in any
/// per-key item that earlier migration attempts couldn't read.
private enum Keychain {
    enum Key: String, CaseIterable {
        case trialStart = "gojo.trialStart"
        case trialToken = "gojo.trialToken"
        case licenseKey = "gojo.licenseKey"
        case licenseToken = "gojo.licenseToken"
        case lastSeenTime = "gojo.lastSeenTime"
    }

    private static let service = "GojoLicense"
    /// The single consolidated item that replaces the old five per-key items.
    private static let blobAccount = "gojo.license"

    /// Populated exactly once per process by `load()`. Every call site in
    /// this file runs on the main actor, so no locking is needed here.
    private static var cache: [String: String]?

    /// Probe the DP keychain with a throwaway write: reads can't detect a
    /// missing entitlement (they report errSecItemNotFound), only writes
    /// fail with errSecMissingEntitlement. Anything but a successful add
    /// falls back to the legacy keychain.
    private static let dataProtectionAvailable: Bool = {
        var attributes = baseQuery(for: "gojo.dpProbe", dataProtection: true)
        attributes[kSecValueData as String] = Data("probe".utf8)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { return false }
        SecItemDelete(baseQuery(for: "gojo.dpProbe", dataProtection: true) as CFDictionary)
        return true
    }()

    private static func baseQuery(for account: String, dataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    private static func readData(_ account: String, dataProtection: Bool) -> Data? {
        var query = baseQuery(for: account, dataProtection: dataProtection)
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return data
    }

    private static func readString(_ account: String, dataProtection: Bool) -> String? {
        readData(account, dataProtection: dataProtection).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Add-or-update rather than delete-then-add: an in-place update can't
    /// destroy the item when the second step fails, and it preserves the
    /// item's identity, so a legacy-keychain "Always Allow" grant keeps
    /// applying across rewrites.
    @discardableResult
    private static func writeData(_ data: Data, account: String, dataProtection: Bool) -> Bool {
        var attributes = baseQuery(for: account, dataProtection: dataProtection)
        attributes[kSecValueData as String] = data
        if dataProtection {
            // The app launches at login and revalidates in the background,
            // so the item must be readable before the first unlock-triggered
            // user session, not just while the device is unlocked.
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecDuplicateItem else { return status == errSecSuccess }
        let update = [kSecValueData as String: data]
        return SecItemUpdate(
            baseQuery(for: account, dataProtection: dataProtection) as CFDictionary,
            update as CFDictionary
        ) == errSecSuccess
    }

    private static func deleteItem(_ account: String, dataProtection: Bool) {
        let query = baseQuery(for: account, dataProtection: dataProtection)
        SecItemDelete(query as CFDictionary)
    }

    /// Populates and returns `cache`, doing at most the work needed to find
    /// (or migrate) the consolidated blob. Order: DP blob, then legacy blob
    /// (migrated into DP when available), then — only if neither blob
    /// exists — the old five-item per-key layout, combined into a new blob.
    @discardableResult
    private static func load() -> [String: String] {
        if let cache { return cache }

        if dataProtectionAvailable,
           let data = readData(blobAccount, dataProtection: true),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = mergeLeftovers(into: dict)
            return cache!
        }

        if let legacyData = readData(blobAccount, dataProtection: false),
           let dict = try? JSONDecoder().decode([String: String].self, from: legacyData) {
            // The legacy copy is only deleted once the DP write is
            // confirmed, so a failed write can't lose the blob entirely.
            if dataProtectionAvailable, writeData(legacyData, account: blobAccount, dataProtection: true) {
                deleteItem(blobAccount, dataProtection: false)
            }
            cache = mergeLeftovers(into: dict)
            return cache!
        }

        // Neither blob exists: migrate the old five-item per-key layout.
        // DP is tried per key too (preferring it) in case an interim build
        // already wrote per-key DP items.
        var dict: [String: String] = [:]
        var migratedKeys: [Key] = []
        for key in Key.allCases {
            let dpValue = dataProtectionAvailable ? readString(key.rawValue, dataProtection: true) : nil
            guard let value = dpValue ?? readString(key.rawValue, dataProtection: false) else { continue }
            dict[key.rawValue] = value
            migratedKeys.append(key)
        }
        // Only remove the old per-key items once the new blob write is
        // confirmed, so a failed write can't lose any value entirely.
        if !dict.isEmpty, store(dict) {
            for key in migratedKeys {
                deleteItem(key.rawValue, dataProtection: false)
                if dataProtectionAvailable {
                    deleteItem(key.rawValue, dataProtection: true)
                }
            }
        }
        cache = dict
        return dict
    }

    /// Picks up old per-key items the five-item migration couldn't read at
    /// the time (e.g. an ACL denial from a differently-signed build): any
    /// key missing from the blob that still exists as a per-key item gets
    /// one read attempt per launch and is folded in on success. Existence
    /// is checked attributes-only, which the keychain never prompts for, so
    /// this is free once no leftovers remain.
    private static func mergeLeftovers(into dict: [String: String]) -> [String: String] {
        var dict = dict
        var merged = false
        for key in Key.allCases where dict[key.rawValue] == nil {
            var probe = baseQuery(for: key.rawValue, dataProtection: false)
            probe[kSecReturnAttributes as String] = true
            var attrs: AnyObject?
            guard SecItemCopyMatching(probe as CFDictionary, &attrs) == errSecSuccess,
                  let value = readString(key.rawValue, dataProtection: false)
            else { continue }
            dict[key.rawValue] = value
            merged = true
        }
        if merged, store(dict) {
            for key in Key.allCases where dict[key.rawValue] != nil {
                deleteItem(key.rawValue, dataProtection: false)
            }
        }
        return dict
    }

    /// Updates the cache first, so even if the keychain write below fails,
    /// the rest of this process's lifetime still sees the new value.
    @discardableResult
    private static func store(_ dict: [String: String]) -> Bool {
        cache = dict
        guard let data = try? JSONEncoder().encode(dict) else { return false }
        return writeData(data, account: blobAccount, dataProtection: dataProtectionAvailable)
    }

    static func getString(_ key: Key) -> String? {
        load()[key.rawValue]
    }

    static func setString(_ value: String, for key: Key) {
        setStrings([key: value])
    }

    /// Batch variant so multi-key updates (activation writes the key and the
    /// token together) land in one atomic blob write — a crash can't leave
    /// half of a logical change behind. Returns whether the write persisted;
    /// the cache holds the new values either way, so a failure only means
    /// the change won't survive this process.
    @discardableResult
    static func setStrings(_ values: [Key: String]) -> Bool {
        var dict = load()
        for (key, value) in values { dict[key.rawValue] = value }
        return store(dict)
    }

    @discardableResult
    static func delete(_ keys: Key...) -> Bool {
        var dict = load()
        // Storing the (possibly now-empty) dict back, rather than deleting
        // the blob item itself, keeps this from re-triggering the five-item
        // migration above on the next launch and resurrecting stale values.
        for key in keys { dict.removeValue(forKey: key.rawValue) }
        return store(dict)
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
