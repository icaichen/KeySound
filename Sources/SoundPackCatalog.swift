import Foundation

/// Central catalog for sound packs: separates real open-source recordings from
/// older synthesized packs, hides Sound Lab `Layer_*` building blocks from the
/// main switcher, and provides clean display names & metadata.
struct SoundPackInfo: Identifiable, Hashable {
    enum Category: String, CaseIterable {
        case real = "Real Recordings"
        case custom = "AI / Custom"
        case classic = "Classic / Synth"
    }

    enum Feel: String {
        case clicky = "Clicky"
        case tactile = "Tactile"
        case linear = "Linear"
        case novelty = "Fun"
    }

    let id: String          // Folder name on disk, or AudioEngineManager.recipeProfileName
    let displayName: String
    let category: Category
    let feel: Feel
    let summary: String
    let license: String?

    var isRealRecording: Bool { category == .real }
}

enum SoundPackCatalog {
    static let defaultPinnedIDs: [String] = [
        "CherryMX_Blue_PBT_keycaps",
        "CherryMX_Brown_PBT_keycaps",
        "CherryMX_Red_ABS_keycaps",
        "CherryMX_Black_PBT_keycaps",
        "Topre_Purple_Hybrid_PBT_keycaps",
        "EG_Crystal_Purple",
        "EG_Oreo"
    ]

    private static let pinnedDefaultsKey = "PinnedSoundPacks"

    /// Metadata for known packs (real MIT recordings first, then classic/synth).
    static let knownPacks: [String: SoundPackInfo] = [
        // Real MIT-licensed recordings (from hainguyents13/mechvibes-dx)
        "CherryMX_Blue_PBT_keycaps": SoundPackInfo(
            id: "CherryMX_Blue_PBT_keycaps",
            displayName: "Cherry MX Blue (PBT)",
            category: .real,
            feel: .clicky,
            summary: "Crisp click-jacket mechanical switch on thick PBT keycaps.",
            license: "MIT · MechvibesDX"
        ),
        "CherryMX_Blue_ABS_keycaps": SoundPackInfo(
            id: "CherryMX_Blue_ABS_keycaps",
            displayName: "Cherry MX Blue (ABS)",
            category: .real,
            feel: .clicky,
            summary: "Bright, classic clicky switch with lighter ABS keycaps.",
            license: "MIT · MechvibesDX"
        ),
        "CherryMX_Brown_PBT_keycaps": SoundPackInfo(
            id: "CherryMX_Brown_PBT_keycaps",
            displayName: "Cherry MX Brown (PBT)",
            category: .real,
            feel: .tactile,
            summary: "Balanced, muted tactile bump with warm PBT resonance.",
            license: "MIT · MechvibesDX"
        ),
        "CherryMX_Brown_ABS_keycaps": SoundPackInfo(
            id: "CherryMX_Brown_ABS_keycaps",
            displayName: "Cherry MX Brown (ABS)",
            category: .real,
            feel: .tactile,
            summary: "Lighter tactile bump with crisp ABS top-out.",
            license: "MIT · MechvibesDX"
        ),
        "CherryMX_Red_ABS_keycaps": SoundPackInfo(
            id: "CherryMX_Red_ABS_keycaps",
            displayName: "Cherry MX Red (ABS)",
            category: .real,
            feel: .linear,
            summary: "Smooth linear switch with clean bottom-out clack.",
            license: "MIT · MechvibesDX"
        ),
        "CherryMX_Black_PBT_keycaps": SoundPackInfo(
            id: "CherryMX_Black_PBT_keycaps",
            displayName: "Cherry MX Black (PBT)",
            category: .real,
            feel: .linear,
            summary: "Heavy, deep linear switch on dense PBT keycaps.",
            license: "MIT · MechvibesDX"
        ),
        "CherryMX_Black_ABS_keycaps": SoundPackInfo(
            id: "CherryMX_Black_ABS_keycaps",
            displayName: "Cherry MX Black (ABS)",
            category: .real,
            feel: .linear,
            summary: "Weighted linear switch with sharper ABS clack.",
            license: "MIT · MechvibesDX"
        ),
        "Topre_Purple_Hybrid_PBT_keycaps": SoundPackInfo(
            id: "Topre_Purple_Hybrid_PBT_keycaps",
            displayName: "Topre Purple Hybrid (PBT)",
            category: .real,
            feel: .tactile,
            summary: "Silenced electro-capacitive thock—round, muted, and refined.",
            license: "MIT · MechvibesDX"
        ),
        "EG_Crystal_Purple": SoundPackInfo(
            id: "EG_Crystal_Purple",
            displayName: "EG Crystal Purple",
            category: .real,
            feel: .tactile,
            summary: "Snappy tactile switch with a clean, glassy bottom-out.",
            license: "MIT · MechvibesDX"
        ),
        "EG_Oreo": SoundPackInfo(
            id: "EG_Oreo",
            displayName: "EG Oreo",
            category: .real,
            feel: .tactile,
            summary: "Deep, creamy tactile thock with a soft return.",
            license: "MIT · MechvibesDX"
        ),

        // Classic / synthesized packs
        "Thocky": SoundPackInfo(
            id: "Thocky",
            displayName: "Thocky (Synth)",
            category: .classic,
            feel: .linear,
            summary: "Synthesized low-end thock profile.",
            license: "Original"
        ),
        "Creamy": SoundPackInfo(
            id: "Creamy",
            displayName: "Creamy (Synth)",
            category: .classic,
            feel: .linear,
            summary: "Synthesized soft creamy profile.",
            license: "Original"
        ),
        "Mahjong": SoundPackInfo(
            id: "Mahjong",
            displayName: "Mahjong Tiles",
            category: .classic,
            feel: .novelty,
            summary: "Crisp tile-clack novelty sound.",
            license: "Original"
        ),
        "MX_Blue": SoundPackInfo(
            id: "MX_Blue",
            displayName: "MX Blue (Legacy Synth)",
            category: .classic,
            feel: .clicky,
            summary: "Earlier synthesized clicky profile.",
            license: "Original"
        ),
        "MX_Brown": SoundPackInfo(
            id: "MX_Brown",
            displayName: "MX Brown (Legacy Synth)",
            category: .classic,
            feel: .tactile,
            summary: "Earlier synthesized tactile profile.",
            license: "Original"
        ),
        "MX_Black": SoundPackInfo(
            id: "MX_Black",
            displayName: "MX Black (Legacy Synth)",
            category: .classic,
            feel: .linear,
            summary: "Earlier synthesized linear profile.",
            license: "Original"
        ),
        "Opera_GX": SoundPackInfo(
            id: "Opera_GX",
            displayName: "Opera GX (Synth)",
            category: .classic,
            feel: .novelty,
            summary: "Synthesized sci-fi browser typing sound.",
            license: "Original"
        ),
        "iPhone": SoundPackInfo(
            id: "iPhone",
            displayName: "iPhone Tap (Synth)",
            category: .classic,
            feel: .novelty,
            summary: "Synthesized touchscreen keyboard tap.",
            license: "Original"
        ),
        "BlackBerry": SoundPackInfo(
            id: "BlackBerry",
            displayName: "BlackBerry (Synth)",
            category: .classic,
            feel: .clicky,
            summary: "Synthesized thumb-keyboard click.",
            license: "Original"
        )
    ]

    /// Safe wrapper around `Bundle.module.resourceURL` that never triggers a
    /// SwiftPM fatalError when running inside a packaged `.app` bundle.
    static var safeModuleResourceURL: URL? {
        guard !Bundle.main.bundlePath.hasSuffix(".app") else { return nil }
        return Bundle.module.resourceURL
    }

    static func soundsDirectory() -> URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent("Sounds")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                return candidate
            }
        }
        return safeModuleResourceURL?.appendingPathComponent("Sounds")
    }

    static func customPacksDirectory() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeySound/CustomPacks")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func savedRecipesDirectory() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeySound/SavedRecipes")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static let savedRecipePrefix = "@recipe:"

    static func isDeletable(_ id: String) -> Bool {
        if id.hasPrefix(savedRecipePrefix) { return true }
        let customPath = customPacksDirectory().appendingPathComponent(id).path
        return FileManager.default.fileExists(atPath: customPath)
    }

    static func deleteCustomSound(id: String) {
        if id.hasPrefix(savedRecipePrefix) {
            let fileName = String(id.dropFirst(savedRecipePrefix.count))
            let url = savedRecipesDirectory().appendingPathComponent("\(fileName).recipe.json")
            try? FileManager.default.removeItem(at: url)
        } else {
            let dir = customPacksDirectory().appendingPathComponent(id)
            try? FileManager.default.removeItem(at: dir)
        }
        setPinned(id, pinned: false)
    }

    /// Returns all user-facing sound packs (excluding `Layer_*` Sound Lab building blocks).
    static func allPacks() -> [SoundPackInfo] {
        var infos: [SoundPackInfo] = []

        if let soundsURL = soundsDirectory() {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: soundsURL.path)) ?? []
            let folders = items.filter { item in
                guard !item.hasPrefix("."), !item.hasPrefix("Layer_") else { return false }
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: soundsURL.appendingPathComponent(item).path, isDirectory: &isDir) && isDir.boolValue
            }
            infos.append(contentsOf: folders.map { folder in
                if let known = knownPacks[folder] {
                    return known
                }
                return SoundPackInfo(
                    id: folder,
                    displayName: folder.replacingOccurrences(of: "_", with: " "),
                    category: .classic,
                    feel: .linear,
                    summary: "Bundled sound pack.",
                    license: nil
                )
            })
        }

        // Include user / AI-generated custom packs
        let customDir = customPacksDirectory()
        let customItems = (try? FileManager.default.contentsOfDirectory(atPath: customDir.path)) ?? []
        for item in customItems where !item.hasPrefix(".") {
            var isDir: ObjCBool = false
            let path = customDir.appendingPathComponent(item).path
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                infos.append(SoundPackInfo(
                    id: item,
                    displayName: cleanPackDisplayName(item),
                    category: .custom,
                    feel: .novelty,
                    summary: "AI-generated custom sound pack.",
                    license: "Custom"
                ))
            }
        }

        // Include user-saved Sound Lab mixes
        let recipesDir = savedRecipesDirectory()
        let recipeFiles = (try? FileManager.default.contentsOfDirectory(atPath: recipesDir.path)) ?? []
        for file in recipeFiles where file.hasSuffix(".recipe.json") {
            let base = String(file.dropLast(".recipe.json".count))
            let url = recipesDir.appendingPathComponent(file)
            let loadedName = (try? SoundRecipe.load(from: url))?.meta.name ?? base
            infos.append(SoundPackInfo(
                id: "\(savedRecipePrefix)\(base)",
                displayName: loadedName,
                category: .custom,
                feel: .tactile,
                summary: "Saved Sound Lab custom mix.",
                license: "Saved Mix"
            ))
        }

        return infos.sorted { a, b in
            if a.category != b.category {
                let order: [SoundPackInfo.Category] = [.real, .custom, .classic]
                return (order.firstIndex(of: a.category) ?? 9) < (order.firstIndex(of: b.category) ?? 9)
            }
            return a.displayName < b.displayName
        }
    }

    static func displayName(for id: String) -> String {
        if id == AudioEngineManager.recipeProfileName {
            return "Sound Lab (Workspace)"
        }
        if id.hasPrefix(savedRecipePrefix) {
            let base = String(id.dropFirst(savedRecipePrefix.count))
            let url = savedRecipesDirectory().appendingPathComponent("\(base).recipe.json")
            if let loaded = try? SoundRecipe.load(from: url) {
                return loaded.meta.name
            }
            return base.replacingOccurrences(of: "-", with: " ")
        }
        return knownPacks[id]?.displayName ?? cleanPackDisplayName(id)
    }

    private static func cleanPackDisplayName(_ id: String) -> String {
        let stripped = id.hasPrefix("AI_") ? String(id.dropFirst(3)) : id
        return stripped.replacingOccurrences(of: "_", with: " ")
    }

    static func pinnedIDs() -> [String] {
        if let saved = UserDefaults.standard.stringArray(forKey: pinnedDefaultsKey), !saved.isEmpty {
            return saved
        }
        return defaultPinnedIDs
    }

    static func setPinned(_ id: String, pinned: Bool) {
        var current = pinnedIDs()
        if pinned {
            if !current.contains(id) { current.append(id) }
        } else {
            current.removeAll { $0 == id }
        }
        UserDefaults.standard.set(current, forKey: pinnedDefaultsKey)
    }

    static func isPinned(_ id: String) -> Bool {
        pinnedIDs().contains(id)
    }
}
