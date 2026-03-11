import Foundation

// MARK: - Claude API Types

struct ClaudeMessage: Codable {
    let role: String
    let content: [ClaudeContent]
}

// MARK: - Tool Result Content Block (text or image inside a tool_result)

struct ToolResultContentBlock: Codable {
    let type: String
    let text: String?
    let source: ImageSource?

    static func textBlock(_ text: String) -> ToolResultContentBlock {
        ToolResultContentBlock(type: "text", text: text, source: nil)
    }

    static func imageBlock(base64: String, mediaType: String = "image/jpeg") -> ToolResultContentBlock {
        ToolResultContentBlock(
            type: "image",
            text: nil,
            source: ImageSource(type: "base64", mediaType: mediaType, data: base64)
        )
    }
}

// MARK: - Content types

enum ClaudeContent: Codable {
    case text(String)
    case image(source: ImageSource)
    case toolUse(id: String, name: String, input: [String: AnyCodable])
    case toolResult(toolUseId: String, content: [ToolResultContentBlock])

    // Convenience factories
    static func toolResultText(toolUseId: String, text: String) -> ClaudeContent {
        .toolResult(toolUseId: toolUseId, content: [.textBlock(text)])
    }

    static func toolResultWithImage(toolUseId: String, text: String, imageBase64: String, mediaType: String = "image/jpeg") -> ClaudeContent {
        .toolResult(toolUseId: toolUseId, content: [
            .textBlock(text),
            .imageBlock(base64: imageBase64, mediaType: mediaType)
        ])
    }

    enum CodingKeys: String, CodingKey {
        case type, text, source, id, name, input
        case toolUseId = "tool_use_id"
        case content
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let source):
            try container.encode("image", forKey: .type)
            try container.encode(source, forKey: .source)
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let toolUseId, let contentBlocks):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseId, forKey: .toolUseId)
            try container.encode(contentBlocks, forKey: .content)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "image":
            let source = try container.decode(ImageSource.self, forKey: .source)
            self = .image(source: source)
        case "tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let input = try container.decode([String: AnyCodable].self, forKey: .input)
            self = .toolUse(id: id, name: name, input: input)
        case "tool_result":
            let toolUseId = try container.decode(String.self, forKey: .toolUseId)
            // Content can be string or array of blocks
            if let text = try? container.decode(String.self, forKey: .content) {
                self = .toolResult(toolUseId: toolUseId, content: [.textBlock(text)])
            } else if let blocks = try? container.decode([ToolResultContentBlock].self, forKey: .content) {
                self = .toolResult(toolUseId: toolUseId, content: blocks)
            } else {
                self = .toolResult(toolUseId: toolUseId, content: [.textBlock("")])
            }
        default:
            let text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            self = .text(text)
        }
    }
}

struct ImageSource: Codable {
    let type: String
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

struct ClaudeRequest: Codable {
    let model: String
    let maxTokens: Int
    let system: String?
    let tools: [ClaudeTool]?
    let messages: [ClaudeMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case tools
        case messages
    }
}

struct TokenUsage: Codable {
    let inputTokens: Int
    let outputTokens: Int

    var totalTokens: Int { inputTokens + outputTokens }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

struct ClaudeResponse: Codable {
    let id: String
    let type: String
    let role: String
    let content: [ClaudeContent]
    let stopReason: String?
    var usage: TokenUsage?

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, usage
        case stopReason = "stop_reason"
    }
}

struct ClaudeTool: Codable {
    let name: String
    let description: String
    let inputSchema: InputSchema

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

struct InputSchema: Codable {
    let type: String
    let properties: [String: PropertySchema]
    let required: [String]?
}

struct PropertySchema: Codable {
    let type: String
    let description: String?
    let enumValues: [String]?

    enum CodingKeys: String, CodingKey {
        case type, description
        case enumValues = "enum"
    }
}

// MARK: - AnyCodable helper

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            value = str
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let str as String:
            try container.encode(str)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let arr as [Any]:
            try container.encode(arr.map { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }

    var stringValue: String? { value as? String }
    var intValue: Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        return nil
    }
    var boolValue: Bool? { value as? Bool }
    var doubleValue: Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }
}
