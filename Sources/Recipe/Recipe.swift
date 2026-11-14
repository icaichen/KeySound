import Foundation

// Codable model for Sound Recipe schema v2.
// v2 = sample-based DJ board: each layer plays a real recording (from a built-in
// pack or a user-imported WAV) with pitch / gain / trim / lowpass shaping.

private extension KeyedDecodingContainer {
    /// Decode a field or fall back to the schema default.
    func d<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

struct SoundRecipe: Codable {
    var version: Int
    var meta: Meta
    var layers: Layers
    var master: Master
    var humanize: Humanize
    var keymap: Keymap

    struct Meta: Codable {
        var name: String
        var author: String?
        var description: String?
        var tags: [String]?
        var basedOn: String?
    }

    /// Reference to a sample: a file inside a built-in pack (pack = folder name under
    /// Sounds/) or an absolute path for user-imported files.
    struct SampleRef: Codable {
        var pack: String   // e.g. "Thocky", or "@user" for imported files
        var file: String   // e.g. "2.wav", or absolute path when pack == "@user"
    }

    /// One channel strip of the DJ board.
    struct SampleLayer: Codable {
        var enabled: Bool
        var gain: Double
        var pitchShiftSt: Double      // semitones, +-12
        var trimMs: Double            // 0 = full sample
        var lowpassHz: Double         // 20000 = bypass; lower = tape-mod / foam feel
        var sample: SampleRef?

        enum CodingKeys: String, CodingKey { case enabled, gain, pitchShiftSt, trimMs, lowpassHz, sample }
        init(enabled: Bool = false, gain: Double = 1, pitchShiftSt: Double = 0,
             trimMs: Double = 0, lowpassHz: Double = 20000, sample: SampleRef? = nil) {
            self.enabled = enabled
            self.gain = gain
            self.pitchShiftSt = pitchShiftSt
            self.trimMs = trimMs
            self.lowpassHz = lowpassHz
            self.sample = sample
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decode(Bool.self, forKey: .enabled)
            gain = c.d(.gain, 1)
            pitchShiftSt = c.d(.pitchShiftSt, 0)
            trimMs = c.d(.trimMs, 0)
            lowpassHz = c.d(.lowpassHz, 20000)
            sample = try c.decodeIfPresent(SampleRef.self, forKey: .sample)
        }
    }

    struct SpaceLayer: Codable {
        var enabled: Bool
        var reverbWet: Double
        var roomSize: Double
        var stereoWidth: Double

        enum CodingKeys: String, CodingKey { case enabled, reverbWet, roomSize, stereoWidth }
        init(enabled: Bool = false, reverbWet: Double = 0.1, roomSize: Double = 0.3, stereoWidth: Double = 0.7) {
            self.enabled = enabled
            self.reverbWet = reverbWet
            self.roomSize = roomSize
            self.stereoWidth = stereoWidth
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decode(Bool.self, forKey: .enabled)
            reverbWet = c.d(.reverbWet, 0.1)
            roomSize = c.d(.roomSize, 0.3)
            stereoWidth = c.d(.stereoWidth, 0.7)
        }
    }

    struct Layers: Codable {
        var click: SampleLayer
        var body: SampleLayer
        var release: SampleLayer
        var space: SpaceLayer

        enum CodingKeys: String, CodingKey { case click, body, release, space }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            click = c.d(.click, SampleLayer())
            body = c.d(.body, SampleLayer())
            release = c.d(.release, SampleLayer())
            space = c.d(.space, SpaceLayer())
        }
        init(click: SampleLayer, body: SampleLayer, release: SampleLayer, space: SpaceLayer) {
            self.click = click
            self.body = body
            self.release = release
            self.space = space
        }
    }

    struct EQ: Codable {
        var lowDb: Double
        var midDb: Double
        var highDb: Double

        enum CodingKeys: String, CodingKey { case lowDb, midDb, highDb }
        init(lowDb: Double = 0, midDb: Double = 0, highDb: Double = 0) {
            self.lowDb = lowDb
            self.midDb = midDb
            self.highDb = highDb
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            lowDb = c.d(.lowDb, 0)
            midDb = c.d(.midDb, 0)
            highDb = c.d(.highDb, 0)
        }
    }

    struct Master: Codable {
        var gain: Double
        var eq: EQ

        enum CodingKeys: String, CodingKey { case gain, eq }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            gain = try c.decode(Double.self, forKey: .gain)
            eq = c.d(.eq, EQ())
        }
        init(gain: Double, eq: EQ) {
            self.gain = gain
            self.eq = eq
        }
    }

    struct Humanize: Codable {
        var pitchJitterSt: Double
        var gainJitterDb: Double
        var timingJitterMs: Double

        enum CodingKeys: String, CodingKey { case pitchJitterSt, gainJitterDb, timingJitterMs }
        init(pitchJitterSt: Double = 0.4, gainJitterDb: Double = 1.5, timingJitterMs: Double = 2) {
            self.pitchJitterSt = pitchJitterSt
            self.gainJitterDb = gainJitterDb
            self.timingJitterMs = timingJitterMs
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pitchJitterSt = c.d(.pitchJitterSt, 0.4)
            gainJitterDb = c.d(.gainJitterDb, 1.5)
            timingJitterMs = c.d(.timingJitterMs, 2)
        }
    }

    struct KeyOverride: Codable {
        var pitchShift: Double
        var gainScale: Double
        var decayScale: Double

        enum CodingKeys: String, CodingKey { case pitchShift, gainScale, decayScale }
        init(pitchShift: Double = 0, gainScale: Double = 1, decayScale: Double = 1) {
            self.pitchShift = pitchShift
            self.gainScale = gainScale
            self.decayScale = decayScale
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pitchShift = c.d(.pitchShift, 0)
            gainScale = c.d(.gainScale, 1)
            decayScale = c.d(.decayScale, 1)
        }
    }

    struct Keymap: Codable {
        var space: KeyOverride?
        var enter: KeyOverride?
        var backspace: KeyOverride?
        var modifier: KeyOverride?
        var keyPitchMode: String

        enum CodingKeys: String, CodingKey { case space, enter, backspace, modifier, keyPitchMode }
        init() {
            space = nil; enter = nil; backspace = nil; modifier = nil
            keyPitchMode = "off"
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            space = try c.decodeIfPresent(KeyOverride.self, forKey: .space)
            enter = try c.decodeIfPresent(KeyOverride.self, forKey: .enter)
            backspace = try c.decodeIfPresent(KeyOverride.self, forKey: .backspace)
            modifier = try c.decodeIfPresent(KeyOverride.self, forKey: .modifier)
            keyPitchMode = c.d(.keyPitchMode, "off")
        }

        func override(for category: String) -> KeyOverride? {
            switch category {
            case "space": return space
            case "enter": return enter
            case "backspace": return backspace
            case "modifier": return modifier
            default: return nil
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case version, meta, layers, master, humanize, keymap
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        guard version == 2 else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: c,
                debugDescription: "Unsupported recipe version \(version)")
        }
        meta = try c.decode(Meta.self, forKey: .meta)
        layers = try c.decode(Layers.self, forKey: .layers)
        master = try c.decode(Master.self, forKey: .master)
        humanize = c.d(.humanize, Humanize())
        keymap = c.d(.keymap, Keymap())
    }

    init(meta: Meta, layers: Layers, master: Master, humanize: Humanize, keymap: Keymap) {
        self.version = 2
        self.meta = meta
        self.layers = layers
        self.master = master
        self.humanize = humanize
        self.keymap = keymap
    }

    static func load(from url: URL) throws -> SoundRecipe {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SoundRecipe.self, from: data)
    }
}
