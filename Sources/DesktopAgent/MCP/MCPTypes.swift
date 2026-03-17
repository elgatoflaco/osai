import Foundation

// MARK: - MCP Protocol Types (JSON-RPC 2.0)

struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: Int
    let method: String
    let params: AnyCodable?

    init(id: Int, method: String, params: Any? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params.map { AnyCodable($0) }
    }
}

struct JSONRPCResponse: Codable {
    let jsonrpc: String
    let id: Int?
    let result: AnyCodable?
    let error: JSONRPCError?
}

struct JSONRPCError: Codable {
    let code: Int
    let message: String
    let data: AnyCodable?
}

// MARK: - MCP Tool from server

struct MCPToolInfo {
    let serverName: String
    let name: String
    let description: String
    let inputSchema: [String: Any]

    /// Full tool name exposed to Claude: "mcp_servername_toolname"
    var qualifiedName: String {
        "mcp_\(serverName)_\(name)"
    }

    /// Convert to ClaudeTool for sending to API
    func toClaudeTool() -> ClaudeTool {
        // Parse properties from inputSchema
        var properties: [String: PropertySchema] = [:]
        var required: [String]? = nil

        if let props = (inputSchema["properties"] as? [String: Any]) {
            for (key, val) in props {
                if let propDict = val as? [String: Any] {
                    let type = propDict["type"] as? String ?? "string"
                    let desc = propDict["description"] as? String
                    let enumVals = propDict["enum"] as? [String]
                    var items: ItemsSchema? = nil
                    if type == "array", let itemsDict = propDict["items"] as? [String: Any] {
                        items = ItemsSchema(
                            type: itemsDict["type"] as? String ?? "string",
                            description: itemsDict["description"] as? String,
                            enumValues: itemsDict["enum"] as? [String]
                        )
                    }
                    properties[key] = PropertySchema(type: type, description: desc, enumValues: enumVals, items: items)
                }
            }
        }

        if let req = inputSchema["required"] as? [String] {
            required = req
        }

        return ClaudeTool(
            name: qualifiedName,
            description: "[\(serverName)] \(description)",
            inputSchema: InputSchema(
                type: "object",
                properties: properties,
                required: required
            )
        )
    }
}

// MARK: - MCP Server Config

struct MCPServerConfig: Codable {
    let command: String
    let args: [String]?
    let env: [String: String]?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case command, args, env, description
    }
}

// MARK: - AI Provider Config

struct AIProviderConfig: Codable {
    let apiKey: String
    let baseURL: String?    // nil = use provider default
    let format: String?     // "anthropic" or "openai" — nil = auto-detect

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case baseURL = "base_url"
        case format
    }
}

// MARK: - Known providers

struct AIProvider {
    let id: String
    let name: String
    let defaultBaseURL: String
    let format: String  // "anthropic" or "openai"
    let models: [String]

    static let known: [AIProvider] = [
        AIProvider(
            id: "anthropic", name: "Anthropic",
            defaultBaseURL: "https://api.anthropic.com/v1/messages",
            format: "anthropic",
            models: [
                "claude-opus-4-20250514",
                "claude-sonnet-4-20250514",
                "claude-haiku-4-5-20251001",
            ]
        ),
        AIProvider(
            id: "openai", name: "OpenAI",
            defaultBaseURL: "https://api.openai.com/v1/chat/completions",
            format: "openai",
            models: [
                "gpt-5", "gpt-5-mini",
                "gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano",
                "gpt-4o", "gpt-4o-mini",
                "o3", "o3-mini", "o4-mini",
            ]
        ),
        AIProvider(
            id: "google", name: "Google Gemini",
            defaultBaseURL: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
            format: "openai",
            models: [
                "gemini-3.1-pro-preview",
                "gemini-3.1-flash-lite-preview",
                "gemini-3-flash-preview",
                "gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.5-flash-lite",
                "gemini-2.0-flash",
            ]
        ),
        AIProvider(
            id: "groq", name: "Groq",
            defaultBaseURL: "https://api.groq.com/openai/v1/chat/completions",
            format: "openai",
            models: ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768"]
        ),
        AIProvider(
            id: "mistral", name: "Mistral",
            defaultBaseURL: "https://api.mistral.ai/v1/chat/completions",
            format: "openai",
            models: [
                "mistral-large-latest", "mistral-small-latest",
                "codestral-latest", "mistral-nemo",
            ]
        ),
        AIProvider(
            id: "openrouter", name: "OpenRouter",
            defaultBaseURL: "https://openrouter.ai/api/v1/chat/completions",
            format: "openai",
            models: [
                "deepseek/deepseek-chat-v3.2",
                "deepseek/deepseek-r1",
                "qwen/qwen3.5-coder",
                "meta-llama/llama-4-maverick",
                "meta-llama/llama-4-scout",
                "anthropic/claude-sonnet-4.6",
                "anthropic/claude-opus-4.6",
                "openai/gpt-5",
                "openai/gpt-4o",
                "google/gemini-3.1-pro-preview",
                "google/gemini-2.5-flash",
                "x-ai/grok-4-0709",
                "x-ai/grok-4-1-fast-non-reasoning",
                "x-ai/grok-4-1-fast-reasoning",
                "x-ai/grok-3",
                "x-ai/grok-3-mini",
            ]
        ),
        AIProvider(
            id: "deepseek", name: "DeepSeek",
            defaultBaseURL: "https://api.deepseek.com/v1/chat/completions",
            format: "openai",
            models: ["deepseek-chat", "deepseek-reasoner"]
        ),
        AIProvider(
            id: "xai", name: "xAI (Grok)",
            defaultBaseURL: "https://api.x.ai/v1/chat/completions",
            format: "openai",
            models: [
                "grok-4-0709", "grok-4-1-fast-reasoning", "grok-4-1-fast-non-reasoning",
                "grok-code-fast-1", "grok-3", "grok-3-mini",
            ]
        ),
    ]

    static func find(id: String) -> AIProvider? {
        known.first { $0.id == id }
    }

    /// Parse "provider/model" format, e.g. "openai/gpt-4o" or "openrouter/anthropic/claude-3.5-sonnet"
    static func resolve(modelString: String) -> (provider: AIProvider, model: String)? {
        if modelString.contains("/") {
            let parts = modelString.split(separator: "/", maxSplits: 1)
            let providerId = String(parts[0])
            let model = String(parts[1])
            if let provider = find(id: providerId) {
                return (provider, model)
            }
            // If first part isn't a known provider, try the full string as model auto-detect
        }
        // Auto-detect provider from model name
        for provider in known {
            if provider.models.contains(where: { modelString.hasPrefix($0.prefix(6)) || modelString == $0 }) {
                return (provider, modelString)
            }
        }
        // Default: Anthropic
        if modelString.starts(with: "claude") {
            return (known[0], modelString)
        }
        return nil
    }
}

// MARK: - Agent Config File

struct AgentConfigFile: Codable {
    var apiKeys: [String: AIProviderConfig]?
    var activeModel: String?   // "provider/model" format, e.g. "anthropic/claude-sonnet-4-20250514"
    var fallbackModels: [String]?  // Array of "provider/model" strings to try when primary fails
    var mcpServers: [String: MCPServerConfig]?
    var gateways: GatewayConfig?
    var maxTokens: Int?
    var maxScreenshotWidth: Int?
    var spendingLimits: SpendingLimits?

    enum CodingKeys: String, CodingKey {
        case apiKeys, activeModel, fallbackModels, mcpServers, gateways, maxTokens, maxScreenshotWidth
        case spendingLimits = "spending_limits"
    }

    static let configDir = NSHomeDirectory() + "/.desktop-agent"
    static let configPath = configDir + "/config.json"

    static func load() -> AgentConfigFile {
        let path = configPath
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let config = try? JSONDecoder().decode(AgentConfigFile.self, from: data) else {
            return AgentConfigFile()
        }
        return config
    }

    func save() throws {
        let dir = AgentConfigFile.configDir
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: AgentConfigFile.configPath))
        // Protect the file (contains API keys)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: AgentConfigFile.configPath)
    }

    // MARK: - API Key helpers

    func getAPIKey(provider: String) -> String? {
        apiKeys?[provider]?.apiKey
    }

    func getBaseURL(provider: String) -> String? {
        apiKeys?[provider]?.baseURL
    }

    mutating func setAPIKey(provider: String, key: String, baseURL: String? = nil, format: String? = nil) {
        if apiKeys == nil { apiKeys = [:] }
        apiKeys?[provider] = AIProviderConfig(apiKey: key, baseURL: baseURL, format: format)
    }

    mutating func removeAPIKey(provider: String) {
        apiKeys?.removeValue(forKey: provider)
    }
}
