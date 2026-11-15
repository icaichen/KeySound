import Foundation
import Combine

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

    /// Consumes 1 credit only after an AI generation succeeds.
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
            let instanceId = json?["instanceId"] as? String

            DispatchQueue.main.async {
                guard let self else { return }
                self.isPro = true
                self.credits += granted

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
    }
    #endif
}
