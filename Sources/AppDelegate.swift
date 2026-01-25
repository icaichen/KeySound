import Cocoa
import CoreGraphics
import AVFoundation
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem?
    var eventTap: CFMachPort?
    // var soundPlayers: [AVAudioPlayer] = [] // Removed
    // var specialSoundPlayers: [String: AVAudioPlayer] = [:] // Removed
    var soundProfiles: [String] = []
    var currentProfile: String = "MX_Blue"
    
    // Settings Window
    var settingsWindow: NSWindow?
    // var audioSettings = AudioSettings.shared // AudioSettings manages AudioEngineManager directly

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        loadProfiles()
        setupStatusBar()
        setupEventTap()
        
        let savedProfile = UserDefaults.standard.string(forKey: "SelectedProfile") ?? "MX_Blue"
        if soundProfiles.contains(savedProfile) {
            selectProfile(savedProfile)
        } else if let first = soundProfiles.first {
             selectProfile(first)
        }
        
        // Ensure settings are synced
        _ = AudioSettings.shared
        
        openSettingsWindow()
    }


    func loadProfiles() {
        var soundsURL: URL?
        
        // 1. Try standard App Bundle Resources
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent("Sounds")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir) && isDir.boolValue {
                soundsURL = candidate
            }
        }
        
        // 2. Fallback to SPM Module
        if soundsURL == nil {
            soundsURL = Bundle.module.resourceURL?.appendingPathComponent("Sounds")
        }
        
        guard let finalURL = soundsURL else {
            print("Sounds directory not found in bundle")
            return
        }
        
        do {
            let items = try FileManager.default.contentsOfDirectory(atPath: finalURL.path)
            soundProfiles = items.filter { item in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: finalURL.appendingPathComponent(item).path, isDirectory: &isDir) && isDir.boolValue
            }.sorted()
        } catch {
            print("Error listing sound profiles: \(error)")
        }
    }

    func selectProfile(_ profile: String) {
        currentProfile = profile
        UserDefaults.standard.set(profile, forKey: "SelectedProfile")
        AudioEngineManager.shared.loadSounds(for: profile)
        updateMenu()
    }

    // loadSounds removed

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "🎹"
        updateMenu()
    }

    func updateMenu() {
        let menu = NSMenu()
        
        let titleItem = NSMenuItem(title: "Keyboard Sounds", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsWindow), keyEquivalent: ",")
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        
        for profile in soundProfiles {
            let item = NSMenuItem(title: profile, action: #selector(menuProfileSelected(_:)), keyEquivalent: "")
            if profile == currentProfile {
                item.state = .on
            }
            menu.addItem(item)
        }
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    @objc func openSettingsWindow() {
        if settingsWindow == nil {
            // Create the SwiftUI view that provides the window contents.
            var settingsView = SettingsView()
            settingsView.onProfileChange = { [weak self] newProfile in
                self?.selectProfile(newProfile)
            }
            
            let hostingController = NSHostingController(rootView: settingsView)
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 350),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.center()
            window.setFrameAutosaveName("SettingsWindow")
            window.contentViewController = hostingController
            window.title = "Settings"
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func menuProfileSelected(_ sender: NSMenuItem) {
        selectProfile(sender.title)
    }

    @objc func toggleListening() {
        if eventTap != nil {
            CGEvent.tapEnable(tap: eventTap!, enable: false)
            eventTap = nil
        } else {
            setupEventTap()
        }
        updateMenu()
    }

    func setupEventTap() {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
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
}

func eventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .keyDown {
        let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        appDelegate.playSound(for: keyCode)
    }
    return Unmanaged.passUnretained(event)
}
