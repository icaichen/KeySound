import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AudioSettings.shared
    @State private var showLicenses = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("KeySound Settings")
                    .font(.headline)

                // Audio & Dynamics
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Audio & Behavior").font(.subheadline).bold()

                        Toggle("Mute All Sounds (⌃⌥M)", isOn: $settings.isMuted)
                        Toggle("Pause Automatically During Calls (Mic Active)", isOn: $settings.autoMuteOnMic)
                            .help("Optional: mutes typing sounds whenever another app is using your microphone")

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Volume")
                                Spacer()
                                Text("\(Int(settings.volume * 100))%").foregroundColor(.secondary)
                            }
                            Slider(value: $settings.volume, in: 0.0...1.0)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Pitch")
                                Spacer()
                                Text(String(format: "%.2fx", settings.pitch)).foregroundColor(.secondary)
                            }
                            Slider(value: $settings.pitch, in: 0.5...2.0, step: 0.05)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Typing Speed Dynamics")
                                Spacer()
                                Text(settings.velocitySensitivity <= 0.01 ? "Off" : "\(Int(settings.velocitySensitivity * 100))%")
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $settings.velocitySensitivity, in: 0.0...1.0)
                            Text("Gently softens rapid typing bursts so fast typing stays comfortable.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Attribution & Licenses
                DisclosureGroup("Sound Credits & Open-Source Licenses", isExpanded: $showLicenses) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Real Mechanical Switch Recordings (MIT License)")
                            .font(.caption).bold()
                        Text("Cherry MX (Black, Blue, Brown, Red), EG Crystal Purple, EG Oreo, and Topre Purple Hybrid recordings are sourced from hainguyents13/mechvibes-dx under the MIT License.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Original Synthesized Packs & Sound Lab Layers")
                            .font(.caption).bold()
                            .padding(.top, 4)
                        Text("Layer_* samples and original synthesized profiles are original assets created for KeySound.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 6)
                }

                HStack {
                    Spacer()
                    Button("Reset Audio Defaults") {
                        settings.volume = 1.0
                        settings.pitch = 1.0
                        settings.velocitySensitivity = 0.35
                        settings.isMuted = false
                    }
                }
            }
            .padding()
        }
        .frame(width: 380, height: 420)
    }
}
