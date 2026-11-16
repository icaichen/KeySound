import AppKit
import Foundation

struct AppUpdateInfo: Decodable, Equatable {
    let version: String
    let build: Int
    let downloadUrl: String
    let releaseNotes: String?
    let publishedAt: String?
}

/// Checks https://website-one-nu-73.vercel.app/version.json for new releases
/// and handles one-click download + in-place .app bundle replacement.
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    private static let manifestURL = URL(string: "https://website-one-nu-73.vercel.app/version.json")!
    private static let lastCheckKey = "keysound.lastUpdateCheckTimestamp"

    @Published var isChecking = false
    @Published var isInstalling = false
    @Published var availableUpdate: AppUpdateInfo?
    @Published var statusMessage: String?

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    var currentBuild: Int {
        if let raw = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
           let val = Int(raw) {
            return val
        }
        return 1
    }

    private init() {}

    /// Silent background check on launch (throttled to once every 24 hours).
    func checkInBackgroundIfNeeded() {
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard now - last > 86_400 else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.checkForUpdates(interactive: false)
        }
    }

    func checkForUpdates(interactive: Bool) {
        guard !isChecking, !isInstalling else { return }
        isChecking = true
        if interactive {
            statusMessage = "Checking for updates…"
        }

        var request = URLRequest(url: Self.manifestURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChecking = false
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)

                if let error {
                    if interactive {
                        self.statusMessage = "Update check failed: \(error.localizedDescription)"
                        self.showInfoAlert(
                            title: "Unable to Check for Updates",
                            message: error.localizedDescription
                        )
                    }
                    return
                }

                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200...299).contains(status),
                      let data,
                      let remote = try? JSONDecoder().decode(AppUpdateInfo.self, from: data) else {
                    if interactive {
                        self.statusMessage = "Could not read update manifest."
                        self.showInfoAlert(
                            title: "Unable to Check for Updates",
                            message: "Server returned an unexpected response (HTTP \(status))."
                        )
                    }
                    return
                }

                if self.isNewer(remote) {
                    self.availableUpdate = remote
                    self.statusMessage = "Version \(remote.version) (build \(remote.build)) is available."
                    if interactive {
                        self.promptUpdateAlert(remote)
                    }
                } else {
                    self.availableUpdate = nil
                    self.statusMessage = "You’re up to date (v\(self.currentVersion))."
                    if interactive {
                        self.showInfoAlert(
                            title: "KeySound is Up to Date",
                            message: "KeySound \(self.currentVersion) (build \(self.currentBuild)) is the latest version."
                        )
                    }
                }
            }
        }.resume()
    }

    func downloadAndInstall(_ info: AppUpdateInfo) {
        guard !isInstalling, let url = URL(string: info.downloadUrl) else { return }
        isInstalling = true
        statusMessage = "Downloading KeySound \(info.version)…"

        URLSession.shared.downloadTask(with: url) { [weak self] tempZipURL, _, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    self.statusMessage = "Download failed: \(error.localizedDescription)"
                    self.showInfoAlert(title: "Update Download Failed", message: error.localizedDescription)
                }
                return
            }

            guard let tempZipURL else {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    self.statusMessage = "Download failed."
                }
                return
            }

            do {
                let fm = FileManager.default
                let workDir = fm.temporaryDirectory.appendingPathComponent("KeySoundUpdate-\(UUID().uuidString)")
                try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

                let zipCopy = workDir.appendingPathComponent("KeySound.zip")
                try fm.moveItem(at: tempZipURL, to: zipCopy)

                let extractDir = workDir.appendingPathComponent("extracted")
                try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzip.arguments = ["-xk", zipCopy.path, extractDir.path]
                try unzip.run()
                unzip.waitUntilExit()

                guard unzip.terminationStatus == 0 else {
                    throw NSError(domain: "UpdateManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to extract KeySound.zip."])
                }

                let newAppURL = self.findAppBundle(in: extractDir)
                guard let newAppURL else {
                    throw NSError(domain: "UpdateManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "KeySound.app not found in downloaded archive."])
                }

                let currentBundleURL = Bundle.main.bundleURL
                guard currentBundleURL.pathExtension == "app" else {
                    // Running via `swift run` in development: reveal extracted app in Finder instead
                    DispatchQueue.main.async {
                        self.isInstalling = false
                        self.statusMessage = "Downloaded v\(info.version) to temporary folder."
                        NSWorkspace.shared.activateFileViewerSelecting([newAppURL])
                    }
                    return
                }

                // Relaunch-and-swap via detached shell script
                let pid = ProcessInfo.processInfo.processIdentifier
                let targetPath = currentBundleURL.path
                let script = """
                while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
                rm -rf "\(targetPath)"
                ditto "\(newAppURL.path)" "\(targetPath)"
                open -n "\(targetPath)"
                rm -rf "\(workDir.path)"
                """

                let updater = Process()
                updater.executableURL = URL(fileURLWithPath: "/bin/sh")
                updater.arguments = ["-c", script]
                try updater.run()

                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    self.statusMessage = "Install failed: \(error.localizedDescription)"
                    self.showInfoAlert(title: "Update Failed", message: error.localizedDescription)
                }
            }
        }.resume()
    }

    private func findAppBundle(in dir: URL) -> URL? {
        let direct = dir.appendingPathComponent("KeySound.app")
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let url as URL in enumerator where url.lastPathComponent == "KeySound.app" {
            return url
        }
        return nil
    }

    private func isNewer(_ remote: AppUpdateInfo) -> Bool {
        let cmp = compareVersion(remote.version, currentVersion)
        if cmp != .orderedSame {
            return cmp == .orderedDescending
        }
        return remote.build > currentBuild
    }

    private func compareVersion(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = lhs.split(separator: ".").compactMap { Int($0) }
        let b = rhs.split(separator: ".").compactMap { Int($0) }
        let count = max(a.count, b.count)
        for i in 0..<count {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av != bv {
                return av < bv ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }

    private func promptUpdateAlert(_ info: AppUpdateInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "KeySound \(info.version) is Available"
        let notes = (info.releaseNotes?.isEmpty == false) ? "\n\n\(info.releaseNotes!)" : ""
        alert.informativeText = "You are currently on v\(currentVersion) (build \(currentBuild)).\(notes)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download & Install")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            downloadAndInstall(info)
        }
    }

    private func showInfoAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
