import Foundation

struct TranslationResult: Equatable {
    /// The translated text.
    let translation: String
    /// For incoming messages: notes on slang/idioms. For outgoing: a literal English back-translation.
    let notes: String
}

enum TranslationDirection {
    case toEnglish
    case toSudanese
}

enum TranslatorError: LocalizedError {
    case missingKey
    case rateLimited
    case invalidKey
    case http(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingKey: return "No Gemini API key yet. Add one in the Tarjim app."
        case .rateLimited: return "Free Gemini limit reached. Wait a minute and try again."
        case .invalidKey: return "Gemini rejected the API key. Check it in the Tarjim app."
        case .http(let code, let message): return "Gemini error \(code): \(message)"
        case .emptyResponse: return "Gemini returned an empty translation. Try again."
        }
    }
}

struct Translator {
    static let defaultModel = "gemini-flash-latest"
    /// Tried in order if the configured model is unavailable (404).
    static let fallbackModels = ["gemini-flash-latest", "gemini-3.5-flash-lite", "gemini-2.5-flash"]

    var apiKey: String
    var model: String
    var script: OutputScript

    init(settings: SharedSettings = .shared) {
        apiKey = settings.apiKey
        model = settings.model
        script = settings.script
    }

    func translate(_ text: String, _ direction: TranslationDirection) async throws -> TranslationResult {
        guard !apiKey.isEmpty else { throw TranslatorError.missingKey }
        let models = [model] + Self.fallbackModels.filter { $0 != model }
        var lastError: Error = TranslatorError.emptyResponse
        for candidate in models {
            do {
                return try await call(model: candidate, text: text, direction: direction)
            } catch TranslatorError.http(let code, let message) where code == 404 {
                lastError = TranslatorError.http(code, message)
                continue
            }
        }
        throw lastError
    }

    private func systemPrompt(for direction: TranslationDirection) -> String {
        switch direction {
        case .toEnglish:
            return """
            You translate text messages sent by the user's family in Sudan. Messages are usually in \
            Sudanese colloquial Arabic (العامية السودانية), but may mix in Modern Standard Arabic, English, \
            or be written in Arabizi (Latin letters with digits such as 2, 3, 5, 7, 9 for Arabic sounds).
            Translate the message into natural, everyday English that keeps the original warmth and tone.
            Keep religious and cultural expressions understandable (e.g. "God willing (inshallah)").
            Return JSON: "translation" = the English translation only; "notes" = a very short explanation \
            of any Sudanese slang, idioms, or cultural meaning that a non-speaker might miss, or "" if none.
            If the message is already English, return it unchanged with notes "".
            """
        case .toSudanese:
            let scriptRule: String
            switch script {
            case .arabic:
                scriptRule = "Write it in Arabic script."
            case .arabizi:
                scriptRule = "Write it in Arabizi (Latin letters with digits like 2, 3, 7 for Arabic sounds), as young Sudanese people text."
            }
            return """
            You help the user text their family in Sudan. Translate the user's English message into \
            natural Sudanese colloquial Arabic (العامية السودانية) exactly as a Sudanese family member \
            would text it: warm, casual, and idiomatic. Do NOT use Modern Standard Arabic, and do not use \
            Egyptian, Levantine, or Gulf dialect words. Keep emojis, names, and numbers. \(scriptRule)
            Return JSON: "translation" = the Sudanese Arabic message only; "notes" = a literal English \
            back-translation of your Sudanese Arabic so the sender can verify the meaning.
            """
        }
    }

    private func call(model: String, text: String, direction: TranslationDirection) async throws -> TranslationResult {
        let escapedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(escapedModel):generateContent")!
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemPrompt(for: direction)]]],
            "contents": [["role": "user", "parts": [["text": text]]]],
            "generationConfig": [
                "temperature": 0.3,
                "responseMimeType": "application/json",
                "responseSchema": [
                    "type": "OBJECT",
                    "properties": [
                        "translation": ["type": "STRING"],
                        "notes": ["type": "STRING"],
                    ],
                    "required": ["translation", "notes"],
                ],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard status == 200 else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? HTTPURLResponse.localizedString(forStatusCode: status)
            switch status {
            case 429: throw TranslatorError.rateLimited
            case 400 where message.localizedCaseInsensitiveContains("api key"),
                 401, 403:
                throw TranslatorError.invalidKey
            default: throw TranslatorError.http(status, message)
            }
        }

        let candidates = json?["candidates"] as? [[String: Any]]
        let parts = (candidates?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        let output = parts
            .filter { ($0["thought"] as? Bool) != true }
            .compactMap { $0["text"] as? String }
            .joined()

        if let payload = output.data(using: .utf8),
           let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any],
           let translation = (object["translation"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !translation.isEmpty {
            let notes = (object["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return TranslationResult(translation: translation, notes: notes)
        }

        let plain = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { throw TranslatorError.emptyResponse }
        return TranslationResult(translation: plain, notes: "")
    }
}
