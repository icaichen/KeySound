import Cocoa
import CoreGraphics
import AVFoundation
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    var statusItem: NSStatusItem?
    var eventTap: CFMachPort?
    var soundProfiles: [String] = []
    var currentProfile: String = "CherryMX_Blue_PBT_keycaps"

    var settingsWindow: NSWindow?
    var soundLabWindow: NSWindow?
    var soundPickerWindow: NSWindow?

    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        loadProfiles()
        setupStatusBar()
        setupEventTap()

        let savedProfile = UserDefaults.standard.string(forKey: "SelectedProfile") ?? "CherryMX_Blue_PBT_keycaps"
        if soundProfiles.contains(savedProfile) {
            selectProfile(savedProfile)
        } else if let firstReal = soundProfiles.first(where: { SoundPackCatalog.knownPacks[$0]?.isRealRecording == true }) {
            selectProfile(firstReal)
        } else if let first = soundProfiles.first {
            selectProfile(first)
        }

        let settings = AudioSettings.shared
        Publishers.CombineLatest3(settings.$isMuted, settings.$autoMuteOnMic, settings.$isAutoMutedByMic)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                self?.updateStatusIcon()
                self?.updateMenu()
            }
            .store(in: &cancellables)

        checkAccessibility()
    }

    func checkAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        updateMenu()
    }

    @objc func openAccessibilityHelp() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = "KeySound needs Accessibility permission to detect key presses.\n\nApp location:\n\(Bundle.main.bundlePath)\n\nEnable KeySound in System Settings → Privacy & Security → Accessibility, then restart the app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Reveal App in Finder")
        alert.addButton(withTitle: "Restart App")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } else if response == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        } else if response == .alertThirdButtonReturn {
            relaunchApp()
        }
    }

    func relaunchApp() {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 0.2; open \"\(Bundle.main.bundlePath)\""]
        task.launch()
        NSApplication.shared.terminate(nil)
    }

    func loadProfiles() {
        var ids = SoundPackCatalog.allPacks().map { $0.id }
        if !ids.contains(AudioEngineManager.recipeProfileName) {
            ids.insert(AudioEngineManager.recipeProfileName, at: 0)
        }
        soundProfiles = ids
    }

    func selectProfile(_ profile: String) {
        currentProfile = profile
        UserDefaults.standard.set(profile, forKey: "SelectedProfile")
        AudioEngineManager.shared.loadSounds(for: profile)
        updateMenu()
    }

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        updateMenu()
    }

    func updateStatusIcon() {
        let muted = AudioSettings.shared.effectiveMuted
        let symbol = muted ? "speaker.slash" : "keyboard"
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "KeySound")
    }

    func updateMenu() {
        let menu = NSMenu()

        let settings = AudioSettings.shared
        let statusTitle: String
        if settings.isMuted {
            statusTitle = "KeySound · Muted"
        } else if settings.autoMuteOnMic && settings.isAutoMutedByMic {
            statusTitle = "KeySound · Paused (Mic Active)"
        } else {
            statusTitle = "KeySound · \(SoundPackCatalog.displayName(for: currentProfile))"
        }
        let titleItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        if !AXIsProcessTrusted() {
            let warningItem = NSMenuItem(title: "⚠️ Accessibility Required", action: #selector(openAccessibilityHelp), keyEquivalent: "")
            warningItem.toolTip = "Click to fix permissions"
            menu.addItem(warningItem)
            menu.addItem(NSMenuItem.separator())
        }

        // Quick Mute & Optional Call Auto-Mute
        let muteItem = NSMenuItem(
            title: settings.isMuted ? "Unmute Sounds (⌃⌥M)" : "Mute All Sounds (⌃⌥M)",
            action: #selector(toggleMute),
            keyEquivalent: ""
        )
        muteItem.state = settings.isMuted ? .on : .off
        menu.addItem(muteItem)

        let micItem = NSMenuItem(
            title: "Pause During Calls (Mic Active)",
            action: #selector(toggleAutoMuteOnMic),
            keyEquivalent: ""
        )
        micItem.state = settings.autoMuteOnMic ? .on : .off
        menu.addItem(micItem)

        menu.addItem(NSMenuItem.separator())

        // Pinned / Real Recording Packs + Sound Lab
        let labItem = NSMenuItem(
            title: SoundPackCatalog.displayName(for: AudioEngineManager.recipeProfileName),
            action: #selector(menuProfileSelected(_:)),
            keyEquivalent: ""
        )
        labItem.representedObject = AudioEngineManager.recipeProfileName
        labItem.state = (currentProfile == AudioEngineManager.recipeProfileName) ? .on : .off
        menu.addItem(labItem)

        let pinned = SoundPackCatalog.pinnedIDs().filter { soundProfiles.contains($0) }
        var displayed = pinned
        if currentProfile != AudioEngineManager.recipeProfileName && !displayed.contains(currentProfile) && soundProfiles.contains(currentProfile) {
            displayed.insert(currentProfile, at: 0)
        }

        for id in displayed {
            let item = NSMenuItem(
                title: SoundPackCatalog.displayName(for: id),
                action: #selector(menuProfileSelected(_:)),
                keyEquivalent: ""
            )
            item.representedObject = id
            item.state = (id == currentProfile) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Browse All Sounds…", action: #selector(openSoundPickerWindow), keyEquivalent: "b"))
        menu.addItem(NSMenuItem(title: "Sound Lab…", action: #selector(openSoundLabWindow), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Settings & Credits…", action: #selector(openSettingsWindow), keyEquivalent: ","))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc func toggleMute() {
        AudioSettings.shared.isMuted.toggle()
    }

    @objc func toggleAutoMuteOnMic() {
        AudioSettings.shared.autoMuteOnMic.toggle()
    }

    @objc func openSoundPickerWindow() {
        let pickerView = SoundPickerView(
            currentProfile: currentProfile,
            onSelectPack: { [weak self] newProfile in
                self?.selectProfile(newProfile)
            },
            onPinsChanged: { [weak self] in
                self?.updateMenu()
            }
        )
        let hostingController = NSHostingController(rootView: pickerView)
        if soundPickerWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.center()
            window.setFrameAutosaveName("SoundPickerWindow")
            window.title = "Sound Picker"
            window.isReleasedWhenClosed = false
            soundPickerWindow = window
        }
        soundPickerWindow?.contentViewController = hostingController
        if let win = soundPickerWindow { showAsNormalWindow(win) }
    }

    @objc func openSettingsWindow() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.center()
            window.setFrameAutosaveName("SettingsWindow")
            window.contentViewController = hostingController
            window.title = "Settings"
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }

        if let win = settingsWindow { showAsNormalWindow(win) }
    }

    @objc func openSoundLabWindow() {
        if currentProfile != AudioEngineManager.recipeProfileName {
            selectProfile(AudioEngineManager.recipeProfileName)
        }

        if soundLabWindow == nil {
            let hostingController = NSHostingController(rootView: SoundLabView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.center()
            window.setFrameAutosaveName("SoundLabWindow")
            window.contentViewController = hostingController
            window.title = "Sound Lab"
            window.isReleasedWhenClosed = false
            soundLabWindow = window
        }

        if let win = soundLabWindow { showAsNormalWindow(win) }
    }

    private func showAsNormalWindow(_ window: NSWindow) {
        window.delegate = self
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.managed, .fullScreenAuxiliary]
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let windows = [self.settingsWindow, self.soundLabWindow, self.soundPickerWindow]
            let anyVisible = windows.contains { win in
                guard let w = win, w !== closing else { return false }
                return w.isVisible
            }
            if !anyVisible {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    @objc func menuProfileSelected(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String {
            selectProfile(id)
        } else {
            selectProfile(sender.title)
        }
    }

    func setupEventTap() {
        let eventMask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue))
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        if let tap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func playSound(for keyCode: Int64) {
        AudioEngineManager.shared.playSound(for: keyCode)
    }

    func playRelease(for keyCode: Int64) {
        AudioEngineManager.shared.playRelease(for: keyCode)
    }
}

func eventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    // Global mute hotkey: Control + Option + M (keyCode 46)
    if type == .keyDown && keyCode == 46 {
        let flags = event.flags
        if flags.contains(.maskControl) && flags.contains(.maskAlternate) && !flags.contains(.maskCommand) {
            DispatchQueue.main.async {
                appDelegate.toggleMute()
            }
            return Unmanaged.passUnretained(event)
        }
    }

    if type == .keyDown {
        appDelegate.playSound(for: keyCode)
    } else if type == .keyUp {
        appDelegate.playRelease(for: keyCode)
    }
    return Unmanaged.passUnretained(event)
}
