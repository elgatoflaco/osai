import Foundation

class OSAIService {
    private static let isoFormatter = ISO8601DateFormatter()

    private let binaryPath: String = {
        // 1. Look in Contents/Helpers/ inside the app bundle
        if let bundleURL = Bundle.main.bundleURL as URL? {
            let helpersPath = bundleURL.appendingPathComponent("Contents/Helpers/osai").path
            if FileManager.default.isExecutableFile(atPath: helpersPath) {
                return helpersPath
            }
        }
        // 2. Look inside Contents/MacOS/
        if let bundlePath = Bundle.main.path(forAuxiliaryExecutable: "osai") {
            return bundlePath
        }
        // 3. Check ~/.desktop-agent/DesktopAgent
        let homeBinary = NSHomeDirectory() + "/.desktop-agent/DesktopAgent"
        if FileManager.default.isExecutableFile(atPath: homeBinary) {
            return homeBinary
        }
        // 4. Fallback to /usr/local/bin/osai
        return "/usr/local/bin/osai"
    }()
    private let configDir = NSHomeDirectory() + "/.desktop-agent"

    // MARK: - CLI Execution

    func run(args: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")

        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        process.environment = env

        try process.run()

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                let raw = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: raw.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    /// Start an app-mode streaming process that emits NDJSON events.
    /// `onEvent` is called on the main thread with each parsed event.
    @discardableResult
    func startAppModeStreaming(args: [String], onEvent: @escaping @Sendable (AppEventType) -> Void) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["--app-mode"] + args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")

        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        process.environment = env

        // Buffer for incomplete lines
        let lineBuffer = LineBuffer()

        // Stream stdout line-by-line, parse NDJSON
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                // EOF — process exited, stop handler to prevent hot loop
                handle.readabilityHandler = nil
                return
            }
            guard let str = String(data: data, encoding: .utf8) else { return }
            let lines = lineBuffer.append(str)
            for line in lines {
                if let event = AppEventType.parse(line) {
                    DispatchQueue.main.async { onEvent(event) }
                }
            }
        }

        // Ignore stderr in app mode
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
        }

        try process.run()
        return process
    }

    /// Wait for a process to finish, then clean up pipe handlers.
    func awaitProcess(_ process: Process) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }
        // Clean up handlers
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (process.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
    }

    // MARK: - Agents

    func loadAgents() -> [AgentInfo] {
        let agentsDir = "\(configDir)/agents"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: agentsDir) else { return [] }

        return files.filter { $0.hasSuffix(".md") }.compactMap { file in
            guard let content = try? String(contentsOfFile: "\(agentsDir)/\(file)", encoding: .utf8) else { return nil }
            return parseAgentMarkdown(content, filename: file)
        }.sorted { $0.name < $1.name }
    }

    private func parseAgentMarkdown(_ content: String, filename: String) -> AgentInfo? {
        let lines = content.components(separatedBy: "\n")
        var name = ""
        var description = ""
        var model = ""
        var backend = "api"
        var triggers: [String] = []
        var inTriggers = false
        var systemPrompt = ""
        var inBody = false
        var frontmatterCount = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                frontmatterCount += 1
                if frontmatterCount >= 2 { inBody = true }
                inTriggers = false
                continue
            }
            if inBody {
                systemPrompt += line + "\n"
                continue
            }
            if trimmed.hasPrefix("name:") {
                name = trimmed.replacingOccurrences(of: "name:", with: "").trimmingCharacters(in: .whitespaces)
                inTriggers = false
            } else if trimmed.hasPrefix("description:") {
                description = trimmed.replacingOccurrences(of: "description:", with: "").trimmingCharacters(in: .whitespaces)
                inTriggers = false
            } else if trimmed.hasPrefix("model:") {
                model = trimmed.replacingOccurrences(of: "model:", with: "").trimmingCharacters(in: .whitespaces)
                inTriggers = false
            } else if trimmed.hasPrefix("backend:") {
                backend = trimmed.replacingOccurrences(of: "backend:", with: "").trimmingCharacters(in: .whitespaces)
                inTriggers = false
            } else if trimmed.hasPrefix("triggers:") {
                inTriggers = true
            } else if inTriggers && trimmed.hasPrefix("- ") {
                triggers.append(String(trimmed.dropFirst(2)))
            } else if !trimmed.isEmpty && !trimmed.hasPrefix("-") {
                inTriggers = false
            }
        }

        guard !name.isEmpty else { return nil }
        return AgentInfo(
            name: name,
            description: description,
            model: model,
            backend: backend,
            triggers: triggers,
            systemPrompt: systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    // MARK: - Tasks

    func loadTasks() -> [TaskInfo] {
        let tasksDir = "\(configDir)/tasks"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: tasksDir) else { return [] }

        return files.filter { $0.hasSuffix(".json") }.compactMap { file in
            guard let data = FileManager.default.contents(atPath: "\(tasksDir)/\(file)"),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return parseTaskJSON(json)
        }.sorted { $0.id < $1.id }
    }

    private func parseTaskJSON(_ json: [String: Any]) -> TaskInfo? {
        guard let id = json["id"] as? String else { return nil }

        let description = json["description"] as? String ?? ""
        let command = json["command"] as? String ?? ""
        let enabled = json["enabled"] as? Bool ?? true
        let runCount = json["runCount"] as? Int ?? 0

        var lastRun: Date?
        if let lastRunStr = json["lastRun"] as? String {
            let taskFormatter = ISO8601DateFormatter()
            taskFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            lastRun = taskFormatter.date(from: lastRunStr)
            if lastRun == nil {
                taskFormatter.formatOptions = [.withInternetDateTime]
                lastRun = taskFormatter.date(from: lastRunStr)
            }
        }

        let scheduleJSON = json["schedule"] as? [String: Any] ?? [:]
        let schedule = TaskSchedule(
            type: scheduleJSON["type"] as? String ?? "unknown",
            at: scheduleJSON["at"] as? String,
            cron: scheduleJSON["cron"] as? String,
            interval: scheduleJSON["interval"] as? String
        )

        var delivery: TaskDelivery?
        if let deliveryJSON = json["delivery"] as? [String: Any] {
            delivery = TaskDelivery(
                platform: deliveryJSON["platform"] as? String ?? "",
                chatId: deliveryJSON["chatId"] as? String
            )
        }

        return TaskInfo(
            id: id,
            description: description,
            command: command,
            schedule: schedule,
            enabled: enabled,
            lastRun: lastRun,
            runCount: runCount,
            delivery: delivery
        )
    }

    // MARK: - Config

    func loadConfig() -> AppConfig {
        let configPath = "\(configDir)/config.json"
        guard let data = FileManager.default.contents(atPath: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return AppConfig()
        }

        var config = AppConfig()
        config.activeModel = json["activeModel"] as? String ?? "google/gemini-3-flash-preview"

        if let keys = json["apiKeys"] as? [String: [String: String]] {
            for (provider, entry) in keys {
                if let key = entry["api_key"] {
                    config.apiKeys[provider] = APIKeyEntry(provider: provider, apiKey: key)
                }
            }
        }

        if let limits = json["spending_limits"] as? [String: Any] {
            config.spendingLimits = SpendingLimits(
                dailyUSD: limits["daily_usd"] as? Double ?? 15.0,
                monthlyUSD: limits["monthly_usd"] as? Double ?? 50.0,
                perSessionUSD: limits["per_session_usd"] as? Double ?? 5.0,
                warnAtPercent: limits["warn_at_percent"] as? Int ?? 70
            )
        }

        if let gateways = json["gateways"] as? [String: [String: Any]] {
            for (name, gw) in gateways {
                config.gateways[name] = GatewayConfig(
                    name: name,
                    enabled: gw["enabled"] as? Bool ?? false
                )
            }
        }

        return config
    }

    // MARK: - Quick Completion (lightweight AI call for suggestions, titles, etc.)

    /// Resolve provider info from a model string like "anthropic/claude-sonnet-4-20250514" or "openrouter/google/gemini-3-flash-preview"
    private struct ProviderInfo {
        let baseURL: String
        let format: String // "anthropic" or "openai"
        let model: String  // model id to send to the API
        let apiKey: String
        let authType: String // "api_key" or "bearer"
    }

    private func resolveProvider(modelId: String, config: AppConfig) -> ProviderInfo? {
        // Provider lookup table
        let providers: [(id: String, baseURL: String, format: String)] = [
            ("anthropic", "https://api.anthropic.com/v1/messages", "anthropic"),
            ("openai", "https://api.openai.com/v1/chat/completions", "openai"),
            ("google", "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", "openai"),
            ("groq", "https://api.groq.com/openai/v1/chat/completions", "openai"),
            ("mistral", "https://api.mistral.ai/v1/chat/completions", "openai"),
            ("openrouter", "https://openrouter.ai/api/v1/chat/completions", "openai"),
            ("deepseek", "https://api.deepseek.com/v1/chat/completions", "openai"),
            ("xai", "https://api.x.ai/v1/chat/completions", "openai"),
        ]

        guard modelId.contains("/") else { return nil }
        let parts = modelId.split(separator: "/", maxSplits: 1)
        let providerId = String(parts[0])
        let model = String(parts[1])

        guard let provider = providers.first(where: { $0.id == providerId }),
              let keyEntry = config.apiKeys[providerId] else { return nil }

        let authType = keyEntry.apiKey.hasPrefix("sk-ant-oat") ? "bearer" : "api_key"

        return ProviderInfo(
            baseURL: provider.baseURL,
            format: provider.format,
            model: model,
            apiKey: keyEntry.apiKey,
            authType: authType
        )
    }

    /// Make a quick, lightweight API call (low max_tokens, no tools).
    /// Returns the text response or nil on failure. Does not throw — failures are silent.
    func quickCompletion(prompt: String, systemPrompt: String? = nil, modelId: String, config: AppConfig, maxTokens: Int = 200) async -> String? {
        guard let provider = resolveProvider(modelId: modelId, config: config) else { return nil }

        var request: URLRequest
        var body: [String: Any]

        if provider.format == "anthropic" {
            request = URLRequest(url: URL(string: provider.baseURL)!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            if provider.authType == "bearer" {
                request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "authorization")
            } else {
                request.setValue(provider.apiKey, forHTTPHeaderField: "x-api-key")
            }
            body = [
                "model": provider.model,
                "max_tokens": maxTokens,
                "messages": [["role": "user", "content": prompt]],
            ]
            if let sys = systemPrompt { body["system"] = sys }
        } else {
            request = URLRequest(url: URL(string: provider.baseURL)!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "authorization")
            var messages: [[String: String]] = []
            if let sys = systemPrompt { messages.append(["role": "system", "content": sys]) }
            messages.append(["role": "user", "content": prompt])
            body = [
                "model": provider.model,
                "max_tokens": maxTokens,
                "messages": messages,
            ]
        }

        request.timeoutInterval = 10 // Quick call — fail fast

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            // Parse response based on format
            if provider.format == "anthropic" {
                if let content = json["content"] as? [[String: Any]],
                   let first = content.first,
                   let text = first["text"] as? String {
                    return text
                }
            } else {
                if let choices = json["choices"] as? [[String: Any]],
                   let first = choices.first,
                   let message = first["message"] as? [String: Any],
                   let text = message["content"] as? String {
                    return text
                }
            }
        } catch {}

        return nil
    }

    // MARK: - Gateway

    func gatewayStatus() -> (running: Bool, pid: Int?) {
        let pidPath = "\(configDir)/gateway.pid"
        if let pidStr = try? String(contentsOfFile: pidPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let pid = Int(pidStr) {
            // Check if process is alive
            if kill(Int32(pid), 0) == 0 {
                return (true, pid)
            }
        }

        // Fallback: pgrep
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "osai.*gateway"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty,
               let pid = Int(output.components(separatedBy: "\n").first ?? "") {
                return (true, pid)
            }
        } catch {}

        return (false, nil)
    }

    // MARK: - Conversations (persistence)

    private var conversationsDir: String { "\(configDir)/conversations" }

    func loadConversations() -> [Conversation] {
        let dir = conversationsDir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }

        return files.filter { $0.hasSuffix(".json") }.compactMap { file in
            guard let data = FileManager.default.contents(atPath: "\(dir)/\(file)"),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return parseConversation(json)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func saveConversation(_ conv: Conversation) {
        let dir = conversationsDir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let messages: [[String: Any]] = conv.messages.map { msg in
            var m: [String: Any] = [
                "id": msg.id,
                "role": msg.role.rawValue,
                "content": msg.content,
                "timestamp": Self.isoFormatter.string(from: msg.timestamp)
            ]
            if let tool = msg.toolName { m["toolName"] = tool }
            if let result = msg.toolResult { m["toolResult"] = result }
            if let reaction = msg.reaction { m["reaction"] = reaction.rawValue }
            if msg.isBookmarked { m["isBookmarked"] = true }
            if let rt = msg.responseTimeMs { m["responseTimeMs"] = rt }
            if let replyTo = msg.replyToMessageId { m["replyToMessageId"] = replyTo }
            if let annotation = msg.annotation { m["annotation"] = annotation }
            if msg.isPinned { m["isPinned"] = true }
            if !msg.editHistory.isEmpty {
                m["editHistory"] = msg.editHistory.map { record in
                    [
                        "id": record.id.uuidString,
                        "content": record.content,
                        "editedAt": Self.isoFormatter.string(from: record.editedAt)
                    ]
                }
            }
            return m
        }

        var json: [String: Any] = [
            "id": conv.id,
            "title": conv.title,
            "createdAt": Self.isoFormatter.string(from: conv.createdAt),
            "messages": messages
        ]
        if let agent = conv.agentName { json["agentName"] = agent }
        if let modelId = conv.modelId { json["modelId"] = modelId }
        if conv.isPinned { json["isPinned"] = true }
        if conv.isArchived { json["isArchived"] = true }
        if conv.totalInputTokens > 0 { json["totalInputTokens"] = conv.totalInputTokens }
        if conv.totalOutputTokens > 0 { json["totalOutputTokens"] = conv.totalOutputTokens }
        if let branchedFromId = conv.branchedFromId { json["branchedFromId"] = branchedFromId }
        if let branchedAtMessageIndex = conv.branchedAtMessageIndex { json["branchedAtMessageIndex"] = branchedAtMessageIndex }
        if !conv.tags.isEmpty { json["tags"] = conv.tags }
        if conv.titleManuallySet { json["titleManuallySet"] = true }
        if let summary = conv.summary { json["summary"] = summary }
        if let colorLabel = conv.colorLabel { json["colorLabel"] = colorLabel }

        let path = "\(dir)/\(conv.id).json"
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    func deleteConversation(_ id: String) {
        let path = "\(conversationsDir)/\(id).json"
        try? FileManager.default.removeItem(atPath: path)
    }

    private func parseConversation(_ json: [String: Any]) -> Conversation? {
        guard let id = json["id"] as? String,
              let title = json["title"] as? String,
              let createdStr = json["createdAt"] as? String,
              let createdAt = Self.isoFormatter.date(from: createdStr) else { return nil }

        let msgArray = json["messages"] as? [[String: Any]] ?? []
        let messages: [ChatMessage] = msgArray.compactMap { m in
            guard let msgId = m["id"] as? String,
                  let roleStr = m["role"] as? String,
                  let role = MessageRole(rawValue: roleStr),
                  let content = m["content"] as? String,
                  let tsStr = m["timestamp"] as? String,
                  let ts = Self.isoFormatter.date(from: tsStr) else { return nil }
            var reaction: MessageReaction?
            if let reactionStr = m["reaction"] as? String {
                reaction = MessageReaction(rawValue: reactionStr)
            }
            let isBookmarked = m["isBookmarked"] as? Bool ?? false
            let responseTimeMs = m["responseTimeMs"] as? Int
            var editHistory: [EditRecord] = []
            if let historyArray = m["editHistory"] as? [[String: String]] {
                editHistory = historyArray.compactMap { record in
                    guard let idStr = record["id"],
                          let uid = UUID(uuidString: idStr),
                          let content = record["content"],
                          let dateStr = record["editedAt"],
                          let date = Self.isoFormatter.date(from: dateStr) else { return nil }
                    return EditRecord(id: uid, content: content, editedAt: date)
                }
            }
            let replyToMessageId = m["replyToMessageId"] as? String
            let annotation = m["annotation"] as? String
            let isPinned = m["isPinned"] as? Bool ?? false
            return ChatMessage(
                id: msgId, role: role, content: content, timestamp: ts,
                toolName: m["toolName"] as? String,
                toolResult: m["toolResult"] as? String,
                reaction: reaction,
                isBookmarked: isBookmarked,
                responseTimeMs: responseTimeMs,
                editHistory: editHistory,
                replyToMessageId: replyToMessageId,
                annotation: annotation,
                isPinned: isPinned
            )
        }

        return Conversation(
            id: id, title: title, messages: messages, createdAt: createdAt,
            agentName: json["agentName"] as? String,
            modelId: json["modelId"] as? String,
            isPinned: json["isPinned"] as? Bool ?? false,
            isArchived: json["isArchived"] as? Bool ?? false,
            tags: json["tags"] as? [String] ?? [],
            totalInputTokens: json["totalInputTokens"] as? Int ?? 0,
            totalOutputTokens: json["totalOutputTokens"] as? Int ?? 0,
            branchedFromId: json["branchedFromId"] as? String,
            branchedAtMessageIndex: json["branchedAtMessageIndex"] as? Int,
            titleManuallySet: json["titleManuallySet"] as? Bool ?? false,
            summary: json["summary"] as? String,
            colorLabel: json["colorLabel"] as? String
        )
    }

    /// Public wrapper around parseConversation for snapshot restoration.
    func parseConversationFromSnapshot(_ json: [String: Any]) -> Conversation? {
        parseConversation(json)
    }

    // MARK: - Task logs

    func loadTaskLog(_ taskId: String) -> String {
        let logPath = "\(configDir)/tasks/\(taskId).log"
        return (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? "No log available."
    }
}

// MARK: - Line Buffer for NDJSON parsing

/// Accumulates partial data and splits on newlines, returning complete lines.
/// Thread-safe via NSLock since readabilityHandler can fire on any thread.
final class LineBuffer: @unchecked Sendable {
    private var buffer = ""
    private let lock = NSLock()

    func append(_ str: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        buffer += str
        var lines: [String] = []
        while let range = buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex..<range.lowerBound])
            if !line.isEmpty { lines.append(line) }
            buffer = String(buffer[range.upperBound...])
        }
        return lines
    }
}
