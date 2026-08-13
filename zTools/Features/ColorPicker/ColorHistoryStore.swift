import AppKit
import Foundation
import SwiftUI

struct StoredColor: Identifiable, Equatable, Codable {
    let id: UUID
    let hex: String
    let createdAt: Date

    init(id: UUID = UUID(), hex: String, createdAt: Date = Date()) {
        self.id = id
        self.hex = hex.uppercased()
        self.createdAt = createdAt
    }

    var nsColor: NSColor {
        NSColor(hex: hex) ?? .black
    }
}

@MainActor
final class ColorHistoryStore: ObservableObject {
    static let shared = ColorHistoryStore()

    @Published private(set) var items: [StoredColor] = []
    private let limit = 24
    private let key = "colorHistory.v1"

    private init() {
        load()
    }

    func add(_ color: NSColor) {
        let hex = color.hexString.uppercased()
        items.removeAll { $0.hex == hex }
        items.insert(StoredColor(hex: hex), at: 0)
        if items.count > limit {
            items = Array(items.prefix(limit))
        }
        save()
    }

    func remove(_ item: StoredColor) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([StoredColor].self, from: data) else { return }
        items = decoded
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    var cssHexString: String { hexString.lowercased() }

    var swiftUIColorString: String {
        guard let rgb = usingColorSpace(.sRGB) else {
            return "Color(red: 0, green: 0, blue: 0)"
        }
        return String(
            format: "Color(red: %.3f, green: %.3f, blue: %.3f)",
            rgb.redComponent,
            rgb.greenComponent,
            rgb.blueComponent
        )
    }

    var uiColorString: String {
        guard let rgb = usingColorSpace(.sRGB) else {
            return "UIColor(red: 0, green: 0, blue: 0, alpha: 1)"
        }
        return String(
            format: "UIColor(red: %.3f, green: %.3f, blue: %.3f, alpha: 1)",
            rgb.redComponent,
            rgb.greenComponent,
            rgb.blueComponent
        )
    }
}
