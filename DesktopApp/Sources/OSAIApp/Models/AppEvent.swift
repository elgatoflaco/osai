import Foundation

// MARK: - App Event (NDJSON protocol from CLI --app-mode)

struct AppEventData: Decodable {
    let event: String
    var content: String?
    var id: String?
    var name: String?
    var detail: String?
    var success: Bool?
    var output: String?
    var durationMs: Int?
    var agent: String?
    var model: String?
    var message: String?
    var inputTokens: Int?
    var outputTokens: Int?
    var suggestions: [String]?

    enum CodingKeys: String, CodingKey {
        case event, content, id, name, detail, success, output
        case durationMs = "duration_ms"
        case agent, model, message
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case suggestions
    }
}

enum AppEventType {
    case text(String)
    case toolStart(id: String, name: String, detail: String?)
    case toolResult(id: String, name: String, success: Bool, output: String?, durationMs: Int?)
    case agentRoute(agent: String, model: String)
    case status(String)
    case tokens(input: Int, output: Int)
    case contextPressure(percent: Int)
    case suggestions([String])
    case error(String)
    case done

    static func parse(_ line: String) -> AppEventType? {
        guard let data = line.data(using: .utf8),
              let event = try? JSONDecoder().decode(AppEventData.self, from: data) else {
            return nil
        }

        switch event.event {
        case "text":
            return .text(event.content ?? "")
        case "tool_start":
            return .toolStart(id: event.id ?? UUID().uuidString, name: event.name ?? "unknown", detail: event.detail)
        case "tool_result":
            return .toolResult(id: event.id ?? "", name: event.name ?? "unknown",
                             success: event.success ?? false, output: event.output, durationMs: event.durationMs)
        case "agent_route":
            return .agentRoute(agent: event.agent ?? "", model: event.model ?? "")
        case "status":
            return .status(event.message ?? "")
        case "tokens":
            return .tokens(input: event.inputTokens ?? 0, output: event.outputTokens ?? 0)
        case "context_pressure":
            return .contextPressure(percent: Int(event.message ?? "0") ?? 0)
        case "suggestions":
            return .suggestions(event.suggestions ?? [])
        case "error":
            return .error(event.message ?? "Unknown error")
        case "done":
            return .done
        default:
            return nil
        }
    }
}
