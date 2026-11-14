import SwiftUI

struct SoundPickerView: View {
    enum Filter: String, CaseIterable {
        case all = "All"
        case real = "Real Recordings"
        case custom = "AI / Custom"
        case clicky = "Clicky"
        case tactile = "Tactile"
        case linear = "Linear"
        case classic = "Classic / Synth"
    }

    @State private var packs: [SoundPackInfo] = []
    @State private var selectedPackID: String
    @State private var pinnedIDs: Set<String> = []
    @State private var searchText: String = ""
    @State private var activeFilter: Filter = .all
    @State private var testInput: String = ""

    // AI SFX Pack generator (moved here so generated packs live right in the library)
    @State private var showAICreator = false
    @State private var sfxPrompt: String = ""
    @State private var isGeneratingSFX = false
    @State private var sfxStatus: String?
    @State private var sfxError: String?

    var onSelectPack: ((String) -> Void)?
    var onPinsChanged: (() -> Void)?

    init(
        currentProfile: String,
        onSelectPack: ((String) -> Void)? = nil,
        onPinsChanged: (() -> Void)? = nil
    ) {
        _selectedPackID = State(initialValue: currentProfile)
        self.onSelectPack = onSelectPack
        self.onPinsChanged = onPinsChanged
    }

    private var filteredPacks: [SoundPackInfo] {
        packs.filter { pack in
            let matchesFilter: Bool
            switch activeFilter {
            case .all: matchesFilter = true
            case .real: matchesFilter = pack.category == .real
            case .custom: matchesFilter = pack.category == .custom
            case .clicky: matchesFilter = pack.feel == .clicky
            case .tactile: matchesFilter = pack.feel == .tactile
            case .linear: matchesFilter = pack.feel == .linear
            case .classic: matchesFilter = pack.category == .classic
            }
            guard matchesFilter else { return false }
            if searchText.trimmingCharacters(in: .whitespaces).isEmpty { return true }
            let q = searchText.lowercased()
            return pack.displayName.lowercased().contains(q)
                || pack.summary.lowercased().contains(q)
                || pack.feel.rawValue.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            aiSFXCreatorSection
            Divider()
            filterBar
            Divider()
            packList
            Divider()
            testTypingBar
        }
        .frame(width: 580, height: 580)
        .onAppear {
            reloadPacks()
        }
    }

    private func reloadPacks() {
        packs = SoundPackCatalog.allPacks()
        pinnedIDs = Set(SoundPackCatalog.pinnedIDs())
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search switches, keycaps, or custom sounds...", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
    }

    private var aiSFXCreatorSection: some View {
        DisclosureGroup(isExpanded: $showAICreator) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Describe a sound effect (e.g. \"water drop\", \"wooden fish\")", text: $sfxPrompt)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { generateSFX() }
                    Button(action: generateSFX) {
                        if isGeneratingSFX {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Generate")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGeneratingSFX || sfxPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Text("Tip: Describe a crisp single hit or material (avoid long ambient scenes like \"heavy rainstorm\").")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(["water drop", "wooden fish", "bubble wrap pop", "high heel clicking", "typewriter bell"], id: \.self) { tip in
                            Button(tip) {
                                sfxPrompt = tip
                            }
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
            .padding(.top, 6)
        } label: {
            HStack {
                Label("Create AI Sound Pack (ElevenLabs SFX)", systemImage: "sparkles")
                    .font(.subheadline.bold())
                Spacer()
                Text(EnvConfig.elevenLabsApiKey.isEmpty ? "Needs ELEVENLABS_API_KEY in .env" : "Ready")
                    .font(.caption2)
                    .foregroundColor(EnvConfig.elevenLabsApiKey.isEmpty ? .secondary : .green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func generateSFX() {
        sfxError = nil
        sfxStatus = nil
        isGeneratingSFX = true
        let prompt = sfxPrompt
        let key = EnvConfig.elevenLabsApiKey
        Task {
            do {
                let packID = try await SFXGenerator.generatePack(prompt: prompt, apiKey: key)
                await MainActor.run {
                    reloadPacks()
                    activeFilter = .custom
                    select(packID)
                    sfxStatus = "Created \"\(SoundPackCatalog.displayName(for: packID))\" and activated it."
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

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Filter.allCases, id: \.self) { filter in
                    Button(action: { activeFilter = filter }) {
                        Text(filter.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(activeFilter == filter ? Color.accentColor : Color.secondary.opacity(0.14))
                            .foregroundColor(activeFilter == filter ? .white : .primary)
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var packList: some View {
        List(filteredPacks) { pack in
            HStack(spacing: 12) {
                Button(action: { select(pack.id) }) {
                    Image(systemName: selectedPackID == pack.id ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedPackID == pack.id ? .accentColor : .secondary)
                        .font(.title3)
                }
                .buttonStyle(.borderless)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(pack.displayName)
                            .font(.headline)
                        Text(pack.feel.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                        if let license = pack.license {
                            Text(license)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Text(pack.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if SoundPackCatalog.isDeletable(pack.id) {
                    Button(action: { deletePack(pack.id) }) {
                        Image(systemName: "trash")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete this custom sound")
                }

                Button(action: { togglePin(pack.id) }) {
                    Image(systemName: pinnedIDs.contains(pack.id) ? "star.fill" : "star")
                        .foregroundColor(pinnedIDs.contains(pack.id) ? .yellow : .secondary)
                }
                .buttonStyle(.borderless)
                .help(pinnedIDs.contains(pack.id) ? "Pinned to menu bar" : "Pin to menu bar")
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                select(pack.id)
            }
        }
    }

    private var testTypingBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .foregroundColor(.secondary)
            TextField("Type here to audition the selected sound...", text: $testInput)
                .textFieldStyle(.roundedBorder)
            if !testInput.isEmpty {
                Button("Clear") { testInput = "" }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func select(_ id: String) {
        selectedPackID = id
        onSelectPack?(id)
    }

    private func deletePack(_ id: String) {
        SoundPackCatalog.deleteCustomSound(id: id)
        reloadPacks()
        if selectedPackID == id {
            let fallback = packs.first(where: { $0.isRealRecording })?.id ?? "CherryMX_Blue_PBT_keycaps"
            select(fallback)
        } else {
            onPinsChanged?()
        }
    }

    private func togglePin(_ id: String) {
        let nowPinned = !pinnedIDs.contains(id)
        if nowPinned {
            pinnedIDs.insert(id)
        } else {
            pinnedIDs.remove(id)
        }
        SoundPackCatalog.setPinned(id, pinned: nowPinned)
        onPinsChanged?()
    }
}
