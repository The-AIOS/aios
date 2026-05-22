# USER.md — Your Vault Configuration

> This file makes the vault yours. CLAUDE.md reads it at session start. Every command checks its section under `## Command personalizations`. This file is **never synced** to the team repo — it's yours alone.
>
> **First time?** Every section has examples marked with *EXAMPLE ONLY*. Replace them with your actual configuration and delete the example lines. Claude knows to ignore example lines.

---

## Identity

> Named sessions you use regularly. When you start Claude with `spawn my-name`, Claude matches `$CLAUDE_AGENT_NAME` against this table to know who you are and how to greet you. Names not listed here are treated as spawned workers (agents).
>
> **Why this matters:** If you always launch Claude as `buddy`, adding it here means Claude greets you personally instead of treating you as a generic worker session.

*EXAMPLE ONLY (Claude: ignore these) — replace with yours:*

| Name | Role | Greeting style |
|------|------|----------------|
| *`buddy`* | *My main session* | *Warm co-pilot — reference the day, recent work, whatever feels natural.* |
| *`ops`* | *Operations session* | *Brief and operational — what needs doing, no small talk.* |

## Session cascade

> **Default rule:** If `{IDENTITY}.md` exists at repo root (matching the session name), read the full file on session start. This covers most cases — no table entry needed. Add exceptions below only when a session needs partial reads or cross-identity file access.

*EXAMPLE ONLY (Claude: ignore these) — replace with yours:*

| *Identity* | *Override* |
|----------|---------|
| *`buddy`* | *Read only `## Handoff` from `COORDINATOR.md`* |

## Remote machines

> If you have other computers where you run Claude (a server, a Mac Mini, a cloud instance), list the SSH spawn patterns here. When you say "tell {machine} to spawn X", Claude uses these. Leave empty if you only use one machine.

*EXAMPLE ONLY (Claude: ignore this) — replace with yours:*

*"tell server to spawn X":*
```
ssh my-server "osascript -e 'tell application \"Terminal\" to do script \"cd ~/aios && spawn SESSION_NAME\"'"
```

## Companies (mounted)

> Multi-company support: each row mounts a separate company's venture context into your vault. `/aios:company` reads and writes this table. `/aios:update` syncs the AIOS framework infrastructure (separate concern).
>
> You can mount **0, 1, or many** companies. An independent consultant might mount their own venture AND a client's company. A company employee mounts just their company. A non-business operator mounts none. Empty section = no companies mounted (use `/aios:company --create` to scaffold your first, or `/aios:company --mount {url}` to mount an existing one).

*EXAMPLE ONLY (Claude: ignore these) — replace with yours, or leave empty if you don't mount any companies:*

| Company | Substrate | Source | Venture folder | Last sync |
|---|---|---|---|---|
| *acme-co* | *github* | *`git@github.com:acme-co/venture-context.git`* | *`vault/00 - notes/context/ventures/acme-co/`* | *2026-05-21* |
| *client-bravo* | *drive* | *`https://drive.google.com/drive/folders/...`* | *`vault/00 - notes/context/ventures/client-bravo/`* | *2026-05-20* |

> **Substrate** = `github` (recommended for code-adjacent companies) or `drive` (recommended for non-coder collaborators). See `plugins/aios/commands/company.md` for the full adapter list.
> **Source** = the GitHub repo URL or Drive folder URL. Read-only; permissions live on GitHub/Drive.
> **Venture folder** = where the company's context mirrors into your vault (auto-derived from company name).
> **Last sync** = updated by `/aios:company --sync {name}` (or `--sync-all`).

## Sources

> Where Claude pulls data for daily plans, communication, and context gathering. `/today`, `/close-day`, and the pipeline executor read this section. If empty, Claude uses vault notes only — no calendar, tasks, or Slack.

### General

*EXAMPLE ONLY (Claude: ignore this) — replace with yours:*
- *Timezone: `America/Your_Timezone`*

> Your timezone. Used by the pipeline executor for calendar queries and Slack recaps. Examples: `America/New_York`, `Europe/London`, `America/Mexico_City`, `Asia/Tokyo`.

### Google accounts

> The pipeline executor supports two Google accounts: primary (work) and personal. Each needs its own OAuth credentials (setup creates these). Personal is optional.

*EXAMPLE ONLY (Claude: ignore these) — replace with yours:*

*Primary:*
- *Google email: `you@company.com`*
- *Google Calendar — via Google Workspace MCP*
- *Google Tasks — via Google Workspace MCP*
- *Google Tasks list: `your-list-id`*

*Personal (optional):*
- *Google email (Personal): `you@gmail.com`*
- *Google Calendar (Personal) — merged into daily plan, tagged [personal]*

### Communication

*EXAMPLE ONLY (Claude: ignore these) — replace with yours:*

- *Slack — send/read messages, search channels, DMs*
  - *Workspace: Your Company*
  - *Key channels: #general, #product, #engineering*
  - *DM contacts: Alice, Bob, Carol*
  - *Channels to monitor: #general, #product*
  - *Skip: #random, #social*
  - *Close-day recap: enabled*
- *Gmail — you@company.com*
- *GitHub Issues — open issues assigned to me*

### Tools

*EXAMPLE ONLY (Claude: ignore these) — replace with yours:*
- *Vercel, Supabase, Stitch, or other tools you use*

### Growth routines

> `/today` reads this section to populate the Evening — Grow block. Each routine points to a project note + section. Leave empty if you don't have growth routines yet — `/today` will gently suggest adding one.

*EXAMPLE ONLY (Claude: ignore this) — replace with yours:*

*Reading:*
- *Project: [[my-reading-project]]*
- *Section: Reading Queue*
- *Time: 19:00*
- *Streak label: Study*

*Writing:*
- *Project: [[my-writing-project]]*
- *Section: Writing Queue*
- *Time: 20:00*
- *Streak label: Content*

### Dev projects

> `/close-day` reads session reports from each local dir. Add your coding projects here so close-day can pick up what you shipped.

*EXAMPLE ONLY (Claude: ignore this) — replace with yours:*

| Project | Repo | Local dir | Stack |
|---------|------|-----------|-------|
| *My App* | *org/my-app* | *`~/code/org/my-app`* | *Next.js* |

---

## Command personalizations

> Every command checks its section here before executing. If a section says "No overrides," the command uses its default behavior. When a new command is created, add a placeholder section here.
>
> **How to personalize:** Replace "No overrides" with your specific preferences. Claude reads this as natural language. Examples:
> - *"Morning block should always start at 06:00, not adaptive"*
> - *"Never suggest /drift on Fridays — I already run it Wednesdays"*
> - *"Group weekly plan by client, not by venture"*

### /today

No overrides — use default behavior.

### /close-day

No overrides — use default behavior.

### /close-session

No overrides — use default behavior.

### /7plan

No overrides — grouping is automatic (reads ventures folder).

### /weekly-learnings

No overrides — use default behavior.

### /drift

No overrides — use default behavior.

### /graduate

No overrides — use default behavior.

### /emerge

No overrides — use default behavior.

### /compact

No overrides — use default behavior.

### /ideas

No overrides — use default behavior.

### /ghost

No overrides — use default behavior.

### /challenge

No overrides — use default behavior.

### /trace

No overrides — use default behavior.

### /connect

No overrides — use default behavior.

### /learned

No overrides — use default behavior.

### /housekeeping

No overrides — use default behavior.

### /role-report

No overrides — use default behavior.

### /company

No overrides — reads `## Companies (mounted)` section above.

### /aios:update

No overrides — reads `.aios-update` tracker at repo root.

### /mcps-setup

No overrides — use default behavior.

### /ingest

No overrides — use default behavior.

### /agent

No overrides — use default behavior.

### /collaborate

No overrides — use default behavior. (Spec runs end-to-end as documented; configure here only if you want to override the `/spaces/` Drive default, change the adjective-animal name suggester, or pre-set a substrate preference for new spaces.)
