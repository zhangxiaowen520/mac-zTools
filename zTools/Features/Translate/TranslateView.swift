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

    private var targetName: String {
        languages.first { $0.0 == targetLanguage }?.1 ?? targetLanguage
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(languages, id: \.0) { item in
                        Button(item.1) { targetLanguage = item.0 }
                    }
                } label: {
                    Text(targetName)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            ZTheme.selectionFill,
                            in: RoundedRectangle(cornerRadius: ZTheme.radiusChip, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: ZTheme.radiusChip, style: .continuous)
                                .strokeBorder(ZTheme.selectionStroke, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    if !result.isEmpty {
                        let old = source
                        source = result
                        result = old
                    }
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(ZTheme.fill, in: RoundedRectangle(cornerRadius: ZTheme.radiusChip, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(result.isEmpty)
                .help("交换原文 / 译文")

                Spacer(minLength: 8)

                ZGhostButton(title: "划词") {
                    Task {
                        if let text = await SelectionHelper.selectedText(), !text.isEmpty {
                            source = text
                        } else {
                            appState.showToast("未获取到选中文本")
                        }
                    }
                }
                .help("读取当前选中文本（需辅助功能）")

                ZGhostButton(title: "剪贴板") {
                    if let str = NSPasteboard.general.string(forType: .string) {
                        source = str
                    }
                }
            }
            .padding(.horizontal, ZTheme.pad)

            HStack(alignment: .top, spacing: 10) {
                editorPane(title: "原文", text: $source)
                editorPane(title: "译文", text: $result, showCopy: !result.isEmpty)
            }
            .padding(.horizontal, ZTheme.pad)
            .frame(maxHeight: .infinity)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, ZTheme.pad)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                ZPrimaryButton(
                    title: "翻译",
                    isLoading: isLoading,
                    enabled: !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    Task { await runTranslate() }
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, ZTheme.pad)
            .padding(.bottom, ZTheme.pad)
        }
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

    private func editorPane(title: String, text: Binding<String>, showCopy: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZSectionLabel(title: title)
                Spacer()
                if showCopy {
                    ZGhostButton(title: "复制") {
                        PasteboardUtil.copyString(text.wrappedValue)
                        appState.showToast("已复制译文")
                    }
                }
            }
            TextEditor(text: text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    ZTheme.fillQuiet,
                    in: RoundedRectangle(cornerRadius: ZTheme.radiusControl, style: .continuous)
                )
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
