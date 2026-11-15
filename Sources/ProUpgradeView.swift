import SwiftUI

struct ProUpgradeView: View {
    @ObservedObject var pro = ProManager.shared
    @State private var licenseInput: String = ""
    @State private var activationMessage: String?
    @State private var isError = false
    @State private var isActivating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: pro.isPro ? "checkmark.seal.fill" : "wand.and.stars")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(pro.isPro ? "KeySound Pro" : "Upgrade to KeySound Pro")
                            .font(.headline)
                        Text(pro.isPro ? "ACTIVE" : "PRO")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(pro.isPro ? Color.green.opacity(0.18) : Color.accentColor.opacity(0.18))
                            .foregroundColor(pro.isPro ? .green : .accentColor)
                            .cornerRadius(4)
                    }
                    Text("\(pro.credits) AI Sound Credits remaining")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            // Tier Comparison
            HStack(alignment: .top, spacing: 12) {
                tierCard(
                    title: "Free",
                    price: "$0",
                    subtitle: "Forever free",
                    features: [
                        "10 MIT real switch packs",
                        "Manual 3-layer Sound Lab",
                        "Offline Switch × Vibe matrix",
                        "3 trial AI Sound Credits"
                    ],
                    highlighted: false
                )

                tierCard(
                    title: "Pro Pass",
                    price: "$9.99",
                    subtitle: "One-time · +15 Credits",
                    features: [
                        "Everything in Free",
                        "15 AI Sound Studio packs",
                        "0-latency 5-variant slicing",
                        "Top-ups: $4.99 / 20 Credits"
                    ],
                    highlighted: true
                )
            }

            // License Activation
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Activate License or Top-Up Key")
                        .font(.subheadline.bold())
                    HStack(spacing: 8) {
                        TextField("Paste Creem license key…", text: $licenseInput)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isActivating)
                        Button(isActivating ? "Verifying…" : "Activate") {
                            activateEnteredKey()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isActivating || licenseInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if let msg = activationMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(isError ? .red : .green)
                    }
                }
                .padding(.vertical, 4)
            }

            // Footer Actions
            HStack {
                if !pro.isPro {
                    Button("Get Pro Pass ($9.99)…") {
                        if let url = ProManager.checkoutURL(for: "pro") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button(pro.isPro ? "Buy 20 Credits ($4.99)…" : "Top-Up ($4.99)…") {
                    if let url = ProManager.checkoutURL(for: "topup") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                #if DEBUG
                // Convenient testing controls (stripped from Release builds)
                Menu("Test Credits") {
                    Button("+5 Test Credits") { pro.grantTestCredits(5) }
                    Button("Unlock Pro (Demo)") { pro.activateDemoProForTesting() }
                    Divider()
                    Button("Reset to Free (3 Credits)") { pro.resetTrialForTesting() }
                }
                .frame(width: 120)
                #endif
            }
        }
        .padding(20)
        .frame(width: 470)
    }

    private func activateEnteredKey() {
        isActivating = true
        activationMessage = nil
        pro.activateLicense(licenseInput) { result in
            isActivating = false
            switch result {
            case .success(let info):
                isError = false
                if info.plan == "topup" {
                    activationMessage = "Top-up applied! Added \(info.creditsGranted) AI Sound Credits."
                } else {
                    activationMessage = "Pro unlocked! Added \(info.creditsGranted) AI Sound Credits."
                }
                licenseInput = ""
            case .failure(let error):
                isError = true
                activationMessage = error.localizedDescription
            }
        }
    }

    private func tierCard(
        title: String,
        price: String,
        subtitle: String,
        features: [String],
        highlighted: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.bold())
                Spacer()
                Text(price).font(.headline)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundColor(highlighted ? .accentColor : .secondary)
            Divider()
            ForEach(features, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundColor(highlighted ? .accentColor : .secondary)
                        .padding(.top, 2)
                    Text(item)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 165, alignment: .topLeading)
        .background(highlighted ? Color.accentColor.opacity(0.07) : Color.secondary.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(highlighted ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(8)
    }
}
