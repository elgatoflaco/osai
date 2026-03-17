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

    func emitAgentRoute(agent: String, model: String) {
        emit(AppEvent(event: "agent_route", agent: agent, model: model))
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

    func emitDone() {
        emit(AppEvent(event: "done"))
    }
}
