import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Puts a clip back on the clipboard and, with Accessibility access, presses ⌘V.
enum Paster {
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    enum AccessibilityStatus {
        case allowed
        case missing
        /// Allowed before but not now: macOS drops the permission when an update is signed differently.
        case lost
    }

    private static let hadAccessibilityKey = "hadAccessibility"

    static func accessibilityStatus() -> AccessibilityStatus {
        if hasAccessibility {
            UserDefaults.standard.set(true, forKey: hadAccessibilityKey)
            return .allowed
        }
        return UserDefaults.standard.bool(forKey: hadAccessibilityKey) ? .lost : .missing
    }

    /// Shows the system prompt that sends the user to Privacy & Security → Accessibility.
    /// Only call this when the user asks for it: the prompt interrupts whatever they're doing.
    static func requestAccessibility() {
        resetAccessibilityEntry()
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Removes ClipKeep's entry from the Accessibility list so the prompt adds a fresh one.
    /// After an update macOS can keep the old entry switched on even though it no longer
    /// applies, and switching it off and on doesn't fix it.
    private static func resetAccessibilityEntry() {
        guard !hasAccessibility, let bundleID = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("ClipKeep: could not reset the Accessibility entry: \(error)")
        }
    }

    /// Returns false if an image clip's file couldn't be read.
    @discardableResult
    /// Opens System Settings at Privacy & Security → Accessibility.
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func write(_ clip: Clip, plainText: Bool, imageURL: URL?) -> Bool {
        let item = NSPasteboardItem()
        if clip.isImage {
            guard let imageURL, let png = try? Data(contentsOf: imageURL) else { return false }
            item.setData(png, forType: .png)
            // Some older apps only accept TIFF.
            if let tiff = NSImage(data: png)?.tiffRepresentation {
                item.setData(tiff, forType: .tiff)
            }
        } else {
            if !plainText, let rtf = clip.rtf {
                item.setData(rtf, forType: .rtf)
            }
            item.setString(clip.text, forType: .string)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        return true
    }

    /// Sends ⌘V to whichever app is in front.
    static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyV = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
