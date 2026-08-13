import AppKit
import SwiftUI

struct ScreenshotEditorView: View {
    let image: NSImage
    let onCopy: (NSImage) -> Void
    let onCopyAndClose: (NSImage, [AnnotationStroke]) -> Void
    let onSave: (NSImage, [AnnotationStroke]) -> Void
    let onOCR: (NSImage) -> Void
    let onPin: (NSImage, [AnnotationStroke]) -> Void
    let onCancel: () -> Void

    @State private var strokes: [AnnotationStroke] = []
    @State private var redoStack: [AnnotationStroke] = []
    @State private var draft: AnnotationStroke?
    @State private var tool: AnnotationTool = .rect
    @State private var color: Color = .red
    @State private var lineWidth: CGFloat = 5
    @State private var canvasSize: CGSize = .zero
    @State private var textDraftPoint: CGPoint?
    @State private var textInput = ""
    @State private var showTextAlert = false
    @State private var nextNumber = 1
    @State private var showDiscardConfirm = false

    init(
        image: NSImage,
        initialStrokes: [AnnotationStroke] = [],
        onCopy: @escaping (NSImage) -> Void,
        onCopyAndClose: @escaping (NSImage, [AnnotationStroke]) -> Void,
        onSave: @escaping (NSImage, [AnnotationStroke]) -> Void,
        onOCR: @escaping (NSImage) -> Void,
        onPin: @escaping (NSImage, [AnnotationStroke]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.image = image
        self.onCopy = onCopy
        self.onCopyAndClose = onCopyAndClose
        self.onSave = onSave
        self.onOCR = onOCR
        self.onPin = onPin
        self.onCancel = onCancel
        _strokes = State(initialValue: initialStrokes)
        let maxNumber = initialStrokes.map(\.number).max() ?? 0
        _nextNumber = State(initialValue: maxNumber + 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.bar)

            Divider()

            AnnotationCanvas(
                image: image,
                strokes: $strokes,
                draft: $draft,
                tool: tool,
                color: color,
                lineWidth: lineWidth,
                nextNumber: nextNumber,
                onCommitDraft: commitDraft,
                onRequestText: { point in
                    textDraftPoint = point
                    textInput = ""
                    showTextAlert = true
                },
                onRequestNumber: { point in
                    let stroke = AnnotationStroke(
                        tool: .number,
                        points: [point],
                        color: color,
                        lineWidth: lineWidth,
                        number: nextNumber
                    )
                    strokes.append(stroke)
                    redoStack.removeAll()
                    nextNumber += 1
                }
            )
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { canvasSize = geo.size }
                        .onChange(of: geo.size) { _, size in canvasSize = size }
                }
            )

            Divider()

            actionBar
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.bar)
        }
        .frame(minWidth: 760, minHeight: 540)
        .alert("添加文字", isPresented: $showTextAlert) {
            TextField("输入标注文字", text: $textInput)
            Button("取消", role: .cancel) {
                textDraftPoint = nil
                textInput = ""
            }
            Button("添加") {
                guard let point = textDraftPoint else { return }
                let stroke = AnnotationStroke(
                    tool: .text,
                    points: [point],
                    color: color,
                    lineWidth: lineWidth,
                    text: textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "文字" : textInput
                )
                strokes.append(stroke)
                redoStack.removeAll()
                textDraftPoint = nil
                textInput = ""
            }
        } message: {
            Text("在点击位置添加文字标注")
        }
        .confirmationDialog("丢弃标注并关闭？", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("丢弃", role: .destructive) { onCancel() }
            Button("取消", role: .cancel) {}
        }
        .onExitCommand {
            requestCancel()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(AnnotationTool.allCases) { item in
                        toolButton(item)
                    }
                }
            }

            Divider().frame(height: 22)

            ForEach(Array(AnnotationPalette.colors.enumerated()), id: \.offset) { _, item in
                Button { color = item } label: {
                    Circle()
                        .fill(item)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    color == item ? Color.accentColor : Color.primary.opacity(0.15),
                                    lineWidth: color == item ? 2 : 0.5
                                )
                        )
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 22)

            Picker("粗细", selection: $lineWidth) {
                ForEach(AnnotationPalette.lineWidths, id: \.self) { width in
                    Text("\(Int(width))").tag(width)
                }
            }
            .labelsHidden()
            .frame(width: 56)
            .help(tool == .mosaic ? "马赛克块大小" : "线宽")

            Divider().frame(height: 22)

            Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.borderless)
                .disabled(strokes.isEmpty && draft == nil)
                .help("撤销")

            Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(.borderless)
                .disabled(redoStack.isEmpty)
                .help("重做")

            Button {
                strokes.removeAll()
                draft = nil
                redoStack.removeAll()
                nextNumber = 1
            } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .disabled(strokes.isEmpty && draft == nil)
                .help("清空标注")
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("取消") { requestCancel() }
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button("钉图") {
                onPin(renderOutput(), strokes)
            }
            .help("置顶悬浮显示")

            Button("OCR") {
                onOCR(renderOutput())
            }

            Button("保存…") {
                onSave(renderOutput(), strokes)
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("复制") {
                onCopy(renderOutput())
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("复制并关闭") {
                onCopyAndClose(renderOutput(), strokes)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .help("⌘↩")
        }
    }

    private func toolButton(_ item: AnnotationTool) -> some View {
        Button { tool = item } label: {
            Image(systemName: item.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tool == item ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(tool == item ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(item.title)
    }

    private func requestCancel() {
        if strokes.isEmpty && draft == nil {
            onCancel()
        } else {
            showDiscardConfirm = true
        }
    }

    private func commitDraft() {
        guard let draft else { return }
        let meaningful: Bool
        switch draft.tool {
        case .pen:
            meaningful = draft.points.count > 1
        case .text, .number:
            meaningful = true
        default:
            meaningful = hypot(draft.end.x - draft.start.x, draft.end.y - draft.start.y) > 3
        }
        if meaningful {
            strokes.append(draft)
            redoStack.removeAll()
        }
        self.draft = nil
    }

    private func undo() {
        if draft != nil {
            draft = nil
            return
        }
        guard let last = strokes.popLast() else { return }
        if last.tool == .number, last.number == nextNumber - 1 {
            nextNumber = max(1, nextNumber - 1)
        }
        redoStack.append(last)
    }

    private func redo() {
        guard let item = redoStack.popLast() else { return }
        if item.tool == .number {
            nextNumber = max(nextNumber, item.number + 1)
        }
        strokes.append(item)
    }

    private func renderOutput() -> NSImage {
        let size = canvasSize == .zero ? CGSize(width: 800, height: 600) : canvasSize
        return AnnotationRenderer.render(image: image, strokes: strokes, canvasSize: size)
    }
}
