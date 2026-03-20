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

    // MARK: - Pricing Database (USD per 1M tokens, March 2026)
    // Sources: official pricing pages of each provider

    static let pricing: [String: ModelPricing] = [
        // ── Anthropic (March 2026) ──
        // Current gen (4.6)
        "claude-opus-4.6":            ModelPricing(inputPer1M:  5.00, outputPer1M: 25.00, contextWindow: 1_000_000),
        "claude-sonnet-4.6":          ModelPricing(inputPer1M:  3.00, outputPer1M: 15.00, contextWindow: 1_000_000),
        "claude-haiku-4.5":           ModelPricing(inputPer1M:  1.00, outputPer1M:  5.00, contextWindow: 200_000),
        "claude-haiku-4-5-20251001":  ModelPricing(inputPer1M:  1.00, outputPer1M:  5.00, contextWindow: 200_000),
        // Legacy gen (4.0) — these snapshot IDs cost more
        "claude-opus-4-20250514":     ModelPricing(inputPer1M: 15.00, outputPer1M: 75.00, contextWindow: 200_000),
        "claude-sonnet-4-20250514":   ModelPricing(inputPer1M:  3.00, outputPer1M: 15.00, contextWindow: 200_000),
        "claude-3-5-sonnet":          ModelPricing(inputPer1M:  3.00, outputPer1M: 15.00, contextWindow: 200_000),
        "claude-3-5-haiku":           ModelPricing(inputPer1M:  0.25, outputPer1M:  1.25, contextWindow: 200_000),

        // ── OpenAI (February 2026) ──
        "gpt-5":                      ModelPricing(inputPer1M:  1.25, outputPer1M: 10.00, contextWindow: 400_000),
        "gpt-5-mini":                 ModelPricing(inputPer1M:  0.25, outputPer1M:  2.00, contextWindow: 400_000),
        "gpt-4.1":                    ModelPricing(inputPer1M:  2.00, outputPer1M:  8.00, contextWindow: 1_000_000),
        "gpt-4.1-mini":               ModelPricing(inputPer1M:  0.40, outputPer1M:  1.60, contextWindow: 1_000_000),
        "gpt-4.1-nano":               ModelPricing(inputPer1M:  0.10, outputPer1M:  0.40, contextWindow: 1_000_000),
        "gpt-4o":                     ModelPricing(inputPer1M:  2.50, outputPer1M: 10.00, contextWindow: 128_000),
        "gpt-4o-mini":                ModelPricing(inputPer1M:  0.15, outputPer1M:  0.60, contextWindow: 128_000),
        "o3":                         ModelPricing(inputPer1M:  2.00, outputPer1M:  8.00, contextWindow: 200_000),
        "o3-mini":                    ModelPricing(inputPer1M:  0.55, outputPer1M:  2.20, contextWindow: 200_000),
        "o3-pro":                     ModelPricing(inputPer1M: 20.00, outputPer1M: 80.00, contextWindow: 200_000),
        "o4-mini":                    ModelPricing(inputPer1M:  1.10, outputPer1M:  4.40, contextWindow: 200_000),

        // ── Google Gemini (March 2026) ──
        "gemini-3.1-pro-preview":     ModelPricing(inputPer1M:  2.00, outputPer1M: 12.00, contextWindow: 1_000_000),
        "gemini-3.1-flash-lite-preview": ModelPricing(inputPer1M: 0.25, outputPer1M: 1.50, contextWindow: 1_000_000),
        "gemini-3-flash-preview":     ModelPricing(inputPer1M:  0.50, outputPer1M:  3.00, contextWindow: 1_000_000),
        "gemini-2.5-pro":             ModelPricing(inputPer1M:  1.25, outputPer1M: 10.00, contextWindow: 1_000_000),
        "gemini-2.5-flash":           ModelPricing(inputPer1M:  0.30, outputPer1M:  2.50, contextWindow: 1_000_000),
        "gemini-2.5-flash-lite":      ModelPricing(inputPer1M:  0.10, outputPer1M:  0.40, contextWindow: 1_000_000),
        "gemini-2.0-flash":           ModelPricing(inputPer1M:  0.10, outputPer1M:  0.40, contextWindow: 1_000_000),

        // ── Groq (March 2026) ──
        "llama-3.3-70b-versatile":    ModelPricing(inputPer1M:  0.59, outputPer1M:  0.79, contextWindow: 128_000),
        "llama-3.1-8b-instant":       ModelPricing(inputPer1M:  0.05, outputPer1M:  0.08, contextWindow: 128_000),
        "mixtral-8x7b-32768":         ModelPricing(inputPer1M:  0.24, outputPer1M:  0.24, contextWindow: 32_768),

        // ── Mistral (March 2026) ──
        "mistral-large-latest":       ModelPricing(inputPer1M:  0.50, outputPer1M:  1.50, contextWindow: 262_144),
        "mistral-small-latest":       ModelPricing(inputPer1M:  0.03, outputPer1M:  0.11, contextWindow: 128_000),
        "codestral-latest":           ModelPricing(inputPer1M:  0.30, outputPer1M:  0.90, contextWindow: 256_000),
        "mistral-nemo":               ModelPricing(inputPer1M:  0.02, outputPer1M:  0.04, contextWindow: 128_000),

        // ── DeepSeek (March 2026 — V3.2 unified pricing) ──
        "deepseek-chat":              ModelPricing(inputPer1M:  0.28, outputPer1M:  0.42, contextWindow: 128_000),
        "deepseek-reasoner":          ModelPricing(inputPer1M:  0.28, outputPer1M:  0.42, contextWindow: 128_000),

        // ── xAI / Grok (March 2026) ──
        "grok-4-0709":                ModelPricing(inputPer1M:  3.00, outputPer1M: 15.00, contextWindow: 256_000),
        "grok-4-1-fast-reasoning":    ModelPricing(inputPer1M:  0.20, outputPer1M:  0.50, contextWindow: 2_000_000),
        "grok-4-1-fast-non-reasoning": ModelPricing(inputPer1M: 0.20, outputPer1M:  0.50, contextWindow: 2_000_000),
        "grok-code-fast-1":           ModelPricing(inputPer1M:  0.20, outputPer1M:  1.50, contextWindow: 256_000),
        "grok-3":                     ModelPricing(inputPer1M:  3.00, outputPer1M: 15.00, contextWindow: 131_072),
        "grok-3-mini":                ModelPricing(inputPer1M:  0.30, outputPer1M:  0.50, contextWindow: 131_072),
        // Legacy aliases
        "grok-2":                     ModelPricing(inputPer1M:  3.00, outputPer1M: 15.00, contextWindow: 131_072),
        "grok-2-mini":                ModelPricing(inputPer1M:  0.30, outputPer1M:  0.50, contextWindow: 131_072),
    ]

    static let defaultPricing = ModelPricing(inputPer1M: 1.00, outputPer1M: 5.00, contextWindow: 128_000)

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
    private(set) var tokensSavedByCompaction: Int = 0
    private(set) var lastCompactionSaved: Int = 0  // tokens saved in the most recent compaction

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
        tokensSavedByCompaction = 0
        lastCompactionSaved = 0
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

    // MARK: - Progressive Compaction Tiers

    /// Returns 0/1/2/3 based on current context usage percentage.
    /// - Tier 0: < 40% — no action needed
    /// - Tier 1: 40-59% — strip images from old messages, truncate tool results to 200 chars
    /// - Tier 2: 60-74% — summarize oldest 50% of conversation into bullet points
    /// - Tier 3: >= 75% — deep compaction (existing behavior)
    var compactionTier: Int {
        let pct = Double(lastInputTokens) / Double(contextWindow)
        if pct >= ContextManager.compactionThreshold { return 3 }
        if pct >= 0.60 { return 2 }
        if pct >= 0.40 { return 1 }
        return 0
    }

    var sessionDuration: TimeInterval {
        Date().timeIntervalSince(sessionStart)
    }

    // MARK: - Token Estimation

    /// Estimate token count for a base64 image.
    /// Base64 encoding in the API request body contributes roughly 1 token per 4 chars.
    /// A typical screenshot (1920x1080) is ~500K-1M base64 chars.
    private func estimateImageTokens(_ base64Length: Int) -> Int {
        return max(base64Length / 4, 1000)
    }

    /// Rough token estimate for a set of messages (4 chars ~ 1 token for text content)
    func estimateMessageTokens(_ messages: [ClaudeMessage]) -> Int {
        var total = 0
        for msg in messages {
            for content in msg.content {
                switch content {
                case .text(let text):
                    total += text.count / 4
                case .image(let source):
                    total += estimateImageTokens(source.data.count)
                case .toolUse(_, _, let input, _):
                    let inputStr = input.map { "\($0.key):\($0.value)" }.joined()
                    total += inputStr.count / 4 + 20
                case .toolResult(_, let blocks):
                    for block in blocks {
                        if let text = block.text { total += text.count / 4 }
                        if let src = block.source { total += estimateImageTokens(src.data.count) }
                    }
                }
            }
            total += 4 // message overhead (role, structure)
        }
        return total
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
        var estimatedTokensSaved = 0

        for i in indicesToStrip {
            let msg = stripped[i]
            let newContent: [ClaudeContent] = msg.content.map { content in
                switch content {
                case .image(let source):
                    strippedCount += 1
                    estimatedTokensSaved += estimateImageTokens(source.data.count)
                    return .text("[image previously sent — already processed]")
                case .toolResult(let id, let blocks):
                    let hadImage = blocks.contains { $0.source != nil }
                    if hadImage {
                        strippedCount += 1
                        // Estimate tokens saved from stripped image blocks
                        for block in blocks {
                            if let src = block.source {
                                estimatedTokensSaved += estimateImageTokens(src.data.count)
                            }
                        }
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
        tokensSavedByCompaction += estimatedTokensSaved
        return stripped
    }

    // MARK: - Tier 1: Truncate Tool Results

    /// Truncate tool result text blocks to maxChars, keeping only the beginning.
    func truncateToolResults(in messages: [ClaudeMessage], maxChars: Int = 200, keepLast: Int = 4) -> [ClaudeMessage] {
        guard messages.count > keepLast else { return messages }
        let boundary = messages.count - keepLast
        var result = messages
        for i in 0..<boundary {
            let msg = result[i]
            let newContent: [ClaudeContent] = msg.content.map { content in
                switch content {
                case .toolResult(let id, let blocks):
                    let truncatedBlocks: [ToolResultContentBlock] = blocks.map { block in
                        if let text = block.text, text.count > maxChars {
                            return .textBlock(String(text.prefix(maxChars)) + "...[truncated]")
                        }
                        return block
                    }
                    return .toolResult(toolUseId: id, content: truncatedBlocks)
                default:
                    return content
                }
            }
            result[i] = ClaudeMessage(role: msg.role, content: newContent)
        }
        return result
    }

    // MARK: - Tool Result Pruning (OpenCode-style)

    /// Aggressively prune old tool results beyond keepLast turns, replacing with "[cleared]".
    /// Preserves tool_use structure (so the model knows which tools were called) but removes
    /// the potentially large output data. This is more aggressive than truncation.
    func pruneOldToolResults(in messages: [ClaudeMessage], keepLast: Int = 6) -> [ClaudeMessage] {
        guard messages.count > keepLast else { return messages }
        let boundary = messages.count - keepLast
        var result = messages
        var prunedTokens = 0

        for i in 0..<boundary {
            let msg = result[i]
            guard msg.role == "user" else { continue }

            let newContent: [ClaudeContent] = msg.content.map { content in
                switch content {
                case .toolResult(let id, let blocks):
                    let originalSize = blocks.compactMap { $0.text }.joined().count
                    if originalSize > 100 {
                        prunedTokens += originalSize / 4
                        return .toolResult(toolUseId: id, content: [.textBlock("[Old tool result cleared]")])
                    }
                    return content
                default:
                    return content
                }
            }
            result[i] = ClaudeMessage(role: msg.role, content: newContent)
        }

        if prunedTokens > 0 {
            tokensSavedByCompaction += prunedTokens
        }
        return result
    }

    // MARK: - Tier 2: Summarize Oldest 50%

    /// Summarize the oldest half of the conversation into bullet points using a cheap model call.
    func summarizeOldestHalf(
        messages: [ClaudeMessage],
        client: AIClient
    ) async throws -> [ClaudeMessage] {
        let halfPoint = messages.count / 2
        guard halfPoint > 2 else { return messages }

        let oldMessages = Array(messages.prefix(halfPoint))
        let recentMessages = Array(messages.suffix(messages.count - halfPoint))

        // Preserve the first user message
        let firstUserMessage = oldMessages.first { $0.role == "user" }

        // Build text summary of old messages
        var summaryParts: [String] = []
        for msg in oldMessages {
            for content in msg.content {
                switch content {
                case .text(let text):
                    if !text.isEmpty {
                        let role = msg.role == "user" ? "User" : "Assistant"
                        let truncated = text.count > 300 ? String(text.prefix(300)) + "..." : text
                        summaryParts.append("[\(role)] \(truncated)")
                    }
                case .toolUse(_, let name, let input, _):
                    let args = input.map { "\($0.key)" }.joined(separator: ", ")
                    summaryParts.append("[Tool] \(name)(\(args))")
                case .toolResult(_, let blocks):
                    let text = blocks.compactMap { $0.text }.joined(separator: " ")
                    if !text.isEmpty {
                        let truncated = text.count > 100 ? String(text.prefix(100)) + "..." : text
                        summaryParts.append("[Result] \(truncated)")
                    }
                default:
                    break
                }
            }
        }

        let rawSummary = summaryParts.joined(separator: "\n")
        let summaryRequest = """
        Condense this conversation into bullet points. Keep file paths, commands, and error messages verbatim. Under 300 words.

        \(String(rawSummary.prefix(6000)))
        """

        let summaryMessages = [ClaudeMessage(role: "user", content: [.text(summaryRequest)])]

        let preTokenEstimate = estimateMessageTokens(oldMessages)

        do {
            let response = try await client.sendMessage(
                messages: summaryMessages,
                system: "You are a conversation summarizer. Output only bullet points, no preamble.",
                tools: nil
            )
            if let usage = response.usage { recordUsage(usage) }

            let summaryText = response.content.compactMap { c -> String? in
                if case .text(let t) = c { return t }; return nil
            }.joined(separator: "\n")

            var compacted: [ClaudeMessage] = []

            if let firstMsg = firstUserMessage {
                compacted.append(firstMsg)
                compacted.append(ClaudeMessage(role: "assistant", content: [.text("Understood. Working on this.")]))
            }

            compacted.append(ClaudeMessage(role: "user", content: [.text("[CONTEXT SUMMARY — \(oldMessages.count) messages condensed]\n\(summaryText)\n[END SUMMARY]")]))
            compacted.append(ClaudeMessage(role: "assistant", content: [.text("Understood. Continuing with full awareness of prior work.")]))
            compacted.append(contentsOf: recentMessages)

            let postTokenEstimate = estimateMessageTokens(compacted)
            let saved = max(preTokenEstimate - postTokenEstimate, 0)
            tokensSavedByCompaction += saved
            lastCompactionSaved = saved
            compactionCount += 1

            return compacted
        } catch {
            // On failure, return messages unchanged
            return messages
        }
    }

    // MARK: - Progressive Compaction Entry Point

    /// Apply the appropriate compaction tier based on current context usage.
    /// Returns the (possibly compacted) messages and a human-readable description of what was done, or nil if nothing.
    func progressiveCompact(
        messages: [ClaudeMessage],
        client: AIClient,
        systemPrompt: String
    ) async throws -> (messages: [ClaudeMessage], description: String?) {
        let tier = compactionTier
        guard tier > 0, messages.count > 6 else {
            return (messages, nil)
        }

        switch tier {
        case 1:
            // Tier 1: strip old images + truncate tool results
            var result = stripOldImages(from: messages, keepLast: 2)
            result = truncateToolResults(in: result, maxChars: 200, keepLast: 8)
            return (result, "Tier 1: stripped old images, truncated tool results")

        case 2:
            // Tier 2: prune old tool results + summarize oldest 50%
            var result = stripOldImages(from: messages, keepLast: 2)
            result = pruneOldToolResults(in: result, keepLast: 8)
            result = truncateToolResults(in: result, maxChars: 200, keepLast: 8)
            if result.count > 10 {
                result = try await summarizeOldestHalf(messages: result, client: client)
                return (result, "Tier 2: pruned + summarized oldest 50%")
            }
            return (result, "Tier 2: pruned tool results and stripped images")

        default:
            // Tier 3: prune aggressively + deep compaction
            var pruned = pruneOldToolResults(in: messages, keepLast: 4)
            pruned = stripOldImages(from: pruned, keepLast: 1)
            let result = try await compactHistory(messages: pruned, client: client, systemPrompt: systemPrompt)
            return (result, "Tier 3: deep compaction with aggressive pruning")
        }
    }

    // MARK: - Deep Compaction (Tier 3)

    func compactHistory(
        messages: [ClaudeMessage],
        client: AIClient,
        systemPrompt: String
    ) async throws -> [ClaudeMessage] {
        compactionCount += 1
        _ = messages.count

        // Step 1: Strip old images first (biggest win — can free 100K+ tokens instantly)
        let imageStripped = stripOldImages(from: messages, keepLast: 2)

        let keepLastTurns = 4
        let keepMessages = keepLastTurns * 3

        if imageStripped.count <= keepMessages {
            lastCompactionSaved = 0
            return imageStripped
        }

        // Step 2: Preserve the first user message (establishes original context/goal)
        let firstUserMessage = imageStripped.first { $0.role == "user" }
        let firstUserIndex = imageStripped.firstIndex { $0.role == "user" } ?? 0

        // Split: old messages to summarize vs recent messages to keep
        let oldMessages = Array(imageStripped.prefix(imageStripped.count - keepMessages))
        let recentMessages = Array(imageStripped.suffix(keepMessages))

        // Estimate pre-compaction token count
        let preTokenEstimate = estimateMessageTokens(oldMessages)

        // Step 3: Build summary of old messages (text only, images already stripped)
        // Skip the first user message since we preserve it separately
        var summaryParts: [String] = []
        for (idx, msg) in oldMessages.enumerated() {
            // Skip the first user message — it will be preserved verbatim
            if idx == firstUserIndex && msg.role == "user" { continue }

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
        Summarize this conversation history concisely. Focus on:
        1. The user's original goal and any sub-goals that emerged
        2. Key decisions made and their rationale
        3. Tools used and their outcomes (especially file paths, commands, errors)
        4. Current task state — what has been done and what remains
        Under 500 words. Be factual and specific. Include file paths and error messages verbatim.

        CONVERSATION:
        \(String(rawSummary.prefix(8000)))
        """

        let summaryMessages = [ClaudeMessage(role: "user", content: [.text(summaryRequest)])]

        do {
            let response = try await client.sendMessage(
                messages: summaryMessages,
                system: "You are a conversation summarizer. Output only the summary, no preamble.",
                tools: nil
            )
            if let usage = response.usage { recordUsage(usage) }

            let summaryText = response.content.compactMap { c -> String? in
                if case .text(let t) = c { return t }; return nil
            }.joined(separator: "\n")

            var compacted: [ClaudeMessage] = []

            // Preserve the first user message (original context)
            if let firstMsg = firstUserMessage {
                compacted.append(firstMsg)
                compacted.append(ClaudeMessage(role: "assistant", content: [.text("Understood. Working on this.")]))
            }

            // Add the AI-generated summary of the middle conversation
            compacted.append(ClaudeMessage(role: "user", content: [.text("[CONVERSATION SUMMARY — \(oldMessages.count) messages compacted]\n\(summaryText)\n[END SUMMARY]")]))
            compacted.append(ClaudeMessage(role: "assistant", content: [.text("Understood. Continuing from where we left off with full context of what was done.")]))

            // Append recent messages
            compacted.append(contentsOf: recentMessages)

            // Track savings
            let postTokenEstimate = estimateMessageTokens(compacted)
            let saved = max(preTokenEstimate - postTokenEstimate, 0)
            lastCompactionSaved = saved
            tokensSavedByCompaction += saved

            return compacted
        } catch {
            var compacted: [ClaudeMessage] = []

            // Even on failure, preserve the first user message
            if let firstMsg = firstUserMessage {
                compacted.append(firstMsg)
                compacted.append(ClaudeMessage(role: "assistant", content: [.text("Understood.")]))
            }

            compacted.append(ClaudeMessage(role: "user", content: [.text("[Earlier conversation compacted. \(oldMessages.count) messages summarized.]")]))
            compacted.append(ClaudeMessage(role: "assistant", content: [.text("Understood. Continuing with recent context.")]))
            compacted.append(contentsOf: recentMessages)

            let postTokenEstimate = estimateMessageTokens(compacted)
            let saved = max(preTokenEstimate - postTokenEstimate, 0)
            lastCompactionSaved = saved
            tokensSavedByCompaction += saved

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
    func consumeTurnSummary() -> String {
        let r = "\u{001B}[0m"
        let d = "\u{001B}[90m"
        let g = "\u{001B}[32m"
        let m = "\u{001B}[35m"
        var summary = "\(d)↑\(fmtTokens(lastInputTokens)) ↓\(fmtTokens(lastOutputTokens)) · \(shortStatus) · \(g)\(fmtCost(sessionCost))\(r)"
        if lastCompactionSaved > 0 {
            summary += " \(m)🗜 -\(fmtTokens(lastCompactionSaved))\(r)"
            lastCompactionSaved = 0  // Reset after displaying
        }
        return summary
    }

    /// One-line cost summary (non-consuming, for read-only access)
    var turnSummary: String {
        let r = "\u{001B}[0m"
        let d = "\u{001B}[90m"
        let g = "\u{001B}[32m"
        let m = "\u{001B}[35m"
        var summary = "\(d)↑\(fmtTokens(lastInputTokens)) ↓\(fmtTokens(lastOutputTokens)) · \(shortStatus) · \(g)\(fmtCost(sessionCost))\(r)"
        if lastCompactionSaved > 0 {
            summary += " \(m)🗜 -\(fmtTokens(lastCompactionSaved))\(r)"
        }
        return summary
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
            lines.append("  \(y)  Compacted \(compactionCount)x · saved ~\(fmtTokens(tokensSavedByCompaction)) tokens\(r)")
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

    func fmtTokens(_ count: Int) -> String {
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
