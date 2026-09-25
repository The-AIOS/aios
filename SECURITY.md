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

**Concretely, what reduces it.** Not one of these is something AIOS switches on for you. They are the levers *you* hold, which is the point — and they are in the order that matters most.

- **Be wise in the models you use.** A model's own refusal behaviour **is one of the controls**, and no permission setting substitutes for it. See below.
- **Scope your connectors to what you actually need.** A server that was never connected cannot be talked into anything. You choose which Google services to enable (the table below), and a worker can be started holding only the servers it needs — `spawn --profile <name>` loads just those, which is about blast radius rather than saving tokens.
- **Define your autonomy levels deliberately** in [`INTENT.md`](./INTENT.md) — and read § *Governance is not enforcement* below before trusting them, because that file shapes behaviour while Claude Code's permission system is what compels it.
- **If you are going to leave it genuinely autonomous, point it only at places you trust.** Autonomy is fine. Untrusted input is survivable. **The combination is the problem** — an unattended run has nobody present to answer a prompt, and silence must never count as yes. Poisoned sources are worse than they sound: the corruption sits *upstream* of the model, so the model cannot detect it.
- **Keep the identity that *reads untrusted content* separate from the identity that *holds credentials*.** This is the structural fix for the paragraph above, rather than a mitigation of it.
- **Use a scoped bot rather than your own account wherever a bot can do the job on its own.** A bot misbehaving is a contained incident; *you* misbehaving is a message your colleagues believe came from you.
- **Read [`FORTRESS.md`](./FORTRESS.md)**, whose whole subject is limiting blast radius.

**Why the model you run belongs on a security page at all.** When a malicious document instructs a session to paste a credential somewhere, the thing that declines is **the model** — not a setting, not a permission prompt, and certainly not this document. That behaviour differs between models, and AIOS cannot supply it on their behalf.

AIOS is built around Claude Code, and a **spawned worker** is always a Claude model: `spawn` passes its model argument straight to the `claude` binary. But the repo also ships [`AGENTS.md`](./AGENTS.md) for other tools that read that convention, and the desktop app **opens terminals** — whatever CLI you run inside one is what is actually running, whoever made it. So which model holds your credentials is a live choice, not a default.

When you genuinely need another model family, call it as a *tool* — text in, text out, no credentials, no vault writes. [`MODEL-ROUTING.md`](./MODEL-ROUTING.md) draws that boundary and explains the privacy trade.

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

**Claude Code's sandbox does not change that by default.** Sandboxed Bash can read these folders unless each one is named in the sandbox's `filesystem.denyRead`, and a `Read(...)` deny rule in `permissions` does not stop it. If a headless job runs `Bash` under the sandbox, list every folder above in a settings file only that job loads, not in your interactive settings: [`MODEL-ROUTING.md`](./MODEL-ROUTING.md) § Verify an id before you trust it has the settings and why.

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

**AIOS ships with bundled MCPs, some written by other people.** The split below is not who wrote them — it is **where the code lives**: fully inside this repo, where you can read it now, or resolved from a registry when it launches, where you cannot. That distinction cuts across authorship, and it is the one you can act on. `unpinned` rows appear where true — a table listing only the reassuring rows converts an unknown into a false assurance.

Pinning policy and the connect-time disclosure rule: [`mcps/_index.md`](./mcps/_index.md). Enforced by `tests/lint-mcp-pinning.py`.

### Code that lives inside AIOS — readable in this repo right now

Five of these are AIOS-built (`playwright`, `pdf-generator`, `spotify-dj`, `nano-banana`, and the Google Workspace helper); `notebooklm-mcp` is vendored whole from an open-source upstream, with the exact commit recorded in a `.upstream-sync` file beside it. Either way **the code is here**: read it, or ask your session to walk you through any part of it.

| Server | Code in this repo | What it reaches · stores | Status |
|---|---|---|---|
| `playwright-mcp` | 136 loc | **Decrypts the Chrome cookie store via Keychain**; writes live cookies to `auth/*.json` (gitignored). No network of its own. | **reviewed 2026-09-15** · `browser-cookie3==0.20.1` pinned (was undeclared) |
| `notebooklm-mcp` | 94 loc · **vendored** from `teng-lin/notebooklm-py` | Drives a real browser against `notebooklm.google.com` using your Google session; saves `~/.notebooklm/storage_state.json`. | reviewed 2026-09-15 · `playwright==1.58.0` |
| `pdf-generator-mcp` | 163 loc | Local only — runs headless Chrome over a temp file to render PDFs. No credentials, no network. | reviewed 2026-09-15 · `mcp` pinned |
| `spotify-dj-mcp` | 141 loc | Spotify via `spotipy`, OAuth to `127.0.0.1:8888`, keys from env. | reviewed 2026-09-15 · `mcp`, `spotipy` pinned |
| `nano-banana-mcp` | 82 loc | Google GenAI image generation; `GEMINI_API_KEY` from env; writes images into the vault. | reviewed 2026-09-15 · `mcp`, `google-genai` pinned |
| `google-workspace-mcp` (helper) | 83 loc | Stdlib only. Reads a local debug log, writes an OAuth consent URL into `auth_link.html`. **The server itself is third-party** — see below. | reviewed 2026-09-15 |

### Code that lives outside AIOS — resolved when it launches

These folders hold configuration and documentation; **the program that actually runs is fetched from npm or PyPI at launch.** A session discloses the resolved version and what the package declares before connecting one.

⚠️ **A vendored copy is not a running copy, and `slack-mcp` is the case to understand.** Its full 3,254 lines *are* in this repo, with the upstream commit recorded — and its registration is `npx -y @jtalk22/slack-mcp`, so what executes is whatever npm publishes at launch. **Reading the copy in this repo tells you nothing about what ran**, and it is the surface that posts to Slack *as you*. You can register it against the local entry point (`mcps/slack-mcp/src/server.js`) instead of `npx` — that ships no lockfile, so an `npm install` there resolves two caret-ranged dependencies. It narrows the unpinned surface from the whole server to those two; it does not remove it.

| Server | Source | Status |
|---|---|---|
| `atlassian-mcp` | `uvx mcp-atlassian` at runtime | **unpinned** — resolved at launch; a session discloses the version and what it declares before connecting |
| Google Workspace server | `uvx workspace-mcp` at runtime | **unpinned** — resolved from the registry at launch, so a session discloses the version and what it declares before connecting it |
| `obsidian-mcp` | `npx @mauricio.wolff/mcp-obsidian@latest` | **unpinned** — resolved from the registry at launch, so a session discloses the version and what it declares before connecting it |
| `stitch-mcp` | `npx @_davideast/stitch-mcp` | **unpinned** — resolved from the registry at launch, so a session discloses the version and what it declares before connecting it |
| `slack-mcp` | `npx -y @jtalk22/slack-mcp` at runtime — **a vendored copy sits in this repo and is not what runs** (upstream commit recorded) | **unpinned** — and this is the one that acts as you in Slack |

**Why all six rows say `unpinned`.** Their versions could not be resolved when this was written, and **a guessed pin is worse than a recorded gap** — it reads as a verified version and is not one. All six are tracked in the lint's `KNOWN_UNPINNED` ratchet: an entry leaves by being pinned, never by being deleted, and any *new* unpinned invocation fails the build.

Two of the six were invisible to that lint until this was written. `mcps/setup.sh` probes reachability with `npx -y <pkg> --help` and `uvx <pkg> --help`, and the lint skipped any line containing `--help` as documentation — but a `--help` probe downloads and executes whatever the registry publishes, exactly like a real launch. **An escape hatch wide enough to hide a real invocation is not a false-positive fix; it is a blind spot.**

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

