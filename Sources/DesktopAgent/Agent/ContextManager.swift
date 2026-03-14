import Foundation

// MARK: - Context Manager (Token Tracking, Cost Calculation, Compaction)

/// Per-model pricing: cost per 1M tokens in USD
struct ModelPricing {
    let inputPer1M: Double   // $/1M input tokens
    let outputPer1M: Double  // $/1M output tokens
    let contextWindow: Int   // max context tokens

    func costForTokens(input: Int, output: Int) -> Double {
        return (Double(input) / 1_000_000.0 * inputPer1M)
             + (Double(output) / 1_000_000.0 * outputPer1M)
    }
}

final class ContextManager {

    // MARK: - Pricing Database (USD per 1M tokens, March 2025)

    static let pricing: [String: ModelPricing] = [
        // Anthropic
        "claude-opus-4-20250514":     ModelPricing(inputPer1M: 15.00, outputPer1M: 75.00, contextWindow: 200_000),
        "claude-sonnet-4-20250514":   ModelPricing(inputPer1M:  3.00, outputPer1M: 15.00, contextWindow: 200_000),
        "claude-haiku-4-5-20251001":  ModelPricing(inputPer1M:  0.80, outputPer1M:  4.00, contextWindow: 200_000),
        // OpenAI
        "gpt-4o":                     ModelPricing(inputPer1M:  2.50, outputPer1M: 10.00, contextWindow: 128_000),
        "gpt-4o-mini":                ModelPricing(inputPer1M:  0.15, outputPer1M:  0.60, contextWindow: 128_000),
        "gpt-4-turbo":                ModelPricing(inputPer1M: 10.00, outputPer1M: 30.00, contextWindow: 128_000),
        "o1":                         ModelPricing(inputPer1M: 15.00, outputPer1M: 60.00, contextWindow: 200_000),
        "o1-mini":                    ModelPricing(inputPer1M:  3.00, outputPer1M: 12.00, contextWindow: 128_000),
        "o3-mini":                    ModelPricing(inputPer1M:  1.10, outputPer1M:  4.40, contextWindow: 200_000),
        // Gemini
        "gemini-2.0-flash":           ModelPricing(inputPer1M:  0.10, outputPer1M:  0.40, contextWindow: 1_000_000),
        "gemini-3-flash-preview":     ModelPricing(inputPer1M:  0.10, outputPer1M:  0.40, contextWindow: 1_000_000),
        "gemini-2.0-pro":             ModelPricing(inputPer1M:  1.25, outputPer1M:  5.00, contextWindow: 2_000_000),
        "gemini-1.5-pro":             ModelPricing(inputPer1M:  1.25, outputPer1M:  5.00, contextWindow: 2_000_000),
        // Groq (free tier / very cheap)
        "llama-3.3-70b-versatile":    ModelPricing(inputPer1M:  0.59, outputPer1M:  0.79, contextWindow: 128_000),
        "llama-3.1-8b-instant":       ModelPricing(inputPer1M:  0.05, outputPer1M:  0.08, contextWindow: 128_000),
        "mixtral-8x7b-32768":         ModelPricing(inputPer1M:  0.24, outputPer1M:  0.24, contextWindow: 32_768),
        // Mistral
        "mistral-large-latest":       ModelPricing(inputPer1M:  2.00, outputPer1M:  6.00, contextWindow: 128_000),
        "mistral-medium-latest":      ModelPricing(inputPer1M:  2.70, outputPer1M:  8.10, contextWindow: 32_000),
        "mistral-small-latest":       ModelPricing(inputPer1M:  0.20, outputPer1M:  0.60, contextWindow: 32_000),
        // DeepSeek
        "deepseek-chat":              ModelPricing(inputPer1M:  0.14, outputPer1M:  0.28, contextWindow: 64_000),
        "deepseek-reasoner":          ModelPricing(inputPer1M:  0.55, outputPer1M:  2.19, contextWindow: 64_000),
        // xAI
        "grok-2":                     ModelPricing(inputPer1M:  2.00, outputPer1M: 10.00, contextWindow: 131_072),
        "grok-2-mini":                ModelPricing(inputPer1M:  2.00, outputPer1M: 10.00, contextWindow: 131_072),
    ]

    static let defaultPricing = ModelPricing(inputPer1M: 3.00, outputPer1M: 15.00, contextWindow: 128_000)

    /// Lookup pricing with fuzzy matching — try exact, then partial match on known keys
    static func lookupPricing(model: String) -> ModelPricing {
        // Exact match
        if let p = pricing[model] { return p }
        // Partial match: find a key that is a prefix of the model or vice versa
        let lower = model.lowercased()
        for (key, val) in pricing {
            if lower.hasPrefix(key) || key.hasPrefix(lower) { return val }
        }
        // Family match: extract base name (e.g. "gemini-3-flash" from "gemini-3-flash-preview-whatever")
        for (key, val) in pricing {
            let keyParts = Set(key.split(separator: "-").map(String.init))
            let modelParts = Set(lower.split(separator: "-").map(String.init))
            let overlap = keyParts.intersection(modelParts)
            if overlap.count >= 2 && (overlap.contains("flash") || overlap.contains("pro") || overlap.contains("haiku") || overlap.contains("sonnet") || overlap.contains("opus")) {
                return val
            }
        }
        return defaultPricing
    }

    // Compaction thresholds
    static let compactionThreshold = 0.75
    static let compactionTarget = 0.40

    // Token tracking
    private(set) var totalInputTokens: Int = 0
    private(set) var totalOutputTokens: Int = 0
    private(set) var turnCount: Int = 0
    private(set) var lastInputTokens: Int = 0
    private(set) var lastOutputTokens: Int = 0
    private(set) var compactionCount: Int = 0
    private(set) var imagesStripped: Int = 0

    let model: String
    let pricing: ModelPricing
    var contextWindow: Int { pricing.contextWindow }
    private let sessionStart = Date()

    init(model: String) {
        self.model = model
        self.pricing = ContextManager.lookupPricing(model: model)
    }

    // MARK: - Reset

    func reset() {
        totalInputTokens = 0
        totalOutputTokens = 0
        turnCount = 0
        lastInputTokens = 0
        lastOutputTokens = 0
        compactionCount = 0
        imagesStripped = 0
    }

    // MARK: - Track Usage

    func recordUsage(_ usage: TokenUsage?) {
        guard let u = usage else { return }
        lastInputTokens = u.inputTokens
        lastOutputTokens = u.outputTokens
        totalInputTokens += u.inputTokens
        totalOutputTokens += u.outputTokens
        turnCount += 1
    }

    // MARK: - Cost Calculation

    /// Total session cost in USD
    var sessionCost: Double {
        pricing.costForTokens(input: totalInputTokens, output: totalOutputTokens)
    }

    /// Cost of the last turn
    var lastTurnCost: Double {
        pricing.costForTokens(input: lastInputTokens, output: lastOutputTokens)
    }

    /// Cost per turn average
    var avgCostPerTurn: Double {
        turnCount > 0 ? sessionCost / Double(turnCount) : 0
    }

    // MARK: - Context Stats

    var contextPercentage: Double {
        return Double(lastInputTokens) / Double(contextWindow) * 100.0
    }

    var totalTokensUsed: Int {
        return totalInputTokens + totalOutputTokens
    }

    var isNearLimit: Bool {
        return Double(lastInputTokens) / Double(contextWindow) > ContextManager.compactionThreshold
    }

    var needsCompaction: Bool { isNearLimit }

    var sessionDuration: TimeInterval {
        Date().timeIntervalSince(sessionStart)
    }

    // MARK: - Image Stripping (Pre-compaction Optimization)

    /// Strip old screenshot/image blocks from conversation history.
    /// Images are by far the most expensive content blocks (~85K tokens each).
    /// Once the AI has processed a screenshot, the raw image data is no longer needed —
    /// the AI's text response already captured what it observed.
    /// This replaces image blocks with a lightweight text placeholder.
    func stripOldImages(from messages: [ClaudeMessage], keepLast: Int = 2) -> [ClaudeMessage] {
        // Find indices of messages that contain images
        var imageMessageIndices: [Int] = []
        for (i, msg) in messages.enumerated() {
            if msg.content.contains(where: { content in
                if case .image = content { return true }
                if case .toolResult(_, let blocks) = content {
                    return blocks.contains { $0.source != nil }
                }
                return false
            }) {
                imageMessageIndices.append(i)
            }
        }

        // Keep the last N image-containing messages intact
        let indicesToStrip = imageMessageIndices.dropLast(keepLast)
        if indicesToStrip.isEmpty { return messages }

        var stripped = messages
        var strippedCount = 0

        for i in indicesToStrip {
            let msg = stripped[i]
            let newContent: [ClaudeContent] = msg.content.map { content in
                switch content {
                case .image:
                    strippedCount += 1
                    return .text("[image previously sent — already processed]")
                case .toolResult(let id, let blocks):
                    let hadImage = blocks.contains { $0.source != nil }
                    if hadImage {
                        strippedCount += 1
                        // Keep text blocks, replace image blocks with placeholder
                        let textOnly = blocks.compactMap { $0.text }.joined(separator: "\n")
                        let placeholder = textOnly.isEmpty
                            ? "[screenshot previously sent — already analyzed]"
                            : textOnly + "\n[screenshot previously sent — already analyzed]"
                        return .toolResultText(toolUseId: id, text: placeholder)
                    }
                    return content
                default:
                    return content
                }
            }
            stripped[i] = ClaudeMessage(role: msg.role, content: newContent)
        }

        imagesStripped += strippedCount
        return stripped
    }

    // MARK: - Compaction

    func compactHistory(
        messages: [ClaudeMessage],
        client: AIClient,
        systemPrompt: String
    ) async throws -> [ClaudeMessage] {
        compactionCount += 1

        // Step 1: Strip old images first (biggest win — can free 100K+ tokens instantly)
        let imageStripped = stripOldImages(from: messages, keepLast: 2)

        let keepLastTurns = 4
        let keepMessages = keepLastTurns * 3

        if imageStripped.count <= keepMessages {
            return imageStripped
        }

        let oldMessages = Array(imageStripped.prefix(imageStripped.count - keepMessages))
        let recentMessages = Array(imageStripped.suffix(keepMessages))

        // Step 2: Build summary of old messages (text only, images already stripped)
        var summaryParts: [String] = []
        for msg in oldMessages {
            for content in msg.content {
                switch content {
                case .text(let text):
                    if !text.isEmpty {
                        let role = msg.role == "user" ? "User" : "Assistant"
                        let truncated = text.count > 500 ? String(text.prefix(500)) + "..." : text
                        summaryParts.append("[\(role)] \(truncated)")
                    }
                case .toolUse(_, let name, let input, _):
                    let args = input.map { "\($0.key)" }.joined(separator: ", ")
                    summaryParts.append("[Tool] \(name)(\(args))")
                case .toolResult(_, let blocks):
                    let text = blocks.compactMap { $0.text }.joined(separator: " ")
                    if !text.isEmpty {
                        let truncated = text.count > 200 ? String(text.prefix(200)) + "..." : text
                        summaryParts.append("[Result] \(truncated)")
                    }
                default:
                    break
                }
            }
        }

        let rawSummary = summaryParts.joined(separator: "\n")

        let summaryRequest = """
        Summarize this conversation concisely. Focus on: key decisions, outcomes, current task state, user's goal.
        Under 500 words. Factual and specific.

        CONVERSATION:
        \(String(rawSummary.prefix(8000)))
        """

        let summaryMessages = [ClaudeMessage(role: "user", content: [.text(summaryRequest)])]

        do {
            let response = try await client.sendMessage(
                messages: summaryMessages,
                system: "You are a conversation summarizer. Output only the summary.",
                tools: nil
            )
            if let usage = response.usage { recordUsage(usage) }

            let summaryText = response.content.compactMap { c -> String? in
                if case .text(let t) = c { return t }; return nil
            }.joined(separator: "\n")

            var compacted: [ClaudeMessage] = []
            compacted.append(ClaudeMessage(role: "user", content: [.text("[CONVERSATION SUMMARY]\n\(summaryText)\n[END SUMMARY]")]))
            compacted.append(ClaudeMessage(role: "assistant", content: [.text("Understood. Continuing from where we left off.")]))
            compacted.append(contentsOf: recentMessages)
            return compacted
        } catch {
            var compacted: [ClaudeMessage] = []
            compacted.append(ClaudeMessage(role: "user", content: [.text("[Earlier conversation compacted. \(oldMessages.count) messages summarized.]")]))
            compacted.append(ClaudeMessage(role: "assistant", content: [.text("Understood. Continuing with recent context.")]))
            compacted.append(contentsOf: recentMessages)
            return compacted
        }
    }

    // MARK: - Format Display

    /// Short context status: "45K/200K"
    var shortStatus: String {
        "\(fmtTokens(lastInputTokens))/\(fmtTokens(contextWindow))"
    }

    /// Colored context bar
    var contextBar: String {
        let pct = contextPercentage
        let w = 20
        let filled = min(Int(pct / 100.0 * Double(w)), w)

        let color: String
        if pct < 50 { color = "\u{001B}[32m" }
        else if pct < 75 { color = "\u{001B}[33m" }
        else { color = "\u{001B}[31m" }

        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: w - filled)
        return "\(color)\(bar)\u{001B}[0m \(String(format: "%.0f", pct))%"
    }

    /// Prompt indicator: colored dot + percentage
    var promptIndicator: String {
        let pct = contextPercentage

        let color: String
        if pct < 50 { color = "\u{001B}[32m" }
        else if pct < 75 { color = "\u{001B}[33m" }
        else { color = "\u{001B}[31m" }

        let pctStr = pct < 1 ? "0" : String(format: "%.0f", pct)
        return "\(color)● \(pctStr)%\u{001B}[0m "
    }

    /// One-line cost summary for after each response
    var turnSummary: String {
        let r = "\u{001B}[0m"
        let d = "\u{001B}[90m"
        let g = "\u{001B}[32m"
        return "\(d)↑\(fmtTokens(lastInputTokens)) ↓\(fmtTokens(lastOutputTokens)) · \(shortStatus) · \(g)\(fmtCost(sessionCost))\(r)"
    }

    /// Full status for /context command (CodexBar-inspired)
    var fullStatus: String {
        let r = "\u{001B}[0m"
        let d = "\u{001B}[90m"
        let b = "\u{001B}[1m"
        let c = "\u{001B}[36m"
        let g = "\u{001B}[32m"
        let y = "\u{001B}[33m"

        let dur = formatDuration(sessionDuration)
        let inputCost = pricing.costForTokens(input: totalInputTokens, output: 0)
        let outputCost = pricing.costForTokens(input: 0, output: totalOutputTokens)

        var lines: [String] = []

        // Header
        lines.append("  \(b)Session Overview\(r)")
        lines.append("  \(contextBar)")
        lines.append("")

        // Cost breakdown (CodexBar style)
        lines.append("  \(b)Cost\(r)")
        lines.append("  \(g)  \(fmtCost(sessionCost))\(r) total \(d)(\(turnCount) turns, \(dur))\(r)")
        lines.append("  \(d)  ↑ Input:  \(fmtTokens(totalInputTokens)) tokens · \(fmtCost(inputCost))\(r)")
        lines.append("  \(d)  ↓ Output: \(fmtTokens(totalOutputTokens)) tokens · \(fmtCost(outputCost))\(r)")
        if turnCount > 0 {
            lines.append("  \(d)  ~ \(fmtCost(avgCostPerTurn))/turn avg\(r)")
        }
        lines.append("")

        // Model info
        lines.append("  \(b)Model\(r)")
        lines.append("  \(c)  \(model)\(r)")
        lines.append("  \(d)  \(fmtCost(pricing.inputPer1M))/1M in · \(fmtCost(pricing.outputPer1M))/1M out · \(fmtTokens(contextWindow)) ctx\(r)")
        lines.append("")

        // Context
        lines.append("  \(b)Context Window\(r)")
        lines.append("  \(d)  \(fmtTokens(lastInputTokens)) / \(fmtTokens(contextWindow)) tokens (\(String(format: "%.1f", contextPercentage))%)\(r)")
        if compactionCount > 0 {
            lines.append("  \(y)  Compacted \(compactionCount)x\(r)")
        }
        if imagesStripped > 0 {
            lines.append("  \(d)  Images stripped: \(imagesStripped)\(r)")
        }

        // Projection
        if turnCount >= 2 {
            let tokensPerTurn = totalInputTokens / turnCount
            let remainingTokens = contextWindow - lastInputTokens
            let turnsLeft = tokensPerTurn > 0 ? remainingTokens / tokensPerTurn : 0
            if turnsLeft > 0 && turnsLeft < 100 {
                lines.append("  \(d)  ~\(turnsLeft) turns until compaction\(r)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Formatters

    private func fmtTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000.0) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000.0) }
        return "\(count)"
    }

    private func fmtCost(_ usd: Double) -> String {
        if usd < 0.01 && usd > 0 { return String(format: "$%.4f", usd) }
        if usd < 1.00 { return String(format: "$%.3f", usd) }
        return String(format: "$%.2f", usd)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }
}
