import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("KeyboardSoundSimulator_KeyboardSoundSimulator.bundle").path
        let buildPath = "/Users/chencai/Development/Keysound/KeyboardSoundSimulator/.build/arm64-apple-macosx/release/KeyboardSoundSimulator_KeyboardSoundSimulator.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}