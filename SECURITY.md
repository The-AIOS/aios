# What this can reach, and whose identity it acts as

> **Read this before you grant anything.** Not because AIOS is unsafe, and not to reassure you — because you cannot consent to something nobody described to you. If a word here is unfamiliar, [`GLOSSARY.md`](./GLOSSARY.md) defines it in one sentence; **not knowing the vocabulary is the normal starting position, not a disqualification.**
>
> Security reports: see the org-level [SECURITY policy](https://github.com/The-AIOS/.github/blob/main/SECURITY.md) for private disclosure. This file is the *posture* — what the software reaches and on whose behalf.

---

## The one thing to understand first

AIOS gives an AI session three things at once: **a large persistent memory of you**, **credentials that act as you**, and **the ability to run commands on your machine**. Each is ordinary on its own. Together they make something unusual, and the honest way to say it is:

> **You are configuring a privileged colleague whose judgment can be influenced by anything it reads.**

That last clause is the part with no clean fix. If a session reads an email, a web page, a PDF, a shared document or a GitHub issue, that content can contain instructions aimed at the session. This is called **prompt injection**, and the important question is not *"can a malicious email read my Drive?"* — it is ***"can the session that read the malicious email then call a tool that reads my Drive?"***

With these connectors, the answer is yes. That is not a defect being hidden from you; it is the shape of every agentic system, and the reason the rest of this document exists.

**Concretely, what reduces it:** connect fewer things; keep the identity that *reads untrusted content* separate from the identity that *holds credentials*; use a scoped bot rather than your own account where a bot will do; and read [`FORTRESS.md`](./FORTRESS.md), whose whole subject is limiting blast radius.

---

## Whose identity each surface acts as

This is the column most tools never show you, and it matters more than the permission list.

| Surface | Acts as | What that means |
|---|---|---|
| **Slack** | **You.** Not a bot. | Messages post under your name. Authentication is a `xoxc-`/`xoxd-` token pair **extracted from your Chrome session**, so the session holds your full interactive Slack identity — every channel and DM you can see. A dedicated Slack app with explicit scopes is the safer pattern for a work account, and AIOS does not currently ship one. |
| **Browser automation** | **You, on any site you are logged into.** | `mcps/playwright-mcp/cookie_import.py` decrypts your Chrome cookie store through the macOS Keychain and writes live session cookies to `auth/<site>.json`. Currently configured: Substack, LinkedIn, X, Paragraph. Anything with a valid cookie can be acted on — including services with no formal integration. |
| **Google Workspace** | You — across the services *you* enable | Calendar, Tasks, Drive, Docs, Sheets, Slides, Gmail, Contacts, Forms are available; **you choose which to turn on**, and Chat ships off by default. Apps Script is deliberately excluded as too broad. Fewer enabled is a smaller surface, and that choice is yours at setup and after. |
| **GitHub** | Your token's scopes | Whatever you granted the PAT. |
| **The vault + shell** | Your user account | A session can read, write, commit, push, and run commands as you. |

**Why the Slack and browser rows deserve a second read.** An AI service identity that misbehaves is a contained incident. *Your* identity misbehaving is a message your colleagues believe came from you. That distinction is worth more than any permission toggle.

**One mitigation costs nothing and helps a lot:** use a **separate Chrome profile** containing only services you intend an agent to reach. `cookie_import.py` reads whatever profile it is pointed at — so what it *cannot* see is decided by which browser you log into.

---

## Where credentials live

Locally, on your machine. AIOS has no cloud backend and sends your credentials nowhere.

- `~/.claude.json` — MCP configuration and some credentials
- `~/.google_workspace_mcp/credentials/` — Google OAuth tokens
- `mcps/playwright-mcp/auth/*.json` — live session cookies (**gitignored**, `.gitignore:41`, so they are never committed)
- `~/.zshrc` or a dedicated secrets file — API keys

**What "local" does and does not mean.** It means no third party receives them. It does **not** mean hardware-isolated: **any process running as your user can read these files.** That is true of most developer tooling and worth knowing rather than discovering.

---

## The update model, stated without euphemism

**`/aios:update` pulls framework code from GitHub and applies it**, and some updates include installer scripts that write outside your vault — to `~/.zshrc`, `~/.claude/` or `~/Library/LaunchAgents/`. `/today` and `/close-day` run the update automatically when your vault is behind. **Files apply on their own; anything that executes asks you first.**

Updates arrive as **git commits you can read** — every change is in the public history, and your session can show you any of them. Cryptographic signature verification is not part of that path today; if you would rather approve each update yourself before it applies, the `### /aios:update` personalization at the end of this section gives you exactly that.

**Automatic updates are ON by default, and that is a deliberate choice** — a framework that silently rots because nobody updated it has its own failure mode. What was *not* acceptable was doing it without telling you. So:

**1. Every session asks before running anything that writes outside your vault** — and it asks with evidence rather than reassurance. It reads the actual script from the downloaded copy and tells you what it found:

> *"This update changes one installer: `hooks/claude-identity/install-wrappers.sh`. It writes to `~/.zshrc`. It's the same script that ran on your last 11 updates; 3 lines changed — here they are. Run it? [y / n / show me the whole file]"*

Specificity is what makes that calm. **"This is safe" is calm and unfounded**, and a session is instructed never to say it — the entry supplies *what* and *why*, the diff supplies *whether*. A new installer always asks. And a diff you can see is a diff an attacker has to survive, which is a real control where a reassurance is not.

**2. You can ask, any time, in plain language.** *"What will this update run?"* · *"Show me what changed in that script."* · *"What can the Slack connector actually do?"* Your session has the downloaded diff in front of it and will answer from the file, not from a claim about the file.

**3. You can turn it off, permanently, in one line.** In your `USER.md`:

```
- **Automatic updates:** no
```

With `no`, `/today` and `/close-day` will **tell you** you are behind and never act on it. To review every update before it applies, add this to `USER.md` → `## Command personalizations`:

```
### /aios:update
Never auto-apply. Show me the changed-file list and the diff of any script
that would be executed, then wait for my go-ahead.
```

**For a machine holding corporate credentials, that review-first posture is the one we would recommend** — along with an internal mirror pinned to a reviewed commit, which AIOS does not provide and which you would operate yourself.

---

## Third-party code: what is reviewed, and what is not

**AIOS ships with bundled MCPs, and many of them are written by other people.** The table separates ours from theirs and says which version is in play, because *which version* is the question you can actually act on. `unpinned` rows appear where true — a table listing only the reassuring rows converts an unknown into a false assurance.

Pinning policy and the connect-time disclosure rule: [`mcps/_index.md`](./mcps/_index.md). Enforced by `tests/lint-mcp-pinning.py`.

### AIOS-built — our code, read for this document (2026-09-15)

| Server | Ours | What it reaches · stores | Status |
|---|---|---|---|
| `playwright-mcp` | 136 loc | **Decrypts the Chrome cookie store via Keychain**; writes live cookies to `auth/*.json` (gitignored). No network of its own. | **reviewed 2026-09-15** · `browser-cookie3==0.20.1` pinned (was undeclared) |
| `notebooklm-mcp` | 94 loc | Drives a real browser against `notebooklm.google.com` using your Google session; saves `~/.notebooklm/storage_state.json`. | reviewed 2026-09-15 · `playwright==1.58.0` |
| `pdf-generator-mcp` | 163 loc | Local only — runs headless Chrome over a temp file to render PDFs. No credentials, no network. | reviewed 2026-09-15 · `mcp` pinned |
| `spotify-dj-mcp` | 141 loc | Spotify via `spotipy`, OAuth to `127.0.0.1:8888`, keys from env. | reviewed 2026-09-15 · `mcp`, `spotipy` pinned |
| `nano-banana-mcp` | 82 loc | Google GenAI image generation; `GEMINI_API_KEY` from env; writes images into the vault. | reviewed 2026-09-15 · `mcp`, `google-genai` pinned |
| `google-workspace-mcp` (helper) | 83 loc | Stdlib only. Reads a local debug log, writes an OAuth consent URL into `auth_link.html`. **The server itself is third-party** — see below. | reviewed 2026-09-15 |

### Third-party — code AIOS does not write, and you can audit any time

| Server | Source | Status |
|---|---|---|
| `slack-mcp` | `@jtalk22/slack-mcp` **v3.2.5** — vendored, runs from the local copy | **vendored at a recorded version.** The code is in this repo: read it, or ask your session to walk you through any part of it. |
| `atlassian-mcp` | `uvx mcp-atlassian` at runtime | **unpinned** — resolved at launch; a session discloses the version and what it declares before connecting |
| Google Workspace server | `uvx workspace-mcp` at runtime | **unpinned** — resolved from the registry at launch, so a session discloses the version and what it declares before connecting it |
| `obsidian-mcp` | `npx @mauricio.wolff/mcp-obsidian@latest` | **unpinned** — resolved from the registry at launch, so a session discloses the version and what it declares before connecting it |
| `stitch-mcp` | `npx @_davideast/stitch-mcp` | **unpinned** — resolved from the registry at launch, so a session discloses the version and what it declares before connecting it |

**Why four rows still say `unpinned`.** Their versions could not be resolved when this was written, and **a guessed pin is worse than a recorded gap** — it reads as a verified version and is not one. They are tracked in the lint's `KNOWN_UNPINNED` ratchet: an entry leaves by being pinned, never by being deleted, and any *new* unpinned invocation fails the build.

**What `reviewed` claims, precisely:** someone read those lines on that date and this table describes what they do. It does **not** claim a later version behaves the same — that is what pinning is for, and pinning gives **reproducibility**: the code you ran yesterday is the code that runs tomorrow.

---

## Governance is not enforcement

[`INTENT.md`](./INTENT.md) records how much autonomy you want per domain. **Adherence to it is soft** — it shapes behaviour, it cannot compel it. Hard limits come from Claude Code's own permission system, and a headless run needs `--permission-mode` beside any tool allowlist or the allowlist is advisory (`CLAUDE.md` § Spawning Sessions, measured).

**AIOS's defaults favour capability, and tightening them is something you do deliberately.** A reasonable critique is that this is backwards — that secure defaults should be the baseline and autonomy the conscious opt-in. If your machine holds credentials that matter, treat [`FORTRESS.md`](./FORTRESS.md)'s containment rungs as the starting point rather than the advanced chapter.

---

## What is already in place

These are the controls you inherit without configuring anything — worth knowing, because most of them are invisible when they work.

- **Credentials never leave your machine.** No cloud backend, no telemetry of your vault.
- **Live session cookies are gitignored** (`.gitignore:41`) — they cannot be committed by accident, which is the realistic way such a file leaks.
- **32 credential-leak checks run in CI** on every change, plus a personalization guard that fails the build if operator-specific content reaches canonical.
- **Vendored MCPs record their upstream** in a `.upstream-sync` file (repo, commit, date), so what was taken and when is auditable.
- **Dependency pins exist and are now enforced** — `tests/lint-mcp-pinning.py` fails the build on any new unpinned invocation.
- **The desktop app is Developer-ID signed and Apple-notarized**, with signature verification in its updater and signed-build verification in CI before publishing.
- **[`FORTRESS.md`](./FORTRESS.md) documents a six-layer containment architecture** for running autonomous agents — network isolation, ecosystem lockdown, SSH hardening, permission gates, one-way data flow, recovery. It also states the thing most such documents omit: *a second machine does nothing about badly scoped credentials.* Isolation limits blast radius; it does not fix authorization.
- **[`INTENT.md`](./INTENT.md) says plainly that its own adherence is soft** and that hard limits require Claude Code's permission system. A governance document that admits it is not enforcement is doing its job.
- **Private disclosure process** — see the org-level SECURITY policy.

**If any of this rules AIOS out for your machine, that is a legitimate conclusion. With great AI powers come great AI responsibilities. This is why AIOS is designed to be *yours* — so you can always decide what to connect, and what to leave out of reach of your AI.**

