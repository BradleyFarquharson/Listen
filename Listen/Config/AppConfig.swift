import Foundation
import Carbon

/// App configuration backed by UserDefaults.
final class AppConfig: ObservableObject {
    // MARK: - Mode
    @Published var mode: RecordingMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") }
    }

    // MARK: - Hotkey
    @Published var hotkey: Hotkey {
        didSet { hotkey.save() }
    }

    // MARK: - Audio
    @Published var sampleRate: Int = 16000
    @Published var channels: Int = 1

    // MARK: - Model (internal, not user-facing)
    @Published var modelName: String = "parakeet-tdt-0.6b-v2"

    enum RecordingMode: String, CaseIterable {
        case pushToTalk = "push-to-talk"
        case toggleMute = "toggle-mute"

        var displayName: String {
            switch self {
            case .pushToTalk: return "Push to Talk"
            case .toggleMute: return "Toggle Mute"
            }
        }
    }

    /// Represents a hotkey — either a modifier-only key (Globe, Right ⌘) or a key + modifiers combo.
    struct Hotkey: Equatable {
        enum Kind: String {
            case globe           // Globe/fn key (modifier-only)
            case modifierOnly    // A single modifier key like Right ⌘ (keycode distinguishes left/right)
            case keyCombo        // Regular key + optional modifiers (e.g. F5, ⌥Space)
        }

        let kind: Kind
        let keyCode: UInt16      // CGEvent keycode (0 for globe)
        let modifiers: UInt32    // CGEventFlags rawValue (masked to relevant bits)
        let displayName: String  // Human-readable label

        // MARK: - Presets

        static let globe = Hotkey(kind: .globe, keyCode: 0, modifiers: 0, displayName: "Globe (fn)")
        static let rightCommand = Hotkey(kind: .modifierOnly, keyCode: 54, modifiers: UInt32(CGEventFlags.maskCommand.rawValue), displayName: "Right ⌘")

        // MARK: - Persistence

        func save() {
            let defaults = UserDefaults.standard
            defaults.set(kind.rawValue, forKey: "hotkey.kind")
            defaults.set(Int(keyCode), forKey: "hotkey.keyCode")
            defaults.set(Int(modifiers), forKey: "hotkey.modifiers")
            defaults.set(displayName, forKey: "hotkey.displayName")
        }

        static func load() -> Hotkey {
            let defaults = UserDefaults.standard
            guard let kindStr = defaults.string(forKey: "hotkey.kind"),
                  let kind = Kind(rawValue: kindStr) else {
                return .globe
            }
            let keyCode = UInt16(defaults.integer(forKey: "hotkey.keyCode"))
            let modifiers = UInt32(defaults.integer(forKey: "hotkey.modifiers"))
            let displayName = defaults.string(forKey: "hotkey.displayName") ?? "Globe (fn)"
            return Hotkey(kind: kind, keyCode: keyCode, modifiers: modifiers, displayName: displayName)
        }

        // MARK: - Create from CGEvent (for hotkey recorder)

        /// Create a Hotkey from a flagsChanged CGEvent (modifier key press).
        static func fromModifierEvent(keyCode: UInt16, flags: CGEventFlags) -> Hotkey {
            let name = modifierDisplayName(keyCode: keyCode, flags: flags)
            // Determine if this is Globe/fn
            if flags.contains(.maskSecondaryFn) && keyCode == 63 {
                return .globe
            }
            return Hotkey(
                kind: .modifierOnly,
                keyCode: keyCode,
                modifiers: sanitizeModifiers(flags),
                displayName: name
            )
        }

        /// Create a Hotkey from a keyDown CGEvent (regular key + modifiers).
        static func fromKeyEvent(keyCode: UInt16, flags: CGEventFlags) -> Hotkey {
            let modStr = modifierSymbols(flags)
            let keyStr = keyDisplayName(keyCode: keyCode)
            let name = modStr.isEmpty ? keyStr : "\(modStr)\(keyStr)"
            return Hotkey(
                kind: .keyCombo,
                keyCode: keyCode,
                modifiers: sanitizeModifiers(flags),
                displayName: name
            )
        }

        // MARK: - Display helpers

        private static func sanitizeModifiers(_ flags: CGEventFlags) -> UInt32 {
            let mask: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate, .maskSecondaryFn]
            return UInt32(flags.intersection(mask).rawValue)
        }

        private static func modifierSymbols(_ flags: CGEventFlags) -> String {
            var s = ""
            if flags.contains(.maskControl) { s += "⌃" }
            if flags.contains(.maskAlternate) { s += "⌥" }
            if flags.contains(.maskShift) { s += "⇧" }
            if flags.contains(.maskCommand) { s += "⌘" }
            return s
        }

        private static func modifierDisplayName(keyCode: UInt16, flags: CGEventFlags) -> String {
            // Globe/fn
            if keyCode == 63 || flags.contains(.maskSecondaryFn) {
                return "Globe (fn)"
            }
            // Right Command = 54, Left Command = 55
            if keyCode == 54 { return "Right ⌘" }
            if keyCode == 55 { return "Left ⌘" }
            // Right Option = 61, Left Option = 58
            if keyCode == 61 { return "Right ⌥" }
            if keyCode == 58 { return "Left ⌥" }
            // Right Shift = 60, Left Shift = 56
            if keyCode == 60 { return "Right ⇧" }
            if keyCode == 56 { return "Left ⇧" }
            // Right Control = 62, Left Control = 59
            if keyCode == 62 { return "Right ⌃" }
            if keyCode == 59 { return "Left ⌃" }
            // Caps Lock = 57
            if keyCode == 57 { return "Caps Lock" }
            return "Modifier \(keyCode)"
        }

        private static func keyDisplayName(keyCode: UInt16) -> String {
            // Function keys
            switch keyCode {
            case 122: return "F1"
            case 120: return "F2"
            case 99: return "F3"
            case 118: return "F4"
            case 96: return "F5"
            case 97: return "F6"
            case 98: return "F7"
            case 100: return "F8"
            case 101: return "F9"
            case 109: return "F10"
            case 103: return "F11"
            case 111: return "F12"
            case 105: return "F13"
            case 107: return "F14"
            case 113: return "F15"
            // Special keys
            case 49: return "Space"
            case 36: return "Return"
            case 48: return "Tab"
            case 51: return "Delete"
            case 53: return "Escape"
            case 123: return "←"
            case 124: return "→"
            case 125: return "↓"
            case 126: return "↑"
            default: break
            }
            // Try to get the character from the keycode
            let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            if let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
                let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
                var deadKeyState: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length: Int = 0
                data.withUnsafeBytes { rawBuf in
                    let ptr = rawBuf.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
                    UCKeyTranslate(
                        ptr,
                        keyCode,
                        UInt16(kUCKeyActionDisplay),
                        0, // no modifiers for display
                        UInt32(LMGetKbdType()),
                        UInt32(kUCKeyTranslateNoDeadKeysBit),
                        &deadKeyState,
                        chars.count,
                        &length,
                        &chars
                    )
                }
                if length > 0 {
                    return String(utf16CodeUnits: chars, count: length).uppercased()
                }
            }
            return "Key \(keyCode)"
        }
    }

    init() {
        let defaults = UserDefaults.standard
        self.mode = RecordingMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .pushToTalk
        self.hotkey = Hotkey.load()
    }
}
