# Desktop Agent — Architecture

Native Swift macOS AI agent that controls the entire operating system. ~5800 lines.

## Project Structure

```
Sources/DesktopAgent/
├── CLI/                        # Terminal interface
│   ├── main.swift              # Entry point, slash commands, interactive loop
│   ├── LineEditor.swift        # Raw terminal input with tab completion & history
│   └── InteractivePicker.swift # TUI model selector (↑/↓ navigate, Enter select)
│
├── Agent/                      # AI agent core
│   ├── AgentLoop.swift         # Main agent loop (30 max iterations)
│   ├── AIClient.swift          # Multi-provider API client (Anthropic + OpenAI format)
│   ├── ToolDefinitions.swift   # 36+ tool definitions for the AI
│   ├── ToolExecutor.swift      # Routes tool calls to drivers
│   ├── SubAgent.swift          # Parallel sub-agent execution (4 types)
│   ├── SelfImprove.swift       # Self-modification system (program.md, system prompt)
│   ├── PluginManager.swift     # Plugin system (markdown + YAML frontmatter)
│   └── MemoryManager.swift     # Persistent memory (markdown files)
│
├── Drivers/                    # macOS system interaction
│   ├── AppleScriptDriver.swift # osascript subprocess, app management
│   ├── AccessibilityDriver.swift # AXUIElement API, UI inspection, window mgmt
│   ├── KeyboardDriver.swift    # CGEvent keyboard/mouse/scroll/drag
│   ├── VisionDriver.swift      # CGDisplayCreateImage screenshots + downscaling
│   ├── ShellDriver.swift       # Process-based shell execution, Spotlight search
│   └── FileDriver.swift        # File read/write/list/info operations
│
├── MCP/                        # Model Context Protocol
│   ├── MCPClient.swift         # JSON-RPC 2.0 over stdio
│   ├── MCPManager.swift        # Multi-server lifecycle management
│   └── MCPTypes.swift          # MCP types, AIProvider, AgentConfigFile
│
└── Models/                     # Shared types
    ├── AgentTypes.swift         # AgentConfig, ToolResult, UIElement, errors
    └── ClaudeTypes.swift        # API request/response types (Codable)
```

## Key Architecture Decisions

### Multi-Provider AI Support
8 providers supported: Anthropic, OpenAI, Google Gemini, Groq, Mistral, OpenRouter, DeepSeek, xAI.
- Anthropic uses its native API format
- All others use OpenAI-compatible format
- `AIClient` handles format conversion transparently
- API keys stored in `~/.desktop-agent/config.json` (0600 permissions)

### Sub-Agent System (Parallel Execution)
Inspired by Claude Code's agent spawning. 4 agent types:
- **explore**: Fast read-only research (shell, files). Max 8 iterations.
- **analyze**: Deep data analysis. Read-only, no GUI.
- **execute**: Full action capability (GUI, shell, AppleScript).
- **general**: All tools except spawning more sub-agents (prevents recursion).

Uses Swift `withTaskGroup` for true parallel execution. Parent context can be shared with children.

### Self-Improvement (Karpathy autoresearch inspired)
The agent can modify its own behavior:
- **program.md**: High-level instructions editable by agent or user
- **system-prompt.md**: Custom system prompt override
- **improvements.log**: Tracks what changes worked and what didn't
- **create_plugin**: Agent can create specialized plugins
- **modify_config**: Agent can adjust its own config (tokens, model, etc.)

Backups are created before modifications. System prompt can be reset to defaults.

### Tool System
36+ tools organized by category:
- **System**: AppleScript, Shell, Spotlight
- **App Management**: list/activate/open apps
- **UI**: Accessibility tree inspection
- **Input**: Mouse click/move/scroll/drag, keyboard type/press
- **Vision**: Screenshots with auto-downscaling
- **Windows**: List/move/resize
- **Files**: Read/write/list/info
- **Memory**: Persistent markdown storage
- **Self-Modification**: Program, system prompt, config, plugins
- **Sub-Agents**: Parallel task execution
- **MCP**: Dynamic tools from connected MCP servers

### CLI UX
- Raw terminal mode with custom line editor
- Tab autocompletion for all slash commands and sub-commands
- Command history (↑/↓ arrows)
- Readline keybindings (Ctrl+A/E/K/U/W)
- Interactive model picker with arrow key navigation
- API key format validation (detects wrong provider)
- Fuzzy command suggestion on typos
- Import keys from OpenClaw config

## Data Flow

```
User Input
    ↓
LineEditor (tab completion, history)
    ↓
Slash Command? ──yes──→ handleSlashCommand()
    ↓ no
AgentLoop.processUserInput()
    ↓
AIClient.sendMessage() ←──── system prompt + memory + program.md
    ↓
Parse response content
    ↓
Tool use? ──yes──→ ToolExecutor.execute()
    │                   ├── SelfModificationTools
    │                   ├── MCP tools
    │                   ├── Sub-agents (parallel)
    │                   └── Built-in drivers
    │                         ↓
    │               Tool result → back to AI
    ↓ no
Return final text response
```

## Configuration Files

```
~/.desktop-agent/
├── config.json         # API keys, active model, MCP servers, settings
├── program.md          # Agent behavior instructions (editable)
├── system-prompt.md    # Custom system prompt override (optional)
├── improvements.log    # Self-improvement history
├── plugins/            # Agent plugins (markdown + YAML frontmatter)
│   ├── web-researcher.md
│   ├── file-analyzer.md
│   ├── app-automator.md
│   └── coder.md
└── memory/             # Persistent memory files
    └── MEMORY.md
```

## Building & Running

```bash
swift build -c release
.build/release/DesktopAgent

# With specific model
.build/release/DesktopAgent --model openai/gpt-4o

# Single command mode
.build/release/DesktopAgent "open Safari and search for Swift tutorials"
```

## First Run

```
/config import-openclaw          # Import keys from OpenClaw
# or
/config set-key anthropic sk-ant-...
/config set-key openai sk-proj-...
/model list                      # Interactive model picker
```
