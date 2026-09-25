# Setup Guide

Turn the Slack browser session you already have into 19 tools for any stdio MCP client.

## Fast path

**Node 22 or 24 recommended. Node 20 remains supported for the v4 line.**

On macOS, sign into Slack in Chrome once, then run:

```bash
npx -y @jtalk22/slack-mcp --setup
```

The wizard:

1. asks where credentials should live;
2. extracts the current Chrome Slack session locally;
3. validates the Slack identity and workspace;
4. persists the selected storage mode;
5. prints the next client-configuration step.

Chrome does not need to stay open after the session exists on disk. No DevTools or clipboard step is required for the normal macOS path.

Prefer a persistent global command:

```bash
npm install -g @jtalk22/slack-mcp
slack-mcp --setup
```

## Verify the CLI

```bash
npx -y @jtalk22/slack-mcp --version
npx -y @jtalk22/slack-mcp --help
npx -y @jtalk22/slack-mcp --doctor
```

`--doctor` exits with one classified result:

- `0`: ready;
- `1`: credentials missing;
- `2`: credentials invalid or expired;
- `3`: network or runtime failure.

`--status` is read-only and does not trigger Chrome extraction.

## Pick your client

Every local client starts the same stdio command:

```json
{
  "command": "npx",
  "args": ["-y", "@jtalk22/slack-mcp"]
}
```

### Claude Code

```bash
claude mcp add slack -- npx -y @jtalk22/slack-mcp
```

Or add to `~/.claude.json`:

```json
{
  "mcpServers": {
    "slack": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@jtalk22/slack-mcp"]
    }
  }
}
```

### Claude Desktop

Configuration file:

- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows: `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "slack": {
      "command": "npx",
      "args": ["-y", "@jtalk22/slack-mcp"]
    }
  }
}
```

### Cursor

Add to `.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "slack": {
      "command": "npx",
      "args": ["-y", "@jtalk22/slack-mcp"]
    }
  }
}
```

### GitHub Copilot in VS Code

Add to `.vscode/mcp.json`:

```json
{
  "servers": {
    "slack": {
      "command": "npx",
      "args": ["-y", "@jtalk22/slack-mcp"]
    }
  }
}
```

### Windsurf

Add to `~/.codeium/windsurf/mcp_config.json`:

```json
{
  "mcpServers": {
    "slack": {
      "command": "npx",
      "args": ["-y", "@jtalk22/slack-mcp"]
    }
  }
}
```

### Gemini CLI

Add to `~/.gemini/settings.json`:

```json
{
  "mcpServers": {
    "slack": {
      "command": "npx",
      "args": ["-y", "@jtalk22/slack-mcp"]
    }
  }
}
```

### Codex CLI

```bash
codex mcp add slack -- npx -y @jtalk22/slack-mcp
```

Or add to `~/.codex/config.toml`:

```toml
[mcp_servers.slack]
command = "npx"
args = ["-y", "@jtalk22/slack-mcp"]
```

### Any other stdio MCP client

Point the client's stdio MCP configuration at:

```text
npx -y @jtalk22/slack-mcp
```

On Windows or Linux, pass `SLACK_TOKEN` and `SLACK_COOKIE` through the client's environment configuration because macOS Chrome/Keychain extraction is unavailable.

## Restart and prove the connection

Fully restart the client after adding its MCP configuration. MCP clients commonly snapshot tool lists at startup.

Then ask the agent to run:

```text
slack_health_check
```

A returned workspace and username means the server is live.

Useful follow-ups:

```text
slack_token_status
slack_list_conversations
slack_conversations_unreads
```

## Storage modes

The macOS setup wizard remembers the selected backend in `~/.slack-mcp-meta.json`. `SLACK_MCP_TOKEN_STORAGE` can override it per client or process.

### `auto` — default

- owner-only token file;
- macOS Keychain backup;
- automatic local refresh.

### `keychain-only`

- credentials live exclusively in the macOS Keychain;
- no plaintext credential file is written;
- file-to-Keychain migration is verified by read-back before the old file is removed;
- a failed Keychain write never silently falls back to plaintext.

Choose **Keychain only** during setup, or configure:

```json
{
  "env": {
    "SLACK_MCP_TOKEN_STORAGE": "keychain-only"
  }
}
```

If a background refresh cannot write to a locked Keychain, the fresh credentials stay available in process memory and persistence is retried later. Existing Keychain entries remain untouched.

### `file`

- owner-only token file;
- Keychain is never accessed;
- useful for CI or machines where Keychain prompts are undesirable.

An unknown storage mode fails at startup rather than guessing.

## Multiple workspaces

Use a profile to isolate every credential and metadata surface:

```json
{
  "mcpServers": {
    "slack-work": {
      "command": "npx",
      "args": ["-y", "@jtalk22/slack-mcp"],
      "env": { "SLACK_MCP_PROFILE": "work" }
    },
    "slack-personal": {
      "command": "npx",
      "args": ["-y", "@jtalk22/slack-mcp"],
      "env": { "SLACK_MCP_PROFILE": "personal" }
    }
  }
}
```

Set up each profile once:

```bash
npx -y @jtalk22/slack-mcp --setup --profile work
npx -y @jtalk22/slack-mcp --setup --profile personal
```

When workspaces live in different Chrome profiles, add `SLACK_MCP_CHROME_PROFILE` to each entry. Profile names accept 1–32 letters, numbers, hyphens, and underscores; invalid names fail closed.

## Keep credentials fresh during long idle periods

The MCP server checks credential health and can refresh while it is running. An optional macOS LaunchAgent can refresh twice daily even when the MCP client is closed.

Create `~/Library/LaunchAgents/com.yourname.slack-token-refresh.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.yourname.slack-token-refresh</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>export NVM_DIR="$HOME/.nvm" &amp;&amp; [ -s "$NVM_DIR/nvm.sh" ] &amp;&amp; \. "$NVM_DIR/nvm.sh" &amp;&amp; exec npx -y @jtalk22/slack-mcp --refresh-tokens</string>
    </array>
    <key>StartCalendarInterval</key>
    <array>
        <dict><key>Hour</key><integer>6</integer><key>Minute</key><integer>17</integer></dict>
        <dict><key>Hour</key><integer>18</integer><key>Minute</key><integer>17</integer></dict>
    </array>
    <key>RunAtLoad</key><true/>
    <key>StandardErrorPath</key><string>/tmp/slack-token-refresh.log</string>
</dict>
</plist>
```

Load it:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.yourname.slack-token-refresh.plist
```

The refresh process follows the storage mode selected during setup. Users of Homebrew Node can replace the `nvm` wrapper with explicit `/opt/homebrew/bin/node` and `/opt/homebrew/bin/npx` paths.

## Manual credentials

Manual extraction remains available when automatic macOS extraction is not applicable:

1. retrieve your own `xoxc-` session token and `xoxd-` `d` cookie from the signed-in Slack browser session;
2. pass them as `SLACK_TOKEN` and `SLACK_COOKIE` through the MCP client's environment configuration;
3. never paste them into an issue, prompt, log, or checked-in file.

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for extraction failure codes and recovery actions.

## Docker and HTTP

```bash
docker pull ghcr.io/jtalk22/slack-mcp-server:latest
```

The package also includes local HTTP and self-hosted deployment modes. See [DEPLOYMENT-MODES.md](DEPLOYMENT-MODES.md) for transport, authentication, and allowed-origin configuration.

## Hosted alternative

The self-hosted server is complete. Hosted is the continuation path when the workflow must run without browser-session rotation:

- permanent OAuth;
- indexed search;
- scheduled and contract-validated briefs;
- shared workspace profiles.

[Hosted free tier and live pricing →](https://mcp.revasserlabs.com/pricing)

## Troubleshooting

### Missing credentials

```bash
npx -y @jtalk22/slack-mcp --doctor
npx -y @jtalk22/slack-mcp --setup
```

### `invalid_auth`

The Slack session rotated or was revoked. Re-run setup or call `slack_refresh_tokens` on macOS.

### Client does not show the tools

1. validate the client's MCP configuration syntax;
2. confirm `npx -y @jtalk22/slack-mcp --version` works in a normal shell;
3. fully quit and restart the client;
4. run `slack_health_check` again.

### Chrome extraction fails

Run `--doctor` and use the structured extraction code. The failure table and exact next actions live in [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
