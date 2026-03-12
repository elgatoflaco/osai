# osai — AI-Powered macOS Desktop Agent

Native Swift CLI agent that controls your entire macOS desktop. 50+ tools, 8 AI providers, 4 messaging gateways, self-improvement, sub-agents, MCP support.

## Quick Start

```bash
# Build
swift build -c release
cp .build/release/DesktopAgent /usr/local/bin/osai
codesign --force --sign - /usr/local/bin/osai

# First run — set up an API key
osai
/config set-key anthropic sk-ant-...
# or import from OpenClaw
/config import-openclaw

# Use it
osai "take a screenshot and describe what you see"
osai "open Safari and search for Swift tutorials"
echo "list my files" | osai
```

## Features

### Desktop Control (50+ tools)
- **GUI Automation**: Click, type, scroll, drag via Accessibility API + CGEvents
- **App Management**: Launch, activate, list, inspect any application
- **UI Inspection**: Full accessibility tree with element roles, titles, actions
- **Screenshots**: Region capture with auto-downscaling for AI vision
- **Window Management**: Move, resize, list all visible windows
- **File Operations**: Read, write, list, info with path resolution
- **Shell Execution**: Run any zsh command with timeout and streaming
- **AppleScript**: Execute arbitrary AppleScript for deep macOS integration
- **Spotlight**: Search files, apps, documents via macOS Spotlight
- **Clipboard**: Read and write clipboard contents
- **Keyboard**: Type text and press shortcuts (cmd+c, ctrl+a, etc.)

### Multi-Provider AI
8 providers supported out of the box:

| Provider | Format | Models |
|----------|--------|--------|
| Anthropic | Native | Claude Sonnet, Opus, Haiku |
| OpenAI | OpenAI | GPT-4o, GPT-4 Turbo |
| Google | OpenAI | Gemini Pro, Flash |
| Groq | OpenAI | Llama, Mixtral |
| Mistral | OpenAI | Mistral Large, Medium |
| OpenRouter | OpenAI | Any model via routing |
| DeepSeek | OpenAI | DeepSeek Chat, Coder |
| xAI | OpenAI | Grok |

```bash
osai --model openai/gpt-4o "explain this code"
osai --model google/gemini-2.0-flash "summarize this"
/model list   # Interactive picker inside the CLI
```

### Multi-Platform Gateway
Bridge osai to messaging platforms. Each chat gets its own persistent agent session.

```bash
osai gateway   # Starts all configured adapters
```

**Supported platforms:**

| Platform | Transport | Config |
|----------|-----------|--------|
| Telegram | Bot API long polling | `bot_token` |
| Discord | WebSocket Gateway v10 | `bot_token` |
| Slack | Socket Mode WebSocket | `bot_token` + `app_token` |
| WhatsApp | wacli CLI polling | `wacli auth` |

**Gateway features:**
- Per-chat message serialization (no race conditions)
- Persistent session history across restarts
- Real-time streaming of agent responses
- Periodic typing indicator (Discord/Telegram refresh every 8s)
- User/channel whitelists for security
- Automatic session eviction after 4h idle
- Task scheduling with automatic delivery back to chat
- Platform-aware message chunking (2000 chars Discord, 4096 Telegram, etc.)

**Configuration** (`~/.desktop-agent/config.json`):
```json
{
  "gateways": {
    "discord": {
      "enabled": true,
      "bot_token": "your-bot-token",
      "allowed_users": ["your-discord-user-id"]
    },
    "telegram": {
      "enabled": true,
      "bot_token": "123456:ABC-DEF...",
      "allowed_users": [123456789]
    }
  }
}
```

### Claude Code Delegation
osai delegates programming tasks to [Claude Code CLI](https://claude.ai/claude-code), giving it access to the full $200/month Claude subscription for coding.

- Real-time stdout streaming to gateway
- 10-minute timeout with process group kill
- Source code protection: osai cannot modify its own `Sources/` directory
- Automatic `/dev/null` stdin to prevent SIGTSTP in background

```
# Inside osai or via gateway:
"refactor the auth module to use async/await"
→ Agent calls claude_code tool → Claude Code does the work → results streamed back
```

### Sub-Agents (Parallel Execution)
The agent can spawn sub-agents for parallel work:

| Type | Capabilities | Max Iterations |
|------|-------------|----------------|
| `explore` | Read-only research (shell, files) | 8 |
| `analyze` | Deep data analysis, no GUI | 8 |
| `execute` | Full action capability | 15 |
| `general` | All tools except spawning more agents | 15 |

### Self-Improvement
Inspired by Karpathy's autoresearch concept:

```bash
/improve focus:speed         # Agent improves itself
/program show                # View current behavior instructions
/program edit                # Open in $EDITOR
/program log                 # View improvement history
```

- `program.md`: High-level behavior instructions (editable by agent or user)
- `system-prompt.md`: Custom system prompt override
- `improvements.log`: Tracks what changes worked
- Auto-backup before modifications

### Adaptive Intelligence

**Tool Orchestrator**: Markov chain prediction of next tools, result caching with TTL, batching hints for parallel operations.

**Error Recovery**: Classifies errors (network, permission, tool, AI), auto-retry with exponential backoff, fallback chains (shell ↔ AppleScript, UI → screenshot).

**UI Intelligence**: Caches app layouts and element positions, learns workflows from successful multi-step actions, pattern recognition for common UI states (file dialogs, search bars, alerts).

**Context Detector**: Detects execution context (terminal, gateway, pipe, sub-agent) and adapts output format and length automatically.

**Intent Analyzer**: Keyword-based intent classification with app-specific tool recommendations and shortcut knowledge.

### MCP (Model Context Protocol)
Dynamically extend the agent with external tool servers:

```bash
/mcp add github npx -y @anthropic/github-mcp
/mcp add filesystem npx -y @anthropic/filesystem-mcp /path
/mcp list
```

The agent can also auto-install MCPs when it determines it needs a capability it doesn't have.

### Plugin System
Specialized agents with custom system prompts and optional model overrides:

```bash
/plugin list                          # Built-in: web-researcher, file-analyzer, app-automator, coder
/plugin run web-researcher "find React best practices 2025"
/plugin create my-plugin "Custom description"
```

### Skill System
Context-injected knowledge that auto-activates based on trigger keywords:

```bash
/skill list
/skill show deploy
# Skills are markdown files at ~/.desktop-agent/skills/<name>.md
```

### Task Scheduling
Schedule recurring or one-off tasks via macOS LaunchAgents:

```bash
# Inside osai:
"every day at 8am check my email and send me a summary on Telegram"
"in 30 minutes remind me to call John"
/task list
/task cancel task-id
```

Tasks run osai in headless mode and deliver results to the originating gateway chat.

### Memory System
Persistent markdown-based memory:

```bash
/memory list
/memory write preferences "User prefers dark mode and vim keybindings"
/memory read preferences
```

## Interactive Commands Reference

| Command | Description |
|---------|-------------|
| `/help` | Show help |
| `/clear` | Clear conversation |
| `/quit` | Exit (also `/exit`, `/q`, Ctrl+D) |
| `/config list` | Show API keys and settings |
| `/config set-key <provider> <key>` | Save API key |
| `/config remove-key <provider>` | Remove API key |
| `/config set-url <provider> <url>` | Custom endpoint |
| `/config import-openclaw` | Import from OpenClaw |
| `/model show` | Show current model |
| `/model list` | Interactive model picker |
| `/model use <provider/model>` | Switch model |
| `/mcp list` | Show MCP servers |
| `/mcp add <name> <cmd> [args]` | Add MCP server |
| `/mcp remove <name>` | Remove MCP server |
| `/mcp start\|stop <name>` | Control MCP server |
| `/plugin list` | List plugins |
| `/plugin run <name> <task>` | Run plugin |
| `/plugin create <name> <desc>` | Create plugin |
| `/memory list\|read\|write\|delete` | Manage memory |
| `/skill list\|show\|delete` | Manage skills |
| `/task list` | List scheduled tasks |
| `/task cancel <id>` | Cancel task |
| `/context` | Token usage & stats |
| `/compact` | Compaction info |
| `/yolo` | Toggle auto-approve |
| `/program show\|edit\|log\|prompt\|reset` | Self-improvement |
| `/improve [focus]` | Ask agent to improve itself |
| `/apps` | List running apps |
| `/windows` | List visible windows |
| `/screen` | Take screenshot |
| `/perms` | Check permissions |
| `/verbose` | Toggle verbose mode |

## Architecture

```
Sources/DesktopAgent/
├── CLI/                        # Terminal interface
│   ├── main.swift              # Entry point, 30+ slash commands, interactive loop
│   ├── LineEditor.swift        # Raw terminal: tab completion, history, readline keys
│   ├── InteractivePicker.swift # TUI model selector (↑/↓ navigate)
│   └── AsideMonitor.swift      # Type while agent works (aside injection)
│
├── Agent/                      # AI agent core
│   ├── AgentLoop.swift         # Main loop (30 iterations max, tool routing)
│   ├── AIClient.swift          # Multi-provider API client
│   ├── ToolDefinitions.swift   # 50+ tool schemas for the AI
│   ├── ToolExecutor.swift      # Routes tool calls to drivers
│   ├── ToolOrchestrator.swift  # Markov prediction, caching, batching
│   ├── ErrorRecovery.swift     # Error classification, retry, fallbacks
│   ├── AdaptiveResponseSystem.swift  # Coordinates context+UI+intent
│   ├── ContextDetector.swift   # Terminal/gateway/pipe detection
│   ├── UIIntelligence.swift    # Layout caching, workflow learning
│   ├── IntentAnalyzer.swift    # Natural language → tool routing
│   ├── SubAgent.swift          # Parallel sub-agent execution
│   ├── ApprovalSystem.swift    # Tool safety classification
│   ├── ContextManager.swift    # Token tracking, compaction
│   ├── SelfImprove.swift       # program.md, system prompt, plugins
│   ├── PluginManager.swift     # Plugin lifecycle
│   ├── SkillManager.swift      # Skill auto-activation
│   ├── MemoryManager.swift     # Persistent memory
│   └── TaskScheduler.swift     # launchd task scheduling
│
├── Drivers/                    # macOS system interaction
│   ├── AccessibilityDriver.swift  # AXUIElement API
│   ├── AppleScriptDriver.swift    # osascript subprocess
│   ├── KeyboardDriver.swift       # CGEvent keyboard/mouse
│   ├── VisionDriver.swift         # Screenshots + downscaling
│   ├── ShellDriver.swift          # Process execution, Spotlight
│   └── FileDriver.swift           # File operations
│
├── Gateway/                    # Multi-platform messaging
│   ├── GatewayServer.swift     # Session management, message serialization
│   ├── GatewayTypes.swift      # Protocol, config types, adapter interface
│   ├── DiscordAdapter.swift    # Discord WebSocket Gateway v10
│   ├── TelegramAdapter.swift   # Telegram Bot API long polling
│   ├── SlackAdapter.swift      # Slack Socket Mode WebSocket
│   ├── WhatsAppAdapter.swift   # WhatsApp via wacli CLI
│   ├── SessionStore.swift      # Persistent session history
│   └── DeliveryQueue.swift     # Disk-based delivery retry queue
│
├── MCP/                        # Model Context Protocol
│   ├── MCPClient.swift         # JSON-RPC 2.0 over stdio
│   ├── MCPManager.swift        # Multi-server lifecycle
│   └── MCPTypes.swift          # Types, AIProvider, config
│
└── Models/                     # Shared types
    ├── AgentTypes.swift         # AgentConfig, ToolResult, UIElement
    └── ClaudeTypes.swift        # API request/response types
```

**41 Swift source files, ~6000 lines of code.**

## Configuration Files

```
~/.desktop-agent/
├── config.json          # API keys, active model, MCP servers, gateway config
├── program.md           # Agent behavior instructions
├── system-prompt.md     # Custom system prompt override (optional)
├── improvements.log     # Self-improvement history
├── plugins/             # Agent plugins (markdown + YAML frontmatter)
├── skills/              # Auto-activating knowledge files
├── tasks/               # Scheduled task definitions (launchd plists)
├── sessions/            # Gateway session history (JSON)
├── memory/              # Persistent memory files
├── ui-cache/            # Cached app layouts and workflows
└── delivery-queue/      # Pending gateway deliveries
```

## Requirements

- macOS 13+ (Ventura or later)
- Swift 5.9+
- Accessibility permissions (System Settings → Privacy → Accessibility)
- Screen Recording permission (for screenshots)
- At least one AI provider API key

## Building

```bash
# Debug build
swift build

# Release build (optimized)
swift build -c release

# Install
cp .build/release/DesktopAgent /usr/local/bin/osai
codesign --force --sign - /usr/local/bin/osai
```

> **Note**: The binary must be re-signed with `codesign` after copying, or macOS will kill it with SIGKILL.

## Usage Examples

### Desktop Automation
```bash
osai "open Finder, go to Downloads, and delete files older than 30 days"
osai "take a screenshot and tell me what apps are open"
osai "open System Settings and enable Dark Mode"
osai "resize the front window to 1200x800 and move it to center"
```

### File Operations
```bash
osai "find all TODO comments in my project"
osai "create a summary of all markdown files in ~/Documents"
echo "organize my Desktop by file type" | osai
```

### Gateway Chat (via Discord/Telegram)
```
User: check my calendar for today
Bot: 📅 You have 3 events today: ...

User: every morning at 8am send me the weather
Bot: ✅ Scheduled daily task "weather briefing" at 08:00

User: refactor the login component to use hooks
Bot: 🧠 Delegating to Claude Code...
     [real-time streaming of Claude Code output]
     ✅ Done. Changed 3 files, added useAuth hook.
```

### Programming (via Claude Code delegation)
```bash
osai "add unit tests for the UserService class"
osai "fix the memory leak in the WebSocket handler"
osai "create a REST API endpoint for user registration"
```

### Task Scheduling
```bash
osai "every weekday at 9am check Hacker News and send me the top 5 stories on Telegram"
osai "in 2 hours remind me to review the PR"
osai "every hour check if the deploy finished and notify me"
```

## Security

### Gateway Whitelists
**Always configure user whitelists** for gateway platforms. Without them, anyone can send messages to your agent and it will execute commands on your machine.

```json
{
  "gateways": {
    "discord": {
      "enabled": true,
      "bot_token": "...",
      "allowed_users": ["your-user-id"],
      "allowed_guilds": ["your-server-id"]
    },
    "telegram": {
      "enabled": true,
      "bot_token": "...",
      "allowed_users": [123456789]
    }
  }
}
```

### Tool Approval System
Tools are classified by risk level:
- **Safe**: Read-only operations (read_file, list_directory, take_screenshot)
- **Moderate**: State-changing but reversible (write_file, type_text, click)
- **Dangerous**: System-level changes (run_shell, run_applescript, claude_code)

In interactive mode, dangerous tools require explicit approval. In gateway mode, all tools are auto-approved (the user whitelist is the security boundary).

### Source Code Protection
osai cannot modify its own source code directly. `write_file` and `run_shell` are blocked from writing to the `Sources/` directory. Programming tasks must go through the `claude_code` tool.

## License

MIT
