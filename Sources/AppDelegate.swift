import Cocoa
import CoreGraphics
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem?
    var eventTap: CFMachPort?
    var soundPlayers: [AVAudioPlayer] = []
    var specialSoundPlayers: [String: AVAudioPlayer] = [:]
    var soundProfiles: [String] = []
    var currentProfile: String = "Tickeys"

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        loadProfiles()
        setupStatusBar()
        setupEventTap()
        
        let savedProfile = UserDefaults.standard.string(forKey: "SelectedProfile") ?? "Tickeys"
        if soundProfiles.contains(savedProfile) {
            selectProfile(savedProfile)
        } else if let first = soundProfiles.first {
             selectProfile(first)
        }
    }

    func loadProfiles() {
        guard let soundsURL = Bundle.module.resourceURL?.appendingPathComponent("Sounds") else {
            print("Sounds directory not found in bundle")
            return
        }
        
        do {
            let items = try FileManager.default.contentsOfDirectory(atPath: soundsURL.path)
            soundProfiles = items.filter { item in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: soundsURL.appendingPathComponent(item).path, isDirectory: &isDir) && isDir.boolValue
            }.sorted()
        } catch {
            print("Error listing sound profiles: \(error)")
        }
    }

    func selectProfile(_ profile: String) {
        currentProfile = profile
        UserDefaults.standard.set(profile, forKey: "SelectedProfile")
        loadSounds(for: profile)
        updateMenu()
    }

    func loadSounds(for profile: String) {
        soundPlayers.removeAll()
        specialSoundPlayers.removeAll()
        
        guard let soundsURL = Bundle.module.resourceURL?.appendingPathComponent("Sounds").appendingPathComponent(profile) else {
            return
        }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: soundsURL.path)
            let wavs = files.filter { $0.hasSuffix(".wav") }.sorted()
            
            for file in wavs {
                let url = soundsURL.appendingPathComponent(file)
                do {
                    let player = try AVAudioPlayer(contentsOf: url)
                    player.prepareToPlay()
                    
                    let lowerFile = file.lowercased()
                    if lowerFile.contains("enter") || lowerFile.contains("return") {
                        specialSoundPlayers["enter"] = player
                    } else if lowerFile.contains("space") {
                        specialSoundPlayers["space"] = player
                    } else if lowerFile.contains("back") || lowerFile.contains("delete") {
                        specialSoundPlayers["backspace"] = player
                    } else if lowerFile.contains("modifier") || lowerFile.contains("shift") || lowerFile.contains("ctrl") || lowerFile.contains("alt") || lowerFile.contains("cmd") {
                        specialSoundPlayers["modifier"] = player
                    } else {
                        soundPlayers.append(player)
                    }
                } catch {
                    print("Error loading sound \(file): \(error)")
                }
            }
            print("Loaded \(soundPlayers.count) generic sounds and \(specialSoundPlayers.count) special sounds for profile \(profile)")
        } catch {
            print("Error loading sounds for \(profile): \(error)")
        }
    }

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
        
        let toggleItem = NSMenuItem(title: eventTap != nil ? "Mute" : "Unmute", action: #selector(toggleListening), keyEquivalent: "m")
        menu.addItem(toggleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let profilesItem = NSMenuItem(title: "Sound Profile", action: nil, keyEquivalent: "")
        profilesItem.isEnabled = false
        menu.addItem(profilesItem)
        
        for profile in soundProfiles {
            let item = NSMenuItem(title: profile, action: #selector(profileSelected(_:)), keyEquivalent: "")
            item.state = (profile == currentProfile) ? .on : .off
            item.target = self
            menu.addItem(item)
        }
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        statusItem?.button?.title = eventTap != nil ? "🎹" : "🔇"
    }
    
    @objc func profileSelected(_ sender: NSMenuItem) {
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
        var player: AVAudioPlayer?
        
        // Check for special keys
        switch keyCode {
        case 36: // Return
            player = specialSoundPlayers["enter"]
        case 49: // Space
            player = specialSoundPlayers["space"]
        case 51: // Delete
            player = specialSoundPlayers["backspace"]
        case 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63: // Modifiers (Esc, Cmd, Shift, Opt, Ctrl, Caps)
            player = specialSoundPlayers["modifier"]
        default:
            break
        }
        
        // Fallback to generic sounds if special sound not found or key is generic
        if player == nil && !soundPlayers.isEmpty {
            let index = Int(keyCode) % soundPlayers.count
            player = soundPlayers[index]
        }
        
        if let p = player {
            if p.isPlaying {
                p.currentTime = 0
                p.play()
            } else {
                p.play()
            }
        }
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
