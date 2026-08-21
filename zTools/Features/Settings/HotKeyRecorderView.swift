import AppKit
import SwiftUI

/// Stable recorder that does not keep NSEvent monitors in @State (avoids SwiftUI lifecycle crashes).
struct HotKeyRecorderView: View {
    let title: String
    let chord: KeyChord?
    let onChange: (KeyChord?) -> Void

    @StateObject private var recorder = HotKeyRecorderModel()

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    recorder.start { newChord in
                        onChange(newChord)
                    }
                }
            } label: {
                Text(recorder.isRecording ? "按下快捷键…" : (chord?.displayString ?? "未设置"))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(recorder.isRecording ? Color.accentColor : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: ZTheme.radiusChip, style: .continuous)
                            .fill(recorder.isRecording ? ZTheme.selectionFill : ZTheme.fill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: ZTheme.radiusChip, style: .continuous)
                            .strokeBorder(recorder.isRecording ? ZTheme.selectionStroke : Color.clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            if chord != nil || recorder.isRecording {
                Button {
                    recorder.stop()
                    onChange(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清除")
            }
        }
        .onDisappear {
            recorder.stop()
        }
    }
}

@MainActor
final class HotKeyRecorderModel: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?
    private var onCapture: ((KeyChord) -> Void)?

    func start(onCapture: @escaping (KeyChord) -> Void) {
        stop()
        self.onCapture = onCapture
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        onCapture = nil
        isRecording = false
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        // Esc cancel
        if event.keyCode == 53 {
            stop()
            return nil
        }
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !mods.isEmpty else { return event }

        // Pure modifier keys
        let keyCode = event.keyCode
        if [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode) {
            return nil
        }

        let chord = KeyChord(keyCode: keyCode, modifiers: mods)
        let callback = onCapture
        stop()
        callback?(chord)
        return nil
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
