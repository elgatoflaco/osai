import Foundation

// MARK: - App Mode NDJSON Emitter
// Emits structured events as newline-delimited JSON to stdout
// for consumption by the desktop app. Thread-safe via NSLock.

struct AppEvent: Encodable {
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
}

final class AppModeEmitter {
    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    func emit(_ event: AppEvent) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? encoder.encode(event),
              let json = String(data: data, encoding: .utf8) else { return }
        // Write directly to stdout file descriptor to bypass TerminalDisplay
        let line = json + "\n"
        line.withCString { ptr in
            _ = write(STDOUT_FILENO, ptr, strlen(ptr))
        }
    }

    func emitText(_ content: String) {
        emit(AppEvent(event: "text", content: content))
    }

    func emitToolStart(id: String, name: String, detail: String = "") {
        emit(AppEvent(event: "tool_start", id: id, name: name, detail: detail.isEmpty ? nil : detail))
    }

    func emitToolResult(id: String, name: String, success: Bool, output: String, durationMs: Int? = nil) {
        let truncated = String(output.prefix(2000))
        emit(AppEvent(event: "tool_result", id: id, name: name, success: success, output: truncated, durationMs: durationMs))
    }

    func emitAgentRoute(agent: String, model: String, matchType: String? = nil) {
        emit(AppEvent(event: "agent_route", agent: agent, model: model, matchType: matchType))
    }

    func emitAgentDelegate(from: String, to: String, task: String) {
        var e = AppEvent(event: "agent_delegate")
        e.id = UUID().uuidString
        e.fromAgent = from
        e.toAgent = to
        e.task = task
        emit(e)
    }

    func emitAgentProgress(id: String, agent: String, status: String) {
        var e = AppEvent(event: "agent_progress")
        e.id = id
        e.agent = agent
        e.message = status
        emit(e)
    }

    func emitAgentComplete(id: String, agent: String, success: Bool, summary: String) {
        var e = AppEvent(event: "agent_complete")
        e.id = id
        e.success = success
        e.agent = agent
        e.message = summary
        emit(e)
    }

    func emitCompaction(tier: Int, messagesBefore: Int, messagesAfter: Int, tokensSaved: Int) {
        var e = AppEvent(event: "compaction")
        e.message = "Tier \(tier): \(messagesBefore) → \(messagesAfter) messages, saved ~\(tokensSaved) tokens"
        e.detail = "\(tier)"
        emit(e)
    }

    func emitDoomLoop(toolName: String, count: Int) {
        var e = AppEvent(event: "doom_loop")
        e.name = toolName
        e.message = "Tool '\(toolName)' called \(count)x with identical inputs — forced strategy change"
        emit(e)
    }

    func emitStatus(_ message: String) {
        emit(AppEvent(event: "status", message: message))
    }

    func emitTokens(input: Int, output: Int) {
        emit(AppEvent(event: "tokens", inputTokens: input, outputTokens: output))
    }

    func emitError(_ message: String) {
        emit(AppEvent(event: "error", message: message))
    }

    func emitContextPressure(usedPercent: Int) {
        emit(AppEvent(event: "context_pressure", message: "\(usedPercent)"))
    }

    func emitSuggestions(_ suggestions: [String]) {
        guard !suggestions.isEmpty else { return }
        emit(AppEvent(event: "suggestions", suggestions: suggestions))
    }

    func emitSessionSummary(turns: Int, cacheHits: Int, cost: Double, contextPct: Int) {
        var e = AppEvent(event: "session_summary")
        e.message = String(format: "%.4f", cost)
        e.detail = "\(turns)|\(cacheHits)|\(contextPct)"
        emit(e)
    }

    func emitDone() {
        emit(AppEvent(event: "done"))
    }
}
