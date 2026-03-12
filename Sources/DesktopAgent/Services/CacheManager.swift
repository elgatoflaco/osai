import Foundation

// MARK: - Smart Caching Layer
// Extends tool result caching with predictive warming, context-aware keys,
// and async cache population based on usage patterns.

final class CacheManager: @unchecked Sendable {

    // MARK: - Types

    struct CacheEntry {
        let result: ToolResult
        let screenshotBase64: String?
        let timestamp: Date
        let inputHash: String
        let accessCount: Int
        let lastAccessed: Date
    }

    struct CacheStats {
        var hits: Int = 0
        var misses: Int = 0
        var warmHits: Int = 0      // Hits from predictive warming
        var evictions: Int = 0
        var totalSavedMs: Int = 0  // Estimated time saved

        var hitRate: Double {
            let total = hits + misses
            return total > 0 ? Double(hits) / Double(total) * 100.0 : 0
        }
    }

    // MARK: - Configuration

    /// Maximum cache entries before LRU eviction
    private let maxEntries: Int

    /// Tool-specific TTLs (seconds)
    static let ttls: [String: TimeInterval] = [
        "get_screen_size": 300,
        "read_program": 120,
        "read_system_prompt": 120,
        "read_improvement_log": 60,
        "file_info": 60,
        "read_memory": 60,
        "list_directory": 30,
        "read_file": 30,
        "spotlight_search": 30,
        "read_clipboard": 10,
        "list_apps": 5,
        "list_windows": 5,
        "list_tasks": 10,
        "get_frontmost_app": 2,
    ]

    static let defaultTTL: TimeInterval = 15

    /// Tools safe to cache
    static let cacheableTools: Set<String> = [
        "list_apps", "get_frontmost_app", "list_windows", "get_screen_size",
        "read_clipboard", "read_file", "list_directory", "file_info",
        "read_memory", "read_program", "read_system_prompt", "read_improvement_log",
        "list_tasks", "spotlight_search"
    ]

    /// Tools that invalidate caches when called
    static let invalidators: [String: Set<String>] = [
        "write_file":         ["read_file", "list_directory", "file_info"],
        "write_clipboard":    ["read_clipboard"],
        "save_memory":        ["read_memory"],
        "edit_program":       ["read_program"],
        "edit_system_prompt": ["read_system_prompt"],
        "open_app":           ["list_apps", "get_frontmost_app", "list_windows"],
        "activate_app":       ["get_frontmost_app"],
        "click_element":      ["get_frontmost_app", "list_windows"],
        "schedule_task":      ["list_tasks"],
        "cancel_task":        ["list_tasks"],
    ]

    // MARK: - State

    private let lock = NSLock()
    private var cache: [String: CacheEntry] = [:]
    private(set) var stats = CacheStats()

    /// Track which tools are being warmed (prevent duplicate warming)
    private var warmingInProgress: Set<String> = []

    init(maxEntries: Int = 200) {
        self.maxEntries = maxEntries
    }

    // MARK: - Core Cache Operations

    /// Get a cached result, returning nil on miss or expiry
    func get(toolName: String, input: [String: AnyCodable]) -> (ToolResult, String?)? {
        guard CacheManager.cacheableTools.contains(toolName) else { return nil }

        let key = cacheKey(toolName: toolName, input: input)

        lock.lock()
        guard let entry = cache[key] else {
            stats.misses += 1
            lock.unlock()
            return nil
        }

        // Check TTL
        let ttl = CacheManager.ttls[toolName] ?? CacheManager.defaultTTL
        if Date().timeIntervalSince(entry.timestamp) > ttl {
            cache.removeValue(forKey: key)
            stats.misses += 1
            lock.unlock()
            return nil
        }

        // Update access tracking
        let updated = CacheEntry(
            result: entry.result, screenshotBase64: entry.screenshotBase64,
            timestamp: entry.timestamp, inputHash: entry.inputHash,
            accessCount: entry.accessCount + 1, lastAccessed: Date()
        )
        cache[key] = updated
        stats.hits += 1
        lock.unlock()

        return (entry.result, entry.screenshotBase64)
    }

    /// Store a result in cache
    func put(toolName: String, input: [String: AnyCodable], result: ToolResult, screenshotBase64: String?) {
        guard CacheManager.cacheableTools.contains(toolName), result.success else { return }

        let key = cacheKey(toolName: toolName, input: input)
        let hash = inputHash(input)

        lock.lock()

        // LRU eviction if at capacity
        if cache.count >= maxEntries {
            evictLRU()
        }

        cache[key] = CacheEntry(
            result: result, screenshotBase64: screenshotBase64,
            timestamp: Date(), inputHash: hash,
            accessCount: 0, lastAccessed: Date()
        )
        lock.unlock()
    }

    /// Invalidate caches affected by a state-changing tool
    func invalidate(forTool toolName: String) {
        guard let affected = CacheManager.invalidators[toolName] else { return }

        lock.lock()
        let before = cache.count
        cache = cache.filter { key, _ in
            !affected.contains(where: { key.hasPrefix($0 + ":") })
        }
        let removed = before - cache.count
        if removed > 0 { stats.evictions += removed }
        lock.unlock()
    }

    /// Clear all cache entries
    func clearAll() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    // MARK: - Predictive Cache Warming

    /// Warm cache for predicted next tools based on orchestrator predictions
    func warmCache(
        predictions: [ToolOrchestrator.Prediction],
        executor: ToolExecutor,
        orchestrator: ToolOrchestrator,
        minConfidence: Double = 0.5
    ) async {
        let warmable = predictions.filter { pred in
            pred.confidence >= minConfidence &&
            CacheManager.cacheableTools.contains(pred.toolName)
        }

        guard !warmable.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for pred in warmable {
                // Skip if already warming or cached
                lock.lock()
                let alreadyWarming = warmingInProgress.contains(pred.toolName)
                if !alreadyWarming {
                    warmingInProgress.insert(pred.toolName)
                }
                lock.unlock()

                if alreadyWarming { continue }

                group.addTask { [weak self] in
                    defer {
                        self?.lock.lock()
                        self?.warmingInProgress.remove(pred.toolName)
                        self?.lock.unlock()
                    }

                    // Warm with empty/default input for tools that don't need params
                    let defaultInput: [String: AnyCodable] = [:]
                    let noParamTools: Set<String> = [
                        "list_apps", "get_frontmost_app", "get_screen_size",
                        "read_clipboard", "list_tasks"
                    ]

                    guard noParamTools.contains(pred.toolName) else { return }

                    // Check if already cached
                    if self?.get(toolName: pred.toolName, input: defaultInput) != nil { return }

                    // Execute and cache
                    let execResult = executor.execute(toolName: pred.toolName, input: defaultInput)
                    self?.put(
                        toolName: pred.toolName, input: defaultInput,
                        result: execResult.result, screenshotBase64: execResult.screenshotBase64
                    )

                    self?.lock.lock()
                    self?.stats.warmHits += 1
                    self?.lock.unlock()
                }
            }
        }
    }

    // MARK: - Analytics

    var statsDescription: String {
        lock.lock()
        let s = stats
        let entryCount = cache.count
        lock.unlock()

        return """
        Cache: \(s.hits)h/\(s.hits + s.misses)t (\(String(format: "%.0f", s.hitRate))%) | \
        \(entryCount) entries | \(s.warmHits) pre-warmed | \(s.evictions) evicted
        """
    }

    // MARK: - Helpers

    private func evictLRU() {
        // Remove least recently accessed entry
        if let lru = cache.min(by: { $0.value.lastAccessed < $1.value.lastAccessed }) {
            cache.removeValue(forKey: lru.key)
            stats.evictions += 1
        }
    }

    private func cacheKey(toolName: String, input: [String: AnyCodable]) -> String {
        "\(toolName):\(inputHash(input))"
    }

    private func inputHash(_ input: [String: AnyCodable]) -> String {
        let sorted = input.sorted { $0.key < $1.key }
        let str = sorted.map { "\($0.key)=\($0.value.value)" }.joined(separator: "&")
        var hash: UInt64 = 5381
        for byte in str.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}
