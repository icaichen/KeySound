import SwiftUI
import UniformTypeIdentifiers

// Sound Lab v2: sample-mixing DJ board with AI Sound Designer, Big Key tuning,
// plain-English controls, and recipe import/export sharing.

struct SoundLabView: View {
    @State private var recipe: SoundRecipe
    @State private var savedFlash = false
    @State private var showAdvanced = false
    @State private var catalog: [(pack: String, files: [String])] = []
    @State private var presets: [URL] = []
    @State private var selectedPreset: String = ""
    @State private var testInput: String = ""

    // No-AI Acoustic Matrix state
    @State private var matrixBase: AISoundDesigner.SwitchBase = .tactile
    @State private var matrixMod: AISoundDesigner.AcousticMod = .thock

    // AI Sound Designer & SFX state
    @State private var aiPrompt: String = ""
    @State private var isGeneratingAI = false
    @State private var aiStatusMessage: String?
    @State private var aiError: String?

    init() {
        let engine = AudioEngineManager.shared
        _recipe = State(initialValue: engine.currentRecipe ?? engine.bundledRecipe() ?? SoundRecipe.fallback)
    }

    private func bind<T>(_ keyPath: WritableKeyPath<SoundRecipe, T>) -> Binding<T> {
        Binding(
            get: { recipe[keyPath: keyPath] },
            set: { newValue in
                recipe[keyPath: keyPath] = newValue
                AudioEngineManager.shared.updateRecipe(recipe)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    acousticMatrixSection
                    aiDesignerSection
                    layerSection(
                        "Click (Initial Snap)",
                        subtitle: "Sharp first contact when your finger hits the keycap",
                        layer: \.layers.click
                    )
                    layerSection(
                        "Body (Main Tone)",
                        subtitle: "Core thock, clack, or pop of the switch",
                        layer: \.layers.body
                    )
                    layerSection(
                        "Release (Key Up)",
                        subtitle: "Softer return sound when the key springs back",
                        layer: \.layers.release
                    )
                    bigKeysSection
                    masterSection
                    DisclosureGroup("Advanced (Room & Humanize)", isExpanded: $showAdvanced) {
                        VStack(alignment: .leading, spacing: 14) {
                            spaceSection
                            humanizeSection
                        }
                        .padding(.top, 8)
                    }
                    footer
                }
                .padding()
            }
            Divider()
            testTypingBar
        }
        .frame(width: 580, height: 640)
        .onAppear {
            catalog = AudioEngineManager.shared.sampleCatalog()
            presets = AudioEngineManager.shared.bundledPresetURLs()
            if selectedPreset.isEmpty {
                let names = presets.map { $0.lastPathComponent }
                selectedPreset = names.first(where: { $0 == "custom-thock.recipe.json" })
                    ?? names.first ?? ""
            }
        }
    }

    // MARK: - Header & AI Designer

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(recipe.meta.name).font(.headline)
                Spacer()
                presetPicker
            }
        }
    }

    private var presetPicker: some View {
        let selection = Binding<String>(
            get: { selectedPreset },
            set: { name in
                selectedPreset = name
                if let url = presets.first(where: { $0.lastPathComponent == name }),
                   let loaded = AudioEngineManager.shared.loadPresetFile(url) {
                    recipe = loaded
                    AudioEngineManager.shared.updateRecipe(loaded)
                }
            }
        )
        return HStack(spacing: 6) {
            Text("Preset").font(.caption).foregroundColor(.secondary)
            Picker("Preset", selection: selection) {
                ForEach(presets.map { $0.lastPathComponent }, id: \.self) { name in
                    Text(name.replacingOccurrences(of: ".recipe.json", with: "")).tag(name)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 170)
        }
    }

    private var acousticMatrixSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Instant Switch Builder (No AI Needed)", systemImage: "slider.horizontal.3")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("Mixes real recordings")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 10) {
                    Picker("Switch", selection: $matrixBase) {
                        ForEach(AISoundDesigner.SwitchBase.allCases) { b in
                            Text(b.rawValue).tag(b)
                        }
                    }
                    .onChange(of: matrixBase) { _ in applyMatrix() }

                    Picker("Vibe", selection: $matrixMod) {
                        ForEach(AISoundDesigner.AcousticMod.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .onChange(of: matrixMod) { _ in applyMatrix() }

                    Button("Apply") { applyMatrix() }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func applyMatrix() {
        let built = AISoundDesigner.buildFromMatrix(base: matrixBase, mod: matrixMod, catalog: catalog)
        recipe = built
        AudioEngineManager.shared.updateRecipe(built)
    }

    private var aiDesignerSection: some View {
        let hasMixKey = !EnvConfig.deepseekApiKey.isEmpty || !EnvConfig.geminiApiKey.isEmpty
        let hasEleven = !EnvConfig.elevenLabsApiKey.isEmpty

        return GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("AI Sound Lab (.env)", systemImage: "sparkles")
                        .font(.subheadline.bold())
                    Spacer()
                    Text(hasMixKey || hasEleven ? "API Key Loaded" : "Add Keys to .env")
                        .font(.caption2)
                        .foregroundColor(hasMixKey || hasEleven ? .green : .secondary)
                }

                HStack(spacing: 8) {
                    TextField("Describe a switch or creative sound (e.g. \"Raindrops on wood\", \"Animal Crossing\")", text: $aiPrompt)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { runAIDesigner() }
                    Button(action: runAIDesigner) {
                        if isGeneratingAI {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("AI Mix")
                        }
                    }
                    .disabled(isGeneratingAI || aiPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Uses GEMINI_API_KEY from .env to design a custom mechanical switch recipe")

                    Button(action: runSFXGenerator) {
                        Text("AI SFX Pack")
                    }
                    .disabled(isGeneratingAI || aiPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Uses ELEVENLABS_API_KEY from .env to generate a brand-new WAV sound pack")
                }

                if let status = aiStatusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.green)
                }

                if let err = aiError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func runAIDesigner() {
        aiError = nil
        aiStatusMessage = nil
        isGeneratingAI = true
        let prompt = aiPrompt
        let currentCatalog = catalog
        let dsKey = EnvConfig.deepseekApiKey
        let gmKey = EnvConfig.geminiApiKey
        Task {
            do {
                let result = try await AISoundDesigner.generateWithAI(
                    prompt: prompt,
                    catalog: currentCatalog,
                    deepseekKey: dsKey,
                    geminiKey: gmKey
                )
                await MainActor.run {
                    recipe = result.recipe
                    AudioEngineManager.shared.updateRecipe(result.recipe)
                    aiStatusMessage = "\(result.statusNote): \(result.recipe.meta.name)"
                    isGeneratingAI = false
                }
            } catch {
                await MainActor.run {
                    aiError = error.localizedDescription
                    isGeneratingAI = false
                }
            }
        }
    }

    private func runSFXGenerator() {
        aiError = nil
        aiStatusMessage = nil
        isGeneratingAI = true
        let prompt = aiPrompt
        let apiKey = EnvConfig.elevenLabsApiKey
        Task {
            do {
                let packID = try await SFXGenerator.generatePack(prompt: prompt, apiKey: apiKey)
                await MainActor.run {
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.loadProfiles()
                        delegate.selectProfile(packID)
                    } else {
                        AudioEngineManager.shared.loadSounds(for: packID)
                    }
                    aiStatusMessage = "Created & activated pack \"\(SoundPackCatalog.displayName(for: packID))\" (also in Browse All Sounds)."
                    isGeneratingAI = false
                }
            } catch {
                await MainActor.run {
                    aiError = error.localizedDescription
                    isGeneratingAI = false
                }
            }
        }
    }

    // MARK: - Layer channel strip

    private func layerSection(
        _ title: String,
        subtitle: String,
        layer: WritableKeyPath<SoundRecipe, SoundRecipe.SampleLayer>
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle(title, isOn: bind(layer).enabled)
                        .toggleStyle(.switch)
                        .font(.subheadline.bold())
                    Spacer()
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if recipe[keyPath: layer].enabled {
                    HStack {
                        samplePicker(layer: layer)
                        Button(action: {
                            if let s = recipe[keyPath: layer].sample {
                                AudioEngineManager.shared.previewSample(s)
                            }
                        }) {
                            Image(systemName: "play.circle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(recipe[keyPath: layer].sample == nil)
                        .help("Preview this raw sample")
                    }

                    slider(
                        "Volume",
                        bind(layer).gain,
                        0...1.5,
                        help: "How loud this layer is in the mix",
                        format: { "\(Int($0 * 100))%" }
                    )
                    slider(
                        "Pitch (Deep ↔ Bright)",
                        bind(layer).pitchShiftSt,
                        -12...12,
                        help: "Lower values sound heavier/deeper; higher values sound lighter/crisper",
                        format: { String(format: "%+.1f st", $0) }
                    )
                    slider(
                        "Length (Snappiness)",
                        bind(layer).trimMs,
                        0...300,
                        help: "Cuts off the tail after X ms (0 = play full sample)",
                        format: { $0 < 1 ? "Full" : "\(Int($0)) ms" }
                    )
                    slider(
                        "Damping (Foam Feel)",
                        dampBinding(layer),
                        0...1,
                        help: "Rolls off harsh high frequencies like case/plate foam",
                        format: { $0 <= 0.01 ? "Open" : "\(Int($0 * 100))%" }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func samplePicker(layer: WritableKeyPath<SoundRecipe, SoundRecipe.SampleLayer>) -> some View {
        let selection = Binding<String>(
            get: {
                guard let s = recipe[keyPath: layer].sample else { return "none" }
                return s.pack
            },
            set: { pack in
                if pack == "none" {
                    recipe[keyPath: layer].sample = nil
                } else {
                    recipe[keyPath: layer].sample = SoundRecipe.SampleRef(pack: pack, file: "generic")
                }
                AudioEngineManager.shared.updateRecipe(recipe)
            }
        )
        return Picker("Sound", selection: selection) {
            Text("None").tag("none")
            ForEach(catalog, id: \.pack) { entry in
                Text(SoundPackCatalog.displayName(for: entry.pack)).tag(entry.pack)
            }
        }
        .pickerStyle(.menu)
    }

    private func dampBinding(_ layer: WritableKeyPath<SoundRecipe, SoundRecipe.SampleLayer>) -> Binding<Double> {
        Binding(
            get: {
                let hz = recipe[keyPath: layer].lowpassHz
                if hz >= 20000 { return 0 }
                return min(1, max(0, 1 - (log(hz) - log(600)) / (log(20000) - log(600))))
            },
            set: { t in
                let hz = t <= 0.001 ? 20000 : exp(log(20000) - t * (log(20000) - log(600)))
                recipe[keyPath: layer].lowpassHz = hz
                AudioEngineManager.shared.updateRecipe(recipe)
            }
        )
    }

    // MARK: - Big Keys

    private var bigKeysSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Big Keys (Space / Enter / Backspace)").font(.subheadline).bold()
                    Spacer()
                    Text("Make stabilizer keys sound deeper")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                slider(
                    "Spacebar Pitch",
                    spacePitchBinding,
                    -8...2,
                    help: "Shifts Spacebar, Enter, and Backspace lower for realistic stabilizer thock",
                    format: { String(format: "%+.1f st", $0) }
                )
                slider(
                    "Big Key Weight",
                    bigKeyGainBinding,
                    0.8...1.4,
                    help: "Relative volume boost for larger keys",
                    format: { "\(Int($0 * 100))%" }
                )
            }
            .padding(.vertical, 4)
        }
    }

    private var spacePitchBinding: Binding<Double> {
        Binding(
            get: { recipe.keymap.space?.pitchShift ?? 0 },
            set: { v in
                let existingSpace = recipe.keymap.space ?? SoundRecipe.KeyOverride()
                recipe.keymap.space = SoundRecipe.KeyOverride(pitchShift: v, gainScale: existingSpace.gainScale, decayScale: existingSpace.decayScale)
                recipe.keymap.enter = SoundRecipe.KeyOverride(pitchShift: v * 0.65, gainScale: existingSpace.gainScale, decayScale: existingSpace.decayScale)
                recipe.keymap.backspace = SoundRecipe.KeyOverride(pitchShift: v * 0.45, gainScale: existingSpace.gainScale, decayScale: existingSpace.decayScale)
                AudioEngineManager.shared.updateRecipe(recipe)
            }
        )
    }

    private var bigKeyGainBinding: Binding<Double> {
        Binding(
            get: { recipe.keymap.space?.gainScale ?? 1.0 },
            set: { g in
                let sp = recipe.keymap.space ?? SoundRecipe.KeyOverride()
                recipe.keymap.space = SoundRecipe.KeyOverride(pitchShift: sp.pitchShift, gainScale: g, decayScale: sp.decayScale)
                let en = recipe.keymap.enter ?? SoundRecipe.KeyOverride()
                recipe.keymap.enter = SoundRecipe.KeyOverride(pitchShift: en.pitchShift, gainScale: g, decayScale: en.decayScale)
                let bk = recipe.keymap.backspace ?? SoundRecipe.KeyOverride()
                recipe.keymap.backspace = SoundRecipe.KeyOverride(pitchShift: bk.pitchShift, gainScale: g, decayScale: bk.decayScale)
                AudioEngineManager.shared.updateRecipe(recipe)
            }
        )
    }

    // MARK: - Master & Advanced

    private var masterSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Master Finish").font(.subheadline).bold()
                slider("Master Volume", bind(\.master.gain), 0...1.5, help: "Overall output level of this recipe", format: { "\(Int($0 * 100))%" })
                slider("Room Echo", roomBinding, 0...0.4, help: "Adds subtle desk/room ambience", format: { "\(Int($0 / 0.4 * 100))%" })
                slider("Stereo Spread", bind(\.layers.space.stereoWidth), 0...1, help: "Left keys pan left, right keys pan right", format: { "\(Int($0 * 100))%" })
                slider("Bass (Thump)", bind(\.master.eq.lowDb), -12...12, help: "Boosts or cuts low-end warmth", format: { String(format: "%+.1f dB", $0) })
                slider("Treble (Crispness)", bind(\.master.eq.highDb), -12...12, help: "Boosts or cuts high-frequency snap", format: { String(format: "%+.1f dB", $0) })
                slider("Human Variation", randomBinding, 0...1, help: "Micro-varies each keystroke so fast typing feels natural", format: { "\(Int($0 * 100))%" })
            }
            .padding(.vertical, 4)
        }
    }

    private var roomBinding: Binding<Double> {
        Binding(get: { recipe.layers.space.reverbWet }, set: { v in
            recipe.layers.space.reverbWet = v
            recipe.layers.space.enabled = v > 0.001
            AudioEngineManager.shared.updateRecipe(recipe)
        })
    }

    private var randomBinding: Binding<Double> {
        Binding(
            get: { min(1, recipe.humanize.pitchJitterSt / 0.8) },
            set: { v in
                recipe.humanize.pitchJitterSt = v * 0.8
                recipe.humanize.gainJitterDb = v * 3
                AudioEngineManager.shared.updateRecipe(recipe)
            }
        )
    }

    private var spaceSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Space (Room Reverb)", isOn: bind(\.layers.space.enabled))
                    .toggleStyle(.switch)
                if recipe.layers.space.enabled {
                    slider("Reverb Wet", bind(\.layers.space.reverbWet), 0...1, format: { "\(Int($0 * 100))%" })
                    slider("Room Size", bind(\.layers.space.roomSize), 0...1, format: { "\(Int($0 * 100))%" })
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var humanizeSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Humanize (Per-Keystroke Jitter)").font(.subheadline).bold()
                slider("Pitch Jitter", bind(\.humanize.pitchJitterSt), 0...2, format: { String(format: "±%.2f st", $0) })
                slider("Volume Jitter", bind(\.humanize.gainJitterDb), 0...6, format: { String(format: "±%.1f dB", $0) })
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Footer & Sharing

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Save as My Sound") {
                var toSave = recipe
                toSave.meta.name = "My Sound"
                AudioEngineManager.shared.saveRecipe(toSave)
                withAnimation { savedFlash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation { savedFlash = false }
                }
            }
            .buttonStyle(.borderedProminent)

            if savedFlash {
                Text("Saved").foregroundColor(.green).font(.caption)
            }

            Spacer()

            Button("Import…") { importRecipe() }
            Button("Export…") { exportRecipe() }
            Button("Reset") {
                AudioEngineManager.shared.deleteUserRecipe()
                if let preset = AudioEngineManager.shared.bundledRecipe() {
                    recipe = preset
                    AudioEngineManager.shared.updateRecipe(preset)
                }
            }
        }
    }

    private var testTypingBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard").foregroundColor(.secondary)
            TextField("Type here to audition your custom mix...", text: $testInput)
                .textFieldStyle(.roundedBorder)
            if !testInput.isEmpty {
                Button("Clear") { testInput = "" }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func exportRecipe() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        let safeName = recipe.meta.name
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .lowercased()
        panel.nameFieldStringValue = "\(safeName.isEmpty ? "keysound" : safeName).recipe.json"
        if panel.runModal() == .OK, let url = panel.url {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(recipe) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func importRecipe() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if let loaded = try? SoundRecipe.load(from: url) {
                recipe = loaded
                AudioEngineManager.shared.updateRecipe(loaded)
            }
        }
    }

    // MARK: - Helpers

    private func slider(
        _ label: String,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>,
        help: String? = nil,
        format: (Double) -> String = { String(format: "%.2f", $0) }
    ) -> some View {
        HStack {
            Text(label)
                .frame(width: 185, alignment: .leading)
                .help(help ?? "")
            Slider(value: value, in: range)
            Text(format(value.wrappedValue))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 62, alignment: .trailing)
        }
    }
}

extension SoundRecipe {
    static var fallback: SoundRecipe {
        SoundRecipe(
            meta: Meta(name: "Fallback", author: nil, description: nil, tags: nil, basedOn: nil),
            layers: Layers(
                click: SampleLayer(),
                body: SampleLayer(),
                release: SampleLayer(),
                space: SpaceLayer()
            ),
            master: Master(gain: 1.0, eq: EQ()),
            humanize: Humanize(),
            keymap: Keymap()
        )
    }
}
