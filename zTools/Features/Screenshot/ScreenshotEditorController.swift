import AppKit
import SwiftUI

@MainActor
final class ScreenshotEditorController {
    static let shared = ScreenshotEditorController()

    private var panel: NSPanel?

    private init() {}

    func present(
        image: NSImage,
        initialStrokes: [AnnotationStroke] = [],
        onCopy: @escaping (NSImage) -> Void,
        onSave: @escaping (NSImage) -> Void,
        onOCR: @escaping (NSImage) -> Void,
        onPin: @escaping (NSImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        close()

        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let maxW = min(screen.width * 0.88, 1320)
        let maxH = min(screen.height * 0.88, 920)
        let img = image.size
        let aspect = img.width > 0 && img.height > 0 ? img.width / img.height : 16 / 10
        var width = maxW
        var height = width / aspect + 120
        if height > maxH {
            height = maxH
            width = (height - 120) * aspect
        }
        width = max(width, 760)
        height = max(height, 540)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "截图编辑"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 760, height: 540)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        let root = ScreenshotEditorView(
            image: image,
            initialStrokes: initialStrokes,
            onCopy: { result in
                onCopy(result)
            },
            onCopyAndClose: { [weak self] result, strokes in
                onCopy(result)
                EditorDraftStore.save(image: image, strokes: strokes)
                self?.close()
            },
            onSave: { result, strokes in
                onSave(result)
                EditorDraftStore.save(image: image, strokes: strokes)
            },
            onOCR: { result in
                onOCR(result)
            },
            onPin: { [weak self] result, strokes in
                onPin(result)
                EditorDraftStore.save(image: image, strokes: strokes)
                self?.close()
            },
            onCancel: { [weak self] in
                onCancel()
                self?.close()
            }
        )

        panel.contentView = NSHostingView(rootView: root)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
