import SwiftUI
import UniformTypeIdentifiers

// Sound Lab v2: sample-mixing DJ board with AI Sound Designer, Big Key tuning,
// plain-English controls, and recipe import/export sharing.

struct SoundLabView: View {
    enum LabTab: String, CaseIterable {
        case mixer = "Switch Mixer"
        case studio = "AI Sound Studio · PRO"
    }

    @ObservedObject private var pro = ProManager.shared
    @State private var activeTab: LabTab
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

    // AI Sound Studio (Pro SFX Pack) state
    @State private var sfxPrompt: String = ""
    @State private var isGeneratingSFX = false
    @State private var sfxStatus: String?
    @State private var sfxError: String?
    @State private var customPacks: [SoundPackInfo] = []
    @State private var activeCustomPackID: String?
    @State private var pinnedIDs: Set<String> = []

    init(initialTab: LabTab = .mixer) {
        _activeTab = State(initialValue: initialTab)
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
            Picker("Mode", selection: $activeTab) {
                ForEach(LabTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .onChange(of: activeTab) { newTab in
                if newTab == .studio {
                    reloadCustomPacks()
                }
            }

            Divider()

            if activeTab == .mixer {
                mixerTabContent
            } else {
                aiStudioTabContent
            }

            Divider()
            testTypingBar
        }
        .frame(width: 580, height: 650)
        .onAppear {
            catalog = AudioEngineManager.shared.sampleCatalog()
            presets = AudioEngineManager.shared.bundledPresetURLs()
            if selectedPreset.isEmpty {
                let names = presets.map { $0.lastPathComponent }
                selectedPreset = names.first(where: { $0 == "custom-thock.recipe.json" })
                    ?? names.first ?? ""
            }
            reloadCustomPacks()
        }
    }

    private var mixerTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                acousticMatrixSection
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
    }

    private var aiStudioTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("AI Sound Studio", systemImage: "wand.and.stars")
                                .font(.headline)
                            Text(pro.isPro ? "PRO ACTIVE" : "PRO")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(pro.isPro ? Color.green.opacity(0.18) : Color.accentColor.opacity(0.18))
                                .foregroundColor(pro.isPro ? .green : .accentColor)
                                .cornerRadius(4)
                            Spacer()
                            Button(action: {
                                (NSApp.delegate as? AppDelegate)?.openProUpgradeWindow()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                    Text("\(pro.credits) Credits")
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12))
                                .foregroundColor(.accentColor)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            .help("Manage Pro Pass & AI Sound Credits")
                        }

                        Text("Create brand-new keystroke sound packs from any idea—raindrops, wooden fish, high heels, bubble wrap, or anything else. KeySound detects real transients for zero-latency typing.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            TextField("Describe any sound (e.g. \"water drop\", \"wooden fish\")", text: $sfxPrompt)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { generateSFXPack() }
                            Button(action: {
                                if pro.canGenerateSFX {
                                    generateSFXPack()
                                } else {
                                    (NSApp.delegate as? AppDelegate)?.openProUpgradeWindow()
                                }
                            }) {
                                if isGeneratingSFX {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text(pro.canGenerateSFX ? "Generate (1 Credit)" : "Get Credits…")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isGeneratingSFX || (pro.canGenerateSFX && sfxPrompt.trimmingCharacters(in: .whitespaces).isEmpty))
                        }

                        Text("Prompt Tip: Describe a crisp single impact or material rather than long ambient scenes.")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(["water drop", "wooden fish", "bubble wrap pop", "high heel clicking", "typewriter bell", "bamboo tap"], id: \.self) { tip in
                                    Button(tip) { sfxPrompt = tip }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }

                        if let status = sfxStatus {
                            Text(status).font(.caption).foregroundColor(.green)
                        }
                        if let err = sfxError {
                            Text(err).font(.caption).foregroundColor(.red)
                        }
                    }
                    .padding(.vertical, 6)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Your AI Sound Packs").font(.subheadline.bold())
                            Spacer()
                            Text("\(customPacks.count) packs").font(.caption).foregroundColor(.secondary)
                        }

                        if customPacks.isEmpty {
                            Text("No AI sound packs yet. Generate one above to test it live.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(customPacks) { pack in
                                HStack(spacing: 10) {
                                    Button(action: { activateCustomPack(pack.id) }) {
                                        Image(systemName: activeCustomPackID == pack.id ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(activeCustomPackID == pack.id ? .accentColor : .secondary)
                                    }
                                    .buttonStyle(.borderless)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pack.displayName).font(.subheadline)
                                        Text(pack.summary).font(.caption2).foregroundColor(.secondary)
                                    }
                                    Spacer()

                                    Button(action: { togglePinCustomPack(pack.id) }) {
                                        Image(systemName: pinnedIDs.contains(pack.id) ? "star.fill" : "star")
                                            .foregroundColor(pinnedIDs.contains(pack.id) ? .yellow : .secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Pin to menu bar")

                                    Button(action: { deleteCustomPack(pack.id) }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Delete this AI sound pack")
                                }
                                .padding(.vertical, 4)
                                Divider()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
    }

    private func reloadCustomPacks() {
        customPacks = SoundPackCatalog.allPacks().filter { $0.category == .custom && !$0.id.hasPrefix(SoundPackCatalog.savedRecipePrefix) }
        pinnedIDs = Set(SoundPackCatalog.pinnedIDs())
        if let delegate = NSApp.delegate as? AppDelegate {
            activeCustomPackID = delegate.currentProfile
        }
    }

    private func generateSFXPack() {
        guard !isGeneratingSFX else { return }
        guard pro.canGenerateSFX else {
            (NSApp.delegate as? AppDelegate)?.openProUpgradeWindow()
            return
        }
        let prompt = sfxPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        sfxError = nil
        sfxStatus = nil
        isGeneratingSFX = true
        let key = EnvConfig.elevenLabsApiKey
        Task {
            do {
                let packID = try await SFXGenerator.generatePack(prompt: prompt, apiKey: key)
                await MainActor.run {
                    pro.consumeCredit()
                    activateCustomPack(packID)
                    reloadCustomPacks()
                    sfxStatus = "Created & activated \"\(SoundPackCatalog.displayName(for: packID))\". Type below to test!"
                    isGeneratingSFX = false
                }
            } catch {
                await MainActor.run {
                    sfxError = error.localizedDescription
                    isGeneratingSFX = false
                }
            }
        }
    }

    private func activateCustomPack(_ id: String) {
        activeCustomPackID = id
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.loadProfiles()
            delegate.selectProfile(id)
        } else {
            AudioEngineManager.shared.loadSounds(for: id)
        }
    }

    private func togglePinCustomPack(_ id: String) {
        let nowPinned = !pinnedIDs.contains(id)
        if nowPinned { pinnedIDs.insert(id) } else { pinnedIDs.remove(id) }
        SoundPackCatalog.setPinned(id, pinned: nowPinned)
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.updateMenu()
        }
    }

    private func deleteCustomPack(_ id: String) {
        SoundPackCatalog.deleteCustomSound(id: id)
        if activeCustomPackID == id {
            activateCustomPack("CherryMX_Blue_PBT_keycaps")
        }
        reloadCustomPacks()
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.loadProfiles()
            delegate.updateMenu()
        }
    }

    // MARK: - Header & AI Designer

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Mix Name")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Name your custom switch mix", text: bind(\.meta.name))
                    .textFieldStyle(.roundedBorder)
                    .font(.headline)
                templatePicker
            }
        }
    }

    private var templatePicker: some View {
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
            Text("Template").font(.caption).foregroundColor(.secondary)
            Picker("Template", selection: selection) {
                ForEach(presets.map { $0.lastPathComponent }, id: \.self) { name in
                    Text(name.replacingOccurrences(of: ".recipe.json", with: "")).tag(name)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 155)
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
            Button("Save Mix") {
                var toSave = recipe
                let trimmed = toSave.meta.name.trimmingCharacters(in: .whitespacesAndNewlines)
                toSave.meta.name = trimmed.isEmpty ? "My Custom Mix" : trimmed
                recipe = toSave
                AudioEngineManager.shared.saveNamedRecipe(toSave)
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.loadProfiles()
                    delegate.updateMenu()
                }
                withAnimation { savedFlash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { savedFlash = false }
                }
            }
            .buttonStyle(.borderedProminent)

            Button("Use This Sound") {
                AudioEngineManager.shared.updateRecipe(recipe)
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.selectProfile(AudioEngineManager.recipeProfileName)
                }
            }
            .buttonStyle(.bordered)

            if savedFlash {
                Text("Saved!").foregroundColor(.green).font(.caption)
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
