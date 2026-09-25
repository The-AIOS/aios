# Troubleshooting Guide

Common issues and their solutions.

---

## Install Flow Sanity Check

If first-run setup is failing, validate command resolution in a clean directory:

```bash
tmpdir="$(mktemp -d)"
cd "$tmpdir"
npx -y @jtalk22/slack-mcp --version
npx -y @jtalk22/slack-mcp --help
npx -y @jtalk22/slack-mcp --doctor
```

Expected:
- `--version` and `--help` exit `0`
- `--doctor` exits with one of:
  - `0` ready
  - `1` missing credentials
  - `2` invalid/expired credentials
  - `3` connectivity/runtime issue
- `--status` is read-only and never attempts Chrome extraction.

If `--version` fails here, the issue is install/runtime path, not Slack credentials.

---

## Hosted Version

The hosted version is live at [mcp.revasserlabs.com](https://mcp.revasserlabs.com). Free tier (no card) ships 2,000 requests/mo + 25 AI tool calls/mo + all 5 workflow profile types. Pro at $19/mo (or $190/yr) unlocks unlimited requests and AI tool calls, permanent OAuth (no 2-week token rotation), email support, and 2 workspaces. Team at $49/mo flat (or $490/yr) covers 5 workspaces with shared workflow profiles and 24h support. Safeguard at $199/mo (waitlist only) adds agent approval gates, the scheduled morning catch-up DM at 8am workspace time, and workspace memory — all *(in development)*.

The OSS package keeps the local-machine path and ships no placeholder tools: every tool it advertises runs on your machine.

---

## DMs Not Showing Up

**Symptom:** `slack_list_conversations` returns channels but no DMs.

**Cause:** Slack's `conversations.list` API doesn't return IMs when using xoxc browser tokens.

**Solution:** This is handled automatically. The server discovers DMs by calling `conversations.open` for each user in your workspace. This happens in `lib/handlers.js`.

If DMs still don't appear:
1. Check you're requesting the right types: `slack_list_conversations types=im,mpim`
2. Verify the user exists: `slack_list_users`

---

## Rate Limiting Errors

**Symptom:** `{"error":"ratelimited"}` in API responses.

**Cause:** Slack limits API calls, especially when listing many users/DMs.

**Solution:** The client (`lib/slack-client.js`) implements automatic retry with exponential backoff:
- First retry: Wait 5 seconds
- Second retry: Wait 10 seconds
- Third retry: Wait 15 seconds

If you still hit limits, reduce batch sizes:
```
slack_list_conversations limit=50
```

---

## Token Expiration

**Symptom:** `invalid_auth` or `token_expired` errors.

**Cause:** Browser tokens (xoxc/xoxd) expire after 1-2 weeks.

**Solution:** The server has 4 layers of token recovery:

1. **Environment variables** - From MCP config (Claude Desktop)
2. **Token file** - `~/.slack-mcp-tokens.json`
3. **macOS Keychain** - Encrypted persistent storage
4. **Chrome auto-extraction** - Fallback when all else fails

**To refresh tokens:**
```bash
# Option 1: In Claude Code/Desktop
slack_refresh_tokens

# Option 2: Package setup wizard
npx -y @jtalk22/slack-mcp --setup

# Option 3: Diagnostics check
npx -y @jtalk22/slack-mcp --doctor

# Option 4: Repo CLI
npm run tokens:auto

# Option 5: Manual
npm run tokens:refresh
```

---

## Web Server Issues

### Server Stops When Terminal Closes

**Solution:** Use LaunchAgent for persistence:

```bash
# Create LaunchAgent
cat > ~/Library/LaunchAgents/com.slack-web-api.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.slack-web-api</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/node</string>
        <string>/Users/YOUR_USERNAME/slack-mcp-server/src/web-server.js</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/Users/YOUR_USERNAME/slack-mcp-server</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF

launchctl load ~/Library/LaunchAgents/com.slack-web-api.plist
```

### API Key Invalid

The web server generates a unique API key on first run, stored in `~/.slack-mcp-api-key`.

The key is printed to the console when you start the server:
```
Dashboard: http://localhost:3000/?key=smcp_xxxxxxxxxxxx
API Key:   smcp_xxxxxxxxxxxx
```

You can also set a custom key:
```bash
SLACK_API_KEY=your-custom-key npm run web
```

### Can't Connect to localhost:3000

Check if the server is running:
```bash
# Get your API key from ~/.slack-mcp-api-key
curl http://localhost:3000/health -H "Authorization: Bearer $(cat ~/.slack-mcp-api-key)"
```

Check LaunchAgent status:
```bash
launchctl list | grep slack-web-api
```

Check logs:
```bash
cat /tmp/slack-web-api.log
cat /tmp/slack-web-api.error.log
```

### Hosted HTTP `/mcp` Returns 503 or 401

If you run `node src/server-http.js`, `/mcp` is protected by default.

`503 http_auth_token_missing` means you did not set:

```bash
SLACK_MCP_HTTP_AUTH_TOKEN=change-this
```

`401 unauthorized` means your request is missing or using the wrong bearer token.

Example request:

```bash
curl http://localhost:3000/mcp \
  -H "Authorization: Bearer $SLACK_MCP_HTTP_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}}}'
```

For local-only testing (not remote exposure), you can opt out:

```bash
SLACK_MCP_HTTP_INSECURE=1 node src/server-http.js
```

---

## Claude Desktop Issues

### Slack Tools Not Appearing

**Symptom:** Claude Desktop doesn't show Slack tools after adding config.

**Solutions:**

1. **Fully restart Claude Desktop:**
   - Cmd+Q (don't just close window)
   - Reopen the app

2. **Check config syntax:**
   ```bash
   cat ~/Library/Application\ Support/Claude/claude_desktop_config.json | python -m json.tool
   ```

3. **Check MCP logs:**
   ```bash
   cat ~/Library/Logs/Claude/mcp-server-slack.log
   ```

4. **Verify node path:**
   ```bash
   which node
   # Use this full path in config
   ```

### MCP Server Crashes on Start

**Check the log:**
```bash
tail -50 ~/Library/Logs/Claude/mcp-server-slack.log
```

**Common causes:**
- Node.js not found (use full path like `/opt/homebrew/bin/node`)
- Missing tokens in env section
- Invalid JSON syntax in config

---

## Chrome Extraction Fails

**Symptom:** `slack_refresh_tokens` returns "Could not extract from Chrome"

**Requirements:**
1. Google Chrome must be running (not just in Dock)
2. Have a Slack tab open at `app.slack.com` (not desktop app)
3. Be logged into Slack in that tab
4. In Chrome menu, enable `View > Developer > Allow JavaScript from Apple Events`
5. Grant accessibility permissions to Terminal/Claude

**Check permissions:**
System Preferences → Privacy & Security → Accessibility → Ensure Terminal is enabled

**Read the reason code.** Extraction errors name their cause per Chrome profile — the `detail` field of the error tells you which of these you're in:

| Reason | Meaning | Fix |
|--------|---------|-----|
| `keychain_timeout` | The Chrome Safe Storage key lookup exceeded the timeout | Unlock the Keychain; retry; raise `SLACK_MCP_KEYCHAIN_TIMEOUT_MS` (default 15000) |
| `keychain_lookup_failed` | Keychain refused the Safe Storage key | Unlock the Keychain; allow this terminal Keychain access |
| `no_cookie_db` | Profile has no Cookies database | Point `SLACK_MCP_CHROME_USER_DATA_DIR` / `SLACK_MCP_CHROME_PROFILE` at the right Chrome |
| `no_slack_cookie_row` | No Slack `d` cookie in that profile | Log into app.slack.com in that Chrome profile |
| `cookie_decrypt_failed` | Cookie wouldn't decrypt with the Safe Storage key | Chrome may have re-keyed — restart Chrome, sign into Slack again, retry |
| `cookie ok, no cached xoxc token in LevelDB` | Cookie found but no cached token on disk | Open Slack in Chrome once so the token gets cached, or use AppleScript mode |

The Safe Storage key is looked up once per run and cached, so a failing Keychain produces one clear error — not a password prompt per profile.

---

## Why Browser Tokens Instead of Slack App?

**Question:** Why not just create a Slack app with proper OAuth?

**Answer:** Slack apps cannot access DMs without explicit OAuth authorization for each conversation. This is by design for privacy.

Browser tokens (xoxc/xoxd) provide the same access you have in Slack's web interface - everything you can see, Claude can see.

**Trade-offs:**
- ✅ Full access to all your conversations
- ✅ No per-conversation authorization needed
- ❌ Tokens expire every 1-2 weeks
- ❌ Requires Chrome for token extraction

---

## Getting Help

1. Check logs:
   - MCP: `~/Library/Logs/Claude/mcp-server-slack.log`
   - Web: `/tmp/slack-web-api.log`

2. Test manually:
   ```bash
   cd ~/slack-mcp-server
   node src/server.js  # Should say "running"
   ```

3. Verify tokens:
   ```bash
   npm run tokens:status
   ```
