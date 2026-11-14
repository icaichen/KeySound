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

    static func generatePack(prompt: String, apiKey: String) async throws -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SFXError.emptyPrompt }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw SFXError.missingApiKey(EnvConfig.primaryEnvPathHint())
        }

        guard let url = URL(string: "https://api.elevenlabs.io/v1/sound-generation?output_format=pcm_44100") else {
            throw SFXError.apiFailed("Invalid ElevenLabs URL.")
        }

        let lower = trimmed.lowercased()
        let isKeyboardPrompt = ["keyboard", "switch", "keycap", "thock", "clack", "typewriter", "mx "]
            .contains { lower.contains($0) }
        let sfxPrompt = isKeyboardPrompt
            ? "Single crisp mechanical keyboard key press: \(trimmed), close-mic dry foley, sharp transient, no background noise"
            : "Short isolated percussive tap sound of \(trimmed), crisp single impact foley, dry close-mic, no ambience, no music"

        let body: [String: Any] = [
            "text": sfxPrompt,
            "duration_seconds": 1.2,
            "prompt_influence": 0.75
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw SFXError.apiFailed("ElevenLabs API returned HTTP \(http.statusCode).")
        }

        let packID = sanitizePackName(trimmed)
        let packDir = SoundPackCatalog.customPacksDirectory().appendingPathComponent(packID)
        try FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)

        guard let baseBuffer = pcmBufferFromRawPCM44100(data: data) else {
            throw SFXError.audioProcessingFailed
        }

        // Extract up to 5 distinct active slices across the 1.5s clip so textures
        // like rain, wood, or pops sound natural and varied on every keystroke.
        let slices = extractActiveSlices(baseBuffer, count: 5, sliceMs: 180)
        if slices.isEmpty {
            let fallback = trimSilenceAndCap(baseBuffer, maxMs: 220) ?? baseBuffer
            let outURL = packDir.appendingPathComponent("1.wav")
            try writeWav(buffer: fallback, to: outURL)
        } else {
            for (idx, slice) in slices.enumerated() {
                let outURL = packDir.appendingPathComponent("\(idx + 1).wav")
                try writeWav(buffer: slice, to: outURL)
            }
        }

        return packID
    }

    private static func extractActiveSlices(_ src: AVAudioPCMBuffer, count: Int, sliceMs: Double) -> [AVAudioPCMBuffer] {
        guard let ch = src.floatChannelData?[0] else { return [] }
        let total = Int(src.frameLength)
        let sr = src.format.sampleRate
        let sliceFrames = Int(sliceMs / 1000.0 * sr)
        guard total > 64 else { return [] }

        var globalMax: Float = 0
        for i in 0..<total {
            let a = abs(ch[i])
            if a > globalMax { globalMax = a }
        }
        guard globalMax > 0.005 else { return [] }

        // Peak-pick distinct transients: >= 22% of globalMax, separated by >= 120ms.
        let minPeak = globalMax * 0.22
        let minSep = Int(0.120 * sr)
        var pickedPeaks: [Int] = []
        var suppressed = [Bool](repeating: false, count: total)

        for _ in 0..<count {
            var bestIdx = -1
            var bestVal: Float = 0
            for i in 0..<total where !suppressed[i] {
                let a = abs(ch[i])
                if a > bestVal {
                    bestVal = a
                    bestIdx = i
                }
            }
            guard bestIdx >= 0, bestVal >= minPeak else { break }
            pickedPeaks.append(bestIdx)
            let lo = max(0, bestIdx - minSep)
            let hi = min(total - 1, bestIdx + minSep)
            for j in lo...hi { suppressed[j] = true }
        }

        // Build clean onset-aligned slices for each real transient.
        var hits: [AVAudioPCMBuffer] = []
        let lookback = Int(0.025 * sr)
        let preRoll = Int(0.002 * sr)

        for peakIdx in pickedPeaks.sorted() {
            let peakAmp = abs(ch[peakIdx])
            let onsetThreshold = peakAmp * 0.08
            let searchFrom = max(0, peakIdx - lookback)
            var onset = searchFrom
            for j in stride(from: peakIdx, through: searchFrom, by: -1) {
                if abs(ch[j]) < onsetThreshold {
                    onset = max(0, j - preRoll)
                    break
                }
            }

            let len = min(sliceFrames, total - onset)
            guard len > Int(0.020 * sr),
                  let slice = AVAudioPCMBuffer(pcmFormat: src.format, frameCapacity: AVAudioFrameCount(len)),
                  let outCh = slice.floatChannelData?[0] else { continue }
            slice.frameLength = AVAudioFrameCount(len)
            for i in 0..<len {
                outCh[i] = ch[onset + i]
            }
            let fadeIn = min(len, Int(0.002 * sr))
            for i in 0..<fadeIn { outCh[i] *= Float(i) / Float(fadeIn) }
            let fadeOut = min(len, Int(0.020 * sr))
            for i in 0..<fadeOut { outCh[len - 1 - i] *= Float(i) / Float(fadeOut) }
            hits.append(slice)
        }

        guard !hits.isEmpty else { return [] }

        // If fewer than `count` real hits were found, derive subtle pitch variants
        // from the real hits instead of ever slicing silent gaps.
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
        return prefix.isEmpty ? "AI_SFX_\(Int(Date().timeIntervalSince1970))" : "AI_\(prefix)"
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

    private static func trimSilenceAndCap(_ src: AVAudioPCMBuffer, maxMs: Double) -> AVAudioPCMBuffer? {
        guard let ch = src.floatChannelData?[0] else { return nil }
        let total = Int(src.frameLength)
        guard total > 0 else { return nil }

        // Find first sample above -36dB (~0.015) so keystroke triggers with zero dead air.
        var start = 0
        for i in 0..<total {
            if abs(ch[i]) > 0.015 {
                start = max(0, i - 64)
                break
            }
        }
        let maxFrames = Int(maxMs / 1000.0 * src.format.sampleRate)
        let len = min(total - start, maxFrames)
        guard len > 16,
              let out = AVAudioPCMBuffer(pcmFormat: src.format, frameCapacity: AVAudioFrameCount(len)),
              let outCh = out.floatChannelData?[0] else { return nil }
        out.frameLength = AVAudioFrameCount(len)
        for i in 0..<len {
            outCh[i] = ch[start + i]
        }
        // Short 10ms fade-out to avoid clicks
        let fade = min(len, Int(0.010 * src.format.sampleRate))
        for i in 0..<fade {
            let idx = len - 1 - i
            outCh[idx] *= Float(i) / Float(fade)
        }
        return out
    }

    private static func writeWav(buffer: AVAudioPCMBuffer, to url: URL) throws {
        let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
        try file.write(from: buffer)
    }
}
