import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AudioSettings.shared
    @State private var profiles: [String] = []
    @State private var selectedProfile: String = UserDefaults.standard.string(forKey: "SelectedProfile") ?? "Tickeys"
    
    // Callback to notify AppDelegate about profile change
    var onProfileChange: ((String) -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Keyboard Sound Settings")
                .font(.headline)
                .padding(.bottom, 10)
            
            // Profile Selection
            VStack(alignment: .leading) {
                Text("Sound Profile")
                Picker("Profile", selection: $selectedProfile) {
                    ForEach(profiles, id: \.self) { profile in
                        Text(profile).tag(profile)
                    }
                }
                .onChange(of: selectedProfile) { newValue in
                    onProfileChange?(newValue)
                }
            }
            
            Divider()
            
            // Volume Control
            VStack(alignment: .leading) {
                HStack {
                    Text("Volume")
                    Spacer()
                    Text("\(Int(settings.volume * 100))%")
                        .foregroundColor(.secondary)
                }
                Slider(value: $settings.volume, in: 0.0...1.0)
            }
            
            // Pitch Control
            VStack(alignment: .leading) {
                HStack {
                    Text("Pitch")
                    Spacer()
                    Text(String(format: "%.2fx", settings.pitch))
                        .foregroundColor(.secondary)
                }
                Slider(value: $settings.pitch, in: 0.5...2.0, step: 0.05)
                Text("Adjusting pitch also affects speed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack {
                Spacer()
                Button("Reset Defaults") {
                    settings.volume = 1.0
                    settings.pitch = 1.0
                }
            }
        }
        .padding()
        .frame(width: 300, height: 350)
        .onAppear {
            loadProfiles()
        }
    }
    
    private func loadProfiles() {
        // Load profiles logic similar to AppDelegate
        // For simplicity, we can fetch from a shared location or just re-scan
        // Since we are in the same module, we can access the bundle
        guard let soundsURL = Bundle.module.resourceURL?.appendingPathComponent("Sounds") else { return }
        do {
            let items = try FileManager.default.contentsOfDirectory(atPath: soundsURL.path)
            self.profiles = items.filter { item in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: soundsURL.appendingPathComponent(item).path, isDirectory: &isDir) && isDir.boolValue
            }.sorted()
        } catch {
            print("Error loading profiles in SettingsView: \(error)")
        }
    }
}
