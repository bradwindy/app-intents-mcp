# App Intents MCP Server Design

**Date:** 2025-12-16
**Status:** Approved

## Overview

A Swift-based MCP server that discovers and executes raw App Intents from macOS applications, exposing them to AI assistants via the Model Context Protocol.

## Goals

- Expose all App Intents from installed macOS apps to AI assistants
- Execute intents directly and return results
- Package as `.mcpb` for easy installation
- Use Swift with modern best practices

## Architecture

```
┌─────────────────┐     stdio/JSON-RPC     ┌──────────────────────┐
│  Claude / AI    │◄─────────────────────►│  app-intents-mcp     │
│  Assistant      │                        │  (Swift binary)      │
└─────────────────┘                        └──────────┬───────────┘
                                                      │
                                           ┌──────────▼───────────┐
                                           │  Intent Discovery    │
                                           │  - Bundle inspection │
                                           │  - Private frameworks│
                                           │  - Shortcuts bridge  │
                                           └──────────┬───────────┘
                                                      │
                                           ┌──────────▼───────────┐
                                           │  Intent Execution    │
                                           │  - Direct invocation │
                                           │  - XPC services      │
                                           └──────────────────────┘
```

### Core Components

1. **MCP Transport Layer** — Handles stdio communication, JSON-RPC message parsing
2. **Intent Discovery Engine** — Scans apps, extracts intent metadata using multiple strategies
3. **Intent Executor** — Invokes intents and captures results
4. **Cache Manager** — Caches discovered intents for performance, refreshes on app changes

## Intent Discovery Strategy

Multi-layered approach, trying each method and merging results:

### Layer 1: App Bundle Inspection

- Scan `/Applications`, `~/Applications`, and `/System/Applications`
- Parse each app's `Info.plist` for `INIntentsSupported`, `NSExtension` entries
- Look for compiled `.intentdefinition` files and `Metadata.appintents` bundles
- Extract intent names, parameters, and descriptions

### Layer 2: Shortcuts Database

- Parse Shortcuts.app database at `~/Library/Shortcuts/`
- Extract intent metadata that Shortcuts has already discovered

### Layer 3: Private Framework Exploration

- Investigate `IntentsCore.framework`, `Shortcuts.framework`, `WorkflowKit.framework`
- Look for classes like `WFAppIntentDiscoveryService`
- Use runtime introspection to discover available APIs

### Discovery Output

```swift
struct DiscoveredIntent {
    let id: String              // Unique identifier
    let appBundleID: String     // Source app
    let name: String            // Human-readable name
    let description: String?    // What it does
    let parameters: [Parameter] // Input parameters
    let returnsResult: Bool     // Whether it returns data
}
```

Intents are cached and indexed. Cache refreshes when apps are installed/updated (via FSEvents monitoring).

## Intent Execution Strategy

Execution strategies in order of preference:

### Strategy 1: Shortcuts CLI Bridge

- Create a minimal Shortcut wrapper on-the-fly
- Execute via `shortcuts run` CLI
- Pros: Uses supported system mechanisms
- Cons: Requires creating/managing temporary shortcuts

### Strategy 2: XPC Service Invocation

- Locate the app's intent-handling XPC service
- Send properly formatted XPC messages directly
- Requires reverse-engineering message format

### Strategy 3: NSUserActivity / Handoff

- Trigger intents via `NSUserActivity`
- Limited to intents that support this mechanism

### Strategy 4: AppleScript/JXA Bridge

- For apps with AppleScript support, bridge through scripting
- Fallback for apps where direct invocation fails

### Execution Result

```swift
struct IntentResult {
    let success: Bool
    let output: Any?          // Returned data (if any)
    let error: String?        // Error message (if failed)
    let executionTime: Double // How long it took
}
```

Strategy success is cached per-intent to optimize future calls.

## MCP Interface

### Tools

| Tool | Description |
|------|-------------|
| `list_intents` | List all discovered intents, optionally filtered by app |
| `search_intents` | Search intents by name, description, or capability |
| `get_intent` | Get detailed info about a specific intent |
| `run_intent` | Execute an intent with provided parameters |
| `refresh_intents` | Force re-scan of installed apps |

**Example tool call:**

```json
{
  "name": "run_intent",
  "arguments": {
    "intent_id": "com.apple.reminders.CreateReminder",
    "parameters": {
      "title": "Buy groceries",
      "dueDate": "2024-01-15T10:00:00Z",
      "list": "Shopping"
    }
  }
}
```

### Resources

- `intent://` — Root listing of all apps with intents
- `intent://com.apple.reminders` — All intents from an app
- `intent://com.apple.reminders/CreateReminder` — Individual intent details

### Prompts

| Prompt | Purpose |
|--------|---------|
| `discover_capabilities` | "What can I automate on this Mac?" |
| `intent_help` | Get usage help for a specific intent |
| `workflow_builder` | Build a multi-step automation using available intents |

## Project Structure

```
app-intents-mcp/
├── Package.swift
├── Sources/
│   └── AppIntentsMCP/
│       ├── main.swift                 # Entry point
│       ├── MCP/
│       │   ├── Transport.swift        # Stdio JSON-RPC handling
│       │   ├── Protocol.swift         # MCP message types
│       │   ├── Server.swift           # Request routing
│       │   ├── Tools.swift            # Tool implementations
│       │   ├── Resources.swift        # Resource provider
│       │   └── Prompts.swift          # Prompt templates
│       ├── Discovery/
│       │   ├── IntentDiscovery.swift  # Orchestrates all strategies
│       │   ├── BundleScanner.swift    # App bundle inspection
│       │   ├── ShortcutsDB.swift      # Shortcuts database parsing
│       │   └── PrivateFrameworks.swift # Runtime framework exploration
│       ├── Execution/
│       │   ├── IntentExecutor.swift   # Orchestrates execution
│       │   ├── ShortcutsBridge.swift  # CLI-based execution
│       │   └── XPCBridge.swift        # Direct XPC invocation
│       ├── Models/
│       │   ├── Intent.swift           # Core intent model
│       │   └── IntentResult.swift     # Execution results
│       └── Cache/
│           └── IntentCache.swift      # SQLite-backed cache
├── manifest.json                       # MCPB manifest
└── README.md
```

### Dependencies

- **swift-argument-parser** — CLI argument handling
- **SQLite.swift** — Cache storage and Shortcuts DB reading
- **Foundation** — File system, JSON, XPC

### Swift Practices

- Swift 6 with strict concurrency checking
- Async/await throughout
- Actors for thread-safe cache access
- Structured error handling with typed errors

## Packaging & Distribution

### MCPB Bundle Structure

```
app-intents-mcp.mcpb (zip archive)
├── manifest.json
├── bin/
│   └── app-intents-mcp    # Universal binary (arm64 + x86_64)
├── icon.png
└── README.md
```

### manifest.json

```json
{
  "name": "app-intents-mcp",
  "version": "1.0.0",
  "description": "Execute macOS App Intents from AI assistants",
  "author": "Bradley",
  "license": "MIT",
  "server": {
    "type": "binary",
    "command": "bin/app-intents-mcp"
  },
  "capabilities": {
    "tools": true,
    "resources": true,
    "prompts": true
  },
  "platform": {
    "os": ["macos"],
    "arch": ["arm64", "x86_64"]
  }
}
```

### Build Commands

```bash
swift build -c release --arch arm64 --arch x86_64
mcpb pack
```

## Security & Permissions

### Required Permissions

| Permission | Why needed | How to request |
|------------|-----------|----------------|
| Automation | Control other apps via intents | System prompt on first use |
| Full Disk Access | Read app bundles in /Applications | Manual in System Settings (if needed) |
| Accessibility | Some intents may need this | Manual in System Settings (if needed) |

### Security Features

- **Intent allowlist/blocklist** — User configures which intents are exposed
- **Confirmation prompts** — Optional confirmation for destructive intents
- **Audit log** — All executions logged to `~/Library/Logs/app-intents-mcp/`
- **No sandboxing** — Needs system access, but minimizes attack surface

### Configuration

`~/.config/app-intents-mcp/config.json`:

```json
{
  "confirmDestructive": true,
  "blockedApps": ["com.example.sensitive-app"],
  "blockedIntents": ["*.Delete*", "*.Send*"],
  "logLevel": "info"
}
```

## Important Notes

### Automation Permission Fallback

If direct automation access fails due to macOS permission restrictions, we'll need to create a **helper app** that the user explicitly grants permissions to. This has been a problem before. Try the direct approach first, fall back to helper app if needed.

## Open Questions

1. **Discovery feasibility** — Which discovery methods actually yield usable data?
2. **Execution reliability** — Which execution strategy works best for which apps?
3. **Permission model** — Will direct automation work, or do we need a helper app?
4. **Parameter mapping** — How do we map intent parameters to JSON schema for MCP tools?

## Implementation Order

1. Scaffold Swift project with MCP transport layer
2. Prototype intent discovery (start with bundle inspection)
3. Prototype intent execution (start with Shortcuts CLI)
4. Build out full MCP interface
5. Package as mcpb
6. Test and iterate on discovery/execution strategies
