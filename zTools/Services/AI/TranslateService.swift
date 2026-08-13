import Foundation

@MainActor
final class TranslateService {
    func provider() throws -> OpenAICompatibleProvider {
        let settings = AppState.shared.settings
        guard let base = URL(string: settings.aiBaseURL) else {
            throw TranslateError.invalidURL
        }
        return OpenAICompatibleProvider(
            id: "openai-compatible",
            baseURL: base,
            apiKey: settings.apiKey,
            model: settings.aiModel
        )
    }

    func translate(text: String, to target: String) async throws -> String {
        try await provider().translate(text: text, from: nil, to: target)
    }

    func testConnection() async throws -> String {
        try await provider().testConnection()
    }
}
