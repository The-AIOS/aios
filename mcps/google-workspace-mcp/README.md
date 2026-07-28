# Google Workspace MCP

Gmail · Calendar · Tasks · Drive · Docs · Sheets · Slides · Contacts · Forms — and Chat, if you enable it.

> **This folder contains no server code.** The server is [`workspace-mcp`](https://github.com/taylorwilsdon/google_workspace_mcp) (MIT, by Taylor Wilsdon), installed on demand from PyPI by `uvx` when Claude starts it. What lives here is the AIOS-side material: your OAuth config template, plus the setup and recovery docs upstream doesn't cover.

## Ask Claude naturally

```
"What's on my calendar today across all my accounts?"
"Schedule a 30-min meeting with a given person tomorrow at 10am"
"List my open Google Tasks sorted by due date"
"Create a task due next Monday from this to-do"
"Send an email with today's meeting agenda to a given recipient"
"Draft a Gmail reply on this thread — sober tone, 3 bullet points"
"Create a Google Doc with the contents from this markdown file in 03 - export/"
"Export a given Drive doc as markdown so I can review it in the vault"
"Find every file in Drive mentioning a given topic modified this month"
```

Accounts (primary + optional personal) are configured in your `USER.md` → Sources. Personal calendar events merge into daily plans tagged `[personal]`.

## Setup

Full walkthrough: [`SETUP.md` → Google Workspace MCP](../../SETUP.md). In short:

1. Create your own **Desktop app** OAuth client — [`personal-account-setup.md`](./personal-account-setup.md), steps 0–4.
2. `cp oauth.json.template oauth.json`, then paste your client id + secret. **`oauth.json` is gitignored** — OAuth credentials are per-person secrets and are never committed, which is why the repo ships only the template.
3. Register with `claude mcp add … -- uvx workspace-mcp --single-user --permissions …`.
4. The first call opens a browser for consent. Tokens cache in `~/.google_workspace_mcp/credentials/`.

**Register it once, from `~/aios`.** `claude mcp add` defaults to *local* (per-directory) scope, so a registration made from a second directory becomes an independent copy that drifts — exactly how two registrations here ended up with different service lists, with no surface reporting the difference. If you want it available everywhere, use a single `--scope user` registration rather than several local ones.

## Permissions

`--permissions service:level`, space-separated. Levels are `readonly` / `full`, except Gmail which is cumulative (`readonly` · `organize` · `drafts` · `send` · `full`).

Services: `calendar` · `chat` · `contacts` · `docs` · `drive` · `forms` · `gmail` · `search` · `sheets` · `slides` · `tasks` · `appscript`

**Adding a service changes the requested OAuth scopes, so it triggers a fresh consent prompt.** Removing one does not.

**Google Chat is off by default.** Add `chat:full` (or `chat:readonly`) for spaces, message read/search/send, reactions and attachments. One caveat to test before depending on it: Google restricts *sending* to some space types when using user credentials rather than a Chat app.

## When it breaks

[`TROUBLESHOOTING.md`](./TROUBLESHOOTING.md) — local-first recovery (stale token, scope mismatch, port held by a dead process). Failures here are almost always local state rather than lost credentials, so start there before opening the Cloud Console.

[`make_auth_link.py`](./make_auth_link.py) — for a consent URL mangled in a chat → terminal → browser hop (HSTS upgrading `localhost`, line-wrapping, `+` in scopes). Writes a static clickable HTML file instead.

## Why this isn't vendored

See [`UPSTREAM.md`](./UPSTREAM.md).
