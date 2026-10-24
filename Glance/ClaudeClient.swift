import Foundation

/// Sends a screenshot to the Claude Messages API and returns the answer.
/// Swift has no official Anthropic SDK, so this calls the REST API directly.
struct ClaudeClient {
    let apiKey: String
    var model = Model.chosen.rawValue

    enum Model: String, CaseIterable {
        case opus = "claude-opus-5-5"
        case sonnet = "claude-sonnet-5-5"

        var menuTitle: String {
            switch self {
            case .opus: "Opus 5.5 (smarter)"
            case .sonnet: "Sonnet 5.5 (faster, half the cost)"
            }
        }

        var shortName: String {
            switch self {
            case .opus: "Opus 5.5"
            case .sonnet: "Sonnet 5.5"
            }
        }

        /// The model picked in Glance's menu; Opus until changed.
        static var chosen: Model {
            get { UserDefaults.standard.string(forKey: "model").flatMap(Model.init) ?? .opus }
            set { UserDefaults.standard.set(newValue.rawValue, forKey: "model") }
        }
    }

    enum Input {
        case image(Data)
        /// A screenshot of the whole screen, taken on a double tap of ⌘.
        case screen(Data)
    }

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
    The user sent a screenshot: either a region they picked out or their whole screen. \
    On a whole screen, find the question they're most likely looking at \
    (anything highlighted, otherwise the obvious or most prominent one) and answer just that. \
    Your reply replaces the clock in the macOS menu bar, which fits about 25 characters, \
    so reply with the bare answer in as few words as possible. \
    No explanation, working, restating the question, full sentences, hedging, or markdown. \
    Multiple choice: just the choice's letter or number (its words only if the choices are unlabeled). \
    Math: just the final result. Text in another language: just the English translation. \
    A word or term: a definition of a few words. Word games and puzzles (like Wordle): just the word to play. \
    Several questions on screen: answer only the one they're on. \
    Good answers look like "B", "42", "1789", "CRANE", "Mitochondria", "x = 3, y = -1".
    """

    /// The reply must be JSON with one short `answer` field, so there's nowhere to
    /// put an explanation (Sonnet adds one otherwise). Reasoning stays in thinking.
    private static let answerFormat: [String: Any] = [
        "type": "json_schema",
        "schema": [
            "type": "object",
            "properties": [
                "answer": [
                    "type": "string",
                    "description": "Only the bare answer, ideally one to three words. Never an explanation.",
                ],
            ],
            "required": ["answer"],
            "additionalProperties": false,
        ] as [String: Any],
    ]

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

    func answer(_ input: Input) async throws -> String {
        do {
            return try await answer(input, strictFormat: true)
        } catch ClaudeError.http(400, _) {
            // Should the API ever reject the answer format, plain text still works.
            return try await answer(input, strictFormat: false)
        }
    }

    private func answer(_ input: Input, strictFormat: Bool) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        // Lets the API retry on another model if this one refuses.
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")

        let content: [[String: Any]]
        switch input {
        case .image(let png):
            content = [Self.imageBlock(png), ["type": "text", "text": "Answer what's in this screenshot."]]
        case .screen(let png):
            content = [Self.imageBlock(png), ["type": "text", "text": "This is my whole screen. Answer the question I'm looking at."]]
        }
        let message: [String: Any] = ["role": "user", "content": content]
        // Low effort keeps answers quick; raise to "medium" or "high" for harder problems.
        var outputConfig: [String: Any] = ["effort": "low"]
        if strictFormat { outputConfig["format"] = Self.answerFormat }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4000,
            "system": Self.systemPrompt,
            "output_config": outputConfig,
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
        let reply = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
        // If the JSON ever comes back broken, fall back to its first line.
        let answer = (reply?["answer"] as? String ?? text.split(separator: "\n").first.map(String.init) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw ClaudeError.empty }
        return answer
    }

    private static func imageBlock(_ png: Data) -> [String: Any] {
        [
            "type": "image",
            "source": ["type": "base64", "media_type": "image/png", "data": png.base64EncodedString()],
        ]
    }
}
