import AppKit
import Carbon.HIToolbox
import SwiftUI

struct KeyChord: Equatable, Hashable {
    var keyCode: UInt16
    var modifierRaw: UInt

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRaw).intersection([.command, .shift, .option, .control])
    }

    var storageValue: String {
        "\(keyCode)|\(modifierRaw)"
    }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierRaw = modifiers.intersection([.command, .shift, .option, .control]).rawValue
    }

    init?(storageValue: String) {
        let parts = storageValue.split(separator: "|")
        guard parts.count == 2,
              let code = UInt16(parts[0]),
              let raw = UInt(parts[1]) else { return nil }
        self.keyCode = code
        self.modifierRaw = NSEvent.ModifierFlags(rawValue: raw)
            .intersection([.command, .shift, .option, .control]).rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifierRaw)
    }

    static func == (lhs: KeyChord, rhs: KeyChord) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifierRaw == rhs.modifierRaw
    }

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        let mods = modifiers
        if mods.contains(.command) { value |= UInt32(cmdKey) }
        if mods.contains(.shift) { value |= UInt32(shiftKey) }
        if mods.contains(.option) { value |= UInt32(optionKey) }
        if mods.contains(.control) { value |= UInt32(controlKey) }
        return value
    }

    var displayString: String {
        var parts: [String] = []
        let mods = modifiers
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option) { parts.append("⌥") }
        if mods.contains(.shift) { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyName(keyCode))
        return parts.joined()
    }

    /// For SwiftUI `.keyboardShortcut` display in menus.
    var keyEquivalentCharacter: Character? {
        let name = Self.keyName(keyCode)
        guard name.count == 1, let ch = name.lowercased().first else {
            switch keyCode {
            case 36: return "\r"
            case 48: return "\t"
            case 49: return " "
            case 51: return "\u{8}"
            case 53: return "\u{1b}"
            default: return nil
            }
        }
        return ch
    }

    var eventModifiers: SwiftUI.EventModifiers {
        var m: SwiftUI.EventModifiers = []
        let mods = modifiers
        if mods.contains(.command) { m.insert(.command) }
        if mods.contains(.shift) { m.insert(.shift) }
        if mods.contains(.option) { m.insert(.option) }
        if mods.contains(.control) { m.insert(.control) }
        return m
    }

    private static func keyName(_ keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "␣", 50: "`",
            51: "⌫", 53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}
