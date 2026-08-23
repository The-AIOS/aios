# Google Workspace MCP — Personal-Account Setup

> **Purpose.** Wire the `google-workspace-mcp` to a **personal Google account** (e.g. an agent's own gmail like `your-agent@gmail.com`), so the agent can read/act on Drive, Docs, Sheets, Slides, Calendar, Tasks, and Gmail for that account — including folders **shared with** it.
>
> Written from a real setup (2026-07-22) on a fortress agent machine. Uses the **local** MCP (its own OAuth client, `uvx`-launched) per the AIOS MCP policy — not the claude.ai-hosted Google connector, which is bound to the active claude.ai OAuth grant and breaks on account switch.

## The three traps (read first — they cost the most time)

1. **`Error 403: org_internal` — "can only be used within its organization."**
   The OAuth client belongs to a Google Cloud project whose consent screen is **Internal** (locked to a Workspace org). A **personal gmail can never use an Internal client.** → Create a **fresh project under the personal account itself** (no org → **External** consent available). Do *not* reuse a client from a work/org project.

2. **`Error 403: access_denied` — "has not completed the Google verification process / developer-approved testers."**
   The app is in **Testing** mode and the account isn't on the test-user list. → Add the account as a **Test user** (below). Testing + test-user is enough to *authorize* and gets you running today — but it is **not a permanent state**. See trap #3, which is the bill for stopping here.

3. **The whole thing works, then dies exactly 7 days later — `invalid_grant: Token has been expired or revoked`.**
   Google expires the **refresh token** of an app whose publishing status is **Testing** after 7 days. Nothing is misconfigured and nothing was revoked by a human: the grant reached its built-in expiry.

   This is the trap that costs the most over the life of the setup, and it costs the most *because it does not fail during setup*. Traps #1 and #2 fail loudly while you are still holding the context — you are in the console, you read the error, you fix it. This one fails on a Tuesday three weeks later, on a machine you are not looking at, and it presents as "the MCP broke" rather than "a policy clock ran out". Whatever depends on this server — a daily-ritual pipeline, a scheduled routine, an agent that reads your calendar every morning — goes dark once a week until a human clicks through a consent screen. The setup guide is the only place that can warn you, because by the time it happens nobody connects the symptom to the step that caused it.

   → **The lever is the publishing status, not verification.** The 7-day clock is attached to **Testing**; moving the app to **In production** (Audience → *Publish app*) is what stops it. Publishing and *being verified* are two different things — an app can sit in Production **unverified**, still showing the "Google hasn't verified this app" screen this document already tells you to expect.

   → **Check what Google asks of you before assuming it is free, because this MCP uses sensitive scopes.** Gmail and Drive are not the basic `email`/`profile`/`openid` trio; they are the scope classes that pull an app into Google's verification requirements, and the requirements (and any user caps on an unverified Production app) are Google's to change, not this document's to promise. **Read what the Audience screen tells you at the moment you click Publish** — that is the only current answer. If it does ask for verification and you do not want to go through it, that is a real decision, not a formality.

   → **Whichever way you go, write the cost down** next to whatever depends on this server. Staying in Testing means **a manual re-auth every 7 days, forever** — a legitimate choice for a throwaway experiment, and the wrong default for a server a daily automation depends on, which is exactly what this document is setting up.

## Part A — Google Cloud Console (the human clicks)

**0. Sign in as the target account.** Open [console.cloud.google.com](https://console.cloud.google.com) **signed in as the personal gmail you're wiring** (use a clean browser profile / incognito so it doesn't grab a work account). This is what makes the consent screen External.

**1. New project** — project dropdown → New Project → name it (e.g. `my-agent-workspace-mcp`) → **Location: No organization** → Create → select it.

**2. Enable APIs** — APIs & Services → **Library** → enable each (search → Enable). **Enable one API per service you put in `--permissions`** — the two lists must match, or the server starts fine and the tools 403 at call time:
> **Drive · Docs · Sheets · Slides · Calendar · Tasks · Gmail** — the core seven
> **People API** ← required for `contacts:full` · **Forms API** ← required for `forms:full` · **Google Chat API** ← required for `chat:full`

*A mismatch here fails late and confusingly.* The scope is granted, OAuth consent succeeds, the tool is exposed — and then the call returns `403 SERVICE_DISABLED: <API> has not been used in project <N> before or it is disabled`, which reads like an auth problem but isn't. If you see that, the error text carries a direct activation URL; open it, enable, wait a minute, retry. No re-consent needed — enabling an API is a project setting, not a scope change.

*(Other AIOS tools use other Google APIs — Generative Language/Gemini for nano-banana, YouTube Data, Analytics — enable those only if you use those tools; they're not needed for this MCP.)*

**3. OAuth consent screen** (new UI may call this **Google Auth Platform**):
- **User type / Audience: External** ← the fix for trap #1.
- App name + user-support email + developer email = the personal gmail.
- **Audience → Test users → + Add users →** the personal gmail → **Save** ← the fix for trap #2.
- Leave in **Testing** (do not publish).

**4. Create the client** — Credentials → **+ Create Credentials → OAuth client ID → Application type: Desktop app** → Create → **Download JSON** (it's `client_secret_*.json`, type `installed`). Desktop type is required — it allows the `http://localhost` redirect the flow uses.

## Part B — Wire it (the agent runs)

**Nothing to install** — the server is fetched from PyPI on demand by `uvx` (see [`UPSTREAM.md`](./UPSTREAM.md)). Skip straight to the credentials.

Stash the downloaded client securely (out of Downloads, machine-local, never in the vault):
```bash
mkdir -p ~/.google_workspace_mcp
cp ~/Downloads/client_secret_*.json ~/.google_workspace_mcp/client_secret.json
chmod 600 ~/.google_workspace_mcp/client_secret.json
```

Register the MCP at **user scope**, pointing at that file (creds land in `~/.claude.json`, machine-local):
```bash
claude mcp add google-workspace --scope user \
  --env GOOGLE_CLIENT_SECRET_PATH="$HOME/.google_workspace_mcp/client_secret.json" \
  --env OAUTHLIB_INSECURE_TRANSPORT=1 \
  --env OAUTHLIB_RELAX_TOKEN_SCOPE=1 \
  -- uvx workspace-mcp --single-user --tool-tier core
```
- **`--single-user`** = bypass multi-user session mapping; use the one token in the credentials dir. Right for an agent that IS one account.
- **`GOOGLE_CLIENT_SECRET_PATH`** > inline `GOOGLE_OAUTH_CLIENT_ID/SECRET` — keeps the secret in a `600` file, not the process args.
- **`OAUTHLIB_RELAX_TOKEN_SCOPE=1`** — Google silently adds `openid`; without this the flow errors on "scope changed."

## Part C — Authorize the account (one-time consent)

The server does OAuth on first tool call and catches the redirect at **`localhost:8000` on the machine running the MCP**. The redirect MUST reach that machine:
- **At the machine's screen:** open the consent URL there.
- **Remote (e.g. a headless machine):** tunnel first, then open the URL on your laptop:
  ```bash
  ssh -L 8000:localhost:8000 <the-mcp-host>
  ```

To drive it without a session restart, run a one-shot consent (`from_client_secrets_file` + `run_local_server(port=8000)`), which prints the URL and, on success, writes the token to `~/.google_workspace_mcp/credentials/{email}.json` in the store's exact format (`token, refresh_token, token_uri, client_id, client_secret, scopes, expiry`). Run it **unbuffered** (`python -u`) or the URL stays stuck in the stdout buffer while `run_local_server` blocks.

At the consent screen you'll see **"Google hasn't verified this app"** — this is expected for a Testing app (not a block): **Advanced → Go to {app} (unsafe) → continue → approve.**

## Part D — Verify + use

- **Token:** `~/.google_workspace_mcp/credentials/{email}.json` — confirm `refresh_token: yes` (self-renews; no constant re-auth).
- **Smoke test** (Drive `sharedWithMe`) confirms the account + that shared folders are visible before reloading anything.
- **To use the MCP tools in a Claude session, restart the session** — MCP tools register at session start, so an MCP added mid-session isn't callable until the next start. After restart, `mcp__google-workspace__*` tools are live and `--single-user` uses the stored token.

## Gotchas condensed
| Symptom | Cause | Fix |
|---|---|---|
| `403 org_internal` | client from an org/Internal project | new project under the personal account, External consent |
| `403 access_denied` (testers) | account not a test user | add it under Audience → Test users |
| `invalid_grant` after ~7 days | app publishing status still **Testing** | move it to **In production** (trap #3) — check what Google asks at that screen; these are sensitive scopes |
| `redirect_uri_mismatch` | client isn't Desktop type | recreate as Desktop, or add `http://localhost:8000/` |
| consent URL never prints | Python stdout buffered while `run_local_server` blocks | run `python -u` / `PYTHONUNBUFFERED=1` |
| "scope has changed" error | Google added `openid` | `OAUTHLIB_RELAX_TOKEN_SCOPE=1` |
| tools missing after wiring | MCP added mid-session | restart the Claude session |
| redirect fails when remote | `localhost:8000` hit the wrong machine | `ssh -L 8000:localhost:8000 <host>` |
