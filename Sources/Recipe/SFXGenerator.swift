import Foundation
import AVFoundation

/// Generates novel/creative keystroke sound packs via ElevenLabs Sound Effects API
/// using `ELEVENLABS_API_KEY` from `.env`, trims leading silence for 0-latency
/// keystrokes, and creates micro-variants so rapid typing feels natural.
enum SFXGenerator {
    enum SFXError: LocalizedError {
        case missingApiKey(String)
        case emptyPrompt
        case apiFailed(String)
        case audioProcessingFailed

        var errorDescription: String? {
            switch self {
            case .missingApiKey(let path):
                return "Missing ELEVENLABS_API_KEY in \(path)"
            case .emptyPrompt:
                return "Describe the sound effect you want to generate."
            case .apiFailed(let msg):
                return msg
            case .audioProcessingFailed:
                return "Generated audio could not be converted into a keystroke pack."
            }
        }
    }

    private static let proxyEndpoint = "https://website-one-nu-73.vercel.app/api/sfx"

    static func generatePack(prompt: String, apiKey: String = "") async throws -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SFXError.emptyPrompt }
        let localKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let lower = trimmed.lowercased()
        let isKeyboardPrompt = ["keyboard", "switch", "keycap", "thock", "clack", "typewriter", "mx "]
            .contains { lower.contains($0) }
        let isGameOrChimePrompt = [
            "zelda", "animal crossing", "mario", "nintendo", "pokemon",
            "8-bit", "8bit", "retro", "game", "chime", "bell", "coin",
            "ui", "beep", "bleep", "synth", "piano", "kalimba", "marimba",
            "melody", "note", "voice"
        ].contains { lower.contains($0) }

        let sfxPrompt: String
        if isKeyboardPrompt {
            sfxPrompt = "Single crisp mechanical keyboard key press: \(trimmed), close-mic dry foley, sharp transient, no background noise"
        } else if isGameOrChimePrompt {
            sfxPrompt = "Short clean game UI sound effect: \(trimmed), isolated crisp single chime or bleep, dry studio audio, no background music"
        } else {
            sfxPrompt = "Short isolated percussive tap sound of \(trimmed), crisp single impact foley, dry close-mic, no ambience, no music"
        }

        let body: [String: Any] = [
            "rawPrompt": trimmed,
            "text": sfxPrompt,
            "prompt_influence": 0.75,
            "plan": true
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: body)

        let payload: ServerSFXPayload
        if let proxyResp = try? await requestAudioOrPlan(
            urlString: proxyEndpoint,
            jsonBody: jsonData,
            apiKeyHeader: nil
        ) {
            payload = proxyResp
        } else if !localKey.isEmpty {
            let rawData = try await requestAudio(
                urlString: "https://api.elevenlabs.io/v1/sound-generation?output_format=pcm_44100",
                jsonBody: jsonData,
                apiKeyHeader: localKey
            )
            payload = ServerSFXPayload(
                isGameOrMelodic: isGameOrChimePrompt,
                typing: rawData,
                space: nil,
                enter: nil,
                backspace: nil
            )
        } else {
            throw SFXError.apiFailed("AI Sound service is temporarily unavailable. Please try again in a moment.")
        }

        guard let baseBuffer = pcmBufferFromRawPCM44100(data: payload.typing) else {
            throw SFXError.audioProcessingFailed
        }

        // Adaptive trimming: let every hit decay naturally to silence, with generous
        // safety ceilings (900ms percussive / 1400ms melodic / 1600ms big keys).
        let melodic = isGameOrChimePrompt || payload.isGameOrMelodic
        let sliceMs: Double = melodic ? 1400 : 900
        let slices = extractActiveSlices(baseBuffer, count: 5, sliceMs: sliceMs)
        guard !slices.isEmpty else {
            throw SFXError.apiFailed("Generated audio was too quiet or silent. Try a simpler sound description (no credit used).")
        }

        let packID = sanitizePackName(trimmed)
        let packDir = SoundPackCatalog.customPacksDirectory().appendingPathComponent(packID)
        try FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)

        for (idx, slice) in slices.enumerated() {
            let outURL = packDir.appendingPathComponent("\(idx + 1).wav")
            try writeWav(buffer: slice, to: outURL)
        }

        // Write dedicated Big Key files (space, enter, backspace):
        // Use AI-generated special clips when present, otherwise derive deeper pitch variants
        // locally at zero extra API cost so every pack has distinct big-key acoustics.
        let specialKeys: [(filename: String, data: Data?, fallbackSemitones: Double)] = [
            ("space.wav", payload.space, -3.5),
            ("enter.wav", payload.enter, -2.0),
            ("backspace.wav", payload.backspace, -1.5)
        ]

        for item in specialKeys {
            var chosen: AVAudioPCMBuffer?
            if let keyData = item.data,
               let keyBuf = pcmBufferFromRawPCM44100(data: keyData),
               let keyHit = extractActiveSlices(keyBuf, count: 1, sliceMs: max(sliceMs, 1600)).first {
                chosen = keyHit
            } else {
                chosen = RecipeEngine.resample(slices[0], semitones: item.fallbackSemitones) ?? slices[0]
            }
            if let bufferToWrite = chosen {
                try writeWav(buffer: bufferToWrite, to: packDir.appendingPathComponent(item.filename))
            }
        }

        return packID
    }

    private struct ServerSFXPayload {
        let isGameOrMelodic: Bool
        let typing: Data
        let space: Data?
        let enter: Data?
        let backspace: Data?
    }

    private struct ServerSFXJSON: Decodable {
        let isGameOrMelodic: Bool?
        let typing: String
        let space: String?
        let enter: String?
        let backspace: String?
    }

    private static func requestAudioOrPlan(urlString: String, jsonBody: Data, apiKeyHeader: String?) async throws -> ServerSFXPayload {
        guard let url = URL(string: urlString) else {
            throw SFXError.apiFailed("Invalid SFX service URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKeyHeader, !apiKeyHeader.isEmpty {
            request.setValue(apiKeyHeader, forHTTPHeaderField: "xi-api-key")
        }
        request.httpBody = jsonBody
        request.timeoutInterval = 35

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SFXError.apiFailed("SFX service returned HTTP \(code).")
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("application/json"),
           let decoded = try? JSONDecoder().decode(ServerSFXJSON.self, from: data),
           let typingData = Data(base64Encoded: decoded.typing) {
            return ServerSFXPayload(
                isGameOrMelodic: decoded.isGameOrMelodic ?? false,
                typing: typingData,
                space: decoded.space.flatMap { Data(base64Encoded: $0) },
                enter: decoded.enter.flatMap { Data(base64Encoded: $0) },
                backspace: decoded.backspace.flatMap { Data(base64Encoded: $0) }
            )
        }

        return ServerSFXPayload(isGameOrMelodic: false, typing: data, space: nil, enter: nil, backspace: nil)
    }

    private static func requestAudio(urlString: String, jsonBody: Data, apiKeyHeader: String?) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw SFXError.apiFailed("Invalid SFX service URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKeyHeader, !apiKeyHeader.isEmpty {
            request.setValue(apiKeyHeader, forHTTPHeaderField: "xi-api-key")
        }
        request.httpBody = jsonBody
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw SFXError.apiFailed("SFX service returned HTTP \(http.statusCode).")
        }
        return data
    }

    private static func extractActiveSlices(_ src: AVAudioPCMBuffer, count: Int, sliceMs: Double) -> [AVAudioPCMBuffer] {
        guard let ch = src.floatChannelData?[0] else { return [] }
        let total = Int(src.frameLength)
        let sr = src.format.sampleRate
        let maxSliceFrames = Int(sliceMs / 1000.0 * sr)
        let minSliceFrames = Int(0.100 * sr)
        guard total > Int(0.040 * sr) else { return [] }

        var globalMax: Float = 0
        for i in 0..<total {
            let a = abs(ch[i])
            if a > globalMax { globalMax = a }
        }
        guard globalMax > 0.001 else { return [] }

        // Normalize clip peak to 0.85 so quiet-but-real sounds use consistent thresholds.
        let normGain: Float = 0.85 / globalMax
        for i in 0..<total {
            ch[i] *= normGain
        }

        // Compute 5ms RMS envelope to detect real attacks without slicing mid-sustain.
        let win = max(1, Int(0.005 * sr))
        let numBins = total / win
        guard numBins > 2 else { return [] }
        var env = [Float](repeating: 0, count: numBins)
        var envMax: Float = 0
        for b in 0..<numBins {
            let start = b * win
            var sumSq: Float = 0
            for i in start..<(start + win) {
                sumSq += ch[i] * ch[i]
            }
            let rms = sqrt(sumSq / Float(win))
            env[b] = rms
            if rms > envMax { envMax = rms }
        }
        guard envMax > 0.005 else { return [] }

        // Gate + re-arm onset detection:
        // Only trigger a new hit after a true 30ms silence gap (<3% of previous hit RMS)
        // so any continuous sound is never split mid-phrase.
        let triggerFloor = max(envMax * 0.25, 0.020)
        let minBinsBetweenOnsets = max(1, Int(0.140 / 0.005)) // 140ms
        var onsets: [Int] = []
        var armed = true
        var rearmQuietRun = 0
        var activeHitPeakRMS: Float = 0
        var lastOnsetBin = -minBinsBetweenOnsets

        for b in 0..<numBins {
            let cur = env[b]
            if !armed {
                if cur < max(activeHitPeakRMS * 0.03, envMax * 0.025) {
                    rearmQuietRun += 1
                    if rearmQuietRun >= 6 { // 30ms true silence
                        armed = true
                        rearmQuietRun = 0
                    }
                } else {
                    rearmQuietRun = 0
                }
            }

            if armed && cur >= triggerFloor && (b - lastOnsetBin) >= minBinsBetweenOnsets {
                // Find exact sample onset just before the transient rises
                let searchStart = max(0, (b - 4) * win)
                let searchEnd = min(total - 1, (b + 3) * win)
                var localPeak: Float = 0
                for j in searchStart...searchEnd {
                    localPeak = max(localPeak, abs(ch[j]))
                }
                let thresh = localPeak * 0.06
                var onsetSample = searchStart
                for j in searchStart...searchEnd {
                    if abs(ch[j]) >= thresh {
                        onsetSample = max(0, j - Int(0.002 * sr))
                        break
                    }
                }

                onsets.append(onsetSample)
                lastOnsetBin = b
                armed = false
                rearmQuietRun = 0
                // Track peak RMS across the next ~80ms for re-arm threshold
                let peakEnd = min(numBins, b + 16)
                activeHitPeakRMS = env[b..<peakEnd].max() ?? cur
                if onsets.count >= count { break }
            }
        }

        // Build each hit up to natural decay (or next hit onset / maxSliceFrames)
        var rawHits: [(buffer: AVAudioPCMBuffer, peak: Float)] = []
        for idx in 0..<onsets.count {
            let onset = onsets[idx]
            let nextOnsetGap = (idx + 1 < onsets.count) ? max(minSliceFrames, onsets[idx + 1] - onset - Int(0.004 * sr)) : maxSliceFrames
            let capLen = min(maxSliceFrames, min(total - onset, nextOnsetGap))
            guard capLen > Int(0.030 * sr) else { continue }

            // Measure local peak RMS of this hit, then stop early once tail decays to real silence
            let onsetBin = min(numBins - 1, onset / win)
            let hitPeakEndBin = min(numBins, onsetBin + 20)
            let hitPeakRMS = env[onsetBin..<hitPeakEndBin].max() ?? envMax
            let silenceRMS = max(hitPeakRMS * 0.015, 0.002)

            var endLen = capLen
            var stoppedNaturally = false
            let minBin = onsetBin + (minSliceFrames / win)
            let maxBin = min(numBins - 1, (onset + capLen) / win)
            if maxBin > minBin + 5 {
                var quietRun = 0
                for b in minBin...maxBin {
                    if env[b] < silenceRMS {
                        quietRun += 1
                        if quietRun >= 5 { // 25ms of natural silence
                            endLen = min(capLen, max(minSliceFrames, (b * win) - onset))
                            stoppedNaturally = true
                            break
                        }
                    } else {
                        quietRun = 0
                    }
                }
            }

            guard let slice = AVAudioPCMBuffer(pcmFormat: src.format, frameCapacity: AVAudioFrameCount(endLen)),
                  let outCh = slice.floatChannelData?[0] else { continue }
            slice.frameLength = AVAudioFrameCount(endLen)
            var slicePeak: Float = 0
            for i in 0..<endLen {
                let s = ch[onset + i]
                outCh[i] = s
                if abs(s) > slicePeak { slicePeak = abs(s) }
            }
            guard slicePeak > 0.02 else { continue }

            let fadeIn = min(endLen, Int(0.002 * sr))
            for i in 0..<fadeIn { outCh[i] *= Float(i) / Float(fadeIn) }
            // Smooth raised-cosine fade-out: 25ms if already decayed, 140ms if capped
            let fadeOutMs = stoppedNaturally ? 0.025 : 0.140
            let fadeOut = min(endLen / 2, Int(fadeOutMs * sr))
            if fadeOut > 0 {
                for i in 0..<fadeOut {
                    let t = Float(i) / Float(fadeOut) // 0 at end -> 1 at fade start
                    let gain = 0.5 * (1.0 - cos(Float.pi * t))
                    outCh[endLen - 1 - i] *= gain
                }
            }
            rawHits.append((slice, slicePeak))
        }

        let maxHitPeak = rawHits.map(\.peak).max() ?? 0
        let hits = rawHits.filter { $0.peak >= maxHitPeak * 0.30 }.map(\.buffer)

        guard !hits.isEmpty else { return [] }

        // If fewer than `count` real hits were found, derive subtle pitch variants
        // from the real hits instead of ever slicing sustained tails or silent gaps.
        if hits.count >= count {
            return Array(hits.prefix(count))
        }
        var results = hits
        let microSemis: [Double] = [-0.55, 0.45, -0.25, 0.7]
        var idx = 0
        while results.count < count {
            let base = hits[idx % hits.count]
            let st = microSemis[idx % microSemis.count]
            results.append(RecipeEngine.resample(base, semitones: st) ?? base)
            idx += 1
        }
        return results
    }

    private static func sanitizePackName(_ prompt: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " _-"))
        let cleaned = prompt.unicodeScalars.filter { allowed.contains($0) }
        let raw = String(String.UnicodeScalarView(cleaned))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
        let prefix = String(raw.prefix(24))
        return prefix.isEmpty ? "Custom_SFX_\(Int(Date().timeIntervalSince1970))" : prefix
    }

    private static func pcmBufferFromRawPCM44100(data: Data) -> AVAudioPCMBuffer? {
        guard data.count >= 4 else { return nil }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false) else {
            return nil
        }
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)),
              let out = buffer.floatChannelData?[0] else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        data.withUnsafeBytes { raw in
            let int16Ptr = raw.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                out[i] = Float(int16Ptr[i]) / 32768.0
            }
        }
        return buffer
    }

    private static func writeWav(buffer: AVAudioPCMBuffer, to url: URL) throws {
        let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
        try file.write(from: buffer)
    }
}
