import Foundation
import Combine
import CryptoKit
import IOKit

struct LicenseActivationResult {
    let plan: String
    let creditsGranted: Int
}

enum LicenseActivationError: LocalizedError {
    case emptyKey
    case alreadyRedeemed
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            return "Please enter a license key."
        case .alreadyRedeemed:
            return "This license key has already been redeemed on this Mac."
        case .invalidResponse:
            return "Unexpected response from license server."
        case .serverError(let message):
            return message
        }
    }
}

/// Manages KeySound Pro status and AI Sound Studio credits via Creem license keys.
/// Starts new users with 3 complimentary trial credits so they can test
/// AI Sound Studio before upgrading to Pro ($9.99 one-time, +15 credits).
final class ProManager: ObservableObject {
    static let shared = ProManager()

    private static let licenseEndpoint = "https://website-one-nu-73.vercel.app/api/license"
    private static let checkoutBaseEndpoint = "https://website-one-nu-73.vercel.app/api/checkout"

    private let isProKey = "keysound.isPro"
    private let creditsKey = "keysound.aiCredits"
    private let initializedKey = "keysound.proInitialized"
    private let licenseKeyStorageKey = "keysound.creemLicenseKey"
    private let instanceIdStorageKey = "keysound.creemInstanceId"
    private let redeemedKeysStorageKey = "keysound.redeemedLicenseKeys"
    private let quotaTokenStorageKey = "keysound.serverQuotaToken"
    private let fallbackDeviceIdStorageKey = "keysound.deviceId"

    private static let clientSigningSecret = "ks_app_v1_9f4c2a8e71d04b3a9c6e12f8a4b7d503"

    @Published var isPro: Bool {
        didSet { UserDefaults.standard.set(isPro, forKey: isProKey) }
    }

    @Published var credits: Int {
        didSet { UserDefaults.standard.set(max(0, credits), forKey: creditsKey) }
    }

    private init() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: initializedKey) {
            defaults.set(true, forKey: initializedKey)
            defaults.set(false, forKey: isProKey)
            defaults.set(3, forKey: creditsKey) // 3 free trial credits
        }
        self.isPro = defaults.bool(forKey: isProKey)
        self.credits = defaults.integer(forKey: creditsKey)
    }

    var canGenerateSFX: Bool {
        credits > 0
    }

    var canUseAIMix: Bool {
        isPro || credits > 0
    }

    static func checkoutURL(for plan: String) -> URL? {
        URL(string: "\(checkoutBaseEndpoint)?plan=\(plan)")
    }

    /// Consumes 1 credit only after an AI generation succeeds (used for local-key fallback).
    func consumeCredit() {
        let decrement = {
            if self.credits > 0 {
                self.credits -= 1
            }
        }
        if Thread.isMainThread {
            decrement()
        } else {
            DispatchQueue.main.async(execute: decrement)
        }
    }

    /// Stable per-Mac device identifier (hardware IOPlatformUUID with UserDefaults fallback).
    var deviceId: String {
        if let uuid = Self.hardwarePlatformUUID(), !uuid.isEmpty {
            return uuid
        }
        if let saved = UserDefaults.standard.string(forKey: fallbackDeviceIdStorageKey), !saved.isEmpty {
            return saved
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: fallbackDeviceIdStorageKey)
        return generated
    }

    var currentQuotaToken: String? {
        let token = UserDefaults.standard.string(forKey: quotaTokenStorageKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (token?.isEmpty == false) ? token : nil
    }

    func applyServerQuota(token: String?, remainingCredits: Int?) {
        let update = {
            if let token, !token.isEmpty {
                UserDefaults.standard.set(token, forKey: self.quotaTokenStorageKey)
            }
            if let remainingCredits {
                self.credits = max(0, remainingCredits)
            }
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    func applyClientAuthHeaders(to request: inout URLRequest) {
        let method = (request.httpMethod ?? "POST").uppercased()
        let path = request.url?.path ?? "/"
        let devId = deviceId
        let ts = String(Int64(Date().timeIntervalSince1970 * 1000))
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let canonical = "\(method)\n\(path)\n\(devId)\n\(ts)\n\(nonce)"

        let key = SymmetricKey(data: Data(Self.clientSigningSecret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(canonical.utf8), using: key)
        let sigHex = mac.map { String(format: "%02x", $0) }.joined()

        request.setValue(devId, forHTTPHeaderField: "X-KS-Device")
        request.setValue(ts, forHTTPHeaderField: "X-KS-Ts")
        request.setValue(nonce, forHTTPHeaderField: "X-KS-Nonce")
        request.setValue(sigHex, forHTTPHeaderField: "X-KS-Sig")
        if let token = currentQuotaToken {
            request.setValue(token, forHTTPHeaderField: "X-Quota-Token")
        }
    }

    /// Ensures the app has a server-signed quota token (requesting the 3-credit trial grant if needed).
    func ensureQuotaToken() async throws -> String {
        if let existing = currentQuotaToken {
            return existing
        }
        guard let url = URL(string: Self.licenseEndpoint) else {
            throw LicenseActivationError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["action": "trial"])
        applyClientAuthHeaders(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard (200...299).contains(httpStatus),
              let token = json?["quotaToken"] as? String, !token.isEmpty else {
            let msg = (json?["error"] as? String) ?? "Failed to initialize trial credits (HTTP \(httpStatus))."
            throw LicenseActivationError.serverError(msg)
        }

        let serverCredits = json?["credits"] as? Int
        applyServerQuota(token: token, remainingCredits: serverCredits)
        return token
    }

    private static func hardwarePlatformUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let prop = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)
        return prop?.takeRetainedValue() as? String
    }

    /// Activates a Creem Pro Pass or Credit Top-Up license key via /api/license.
    func activateLicense(
        _ rawKey: String,
        completion: @escaping (Result<LicenseActivationResult, Error>) -> Void
    ) {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(LicenseActivationError.emptyKey))
            return
        }

        let normalized = trimmed.uppercased()
        let redeemed = Set(UserDefaults.standard.stringArray(forKey: redeemedKeysStorageKey) ?? [])
        if redeemed.contains(normalized) {
            completion(.failure(LicenseActivationError.alreadyRedeemed))
            return
        }

        guard let url = URL(string: Self.licenseEndpoint) else {
            completion(.failure(LicenseActivationError.invalidResponse))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyClientAuthHeaders(to: &request)

        let deviceName = Host.current().localizedName ?? "KeySound Mac"
        let payload: [String: Any] = [
            "action": "activate",
            "key": trimmed,
            "instanceName": deviceName
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data else {
                DispatchQueue.main.async { completion(.failure(LicenseActivationError.invalidResponse)) }
                return
            }

            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard (200...299).contains(httpStatus),
                  let valid = json?["valid"] as? Bool, valid else {
                let serverMsg = (json?["error"] as? String)
                    ?? "License activation failed (HTTP \(httpStatus))."
                DispatchQueue.main.async {
                    completion(.failure(LicenseActivationError.serverError(serverMsg)))
                }
                return
            }

            let plan = (json?["plan"] as? String) ?? "pro"
            let granted = (json?["creditsToGrant"] as? Int) ?? (plan == "topup" ? 20 : 15)
            let serverCredits = json?["serverCredits"] as? Int
            let quotaToken = json?["quotaToken"] as? String
            let instanceId = json?["instanceId"] as? String

            DispatchQueue.main.async {
                guard let self else { return }
                self.isPro = true
                if let quotaToken, !quotaToken.isEmpty {
                    UserDefaults.standard.set(quotaToken, forKey: self.quotaTokenStorageKey)
                }
                if let serverCredits {
                    self.credits = max(0, serverCredits)
                } else {
                    self.credits += granted
                }

                var updated = Set(UserDefaults.standard.stringArray(forKey: self.redeemedKeysStorageKey) ?? [])
                updated.insert(normalized)
                UserDefaults.standard.set(Array(updated), forKey: self.redeemedKeysStorageKey)

                if plan == "pro" {
                    UserDefaults.standard.set(trimmed, forKey: self.licenseKeyStorageKey)
                    if let instanceId, !instanceId.isEmpty {
                        UserDefaults.standard.set(instanceId, forKey: self.instanceIdStorageKey)
                    }
                }

                completion(.success(LicenseActivationResult(plan: plan, creditsGranted: granted)))
            }
        }.resume()
    }

    #if DEBUG
    /// Local testing helpers (stripped from Release builds).
    func activateDemoProForTesting() {
        isPro = true
        credits += 15
    }

    func grantTestCredits(_ amount: Int) {
        credits += amount
    }

    func resetTrialForTesting() {
        isPro = false
        credits = 3
        UserDefaults.standard.removeObject(forKey: licenseKeyStorageKey)
        UserDefaults.standard.removeObject(forKey: instanceIdStorageKey)
        UserDefaults.standard.removeObject(forKey: redeemedKeysStorageKey)
        UserDefaults.standard.removeObject(forKey: quotaTokenStorageKey)
    }
    #endif
}
