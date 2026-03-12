# Desktop Agent — Architecture

Native Swift macOS AI agent that controls the entire operating system. ~6000 lines, 41 source files.

## Project Structure

```
Sources/DesktopAgent/
├── CLI/                        # Terminal interface
│   ├── main.swift              # Entry point, 30+ slash commands, interactive loop
│   ├── LineEditor.swift        # Raw terminal: tab completion, history, readline keys
│   ├── InteractivePicker.swift # TUI model selector (↑/↓ navigate)
│   └── AsideMonitor.swift      # Type while agent works (aside injection)
│
├── Agent/                      # AI agent core
│   ├── AgentLoop.swift         # Main loop (30 iterations, tool routing, streaming)
│   ├── AIClient.swift          # Multi-provider API client (Anthropic + OpenAI format)
│   ├── ToolDefinitions.swift   # 50+ tool definitions for the AI
│   ├── ToolExecutor.swift      # Routes tool calls to drivers
│   ├── ToolOrchestrator.swift  # Markov chain prediction, result caching, batching
│   ├── ErrorRecovery.swift     # Error classification, retry with backoff, fallbacks
│   ├── AdaptiveResponseSystem.swift  # Coordinates context + UI + intent systems
│   ├── ContextDetector.swift   # Detects terminal/gateway/pipe/subagent context
│   ├── UIIntelligence.swift    # Caches app layouts, learns workflows
│   ├── IntentAnalyzer.swift    # Natural language intent → tool routing
│   ├── SubAgent.swift          # Parallel sub-agent execution (4 types)
│   ├── ApprovalSystem.swift    # Tool safety classification (safe/moderate/dangerous)
│   ├── ContextManager.swift    # Token tracking, auto-compaction at 75%
│   ├── SelfImprove.swift       # program.md, system prompt, plugin creation
│   ├── PluginManager.swift     # Plugin system (markdown + YAML frontmatter)
│   ├── SkillManager.swift      # Auto-activating contextual knowledge
│   ├── MemoryManager.swift     # Persistent markdown memory
│   └── TaskScheduler.swift     # launchd-based task scheduling + delivery
│
├── Drivers/                    # macOS system interaction
│   ├── AppleScriptDriver.swift # osascript subprocess, app management
│   ├── AccessibilityDriver.swift # AXUIElement API, UI inspection, window mgmt
│   ├── KeyboardDriver.swift    # CGEvent keyboard/mouse/scroll/drag
│   ├── VisionDriver.swift      # CGDisplayCreateImage screenshots + downscaling
│   ├── ShellDriver.swift       # Process-based shell execution, Spotlight search
│   └── FileDriver.swift        # File read/write/list/info operations
│
├── Gateway/                    # Multi-platform messaging bridge
│   ├── GatewayServer.swift     # Session management, per-chat message queue
│   ├── GatewayTypes.swift      # Protocol, config types, adapter interface
│   ├── DiscordAdapter.swift    # Discord Bot via WebSocket Gateway v10
│   ├── TelegramAdapter.swift   # Telegram Bot API long polling
│   ├── SlackAdapter.swift      # Slack Socket Mode via WebSocket
│   ├── WhatsAppAdapter.swift   # WhatsApp via wacli CLI
│   ├── SessionStore.swift      # Persistent session history with validation
│   └── DeliveryQueue.swift     # Disk-based delivery retry queue
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

### Gateway Architecture
Multi-platform messaging bridge with production-grade reliability:

```
Discord/Telegram/Slack/WhatsApp
         ↓ (adapter)
    GatewayServer
         ↓
    SessionQueue (actor — serializes per chat)
         ↓
    AgentLoop (one per chat, persistent)
         ↓
    onStreamText callback → adapter.sendMessage()
```

**Key design choices:**
- **Per-session actor queue**: Messages within the same chat are strictly serialized via `SessionQueue` actor. Different chats process concurrently.
- **Fire-and-forget pattern**: Adapters don't wait for responses. Responses stream back via `onStreamText` callback.
- **Session persistence**: `SessionStore` saves/loads conversation history per chat, with validation to prevent corrupted tool_result references.
- **Periodic typing**: Discord/Telegram typing indicators refresh every 8s (platforms auto-expire after ~5s).
- **Idle eviction**: Sessions unused for 4 hours are evicted. Checked every 10 minutes.

### Claude Code Delegation
Programming tasks are proxied to Claude Code CLI for access to the Claude subscription:

```
AgentLoop → handleClaudeCode()
  → Process(claude --dangerously-skip-permissions -p --output-format text "prompt")
  → setpgid() for process group management
  → Background pipe reader (DispatchQueue)
  → 3-second buffer flush to gateway
  → 10-minute DispatchSemaphore timeout
  → kill(-pid, SIGKILL) on timeout (kills entire process tree)
  → Reader gets 5s grace period, then pipe force-closed
```

### Tool Orchestrator
Markov chain (bigram + trigram) based tool prediction:
- Predicts likely next tools based on usage patterns
- Result caching with TTL and invalidation rules
- Batching hints for parallel tool execution
- Persists patterns to disk for cross-session learning

### Error Recovery
Automatic error handling with classification and strategies:
- **Categories**: Network, permission, tool error, AI error, rate limit, timeout
- **Retry**: Exponential backoff with jitter
- **Fallbacks**: `run_shell` ↔ `run_applescript`, UI interaction → screenshot verification
- **Preflight checks**: Validates tool inputs before execution

### Adaptive Response System
Coordinates three subsystems:
- **ContextDetector**: Detects terminal/gateway/pipe/subagent, adjusts output format and length
- **UIIntelligence**: Caches app layouts, element positions, learned workflows
- **IntentAnalyzer**: Maps natural language to tool recommendations with app-specific profiles

### Sub-Agent System (Parallel Execution)
Inspired by Claude Code's agent spawning. 4 agent types:
- **explore**: Fast read-only research (shell, files). Max 8 iterations.
- **analyze**: Deep data analysis. Read-only, no GUI.
- **execute**: Full action capability (GUI, shell, AppleScript).
- **general**: All tools except spawning more sub-agents (prevents recursion).

Uses Swift `withTaskGroup` for true parallel execution.

### Self-Improvement
The agent can modify its own behavior:
- **program.md**: High-level instructions editable by agent or user
- **system-prompt.md**: Custom system prompt override
- **improvements.log**: Tracks what changes worked and what didn't
- **Source protection**: Cannot modify `Sources/` directly, must use `claude_code`

### Tool System
50+ tools organized by category:
- **System**: AppleScript, Shell, Spotlight
- **App Management**: list/activate/open/frontmost apps
- **UI**: Accessibility tree inspection with max_depth
- **Input**: Mouse click/move/scroll/drag, keyboard type/press
- **Vision**: Screenshots with auto-downscaling and region capture
- **Windows**: List/move/resize
- **Files**: Read/write/list/info
- **Clipboard**: Read/write
- **Memory**: Persistent markdown storage
- **Self-Modification**: Program, system prompt, config, plugins
- **Sub-Agents**: Parallel task execution (4 types)
- **MCP**: Dynamic tools from connected MCP servers
- **Orchestrator**: Stats, insights, cache management
- **Adaptive**: Stats, UI cache lookup, cache clear
- **Gateway**: Configure platforms, import config
- **Scheduler**: Schedule/list/cancel/run tasks
- **Claude Code**: Delegate programming to Claude Code CLI

## Data Flow

```
User Input (terminal / gateway / pipe)
    ↓
Context Detection (terminal? gateway? pipe? subagent?)
    ↓
Slash Command? ──yes──→ handleSlashCommand()
    ↓ no
Intent Analysis (category, suggested tools, app context)
    ↓
AgentLoop.processUserInput()
    ↓
Memory + Skills + Adaptive Context → System Prompt
    ↓
AIClient.sendMessage() ←──── auto-retry on transient errors
    ↓
Parse response content
    ↓
Tool use? ──yes──→ Approval Check → Preflight Check
    │                   ↓
    │              Orchestrator Cache Hit? → return cached
    │                   ↓ no
    │              ToolExecutor.execute()
    │                   ├── Claude Code (process spawn + streaming)
    │                   ├── Sub-agents (parallel TaskGroup)
    │                   ├── MCP tools (JSON-RPC)
    │                   ├── Gateway tools (config management)
    │                   ├── Scheduler tools (launchd)
    │                   └── Built-in drivers
    │                         ↓
    │               Error? → ErrorRecovery (retry/fallback)
    │                         ↓
    │               Record in Orchestrator → back to AI
    ↓ no (end_turn)
onStreamText → gateway adapter → platform API
    ↓
Return final text response
```

## Configuration Files

```
~/.desktop-agent/
├── config.json          # API keys, model, MCP servers, gateway config, settings
├── program.md           # Agent behavior instructions (editable)
├── system-prompt.md     # Custom system prompt override (optional)
├── improvements.log     # Self-improvement history
├── plugins/             # Agent plugins (markdown + YAML frontmatter)
├── skills/              # Auto-activating knowledge files
├── tasks/               # Scheduled task definitions (launchd plists)
├── sessions/            # Gateway session history (JSON per chat)
├── memory/              # Persistent memory files
├── ui-cache/            # Cached app layouts, workflows, patterns (JSON)
└── delivery-queue/      # Pending gateway deliveries (retry queue)
```

## Building & Running

```bash
# Debug build
swift build

# Release build
swift build -c release

# Install globally
cp .build/release/DesktopAgent /usr/local/bin/osai
codesign --force --sign - /usr/local/bin/osai

# Run
osai                              # Interactive mode
osai "command"                    # Single command
osai gateway                     # Start messaging bridge
osai --model google/gemini "hi"  # Specific model
osai --verbose "debug this"      # Verbose output
```

> **Important**: Binary must be re-signed after `cp` or macOS kills it (SIGKILL).
