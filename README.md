# app-intents-mcp

WORK IN PROGRESS: Not yet working, watch this space.

An MCP server that exposes macOS App Intents to AI assistants like Claude.

## Features

- **Discover** App Intents from all installed macOS applications
- **Search** intents by name, description, or app
- **Execute** intents directly from your AI assistant
- **Browse** intents as MCP resources

## Installation

### Via MCPB

```bash
mcpb install app-intents-mcp.mcpb
```

### Manual

1. Download the latest release
2. Add to your Claude Desktop configuration:

```json
{
  "mcpServers": {
    "app-intents-mcp": {
      "command": "/path/to/app-intents-mcp"
    }
  }
}
```

## Usage

Once installed, you can ask Claude things like:

- "What can you control on my Mac?"
- "Remind me to call mom tomorrow at 5pm"
- "Search for calendar-related intents"
- "Show me all intents from the Reminders app"

## Tools

| Tool | Description |
|------|-------------|
| `list_intents` | List all discovered intents |
| `search_intents` | Search intents by query |
| `get_intent` | Get details about an intent |
| `run_intent` | Execute an intent |
| `refresh_intents` | Re-scan for intents |

## Permissions

The server may need Automation permissions to execute intents. Grant these when prompted by macOS.

## License

MIT
