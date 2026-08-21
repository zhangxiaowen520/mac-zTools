import AppKit
import SwiftUI
import Vision

final class OCRService: @unchecked Sendable {
    func recognize(image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum OCRError: LocalizedError {
    case invalidImage
    var errorDescription: String? { "无法读取图片" }
}

struct OCRResultView: View {
    @EnvironmentObject private var appState: AppState
    @State var text: String

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $text)
                .font(.system(size: 14))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    ZTheme.fillQuiet,
                    in: RoundedRectangle(cornerRadius: ZTheme.radiusControl, style: .continuous)
                )
                .padding(.horizontal, ZTheme.pad)
                .padding(.bottom, 12)

            HStack(spacing: 12) {
                Button("复制") {
                    PasteboardUtil.copyString(text)
                    appState.showToast("已复制")
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))

                Button("再截") {
                    appState.panelController.close()
                    appState.handle(.ocr)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

                Spacer()

                ZPrimaryButton(title: "翻译") {
                    appState.openTranslate(text: text)
                }
            }
            .padding(.horizontal, ZTheme.pad)
            .padding(.bottom, ZTheme.pad)
        }
    }
}
