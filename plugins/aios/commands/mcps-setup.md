---
tags:
  - vault-commands
  - command
  - mcps
  - setup
description: Guided MCP setup — walks you through tokens + zshrc + register + verify for every bundled MCP.
allowed-tools: >-
  Bash(bash mcps/setup.sh*), Bash(claude mcp*), Bash(source*), Bash(grep*),
  Bash(open*), Bash(curl*), Bash(uvx*), Read, Edit, Write, Grep
---

# /mcps-setup — Guided MCP Setup

You are walking the user through setting up the bundled MCPs in this vault. The goal: get every MCP they need working, end-to-end, without them having to figure out which tokens, which URLs, which commands. You handle all of it conversationally.

## Guiding principles

- **One MCP at a time.** Don't dump 10 URLs on the user. Serialize.
- **Always ask "want this?" per MCP.** Every MCP section opens with an opt-in question: "Do you want [service] for [purpose]? (y/skip)". Never assume — a user may not use Atlassian, may not care about music control, may not need design tools. Respect their time; don't walk them through tokens they'll never use.
- **"Already working" means the BUNDLED version is working — not a remote equivalent.** When checking `claude mcp list`, treat an MCP as "already working" ONLY if the bundled entry (e.g., `atlassian: ~/aios/mcps/atlassian-mcp/run.sh ✓ Connected`) is shown. A `claude.ai Atlassian` entry shown as ✓ Connected does NOT count — that's the remote-hosted one we're replacing. The policy is **local over remote**: bundled authenticates independently of the Anthropic OAuth grant, survives account switches, and lives in the vault. Always proceed with setup if only the remote variant is active, and at the end instruct the user to disable it at claude.ai → Connectors.
- **Validate before trusting.** After each token, make a real API call to that service. If it fails, surface the exact error and let them retry.
- **Never echo tokens back.** When the user pastes a value, treat it as opaque. Confirm receipt by counting characters (`"token accepted — 40 chars"`), not by printing it.
- **Write the token to `~/.zshrc` atomically.** Use the marker-block pattern (see below) so re-running this command regenerates the block without duplicating vars.
- **Bundled only.** If the user has a `mcp__claude_ai_*` equivalent active for a service we've set up bundled, flag it for disable at claude.ai → Connectors at the end.

## The marker-block pattern for `~/.zshrc`

Manage all MCP env vars inside this block:

```
# === BEGIN MCP CREDENTIALS (managed by /mcps-setup) ===
export GEMINI_API_KEY="..."
export GITHUB_TOKEN="..."
export ATLASSIAN_URL="..."
export ATLASSIAN_USERNAME="..."
export ATLASSIAN_API_TOKEN="..."
export SLACK_XOXB_TOKEN="..."
export SPOTIFY_CLIENT_ID="..."
export SPOTIFY_CLIENT_SECRET="..."
export SPOTIFY_REDIRECT_URI="http://127.0.0.1:8888/callback"
export STITCH_API_KEY="..."
# === END MCP CREDENTIALS ===
```

On every run: read `~/.zshrc`, if the block exists, replace it; if not, append. **Never** scatter `export` statements across the file — always inside this block. This makes `/mcps-setup` safely re-runnable.

## Steps

### 1. Install dependencies first

Run `bash mcps/setup.sh` — idempotent. Installs Python venvs for the MCPs that need them, confirms Node / uvx / pipx / pandoc / Chrome are present. This step has no auth — if it succeeds, move on.

### 2. Inventory: what's already bundled and working?

- `claude mcp list` → parse output carefully:
  - **BUNDLED entries** look like `atlassian: ~/aios/mcps/atlassian-mcp/run.sh - ✓ Connected` — local paths pointing into the vault
  - **REMOTE entries** look like `claude.ai Atlassian: https://mcp.atlassian.com/v1/mcp - ✓ Connected` — URLs into Anthropic-hosted or vendor-hosted services
  - Only BUNDLED ✓ counts as "already working" for this command's purposes. Remote ✓ means "still needs bundling" — treat it as NOT working.
- `source ~/.zshrc 2>/dev/null && env | grep -E "^(GEMINI_API_KEY|GITHUB_TOKEN|ATLASSIAN|SLACK_XOXB|SPOTIFY|STITCH_API_KEY)"` → which env vars are set (only show names + lengths, never values)
- Tell the user: "Bundled + working: X, Y. Need bundled setup (may have remote-hosted version currently): A, B, C. Let's walk through them — I'll ask before each if you want it."

### 3. Walk through each MCP needing setup

For each one, follow the per-MCP flow below. **Always start with the opt-in question** — "Want [service] for [purpose]? (y/skip)". If they skip, move on silently, don't pester.

If they want it:
1. Open the token URL with `open <url>` so the user lands on the right page
2. Ask: "paste the token here when ready"
3. Validate via real API call
4. Write to zshrc (inside the marker block)
5. Register with Claude Code if needed
6. Verify via `claude mcp list` — confirm the BUNDLED entry shows ✓ Connected

### 4. After all MCPs, summarize

Tell the user:
- Which MCPs are now ✓ Connected (list them)
- Which `mcp__claude_ai_*` still appear in their list — they should disable those at `claude.ai → Settings → Connectors`
- Restart instruction: "open a new terminal (or `source ~/.zshrc`) so the env vars are live in every shell"
- Offer: "want me to smoke-test each MCP with a real tool call?"

---

## Per-MCP flow (use these specs)

### PDF Generator (no auth — just install)

- **Ask first:** "Want PDF generation (markdown → branded PDF, HTML → PDF via Chrome headless)? No auth needed, works immediately. (y/skip)"
- No tokens. Just verify pandoc + Chrome are present.
- Register: `claude mcp add pdf-generator -- ~/aios/mcps/pdf-generator-mcp/.venv/bin/python ~/aios/mcps/pdf-generator-mcp/server.py`
- Validate: confirm ✓ Connected in `claude mcp list`. That's it.

### GitHub

- **Ask first:** "Want GitHub MCP (repos, issues, PRs, files, branches, workflows)? Needs a Personal Access Token. (y/skip)"
- **Token URL:** `https://github.com/settings/tokens/new`
- **Guidance to user:** "Create a Personal Access Token. Name: 'Claude Code MCP'. Expiration: your call (90 days or no expiration). Scopes: check `repo`, `read:org`, `read:user`, `workflow`. Click Generate. Copy the `ghp_...` token."
- **Env var:** `GITHUB_TOKEN`
- **Validation:** `curl -s -H "Authorization: Bearer <token>" https://api.github.com/user | jq .login` — should return their username.
- **Register:** `claude mcp add github -- npx -y @modelcontextprotocol/server-github`

### Nano Banana (Gemini image gen)

- **Ask first:** "Want image generation (Gemini 2.5 Flash Image — cover art, content visuals, mockups)? Needs a Gemini API key and paid Cloud Billing (~$0.04/image, free tier has 0 image quota). (y/skip)"
- **Token URL:** `https://aistudio.google.com/apikey`
- **Guidance:** "Click 'Create API key'. Pick a Google Cloud project (or let Google create one). Copy the `AIza...` key. **Important:** image generation requires billing enabled on that Cloud project — go to console.cloud.google.com → your project → Billing → link a billing account. Free tier has 0 image quota. Cost is ~$0.04/image."
- **Env var:** `GEMINI_API_KEY`
- **Validation:** `curl -s "https://generativelanguage.googleapis.com/v1beta/models?key=<token>" | jq '.models[0].name'` — should return a model name, not an error.
- **Register:** `claude mcp add nano-banana -- ~/aios/mcps/nano-banana-mcp/.venv/bin/python ~/aios/mcps/nano-banana-mcp/server.py`

### Atlassian (Jira + Confluence)

- **Ask first:** "Want Atlassian MCP (Jira tickets, Confluence pages)? Skip if your team doesn't use Atlassian. (y/skip)"
- **Token URL:** `https://id.atlassian.com/manage-profile/security/api-tokens`
- **Guidance:** "Click **Create API token with scopes** (recommended — least privilege). Name: 'Claude Code MCP'. Expires: 1 year. Select **Jira** app, scopes: `read:jira-user`, `read:jira-work`, `write:jira-work`, optionally `manage:jira-project`. If you also need Confluence, scopes: `read:confluence-content.all`, `write:confluence-content.all`. Copy the `ATATT3...` token. (A classic full-account token also works — scoped is just tighter security.)"
- **Env vars:** `ATLASSIAN_URL` (e.g., `https://yourco.atlassian.net` — **verify the exact subdomain** — yourco vs yourco + "hq" or similar can bite you), `ATLASSIAN_USERNAME` (your login email), `ATLASSIAN_API_TOKEN` (scoped or classic).
- **Common gotcha:** the `ATLASSIAN_URL` must match your workspace's actual subdomain exactly. An incorrect URL returns HTTP 401 "Client must be authenticated" — which looks like an auth failure, but is actually "workspace doesn't exist at this URL." First step when debugging 401: re-check the URL by opening it in a browser and seeing if your Atlassian home loads.
- **Validation:** `curl -s -u "<user>:<token>" "<url>/rest/api/3/myself" | jq .emailAddress` — should return their email.
- **Register via wrapper** (keeps token out of `~/.claude.json`): `claude mcp add atlassian -- ~/aios/mcps/atlassian-mcp/run.sh`

### Slack

- **Ask first:** "Want Slack MCP? Messages post AS YOU (Chrome token extraction — same experience as Slack web). Skip if you don't use Slack with your team. (y/skip)"

**Default path: Chrome token extraction.** The user posts AS THEMSELVES — messages appear from their own name in colleagues' DMs, channels, and the message-yourself thread. Same experience as using Slack web/desktop directly. No Slack app to create, no admin approval, no env vars to manage.

Guidance to the user (one message):

> 1. Make sure you're signed into Slack in **Chrome** (not the desktop app — the web version at `app.slack.com`)
> 2. Quit Chrome completely, then re-open it. Token extraction needs a fresh Chrome launch to read the keychain.
>    `osascript -e 'tell application "Google Chrome" to quit' && sleep 1 && open -a "Google Chrome"`
> 3. Run: `npx -y @jtalk22/slack-mcp --refresh-tokens` — auto-extracts your `xoxc-` (token) + `xoxd-` (cookie) from Chrome, caches to `~/.slack-mcp-tokens.json`
> 4. Verify: `npx -y @jtalk22/slack-mcp --status` — should print `Status: VALID`, your user name, your team

- **Env vars:** none. Tokens live in the local file, not zshrc.
- **Register:** `claude mcp add slack -- npx -y @jtalk22/slack-mcp`
- **Validation:** `npx -y @jtalk22/slack-mcp --status` returns `VALID`. Then `claude mcp list` shows `slack: ✓ Connected`.
- **Token refresh:** if the user logs out of Slack in Chrome or rotates their Slack password, re-run step 3. One command, no new auth.
- **What the user gets:** send messages, read threads, search, list channels, manage reactions — all acting as them. Posts appear in Slack history exactly as if they typed them manually.

**Only fall back to Option B (bot token) if** the user explicitly wants a persistent bot identity — e.g., running the MCP on a server that has no Chrome browser, or wanting messages to clearly come from an "AI OS bot" persona rather than from themselves. Rare for vault use.

#### Option B — Bot token (advanced fallback)

Creates a dedicated Slack app. Messages post AS THE BOT, not as the user. Requires Slack workspace admin rights (or admin-approval flow) to install.

> 1. `https://api.slack.com/apps` → **Create New App** → **From scratch**
> 2. App name + workspace
> 3. **OAuth & Permissions** → **Bot Token Scopes** → add: `channels:history`, `channels:read`, `groups:history`, `groups:read`, `im:history`, `im:read`, `mpim:history`, `mpim:read`, `chat:write`, `users:read`, `users:read.email`, `reactions:read`, `reactions:write` (skip `search:read` — user-token only)
> 4. **Install to Workspace** → Allow
> 5. Copy the **Bot User OAuth Token** (`xoxb-...`)

- **Env var:** `SLACK_XOXB_TOKEN`
- **Validation:** `curl -s -H "Authorization: Bearer <token>" https://slack.com/api/auth.test | jq .team`
- **Register:** same — `claude mcp add slack -- npx -y @jtalk22/slack-mcp`

**Precedence when both configured:** Chrome-extracted user tokens (`~/.slack-mcp-tokens.json`) win over `SLACK_XOXB_TOKEN`. Having both is fine — Chrome tokens are used, bot token stays dormant as fallback.

### Spotify DJ (optional)

- **Ask first:** "Want Spotify DJ MCP (music playback control — play, pause, next, volume, search)? Requires Spotify Premium. (y/skip)"
- **Setup URL:** `https://developer.spotify.com/dashboard`
- **Guidance:** "Create a new app. Redirect URI must be exactly `http://127.0.0.1:8888/callback`. Enable the Web API. Copy both Client ID and Client Secret."
- **Env vars:** `SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET`, `SPOTIFY_REDIRECT_URI` (default `http://127.0.0.1:8888/callback`).
- **Validation:** client credentials flow — `curl -s -X POST https://accounts.spotify.com/api/token -d "grant_type=client_credentials&client_id=<id>&client_secret=<secret>"` — should return an access_token.
- **Register:** `claude mcp add spotify-dj -- ~/aios/mcps/spotify-dj-mcp/.venv/bin/python ~/aios/mcps/spotify-dj-mcp/server.py`

### Stitch (Google AI-native design → code)

- **Ask first:** "Want Stitch MCP (Google AI-native design → production HTML — generate UI screens from natural language)? (y/skip)"
- **Token URL:** `https://stitch.withgoogle.com/` → profile → **API keys** → create key
- **Guidance:** "Sign in with your Google account. Create an API key labeled 'Claude Code MCP'. Copy the `sk_stitch_...` value."
- **Env var:** `STITCH_API_KEY`
- **Validation:** stdio smoke test — the proxy logs `Connected to Stitch, discovered 12 tools` when the key is valid. A bare `npx -y @_davideast/stitch-mcp proxy </dev/null` that exits with the Google API error means the key is wrong or missing.
- **Register:** `claude mcp add stitch -- npx -y @_davideast/stitch-mcp proxy` (reads `STITCH_API_KEY` from env at launch — keep it in the marker block, not in args)
- **Bonus — seed a known design system:** by default, Stitch auto-invents a design system per project. To generate screens in a reference brand's style (Stripe, Linear, Apple, etc.), paste a pre-built `DESIGN.md` from [VoltAgent/awesome-design-md](https://github.com/VoltAgent/awesome-design-md) (69 files) into `create_design_system` → `apply_design_system` before `generate_screen_from_text`. The same files also drop into any code project root for Claude Code / Cursor — no Stitch dependency.

### Google Workspace (interactive OAuth, one-time per machine)

- **Ask first:** "Want Google Workspace MCP (Calendar, Tasks, Drive, Docs, Sheets, Slides, Gmail)? This is the most-used MCP for /today and /close-day — skip only if you genuinely don't use Google Workspace. (y/skip)"
- No token to paste. This MCP uses OAuth browser flow.
- After deps installed, ask user to run `uvx workspace-mcp --single-user --permissions drive:full sheets:full slides:full docs:full calendar:full tasks:full` once in a terminal — it opens a browser, user signs in, OAuth token is cached locally.
- Already registered in `~/.claude.json` on most setups (top-level `mcpServers`). If not, register: `claude mcp add google-workspace -- uvx workspace-mcp --single-user --permissions drive:full sheets:full slides:full docs:full calendar:full tasks:full`

### NotebookLM (interactive CLI, one-time per machine)

- **Ask first:** "Want NotebookLM MCP (turn vault content, research, or links into audio overviews / podcasts)? (y/skip)"
- No token here either. Needs `notebooklm login` which opens a browser.
- After deps installed: `source ~/aios/mcps/notebooklm-mcp/.venv/bin/activate && notebooklm login`
- Already registered via skill install during `setup.sh`.

### Playwright (browser-auth capability — NOT a registered MCP)

> ⚠️ **Setup-only — not a registered MCP server.** Playwright is a *capability layer* (saved browser auth via Chrome cookie extraction) that Python scripts consume on demand. There is no `server.py`, no `claude mcp add` step, no `Register:` line. The setup terminates with `cookie_import.py`. Don't pattern-match against the other MCP sections above — Playwright is structurally different. Trying `claude mcp add playwright -- … server.py` will fail with "Failed to connect" because the file doesn't exist.

- **Ask first:** "Want Playwright (headless browser automation — publish posts, scrape, screenshot, test UIs, all with your saved auth)? (y/skip)"
- Uses the same extract-from-Chrome pattern as `slack-mcp` — no separate login flow, no magic links, no per-site quirks.
- **Instruct the user:** sign in to Substack, LinkedIn, and X/Twitter in Chrome (web versions). Then run:
  ```
  ~/aios/mcps/playwright-mcp/.venv/bin/python ~/aios/mcps/playwright-mcp/cookie_import.py
  ```
- First run triggers macOS Keychain prompt — tell the user to click **"Always Allow"**.
- Script writes `auth/substack.json`, `auth/linkedin.json`, `auth/x.json` (all gitignored).
- **X caveat:** cookies log you in but Twitter's bot-detection blocks heavy interaction from Playwright. For reading timeline / loading pages it works; for posting tweets, needs `pip install playwright-stealth` (install only when X auto-posting becomes needed).
- Script validates critical session cookie per site (`substack.sid`, `li_at`, `auth_token`) — will warn if missing, telling the user they may not be fully logged in.
- Adding a new site: edit `SITES` dict at top of `cookie_import.py`, add `("sitename", (["domain.com"], "session_cookie_name"))`, re-run.
- **Consumption pattern (no MCP tools):** Claude (or you) writes Python scripts that `import playwright`, load the relevant `auth/{site}.json` as `storage_state`, and drive the browser. Examples in `mcps/playwright-mcp/README.md`. Invocation is `Bash(~/aios/mcps/playwright-mcp/.venv/bin/python script.py)`, NOT a registered MCP tool. **Setup ends with `cookie_import.py`. There is no Register step.**

---

## Rules

- **Serialize the flow.** One MCP at a time. Ask, wait, validate, move on.
- **Every token gets API-validated before persisting.** No silent failures.
- **Marker-block discipline.** Re-runs of `/mcps-setup` regenerate the block atomically — they don't duplicate env exports.
- **Never print tokens back.** Say "accepted (42 chars)", never show the value.
- **Skip silently when done.** If an MCP is already ✓ Connected with its env var set, don't pester the user.
- **End with a disable prompt.** If `mcp__claude_ai_*` tools appear in the list, tell the user exactly where to disable them (claude.ai → Settings → Connectors → per Anthropic account).

## Output

No persistent file output. This command is conversational — progress is printed to the session, and the side effects are:
- `~/.zshrc` updated with marker block
- `~/.claude.json` updated via `claude mcp add` calls
- MCP servers become ✓ Connected

If anything fails, leave the user in a recoverable state: partial progress is saved, they can re-run `/mcps-setup` and it picks up where it left off.
