import Foundation

// MARK: - Multi-Provider AI Client

final class AIClient {
    private let apiKey: String
    private let model: String
    private let maxTokens: Int
    private let baseURL: String
    private let format: String  // "anthropic" or "openai"
    private let session: URLSession

    init(apiKey: String, model: String, maxTokens: Int, baseURL: String, format: String) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.baseURL = baseURL
        self.format = format

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 120
        sessionConfig.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: sessionConfig)
    }

    /// Initialize from AgentConfig (resolves provider automatically)
    convenience init(config: AgentConfig) {
        self.init(
            apiKey: config.apiKey,
            model: config.model,
            maxTokens: config.maxTokens,
            baseURL: config.baseURL,
            format: config.apiFormat
        )
    }

    func sendMessage(
        messages: [ClaudeMessage],
        system: String?,
        tools: [ClaudeTool]?
    ) async throws -> ClaudeResponse {
        switch format {
        case "openai":
            return try await sendOpenAI(messages: messages, system: system, tools: tools)
        default:
            return try await sendAnthropic(messages: messages, system: system, tools: tools)
        }
    }

    // MARK: - Anthropic Format

    private func sendAnthropic(
        messages: [ClaudeMessage],
        system: String?,
        tools: [ClaudeTool]?
    ) async throws -> ClaudeResponse {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = ClaudeRequest(
            model: model,
            maxTokens: maxTokens,
            system: system,
            tools: tools,
            messages: messages
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentError.networkError("Invalid response")
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AgentError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        var decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        // Parse usage if decoder missed it (Anthropic returns it at top level)
        if decoded.usage == nil,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let usageDict = json["usage"] as? [String: Any] {
            let input = usageDict["input_tokens"] as? Int ?? 0
            let output = usageDict["output_tokens"] as? Int ?? 0
            decoded.usage = TokenUsage(inputTokens: input, outputTokens: output)
        }

        return decoded
    }

    // MARK: - OpenAI-Compatible Format

    private func sendOpenAI(
        messages: [ClaudeMessage],
        system: String?,
        tools: [ClaudeTool]?
    ) async throws -> ClaudeResponse {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")

        // OpenRouter-specific headers
        if baseURL.contains("openrouter.ai") {
            request.setValue("https://github.com/adrianba/osai", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("OSAI Desktop Agent", forHTTPHeaderField: "X-Title")
        }

        // Convert messages to OpenAI format
        var openaiMessages: [[String: Any]] = []

        if let system = system {
            openaiMessages.append(["role": "system", "content": system])
        }

        for msg in messages {
            let converted = convertMessagesToOpenAI(msg)
            openaiMessages.append(contentsOf: converted)
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": openaiMessages
        ]

        // Convert tools to OpenAI format
        if let tools = tools, !tools.isEmpty {
            let openaiTools = tools.map { tool -> [String: Any] in
                var props: [String: Any] = [:]
                for (key, prop) in tool.inputSchema.properties {
                    var propDict: [String: Any] = ["type": prop.type]
                    if let desc = prop.description { propDict["description"] = desc }
                    if let enums = prop.enumValues { propDict["enum"] = enums }
                    if prop.type == "array", let items = prop.items {
                        var itemsDict: [String: Any] = ["type": items.type]
                        if let d = items.description { itemsDict["description"] = d }
                        if let e = items.enumValues { itemsDict["enum"] = e }
                        propDict["items"] = itemsDict
                    }
                    props[key] = propDict
                }
                var schema: [String: Any] = ["type": "object", "properties": props]
                if let req = tool.inputSchema.required { schema["required"] = req }

                return [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": schema
                    ]
                ]
            }
            body["tools"] = openaiTools
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentError.networkError("Invalid response")
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AgentError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Parse OpenAI response and convert to Claude format
        return try parseOpenAIResponse(data)
    }

    // MARK: - Format Conversion

    /// Convert a Claude message to one or more OpenAI messages.
    /// OpenAI requires each tool result as a separate message with role "tool".
    private func convertMessagesToOpenAI(_ message: ClaudeMessage) -> [[String: Any]] {
        // Collect tool results — OpenAI needs one message per tool_call_id
        var toolResults: [[String: Any]] = []
        var hasToolResult = false
        for content in message.content {
            if case .toolResult(let toolUseId, let blocks) = content {
                hasToolResult = true
                let text = blocks.compactMap { $0.text }.joined(separator: "\n")
                toolResults.append([
                    "role": "tool",
                    "tool_call_id": toolUseId,
                    "content": text
                ])
            }
        }

        if hasToolResult { return toolResults }

        // Check for tool_use (assistant with tool calls)
        var result: [String: Any] = ["role": message.role]
        var toolCalls: [[String: Any]] = []
        var textParts: [String] = []

        for content in message.content {
            switch content {
            case .text(let text):
                if !text.isEmpty { textParts.append(text) }
            case .toolUse(let id, let name, let input, let thoughtSig):
                let args = input.mapValues { $0.value }
                let argsJson = (try? JSONSerialization.data(withJSONObject: args)) ?? Data()
                var tc: [String: Any] = [
                    "id": id,
                    "type": "function",
                    "function": [
                        "name": name,
                        "arguments": String(data: argsJson, encoding: .utf8) ?? "{}"
                    ]
                ]
                // Gemini thought signatures: must be echoed back
                if let sig = thoughtSig {
                    tc["extra_content"] = ["google": ["thought_signature": sig]]
                }
                toolCalls.append(tc)
            default:
                break
            }
        }

        if !toolCalls.isEmpty {
            result["tool_calls"] = toolCalls
            if !textParts.isEmpty {
                result["content"] = textParts.joined(separator: "\n")
            }
            return [result]
        }

        // Regular text message (possibly with images)
        var contentParts: [Any] = []
        for content in message.content {
            switch content {
            case .text(let text):
                contentParts.append(["type": "text", "text": text])
            case .image(let source):
                contentParts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:\(source.mediaType);base64,\(source.data)"]
                ])
            case .toolResult(_, let blocks):
                for block in blocks {
                    if let text = block.text {
                        contentParts.append(["type": "text", "text": text])
                    }
                    if let source = block.source {
                        contentParts.append([
                            "type": "image_url",
                            "image_url": ["url": "data:\(source.mediaType);base64,\(source.data)"]
                        ])
                    }
                }
            default:
                break
            }
        }

        if contentParts.count == 1, let first = contentParts.first as? [String: Any],
           first["type"] as? String == "text" {
            result["content"] = first["text"]
        } else if !contentParts.isEmpty {
            result["content"] = contentParts
        } else {
            result["content"] = ""
        }

        return [result]
    }

    private func parseOpenAIResponse(_ data: Data) throws -> ClaudeResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String,
              let choices = json["choices"] as? [[String: Any]],
              let choice = choices.first,
              let message = choice["message"] as? [String: Any] else {
            throw AgentError.networkError("Invalid OpenAI response format")
        }

        let finishReason = choice["finish_reason"] as? String
        var content: [ClaudeContent] = []

        // Parse text content
        if let text = message["content"] as? String, !text.isEmpty {
            content.append(.text(text))
        }

        // Parse tool calls
        if let toolCalls = message["tool_calls"] as? [[String: Any]] {
            for tc in toolCalls {
                guard let tcId = tc["id"] as? String,
                      let function = tc["function"] as? [String: Any],
                      let name = function["name"] as? String,
                      let argsStr = function["arguments"] as? String else { continue }

                var input: [String: AnyCodable] = [:]
                if let argsData = argsStr.data(using: .utf8),
                   let argsDict = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
                    input = argsDict.mapValues { AnyCodable($0) }
                }
                // Extract Gemini thought signature if present
                var thoughtSig: String? = nil
                if let extra = tc["extra_content"] as? [String: Any],
                   let google = extra["google"] as? [String: Any],
                   let sig = google["thought_signature"] as? String {
                    thoughtSig = sig
                }
                content.append(.toolUse(id: tcId, name: name, input: input, thoughtSignature: thoughtSig))
            }
        }

        // Map finish_reason to stop_reason
        let stopReason: String?
        switch finishReason {
        case "stop": stopReason = "end_turn"
        case "tool_calls": stopReason = "tool_use"
        case "length": stopReason = "max_tokens"
        default: stopReason = finishReason
        }

        // Parse usage from OpenAI response
        var usage: TokenUsage? = nil
        if let usageDict = json["usage"] as? [String: Any] {
            let prompt = usageDict["prompt_tokens"] as? Int ?? 0
            let completion = usageDict["completion_tokens"] as? Int ?? 0
            usage = TokenUsage(inputTokens: prompt, outputTokens: completion)
        }

        return ClaudeResponse(
            id: id,
            type: "message",
            role: "assistant",
            content: content,
            stopReason: stopReason,
            usage: usage
        )
    }
}
