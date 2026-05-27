# Google Workspace MCP — Troubleshooting & Setup Guide

## Critical insight before you start debugging

**Most auth failures are LOCAL state issues, not Google Cloud Console project issues.** The console project rarely changes after Day 0 setup; what changes is the local token cache, MCP server state, or scope drift between the MCP code and what's authorized in the consent screen.

**Start debugging locally before touching Google Cloud Console.** A real recovery session spent ~30 minutes investigating console config before realizing the project was fine — the local cached token had been issued with fewer scopes than the MCP was now requesting, causing every OAuth attempt to 400 before the consent screen even rendered. The fix took 90 seconds once attention moved to local state.

---

## Symptoms reference — start here

| What you see | Most likely cause | Where to look first |
|---|---|---|
| "Access blocked: Authorization Error" | App in Testing mode without your email as test user; OR Google's unverified-app block | Console → OAuth consent screen → Test users |
| "Error 400: invalid_request" (no detail) | Scopes mismatch — MCP requesting scopes not in consent screen | Console → OAuth consent screen → Data Access (scope count) |
| "Bad Request Error 400" (no detail) | Same as above, OR an API not enabled in the project | Console → APIs & Services → Enabled APIs |
| "Invalid or expired OAuth state parameter" | State token expired (~5 min lifespan); OR URL is from a previous attempt; OR a stale MCP process holds port 8000 | Generate a fresh auth URL; kill stale MCP processes |
| Auth completes but tool calls still 401 | Cached token poisoned; MCP server in a bad state | Local — delete cached token, restart MCP |
| Worked yesterday, intermittent today | MCP version added new scopes since last successful auth | Local — check MCP version, then sync scopes in console |

---

## DAY N — auth recovery (the recipe that works)

When auth was working and now isn't. This 4-step fix resolved a stuck auth state in ~90 seconds after ~30 min of unnecessary console debugging.

### Diagnostic flow

1. **Read what the MCP server sees** — `tail -50 mcps/google-workspace-mcp/mcp_server_debug.log`. Look for: "OAuth client credentials loaded from environment variables" (creds fine), "Token expired" (needs re-consent), "Scope mismatch" (MCP requests more than the cached token has).
2. **Check process state** — macOS/Linux: `lsof -iTCP:8000 -sTCP:LISTEN`; Windows: `netstat -ano | findstr ":8000.*LISTENING"`. A Python PID listening = the OAuth callback server is up. Nothing = the server is dead or the listener didn't start. **Multiple Python workspace processes = the stale-process bug (oldest holds port 8000, newest holds the state token → callback hits the wrong process).**
3. **Check the cached token** — `ls -la ~/.google_workspace_mcp/credentials/`. If the JSON is >7 days old (Testing mode), the refresh token has expired and the file is useless.

### The 4-step fix

1. **Delete the cached token** — `rm ~/.google_workspace_mcp/credentials/{your-email}.json`. Forces a true cold-start auth instead of a silent refresh against a stale token.
2. **Kill the MCP server process** — macOS/Linux: `kill -9 {PID}`; Windows: `Stop-Process -Id {PID} -Force`. If multiple workspace processes exist, kill all of them.
3. **Trigger any MCP tool call** — the MCP framework respawns a fresh server that re-reads env vars and starts clean.
4. **Complete auth with `prompt=consent`** — the new URL should use `prompt=consent` (true cold-start), not `prompt=select_account`. Open it in a **fresh incognito window** (avoids cached-cookie pollution), sign in as the configured user, take the "Advanced → Continue (unsafe)" path, approve all scopes, land on the localhost success page, retry the original tool call.

### What does NOT work (don't waste time on these)

- Retrying the same OAuth URL with stale state — state tokens expire in ~5 min, always regenerate.
- Checking "Authorized redirect URIs" for a Desktop-app client — that section doesn't exist for Desktop apps; Google auto-handles the localhost loopback.
- Re-adding yourself as a test user — only relevant if you were actually removed; check first.

---

## DAY 0 — setting up the Google Cloud Console project (from scratch)

### 1. Create the project
console.cloud.google.com → project dropdown → NEW PROJECT → name it (e.g. "workspace-mcp") → CREATE → **confirm the dropdown now shows the new project selected** (Google sometimes keeps you on the old one).

### 2. Enable required APIs
APIs & Services → Library → enable each: Calendar, Docs, Drive, Gmail, Slides, Sheets, Tasks, People (for contacts), Forms (optional). Every scope the MCP requests must have its API enabled, or Google rejects OAuth with a generic 400.

### 3. Configure the OAuth consent screen
APIs & Services → OAuth consent screen → **External** (for personal Gmail) → CREATE. Fill Branding (app name + your email ×2). On the Audience tab, **leave publishing status as "Testing"** (avoids the multi-week verification review) and **add your email under Test users**.

**Testing-mode caveats:** refresh tokens expire every 7 days (re-consent weekly); each test user sees an "Unverified app" warning and must click Advanced → Continue (unsafe). Safe for personal use. **Don't click PUBLISH APP** unless distributing to non-test users — it triggers Google verification and can block all auth until complete.

### 4. Add scopes
APIs & Services → OAuth consent screen → Data Access → ADD OR REMOVE SCOPES → "Manually add scopes" textbox → paste the full list (see Reference below) → Add to table → UPDATE → SAVE. **All 23 scopes are needed** — each maps to a specific MCP capability; drop one and its tools fail. Note: the scope view can be limited to 10 rows — adjust the view to see/select all.

### 5. Create OAuth 2.0 Client ID
APIs & Services → Credentials → + CREATE CREDENTIALS → OAuth client ID → **Application type: Desktop app** (uses RFC 8252 native-app flow with PKCE; Google auto-handles `localhost` redirects — no manual URI registration). Name it → CREATE → copy the client ID + secret.

### 6. Configure the MCP
Set env vars in your shell profile (recommended):
```bash
export GOOGLE_OAUTH_CLIENT_ID="...apps.googleusercontent.com"
export GOOGLE_OAUTH_CLIENT_SECRET="GOCSPX-..."
```
Or save `oauth.json` in the MCP folder. The server reads env vars first, then `oauth.json`. Restart the terminal so vars are picked up.

### 7. First-time auth
Trigger any tool call → MCP emits an "ACTION REQUIRED" auth URL → open it, sign in, Advanced → Continue (unsafe), approve scopes → redirect to localhost success → token saved at `~/.google_workspace_mcp/credentials/{email}.json` → future calls use it silently.

---

## Common pitfalls

- **Scope drift** (the cause of most "it worked yesterday" failures): when the MCP version bumps and adds tools (e.g. Slides support), the new scopes must be added to the consent screen. The pre-bump cached token lacks them; refresh fails confusingly. **Mitigation:** re-check the consent-screen scope list against the MCP's requested scopes after every `git pull` / MCP update.
- **Multi-account confusion:** if signed into multiple Google accounts, OAuth may default to the wrong one. Use an incognito window with only the target account.
- **Testing-mode 7-day expiry:** re-consent weekly, or publish to Production (multi-week review).
- **The "publish" trap:** clicking PUBLISH APP thinking it just saves consent-screen changes triggers verification and can block auth. Stay in Testing unless you truly need Production; if you must, use a separate OAuth client and keep the Testing client live.
- **Stale-process OAuth loop (Windows):** stale Python workspace processes accumulate across Claude Code restarts; the oldest holds port 8000, the newest holds the state token → callback hits the wrong process → "Invalid or expired OAuth state." Kill all workspace Python processes, verify port 8000 is free, retrigger a tool call to respawn a single fresh MCP.

---

## Reference — the 23 scopes

```
https://www.googleapis.com/auth/spreadsheets
https://www.googleapis.com/auth/spreadsheets.readonly
https://www.googleapis.com/auth/drive
https://www.googleapis.com/auth/drive.readonly
https://www.googleapis.com/auth/drive.file
https://www.googleapis.com/auth/documents
https://www.googleapis.com/auth/documents.readonly
https://www.googleapis.com/auth/presentations
https://www.googleapis.com/auth/presentations.readonly
https://www.googleapis.com/auth/calendar
https://www.googleapis.com/auth/calendar.readonly
https://www.googleapis.com/auth/calendar.events
https://www.googleapis.com/auth/gmail.readonly
https://www.googleapis.com/auth/gmail.modify
https://www.googleapis.com/auth/gmail.compose
https://www.googleapis.com/auth/gmail.send
https://www.googleapis.com/auth/gmail.labels
https://www.googleapis.com/auth/gmail.settings.basic
https://www.googleapis.com/auth/tasks
https://www.googleapis.com/auth/tasks.readonly
https://www.googleapis.com/auth/userinfo.email
https://www.googleapis.com/auth/userinfo.profile
openid
```

Drive/Docs/Slides/Sheets (full + readonly) → create/edit/copy decks, docs, sheets, fetch attachments. Calendar (full + readonly + events) → daily-plan integration. Gmail (modify/compose/send/labels/settings/readonly) → read + draft + send + manage. Tasks (full + readonly) → daily-plan to-dos. openid + userinfo → OAuth identity (required for token issuance).

---

## See also

- `README.md` (this folder) — what the MCP does + register command.
- `mcps/_index.md` → "Where credentials live" — the local-first debugging principle + where tokens/keys actually live.
- `make_auth_link.py` (this folder) — Windows helper that turns the latest auth URL from `mcp_server_debug.log` into a clickable local HTML button (works around URL mangling in chat → terminal → browser pipelines).
