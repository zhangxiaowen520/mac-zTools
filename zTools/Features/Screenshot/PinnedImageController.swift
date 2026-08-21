import AppKit
import SwiftUI

@MainActor
final class PinnedImageController {
    static let shared = PinnedImageController()

    private var windows: [UUID: NSPanel] = [:]

    private init() {}

    func pin(_ image: NSImage) {
        let id = UUID()
        let maxSide: CGFloat = 420
        let imgSize = image.size
        let scale = min(1, maxSide / max(imgSize.width, imgSize.height, 1))
        let size = CGSize(
            width: max(160, imgSize.width * scale + 16),
            height: max(120, imgSize.height * scale + 40)
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 140, height: 100)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = PinnedImageView(image: image) { [weak self] in
            self?.close(id)
        } onCopy: {
            PasteboardUtil.copyImage(image)
            ToastController.shared.show("已复制钉图")
        }

        panel.contentView = NSHostingView(rootView: root.frame(width: size.width, height: size.height))
        panel.setContentSize(size)

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let offset = CGFloat(windows.count % 5) * 28
            panel.setFrameOrigin(CGPoint(
                x: visible.maxX - size.width - 28 - offset,
                y: visible.maxY - size.height - 28 - offset
            ))
        }

        panel.makeKeyAndOrderFront(nil)
        windows[id] = panel
    }

    func close(_ id: UUID) {
        windows[id]?.orderOut(nil)
        windows[id] = nil
        windows.removeValue(forKey: id)
    }

    func closeAll() {
        windows.values.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

private struct PinnedImageView: View {
    let image: NSImage
    let onClose: () -> Void
    let onCopy: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("钉图")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("复制")
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Color.primary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: ZTheme.radiusChip, style: .continuous))
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .zGlass(radius: ZTheme.radiusCard)
    }
}
