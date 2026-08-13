import AppKit
import SwiftUI

struct TranslateView: View {
    @EnvironmentObject private var appState: AppState
    var initialText: String = ""

    @State private var source = ""
    @State private var result = ""
    @State private var targetLanguage = "zh"
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didApplyInitial = false

    private let languages: [(String, String)] = [
        ("zh", "中文"),
        ("en", "English"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("es", "Español")
    ]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("目标语言")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $targetLanguage) {
                    ForEach(languages, id: \.0) { item in
                        Text(item.1).tag(item.0)
                    }
                }
                .labelsHidden()
                .frame(width: 140)

                Spacer()

                Button("划词") {
                    Task {
                        if let text = await SelectionHelper.selectedText(), !text.isEmpty {
                            source = text
                        } else {
                            appState.showToast("未获取到选中文本")
                        }
                    }
                }
                .buttonStyle(.bordered)
                .help("读取当前选中文本（需辅助功能）")

                Button("剪贴板") {
                    if let str = NSPasteboard.general.string(forType: .string) {
                        source = str
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 6) {
                Text("原文")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $source)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 110)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.horizontal, 14)

            HStack {
                Button {
                    Task { await runTranslate() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 64)
                    } else {
                        Label("翻译", systemImage: "globe")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                .keyboardShortcut(.return, modifiers: .command)

                Button("交换") {
                    if !result.isEmpty {
                        source = result
                        result = ""
                    }
                }
                .buttonStyle(.bordered)
                .disabled(result.isEmpty)

                Spacer()
            }
            .padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("译文")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !result.isEmpty {
                        Button("复制") {
                            PasteboardUtil.copyString(result)
                            appState.showToast("已复制译文")
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
                TextEditor(text: $result)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 110)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.horizontal, 14)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 14)
        .onAppear {
            targetLanguage = appState.settings.targetLanguage
            if !didApplyInitial {
                didApplyInitial = true
                if !initialText.isEmpty {
                    source = initialText
                    Task { await runTranslate() }
                } else if source.isEmpty, let str = NSPasteboard.general.string(forType: .string), !str.isEmpty {
                    source = str
                }
            }
        }
    }

    private func runTranslate() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let text = try await appState.translateService.translate(text: source, to: targetLanguage)
            result = text
            appState.settings.targetLanguage = targetLanguage
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
