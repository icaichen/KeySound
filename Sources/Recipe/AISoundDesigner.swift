import Foundation

/// Creates `SoundRecipe` configurations in two ways:
/// 1. Deterministic Switch × Mod Acoustic Matrix (100% offline, no AI required)
/// 2. Real Gemini AI generation using `GEMINI_API_KEY` from `.env`
enum AISoundDesigner {
    enum SwitchBase: String, CaseIterable, Identifiable {
        case clicky = "Clicky (Blue)"
        case tactile = "Tactile (Brown / Oreo)"
        case linear = "Linear (Red / Black)"
        case topre = "Topre (Electro-Capacitive)"
        case wood = "Wood / Mahjong"

        var id: String { rawValue }
    }

    enum AcousticMod: String, CaseIterable, Identifiable {
        case thock = "Thock (Deep)"
        case creamy = "Creamy (Smooth)"
        case clack = "Clack (Bright)"
        case foam = "Foam (Quiet)"
        case marbly = "Marbly (Poppy)"

        var id: String { rawValue }
    }

    enum DesignError: LocalizedError {
        case emptyPrompt
        case missingApiKey(String)
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .emptyPrompt:
                return "Describe the mechanical keyboard sound you want first."
            case .missingApiKey(let path):
                return "Missing GEMINI_API_KEY in \(path)"
            case .invalidResponse(let msg):
                return msg
            }
        }
    }

    // MARK: - 1. No-AI Switch × Mod Acoustic Matrix

    static func buildFromMatrix(
        base: SwitchBase,
        mod: AcousticMod,
        catalog: [(pack: String, files: [String])]
    ) -> SoundRecipe {
        let available = Set(catalog.map { $0.pack })
        func pick(_ candidates: [String]) -> String? {
            candidates.first(where: { available.contains($0) }) ?? catalog.first?.pack
        }

        var clickPack: String?
        var clickGain = 0.55
        var clickPitch = 0.0
        var clickTrim = 28.0
        var clickLowpass = 12000.0

        var bodyPack: String?
        var bodyGain = 1.0
        var bodyPitch = 0.0
        var bodyTrim = 0.0
        var bodyLowpass = 16000.0

        let releasePack = pick(["Layer_Release_Soft", "Topre_Purple_Hybrid_PBT_keycaps"])
        var releaseGain = 0.35

        var lowDb = 1.0
        var highDb = 0.0
        var reverbWet = 0.08
        var roomSize = 0.25

        switch base {
        case .clicky:
            clickPack = pick(["Layer_Click_Snap", "CherryMX_Blue_PBT_keycaps"])
            clickGain = 0.90
            bodyPack = pick(["CherryMX_Blue_PBT_keycaps", "Layer_Body_Crisp"])
            highDb += 2.0
        case .tactile:
            clickPack = pick(["Layer_Click_Soft", "CherryMX_Brown_PBT_keycaps"])
            clickGain = 0.60
            bodyPack = pick(["EG_Oreo", "CherryMX_Brown_PBT_keycaps", "EG_Crystal_Purple"])
        case .linear:
            clickPack = pick(["Layer_Click_Soft", "CherryMX_Red_ABS_keycaps"])
            clickGain = 0.45
            bodyPack = pick(["CherryMX_Black_PBT_keycaps", "CherryMX_Red_ABS_keycaps", "Layer_Body_Thock"])
        case .topre:
            clickPack = pick(["Layer_Click_Soft", "Topre_Purple_Hybrid_PBT_keycaps"])
            clickGain = 0.35
            bodyPack = pick(["Topre_Purple_Hybrid_PBT_keycaps", "Layer_Body_Thock"])
            lowDb += 2.0
        case .wood:
            clickPack = pick(["Layer_Click_Snap", "EG_Crystal_Purple"])
            clickGain = 0.65
            bodyPack = pick(["Layer_Body_Wood", "Mahjong", "EG_Oreo"])
        }

        switch mod {
        case .thock:
            bodyPitch -= 2.5
            clickPitch -= 1.5
            bodyLowpass = 5200
            lowDb += 3.5
            highDb -= 1.5
        case .creamy:
            clickGain *= 0.8
            clickLowpass = 8500
            bodyLowpass = 6500
            lowDb += 2.5
            reverbWet = 0.12
        case .clack:
            clickGain = min(1.2, clickGain * 1.2)
            clickLowpass = 18500
            bodyLowpass = 18000
            bodyPitch += 1.0
            highDb += 3.5
        case .foam:
            clickGain *= 0.55
            clickLowpass = 4800
            bodyLowpass = 3400
            releaseGain = 0.2
            highDb -= 4.5
            bodyGain = 0.85
        case .marbly:
            bodyPitch += 1.2
            clickTrim = 20
            bodyTrim = 85
            lowDb += 1.5
            highDb += 2.0
            reverbWet = 0.10
            roomSize = 0.30
        }

        var keymap = SoundRecipe.Keymap()
        keymap.space = SoundRecipe.KeyOverride(pitchShift: -2.5, gainScale: 1.15, decayScale: 1.0)
        keymap.enter = SoundRecipe.KeyOverride(pitchShift: -1.5, gainScale: 1.1, decayScale: 1.0)
        keymap.backspace = SoundRecipe.KeyOverride(pitchShift: -1.0, gainScale: 1.05, decayScale: 1.0)

        return SoundRecipe(
            meta: SoundRecipe.Meta(
                name: "\(base.rawValue.components(separatedBy: " ").first ?? "Custom") · \(mod.rawValue.components(separatedBy: " ").first ?? "")",
                author: "KeySound Matrix",
                description: "\(base.rawValue) + \(mod.rawValue)",
                tags: ["matrix"],
                basedOn: bodyPack
            ),
            layers: SoundRecipe.Layers(
                click: SoundRecipe.SampleLayer(
                    enabled: clickPack != nil,
                    gain: clickGain,
                    pitchShiftSt: clickPitch,
                    trimMs: clickTrim,
                    lowpassHz: clickLowpass,
                    sample: clickPack.map { SoundRecipe.SampleRef(pack: $0, file: "generic") }
                ),
                body: SoundRecipe.SampleLayer(
                    enabled: bodyPack != nil,
                    gain: bodyGain,
                    pitchShiftSt: bodyPitch,
                    trimMs: bodyTrim,
                    lowpassHz: bodyLowpass,
                    sample: bodyPack.map { SoundRecipe.SampleRef(pack: $0, file: "generic") }
                ),
                release: SoundRecipe.SampleLayer(
                    enabled: releasePack != nil,
                    gain: releaseGain,
                    pitchShiftSt: 0,
                    trimMs: 45,
                    lowpassHz: 9000,
                    sample: releasePack.map { SoundRecipe.SampleRef(pack: $0, file: "generic") }
                ),
                space: SoundRecipe.SpaceLayer(
                    enabled: reverbWet > 0.01,
                    reverbWet: reverbWet,
                    roomSize: roomSize,
                    stereoWidth: 0.7
                )
            ),
            master: SoundRecipe.Master(
                gain: 1.0,
                eq: SoundRecipe.EQ(lowDb: lowDb, midDb: 0, highDb: highDb)
            ),
            humanize: SoundRecipe.Humanize(pitchJitterSt: 0.35, gainJitterDb: 1.5, timingJitterMs: 2),
            keymap: keymap
        )
    }

    // MARK: - 2. Real AI Mix (DeepSeek preferred + Gemini fallback, via .env)

    struct AIResult {
        let recipe: SoundRecipe
        let statusNote: String
    }

    static func generateWithAI(
        prompt: String,
        catalog: [(pack: String, files: [String])],
        deepseekKey: String,
        geminiKey: String
    ) async throws -> AIResult {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DesignError.emptyPrompt }

        let dsKey = deepseekKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let gmKey = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !dsKey.isEmpty || !gmKey.isEmpty else {
            throw DesignError.missingApiKey(EnvConfig.primaryEnvPathHint())
        }

        let systemPrompt = buildSystemInstruction(catalog: catalog)

        if !dsKey.isEmpty {
            do {
                let recipe = try await generateWithDeepSeek(
                    prompt: trimmed,
                    systemInstruction: systemPrompt,
                    apiKey: dsKey
                )
                return AIResult(recipe: recipe, statusNote: "Generated with DeepSeek (deepseek-chat)")
            } catch {
                // If Gemini key is also configured, try Gemini next before failing/falling back
                if gmKey.isEmpty {
                    let fallback = smartKeywordFallback(prompt: trimmed, catalog: catalog)
                    return AIResult(
                        recipe: fallback,
                        statusNote: "DeepSeek unavailable (\(error.localizedDescription)) — applied Smart Mix"
                    )
                }
            }
        }

        return try await generateWithGemini(
            prompt: trimmed,
            catalog: catalog,
            apiKey: gmKey
        )
    }

    private static func generateWithDeepSeek(
        prompt: String,
        systemInstruction: String,
        apiKey: String
    ) async throws -> SoundRecipe {
        guard let url = URL(string: "https://api.deepseek.com/chat/completions") else {
            throw DesignError.invalidResponse("Invalid DeepSeek API URL.")
        }

        let body: [String: Any] = [
            "model": "deepseek-chat",
            "messages": [
                ["role": "system", "content": systemInstruction],
                ["role": "user", "content": "Design a keyboard sound for: \(prompt)"]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.4
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw DesignError.invalidResponse("DeepSeek HTTP \(status)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              let recipeData = content.data(using: .utf8) else {
            throw DesignError.invalidResponse("Could not parse DeepSeek response.")
        }
        return try JSONDecoder().decode(SoundRecipe.self, from: recipeData)
    }

    private static func buildSystemInstruction(catalog: [(pack: String, files: [String])]) -> String {
        let packList = catalog.map { $0.pack }.joined(separator: ", ")
        return """
        You are an expert acoustic sound designer for a mechanical keyboard simulator.
        Output ONLY valid JSON matching SoundRecipe v2:
        {
          "version": 2,
          "meta": { "name": "Short Name", "description": "..." },
          "layers": {
            "click": { "enabled": true, "gain": 0.6, "pitchShiftSt": 0, "trimMs": 25, "lowpassHz": 12000, "sample": { "pack": "<PACK>", "file": "generic" } },
            "body":  { "enabled": true, "gain": 1.0, "pitchShiftSt": -2, "trimMs": 0, "lowpassHz": 6000, "sample": { "pack": "<PACK>", "file": "generic" } },
            "release": { "enabled": true, "gain": 0.35, "pitchShiftSt": 0, "trimMs": 45, "lowpassHz": 9000, "sample": { "pack": "<PACK>", "file": "generic" } },
            "space": { "enabled": true, "reverbWet": 0.1, "roomSize": 0.3, "stereoWidth": 0.7 }
          },
          "master": { "gain": 1.0, "eq": { "lowDb": 2, "midDb": 0, "highDb": -1 } },
          "humanize": { "pitchJitterSt": 0.35, "gainJitterDb": 1.5, "timingJitterMs": 2 },
          "keymap": {
            "space": { "pitchShift": -2.5, "gainScale": 1.15, "decayScale": 1.0 },
            "enter": { "pitchShift": -1.5, "gainScale": 1.1, "decayScale": 1.0 },
            "backspace": { "pitchShift": -1.0, "gainScale": 1.05, "decayScale": 1.0 }
          }
        }
        Acoustic guide for packs:
        - Layer_Click_Snap: crisp high-frequency switch click
        - Layer_Click_Soft: gentle, muted initial tap
        - Layer_Body_Thock: deep low-end thock body
        - Layer_Body_Crisp: bright, clean clack body
        - Layer_Body_Wood: warm woody/marbly resonance
        - Layer_Release_Soft: soft keycap return sound
        - Topre_Purple_Hybrid_PBT_keycaps: silenced round electro-capacitive thock
        - EG_Oreo: deep creamy tactile thock
        - EG_Crystal_Purple: glassy, snappy tactile
        - CherryMX_Blue_PBT_keycaps / ABS: classic loud clicky switch
        - CherryMX_Brown_PBT_keycaps / ABS: balanced tactile bump
        - CherryMX_Black_PBT_keycaps / Red_ABS: smooth linear bottom-out
        Choose <PACK> strictly from: [\(packList)].
        """
    }

    static func generateWithGemini(
        prompt: String,
        catalog: [(pack: String, files: [String])],
        apiKey: String
    ) async throws -> AIResult {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DesignError.emptyPrompt }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw DesignError.missingApiKey(EnvConfig.primaryEnvPathHint())
        }

        let systemInstruction = buildSystemInstruction(catalog: catalog)

        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemInstruction]]],
            "contents": [["parts": [["text": "Design a keyboard sound for: \(trimmed)"]]]],
            "generationConfig": ["responseMimeType": "application/json", "temperature": 0.4]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        let preferredModels = ["gemini-3.8-flash", "gemini-3-flash", "gemini-2.5-flash"]
        var tried = Set<String>()
        var lastError = "Gemini request failed."
        var sawTransientBusy = false

        for model in preferredModels {
            tried.insert(model)
            let (status, data) = try await postGenerate(model: model, apiKey: key, body: bodyData)
            if (200...299).contains(status) {
                let recipe = try decodeRecipe(from: data)
                return AIResult(recipe: recipe, statusNote: "Generated with \(model)")
            }
            lastError = extractErrorMessage(status: status, data: data)
            if status == 429 || status == 503 { sawTransientBusy = true }
            // Only abort immediately on auth/bad-request errors (400/401/403)
            if status != 404 && status != 429 && status != 503 {
                throw DesignError.invalidResponse(lastError)
            }
        }

        // Discover any other available generateContent models on this API key and try them
        let discoveredModels = try await discoverAvailableModels(apiKey: key)
        for model in discoveredModels where !tried.contains(model) {
            let (status, data) = try await postGenerate(model: model, apiKey: key, body: bodyData)
            if (200...299).contains(status) {
                let recipe = try decodeRecipe(from: data)
                return AIResult(recipe: recipe, statusNote: "Generated with \(model)")
            }
            lastError = extractErrorMessage(status: status, data: data)
            if status == 429 || status == 503 { sawTransientBusy = true }
        }

        // If Gemini is temporarily overloaded (503/429), fall back to smart acoustic matrix
        if sawTransientBusy {
            let fallback = smartKeywordFallback(prompt: trimmed, catalog: catalog)
            return AIResult(
                recipe: fallback,
                statusNote: "Gemini servers busy — applied Smart Acoustic Mix instead"
            )
        }

        throw DesignError.invalidResponse(lastError)
    }

    private static func smartKeywordFallback(
        prompt: String,
        catalog: [(pack: String, files: [String])]
    ) -> SoundRecipe {
        let p = prompt.lowercased()
        let base: SwitchBase
        if p.contains("click") || p.contains("blue") || p.contains("typewriter") { base = .clicky }
        else if p.contains("topre") || p.contains("silent") || p.contains("quiet") { base = .topre }
        else if p.contains("wood") || p.contains("mahjong") || p.contains("rain") { base = .wood }
        else if p.contains("red") || p.contains("black") || p.contains("linear") { base = .linear }
        else { base = .tactile }

        let mod: AcousticMod
        if p.contains("cream") || p.contains("milk") || p.contains("oreo") { mod = .creamy }
        else if p.contains("clack") || p.contains("bright") || p.contains("crisp") { mod = .clack }
        else if p.contains("foam") || p.contains("quiet") || p.contains("mute") { mod = .foam }
        else if p.contains("marb") || p.contains("pop") { mod = .marbly }
        else { mod = .thock }

        return buildFromMatrix(base: base, mod: mod, catalog: catalog)
    }

    private static func postGenerate(model: String, apiKey: String, body: Data) async throws -> (Int, Data) {
        let cleanModel = model.replacingOccurrences(of: "models/", with: "")
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(cleanModel):generateContent") else {
            throw DesignError.invalidResponse("Invalid Gemini API URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = body
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (status, data)
    }

    private static func discoverAvailableModels(apiKey: String) async throws -> [String] {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models") else { return [] }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return []
        }

        return models.compactMap { m in
            let methods = m["supportedGenerationMethods"] as? [String] ?? []
            let name = (m["name"] as? String ?? "").replacingOccurrences(of: "models/", with: "")
            guard methods.contains("generateContent"),
                  !name.isEmpty,
                  !name.contains("1.5"), !name.contains("2.0"), !name.contains("2.5") else {
                return nil
            }
            return name
        }.reversed()
    }

    private static func decodeRecipe(from data: Data) throws -> SoundRecipe {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String,
              let recipeData = text.data(using: .utf8) else {
            throw DesignError.invalidResponse("Could not parse Gemini response.")
        }
        return try JSONDecoder().decode(SoundRecipe.self, from: recipeData)
    }

    private static func extractErrorMessage(status: Int, data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = json["error"] as? [String: Any],
           let msg = err["message"] as? String {
            return "Gemini HTTP \(status): \(msg)"
        }
        return "Gemini API returned HTTP \(status)."
    }
}
