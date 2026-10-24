import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Puts a clip back on the clipboard and, with Accessibility access, presses ⌘V.
enum Paster {
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security → Accessibility.
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
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
