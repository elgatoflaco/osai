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
    var fromAgent: String?
    var toAgent: String?
    var task: String?
    var matchType: String?

    enum CodingKeys: String, CodingKey {
        case event, content, id, name, detail, success, output
        case durationMs = "duration_ms"
        case agent, model, message
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case suggestions
        case fromAgent = "from_agent"
        case toAgent = "to_agent"
        case task
        case matchType = "match_type"
    }
}

enum AppEventType {
    case text(String)
    case toolStart(id: String, name: String, detail: String?)
    case toolResult(id: String, name: String, success: Bool, output: String?, durationMs: Int?)
    case agentRoute(agent: String, model: String, matchType: String?)
    case agentDelegate(id: String, from: String, to: String, task: String)
    case agentProgress(id: String, agent: String, status: String)
    case agentComplete(id: String, agent: String, success: Bool, summary: String)
    case doomLoop(toolName: String, message: String)
    case compaction(tier: Int, message: String)
    case sessionSummary(turns: Int, cacheHits: Int, cost: Double, contextPct: Int)
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
            return .agentRoute(agent: event.agent ?? "", model: event.model ?? "", matchType: event.matchType)
        case "agent_delegate":
            return .agentDelegate(id: event.id ?? UUID().uuidString, from: event.fromAgent ?? "", to: event.toAgent ?? "", task: event.task ?? "")
        case "agent_progress":
            return .agentProgress(id: event.id ?? "", agent: event.agent ?? "", status: event.message ?? "")
        case "agent_complete":
            return .agentComplete(id: event.id ?? "", agent: event.agent ?? "", success: event.success ?? true, summary: event.message ?? "")
        case "doom_loop":
            return .doomLoop(toolName: event.name ?? "unknown", message: event.message ?? "")
        case "compaction":
            let tier = Int(event.detail ?? "0") ?? 0
            return .compaction(tier: tier, message: event.message ?? "")
        case "session_summary":
            let cost = Double(event.message ?? "0") ?? 0
            let parts = (event.detail ?? "0|0|0").split(separator: "|")
            let turns = Int(parts.count > 0 ? parts[0] : "0") ?? 0
            let cacheHits = Int(parts.count > 1 ? parts[1] : "0") ?? 0
            let contextPct = Int(parts.count > 2 ? parts[2] : "0") ?? 0
            return .sessionSummary(turns: turns, cacheHits: cacheHits, cost: cost, contextPct: contextPct)
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
