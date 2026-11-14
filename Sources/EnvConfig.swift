import Foundation

/// Reads API keys from `.env` files for local testing without hardcoding secrets.
enum EnvConfig {
    static var deepseekApiKey: String {
        value(for: "DEEPSEEK_API_KEY")
    }

    static var geminiApiKey: String {
        value(for: "GEMINI_API_KEY")
    }

    static var elevenLabsApiKey: String {
        value(for: "ELEVENLABS_API_KEY")
    }

    static func value(for key: String) -> String {
        if let envVal = ProcessInfo.processInfo.environment[key], !envVal.isEmpty {
            return envVal
        }
        for url in candidateEnvURLs() {
            if let parsed = parseEnvFile(at: url)[key], !parsed.isEmpty {
                return parsed
            }
        }
        return ""
    }

    static func primaryEnvPathHint() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeySound/.env").path
        let repoEnv = "/Users/chencai/Development/Keysound/.env"
        if FileManager.default.fileExists(atPath: repoEnv) {
            return repoEnv
        }
        return appSupport
    }

    private static func candidateEnvURLs() -> [URL] {
        var urls: [URL] = []
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeySound/.env")
        urls.append(appSupport)
        urls.append(URL(fileURLWithPath: "/Users/chencai/Development/Keysound/.env"))
        urls.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".env"))
        return urls
    }

    private static func parseEnvFile(at url: URL) -> [String: String] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let eqIdx = line.firstIndex(of: "=") else { continue }
            let k = String(line[..<eqIdx]).trimmingCharacters(in: .whitespaces)
            var v = String(line[line.index(after: eqIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
                v = String(v.dropFirst().dropLast())
            } else if let commentIdx = v.firstIndex(of: "#") {
                v = String(v[..<commentIdx]).trimmingCharacters(in: .whitespaces)
            }
            result[k] = v
        }
        return result
    }
}
