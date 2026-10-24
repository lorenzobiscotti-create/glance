import Foundation

/// Sends a screenshot to the Claude Messages API and returns the answer text.
/// Swift has no official Anthropic SDK, so this calls the REST API directly.
struct ClaudeClient {
    let apiKey: String
    var model = "claude-opus-5-5"

    enum ClaudeError: LocalizedError {
        case http(Int, String)
        case refused
        case empty

        var errorDescription: String? {
            switch self {
            case .http(let code, let message): "API error \(code): \(message)"
            case .refused: "Claude declined to answer"
            case .empty: "No answer came back"
            }
        }
    }

    private static let systemPrompt = """
    The image is a region of the user's screen they just highlighted. \
    Start with the answer alone on the first line, as short as possible: ideally under 25 characters, \
    such as a word, number, or multiple-choice letter. \
    If it's a question, answer it. If it's text in another language, translate it to English. \
    If it's a single word or term, define it. If it's math, give the result. \
    After the first line you may add a blank line and at most two sentences of explanation.
    """

    /// True if the key works, false if the API rejects it, nil if it couldn't tell (e.g. offline).
    func checkKey() async -> Bool? {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
        request.timeoutInterval = 15
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode
        else { return nil }
        switch status {
        case 200: return true
        case 401, 403: return false
        default: return nil
        }
    }

    func answer(imagePNG: Data) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        // Lets the API retry on another model if this one refuses.
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")

        let image: [String: Any] = [
            "type": "image",
            "source": ["type": "base64", "media_type": "image/png", "data": imagePNG.base64EncodedString()],
        ]
        let prompt: [String: Any] = ["type": "text", "text": "Answer what's in this screenshot."]
        let message: [String: Any] = ["role": "user", "content": [image, prompt]]
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4000,
            "system": Self.systemPrompt,
            // Low effort keeps answers quick; raise to "medium" or "high" for harder problems.
            "output_config": ["effort": "low"],
            "fallbacks": "default",
            "messages": [message],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            throw ClaudeError.http(status, message)
        }
        if json["stop_reason"] as? String == "refusal" {
            throw ClaudeError.refused
        }

        // Thinking blocks come back too; keep only the text.
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClaudeError.empty }
        return text
    }
}
