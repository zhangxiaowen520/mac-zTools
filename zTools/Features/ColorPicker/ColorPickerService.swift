import AppKit
import SwiftUI

final class ColorPickerService {
    @MainActor
    func pick(completion: @escaping (NSColor?) -> Void) {
        let sampler = NSColorSampler()
        sampler.show { color in
            completion(color)
        }
    }
}

extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var rgbString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "rgb(0, 0, 0)" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return "rgb(\(r), \(g), \(b))"
    }

    var hslString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "hsl(0, 0%, 0%)" }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let l = b * (1 - s / 2)
        let sat: CGFloat
        if l == 0 || l == 1 {
            sat = 0
        } else {
            sat = (b - l) / min(l, 1 - l)
        }
        return String(format: "hsl(%.0f, %.0f%%, %.0f%%)", h * 360, sat * 100, l * 100)
    }
}

struct ColorPickerResultView: View {
    let color: NSColor
    @ObservedObject private var history = ColorHistoryStore.shared
    @State private var copied: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: ZTheme.radiusCard, style: .continuous)
                        .fill(Color(nsColor: color))
                        .frame(height: 96)
                        .overlay(
                            RoundedRectangle(cornerRadius: ZTheme.radiusCard, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                        )
                    Text(color.hexString)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                }
                .padding(.horizontal, ZTheme.pad)

                VStack(spacing: 6) {
                    colorRow("HEX", color.hexString)
                    colorRow("RGB", color.rgbString)
                    colorRow("HSL", color.hslString)
                    colorRow("CSS", color.cssHexString)
                    colorRow("SwiftUI", color.swiftUIColorString)
                    colorRow("UIColor", color.uiColorString)
                }
                .padding(.horizontal, ZTheme.pad)

                if !history.items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ZSectionLabel(title: "历史色板")
                            Spacer()
                            Button("清空") { history.clear() }
                                .font(.caption2)
                                .buttonStyle(.borderless)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                            ForEach(history.items) { item in
                                Button {
                                    PasteboardUtil.copyString(item.hex)
                                    copied = item.hex
                                } label: {
                                    RoundedRectangle(cornerRadius: ZTheme.radiusChip, style: .continuous)
                                        .fill(Color(nsColor: item.nsColor))
                                        .frame(height: 28)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: ZTheme.radiusChip, style: .continuous)
                                                .strokeBorder(
                                                    item.hex == color.hexString ? ZTheme.accent : Color.primary.opacity(0.12),
                                                    lineWidth: item.hex == color.hexString ? 2 : 0.5
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(item.hex)
                                .contextMenu {
                                    Button("复制 \(item.hex)") {
                                        PasteboardUtil.copyString(item.hex)
                                    }
                                    Button("删除", role: .destructive) {
                                        history.remove(item)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, ZTheme.pad)
                }

                if let copied {
                    Text("已复制 \(copied)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.horizontal, ZTheme.pad)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 14)
        }
        .onAppear {
            ColorHistoryStore.shared.add(color)
        }
    }

    private func colorRow(_ title: String, _ value: String) -> some View {
        Button {
            PasteboardUtil.copyString(value)
            copied = title
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)
                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(ZTheme.fill, in: RoundedRectangle(cornerRadius: ZTheme.radiusChip, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
