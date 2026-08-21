import SwiftUI

struct OverlayChrome<Content: View>: View {
    let title: String
    let onClose: () -> Void
    var onDragWindow: ((CGSize) -> Void)? = nil
    var animatesAppear: Bool = true
    @ViewBuilder let content: Content

    @State private var lastDrag: CGSize = .zero
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                ZCloseButton(action: onClose)
            }
            .padding(.horizontal, ZTheme.pad)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let delta = CGSize(
                            width: value.translation.width - lastDrag.width,
                            height: value.translation.height - lastDrag.height
                        )
                        lastDrag = value.translation
                        onDragWindow?(delta)
                    }
                    .onEnded { _ in lastDrag = .zero }
            )

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .zGlass(radius: ZTheme.radiusCard)
        .scaleEffect(appeared || !animatesAppear ? 1 : 0.96)
        .opacity(appeared || !animatesAppear ? 1 : 0)
        .onAppear {
            guard animatesAppear else { return }
            withAnimation(ZTheme.springPanel) { appeared = true }
        }
    }
}

struct ZCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .help("关闭 (Esc)")
    }
}

struct ZSearchField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .onSubmit { onSubmit?() }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(ZTheme.fill, in: RoundedRectangle(cornerRadius: ZTheme.radiusControl, style: .continuous))
    }
}

struct ZIconTile: View {
    let systemImage: String
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background(
                ZTheme.fill,
                in: RoundedRectangle(cornerRadius: ZTheme.radiusTile, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ZTheme.radiusTile, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
    }
}

struct ZPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(ZTheme.accent, in: RoundedRectangle(cornerRadius: ZTheme.radiusControl, style: .continuous))
            .shadow(color: ZTheme.accent.opacity(0.28), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isLoading)
        .opacity(enabled ? 1 : 0.45)
    }
}

struct ZSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .tracking(0.4)
    }
}

struct ZKeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(ZTheme.fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct ZGhostButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
    }
}

extension View {
    func zGlass(radius: CGFloat = ZTheme.radiusCard, shadowed: Bool = true, hairline: Bool = true) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            if hairline {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(ZTheme.hairline, lineWidth: 0.8)
            }
        }
        .shadow(
            color: shadowed ? ZTheme.shadowColor : .clear,
            radius: ZTheme.shadowRadius,
            y: ZTheme.shadowY
        )
    }

    func zSelected(_ selected: Bool, radius: CGFloat = ZTheme.radiusChip) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(selected ? ZTheme.selectionFill : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(selected ? ZTheme.selectionStroke : Color.clear, lineWidth: 1)
        )
    }

    func settingsPane() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
    }
}
