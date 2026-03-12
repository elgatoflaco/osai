import Foundation
import CoreGraphics

// MARK: - UI Intelligence
// Learns and caches app layouts, UI patterns, and element positions.
// Optimizes interactions based on learned patterns from successful actions.

final class UIIntelligence {

    // MARK: - Types

    /// A cached UI element with its position and identifiers
    struct CachedElement: Codable {
        let role: String
        let title: String?
        let centerX: Int
        let centerY: Int
        let width: Int
        let height: Int
        let actions: [String]
        var hitCount: Int       // How many times we've interacted with this
        var lastSeen: Date
        var lastSuccess: Date?  // Last time clicking this succeeded
    }

    /// Cached layout for an app
    struct AppLayout: Codable {
        let appName: String
        let bundleId: String?
        var elements: [String: CachedElement]  // Key: "role:title" or "role:position"
        var workflows: [CachedWorkflow]
        var lastUpdated: Date
        var windowBounds: CachedRect?
    }

    /// Cached rectangle (CGRect isn't Codable)
    struct CachedRect: Codable {
        let x: Double, y: Double, width: Double, height: Double

        init(from rect: CGRect) {
            x = Double(rect.origin.x)
            y = Double(rect.origin.y)
            width = Double(rect.size.width)
            height = Double(rect.size.height)
        }
    }

    /// A learned sequence of actions that achieves a goal
    struct CachedWorkflow: Codable {
        let name: String                // e.g., "open_new_tab", "save_file"
        let steps: [WorkflowStep]
        var successCount: Int
        var failCount: Int
        var lastUsed: Date
        var avgDurationMs: Int

        var reliability: Double {
            let total = successCount + failCount
            return total > 0 ? Double(successCount) / Double(total) : 0
        }
    }

    /// A single step in a workflow
    struct WorkflowStep: Codable {
        let toolName: String            // "click_element", "press_key", etc.
        let parameters: [String: String] // Simplified params for matching
        let waitAfterMs: Int?
    }

    /// A recognized UI pattern (e.g., "file dialog", "search bar")
    struct UIPattern: Codable {
        let name: String
        let indicators: [String]         // UI element titles/roles that identify this pattern
        let suggestedActions: [String]   // Tool names commonly used with this pattern
        var confidence: Double
    }

    // MARK: - Constants

    private static let cacheDir = NSHomeDirectory() + "/.desktop-agent/ui-cache"
    private static let maxCachedApps = 50
    private static let maxElementsPerApp = 200
    private static let elementStaleDays = 30.0

    // MARK: - State

    private var layoutCache: [String: AppLayout] = [:]  // Key: appName.lowercased()
    private var knownPatterns: [UIPattern] = []
    private var activeWorkflow: (name: String, steps: [WorkflowStep], currentStep: Int)?

    // MARK: - Init

    init() {
        ensureCacheDir()
        loadKnownPatterns()
    }

    // MARK: - Layout Caching

    /// Record UI elements for an app, building up the layout cache
    func recordElements(appName: String, bundleId: String?, elements: [UIElement], windowBounds: CGRect?) {
        let key = appName.lowercased()
        var layout = layoutCache[key] ?? AppLayout(
            appName: appName, bundleId: bundleId,
            elements: [:], workflows: [],
            lastUpdated: Date(), windowBounds: nil
        )

        // Update window bounds if provided
        if let bounds = windowBounds {
            layout.windowBounds = CachedRect(from: bounds)
        }

        // Cache each element
        for element in flattenElements(elements) {
            guard let pos = element.position, let size = element.size else { continue }
            let elementKey = makeElementKey(element)

            let cached = CachedElement(
                role: element.role,
                title: element.title,
                centerX: Int(pos.x + size.width / 2),
                centerY: Int(pos.y + size.height / 2),
                width: Int(size.width),
                height: Int(size.height),
                actions: element.actions,
                hitCount: layout.elements[elementKey]?.hitCount ?? 0,
                lastSeen: Date(),
                lastSuccess: layout.elements[elementKey]?.lastSuccess
            )

            layout.elements[elementKey] = cached
        }

        // Trim old elements if over limit
        if layout.elements.count > Self.maxElementsPerApp {
            let cutoff = Date().addingTimeInterval(-Self.elementStaleDays * 86400)
            layout.elements = layout.elements.filter { $0.value.lastSeen > cutoff }

            // If still over, keep most recently seen
            if layout.elements.count > Self.maxElementsPerApp {
                let sorted = layout.elements.sorted { $0.value.lastSeen > $1.value.lastSeen }
                layout.elements = Dictionary(uniqueKeysWithValues: sorted.prefix(Self.maxElementsPerApp).map { ($0.key, $0.value) })
            }
        }

        layout.lastUpdated = Date()
        layoutCache[key] = layout
    }

    /// Record a successful interaction with a UI element
    func recordInteraction(appName: String, elementRole: String, elementTitle: String?, x: Int, y: Int, success: Bool) {
        let key = appName.lowercased()
        guard var layout = layoutCache[key] else { return }

        // Find the closest matching element
        let elementKey = "\(elementRole):\(elementTitle ?? "")"
        if var element = layout.elements[elementKey] {
            element.hitCount += 1
            if success {
                element.lastSuccess = Date()
            }
            layout.elements[elementKey] = element
        }

        layoutCache[key] = layout
    }

    /// Get cached element positions for an app (avoids needing get_ui_elements)
    func getCachedLayout(appName: String) -> AppLayout? {
        let key = appName.lowercased()
        guard let layout = layoutCache[key] else { return nil }

        // Only return if reasonably fresh (within 5 minutes)
        guard Date().timeIntervalSince(layout.lastUpdated) < 300 else { return nil }
        return layout
    }

    /// Find a cached element by role and/or title
    func findElement(appName: String, role: String? = nil, titleContains: String? = nil) -> CachedElement? {
        let key = appName.lowercased()
        guard let layout = layoutCache[key] else { return nil }

        return layout.elements.values.first { elem in
            var matches = true
            if let r = role { matches = matches && elem.role == r }
            if let t = titleContains {
                matches = matches && (elem.title?.lowercased().contains(t.lowercased()) ?? false)
            }
            return matches
        }
    }

    /// Get the most frequently interacted elements for an app
    func getHotElements(appName: String, limit: Int = 10) -> [CachedElement] {
        let key = appName.lowercased()
        guard let layout = layoutCache[key] else { return [] }

        return layout.elements.values
            .filter { $0.hitCount > 0 }
            .sorted { $0.hitCount > $1.hitCount }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Workflow Learning

    /// Record a successful multi-step workflow
    func recordWorkflow(appName: String, name: String, steps: [WorkflowStep], durationMs: Int, success: Bool) {
        let key = appName.lowercased()
        guard var layout = layoutCache[key] else { return }

        if let idx = layout.workflows.firstIndex(where: { $0.name == name }) {
            // Update existing workflow
            var wf = layout.workflows[idx]
            if success {
                wf.successCount += 1
            } else {
                wf.failCount += 1
            }
            wf.avgDurationMs = (wf.avgDurationMs + durationMs) / 2
            wf.lastUsed = Date()
            layout.workflows[idx] = wf
        } else {
            // New workflow
            layout.workflows.append(CachedWorkflow(
                name: name,
                steps: steps,
                successCount: success ? 1 : 0,
                failCount: success ? 0 : 1,
                lastUsed: Date(),
                avgDurationMs: durationMs
            ))
        }

        // Keep only the 20 most reliable workflows
        if layout.workflows.count > 20 {
            layout.workflows.sort { $0.reliability > $1.reliability }
            layout.workflows = Array(layout.workflows.prefix(20))
        }

        layoutCache[key] = layout
    }

    /// Look up a cached workflow for an app
    func findWorkflow(appName: String, name: String) -> CachedWorkflow? {
        let key = appName.lowercased()
        guard let layout = layoutCache[key] else { return nil }
        return layout.workflows.first { $0.name.lowercased().contains(name.lowercased()) && $0.reliability > 0.5 }
    }

    // MARK: - Pattern Recognition

    /// Detect UI patterns from current elements
    func detectPatterns(elements: [UIElement]) -> [UIPattern] {
        let titles = flattenElements(elements).compactMap { $0.title?.lowercased() }
        let roles = flattenElements(elements).map { $0.role.lowercased() }
        let allIndicators = Set(titles + roles)

        return knownPatterns.filter { pattern in
            let matches = pattern.indicators.filter { allIndicators.contains($0.lowercased()) }
            return Double(matches.count) / Double(max(pattern.indicators.count, 1)) > 0.5
        }
    }

    /// Get suggested tools based on detected patterns
    func suggestedTools(for patterns: [UIPattern]) -> [String] {
        var tools: [String: Double] = [:]
        for pattern in patterns {
            for tool in pattern.suggestedActions {
                tools[tool, default: 0] += pattern.confidence
            }
        }
        return tools.sorted { $0.value > $1.value }.map { $0.key }
    }

    // MARK: - Persistence

    /// Save all cached layouts to disk
    func saveCache() {
        for (key, layout) in layoutCache {
            let path = Self.cacheDir + "/\(key).json"
            do {
                let data = try JSONEncoder().encode(layout)
                try data.write(to: URL(fileURLWithPath: path))
            } catch {
                // Silent failure — cache is a nice-to-have
            }
        }
    }

    /// Load a specific app's cached layout from disk
    func loadCachedLayout(appName: String) -> AppLayout? {
        let key = appName.lowercased()
        if let cached = layoutCache[key] { return cached }

        let path = Self.cacheDir + "/\(key).json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let layout = try? JSONDecoder().decode(AppLayout.self, from: data) else { return nil }

        layoutCache[key] = layout
        return layout
    }

    /// Clear all caches
    func clearCache() {
        layoutCache.removeAll()
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: Self.cacheDir) {
            for file in files where file.hasSuffix(".json") && file != "patterns.json" {
                try? fm.removeItem(atPath: Self.cacheDir + "/" + file)
            }
        }
    }

    /// Get cache stats
    var stats: String {
        let apps = layoutCache.count
        let totalElements = layoutCache.values.reduce(0) { $0 + $1.elements.count }
        let totalWorkflows = layoutCache.values.reduce(0) { $0 + $1.workflows.count }
        return "UI Intelligence: \(apps) apps cached, \(totalElements) elements, \(totalWorkflows) workflows"
    }

    // MARK: - Helpers

    private func flattenElements(_ elements: [UIElement]) -> [UIElement] {
        var flat: [UIElement] = []
        for el in elements {
            flat.append(el)
            flat.append(contentsOf: flattenElements(el.children))
        }
        return flat
    }

    private func makeElementKey(_ element: UIElement) -> String {
        if let title = element.title, !title.isEmpty {
            return "\(element.role):\(title)"
        }
        if let pos = element.position {
            return "\(element.role):(\(Int(pos.x)),\(Int(pos.y)))"
        }
        return "\(element.role):unknown"
    }

    private func ensureCacheDir() {
        try? FileManager.default.createDirectory(
            atPath: Self.cacheDir,
            withIntermediateDirectories: true
        )
    }

    private func loadKnownPatterns() {
        // Built-in UI patterns that the system recognizes
        knownPatterns = [
            UIPattern(
                name: "file_dialog",
                indicators: ["save", "open", "choose", "cancel", "filename", "file name", "AXSheet"],
                suggestedActions: ["type_text", "click_element", "press_key"],
                confidence: 0.8
            ),
            UIPattern(
                name: "search_bar",
                indicators: ["search", "find", "filter", "AXSearchField", "AXTextField"],
                suggestedActions: ["click_element", "type_text"],
                confidence: 0.7
            ),
            UIPattern(
                name: "alert_dialog",
                indicators: ["ok", "cancel", "yes", "no", "confirm", "delete", "AXSheet", "AXDialog"],
                suggestedActions: ["click_element", "press_key"],
                confidence: 0.85
            ),
            UIPattern(
                name: "text_editor",
                indicators: ["AXTextArea", "AXScrollArea", "AXTextView", "editor", "document"],
                suggestedActions: ["type_text", "press_key", "click_element"],
                confidence: 0.7
            ),
            UIPattern(
                name: "navigation_bar",
                indicators: ["back", "forward", "reload", "AXToolbar", "AXNavigationBar", "address"],
                suggestedActions: ["click_element", "type_text"],
                confidence: 0.75
            ),
            UIPattern(
                name: "menu_bar",
                indicators: ["AXMenuBar", "AXMenu", "AXMenuItem", "file", "edit", "view", "window", "help"],
                suggestedActions: ["click_element", "press_key"],
                confidence: 0.9
            ),
            UIPattern(
                name: "tab_bar",
                indicators: ["AXTabGroup", "AXTab", "tab"],
                suggestedActions: ["click_element"],
                confidence: 0.8
            ),
        ]

        // Load user-learned patterns from disk
        let path = Self.cacheDir + "/patterns.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let learned = try? JSONDecoder().decode([UIPattern].self, from: data) {
            knownPatterns.append(contentsOf: learned)
        }
    }
}
