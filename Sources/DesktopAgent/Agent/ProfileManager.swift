import Foundation

// MARK: - Profile System
// Profiles are markdown files in ~/.desktop-agent/profiles/ that get appended to the system prompt.
// Each profile tailors the agent's behavior for different tasks (coding, creative, research, etc.)

struct ProfileManager {
    static let profilesDir = NSHomeDirectory() + "/.desktop-agent/profiles"

    // MARK: - Load profile content

    /// Load the content of a named profile (without .md extension)
    static func load(name: String) -> String? {
        let path = profilesDir + "/\(name).md"
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    /// List all available profile names (sorted)
    static func listProfiles() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: profilesDir) else {
            return []
        }
        return files
            .filter { $0.hasSuffix(".md") }
            .map { String($0.dropLast(3)) }
            .sorted()
    }

    /// Check if a profile exists
    static func exists(name: String) -> Bool {
        FileManager.default.fileExists(atPath: profilesDir + "/\(name).md")
    }

    /// Get the full path for a profile
    static func path(for name: String) -> String {
        profilesDir + "/\(name).md"
    }

    // MARK: - Install defaults

    /// Install built-in profile templates if the profiles directory doesn't exist yet
    static func installDefaults() {
        let fm = FileManager.default
        // Only install if the directory doesn't exist at all
        guard !fm.fileExists(atPath: profilesDir) else { return }

        try? fm.createDirectory(atPath: profilesDir, withIntermediateDirectories: true)

        let templates: [(String, String)] = [
            ("default", defaultProfile),
            ("coding", codingProfile),
            ("creative", creativeProfile),
        ]

        for (name, content) in templates {
            let path = profilesDir + "/\(name).md"
            if !fm.fileExists(atPath: path) {
                try? content.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - Built-in profile templates

    private static let defaultProfile = """
    ## Profile: Default

    You are a general-purpose assistant. Balance efficiency with thoroughness.
    Adapt your communication style to the user's needs — be concise for quick tasks,
    detailed for complex ones. Use the best tool for each job.
    """

    private static let codingProfile = """
    ## Profile: Coding

    You are a senior software engineer. Focus on:
    - Writing clean, maintainable, well-tested code
    - Following language idioms and best practices
    - Preferring simple solutions over clever ones
    - Explaining architectural decisions briefly
    - Using shell/CLI tools for file operations, git, builds
    - Running tests after changes when possible

    Communication style: terse, technical. Skip pleasantries.
    Use code blocks with language tags. Show diffs when modifying existing code.
    Prefer `run_shell` and `read_file`/`write_file` over GUI automation.
    """

    private static let creativeProfile = """
    ## Profile: Creative

    You are a creative collaborator. Focus on:
    - Brainstorming freely without premature judgment
    - Offering multiple options and variations
    - Building on ideas iteratively
    - Using vivid, engaging language
    - Creating visual content when appropriate (SVG, images, design files)

    Communication style: expressive, enthusiastic, exploratory.
    Ask clarifying questions about aesthetic preferences and creative direction.
    When generating content, provide 2-3 variations when the user hasn't specified exact requirements.
    """
}
