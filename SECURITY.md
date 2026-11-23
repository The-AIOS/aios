# What this can reach, and whose identity it acts as

> **Read this before you grant anything.** Not because AIOS is unsafe, and not to reassure you — because you cannot consent to something nobody described to you. If a word here is unfamiliar, [`GLOSSARY.md`](./GLOSSARY.md) defines it in one sentence; **not knowing the vocabulary is the normal starting position, not a disqualification.**
>
> Security reports: see the org-level [SECURITY policy](https://github.com/The-AIOS/.github/blob/main/SECURITY.md) for private disclosure. This file is the *posture* — what the software reaches and on whose behalf.

---

## What leaves your machine

- **Everything a session reads goes to Anthropic as model input**: the notes, mail, calendar entries and files it opens, your messages, and any file it happens to read, a token file included. That is how the model sees them. How long Anthropic keeps them, and whether they are used for training, follows **your Claude account's terms**, not anything AIOS sets. Claude Code's own usage reporting is Anthropic's, configured in Claude Code, not by AIOS.
- **Each connector talks to its own provider, as you.** Google, Slack, GitHub and the rest receive what a session asks them for, under your account.
- **Your vault's history goes to the git host you chose** (a private repository you own, which is still a copy on that host's servers).
- **Web searches and page fetches** go to the search and web services a session calls. **Optional other models** (the text bridge in `hooks/pipeline/openrouter.py`) receive only the text sent to them, and only if you set them up.
- **Any tool that can send can be told to send.** A session that can email, post or run `curl` can carry what it read anywhere, if something it read instructs it to. See prompt injection, below.
- **What stays with you:** AIOS has no server of its own and sends no telemetry, and it never sends your credentials anywhere by design. Tokens sit on your disk, readable by whatever runs as you.

To remove AIOS completely, see [§ Uninstall](#uninstall). To check whether your terminal commands run sandboxed, run `/sandbox` in Claude Code.

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
- **Turn on your remote's force-push protection for `main`** (GitHub: a branch rule that blocks force pushes). AIOS's `pre-push` hook makes an agent stop and ask you before a force push or a branch deletion, but an agent can re-run with the override once it has your yes, and a hook only exists on machines that installed it. The remote's rule holds for every machine and every session. Deleted files need no lock: each commit says how many it deletes, and git keeps the undo.
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
| **Browser automation** | **You, on any site you are logged into.** | `mcps/playwright-mcp/cookie_import.py` decrypts your Chrome cookie store through the macOS Keychain and writes live session cookies to `auth/<site>.json`. The importer knows Substack, LinkedIn, X and Paragraph out of the box, and imports only the sites you name. Anything with a valid cookie can be acted on — including services with no formal integration. |
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
| `playwright-mcp` | 166 loc | **Decrypts the Chrome cookie store via Keychain**; writes live cookies to `auth/*.json` (gitignored). No network of its own. | **reviewed 2026-11-23** (each cookie now kept only for its own site; files owner-only) · `browser-cookie3==0.20.1` pinned (was undeclared) |
| `notebooklm-mcp` | 94 loc · **vendored** from `teng-lin/notebooklm-py` | Drives a real browser against `notebooklm.google.com` using your Google session; saves `~/.notebooklm/storage_state.json`. | reviewed 2026-09-15 · `playwright==1.58.0` |
| `pdf-generator-mcp` | 163 loc | Local only — runs headless Chrome over a temp file to render PDFs. No credentials, no network. | reviewed 2026-09-15 · `mcp` pinned |
| `spotify-dj-mcp` | 141 loc | Spotify via `spotipy`, OAuth to `127.0.0.1:8888`, keys from env. | reviewed 2026-09-15 · `mcp`, `spotipy` pinned |
| `nano-banana-mcp` | 82 loc | Google GenAI image generation; `GEMINI_API_KEY` from env; writes images into the vault. | reviewed 2026-09-15 · `mcp`, `google-genai` pinned |
| `google-workspace-mcp` (helper) | 83 loc | Stdlib only. Reads a local debug log, writes an OAuth consent URL into `auth_link.html`. **The server itself is third-party** — see below. | reviewed 2026-09-15 |

### Code that lives outside AIOS — resolved when it launches

These folders hold configuration and documentation; **the program that actually runs is fetched from npm or PyPI at launch.** A session discloses the resolved version and what the package declares before connecting one.

⚠️ **A vendored copy is only worth reading if it is what runs.** `slack-mcp` posts to Slack *as you*, and until 2026-09-25 the repo held a 3.2.5 copy while every registration ran whatever npm published (5.0.0 by then). It now carries the complete published `@jtalk22/slack-mcp@5.0.0` package, byte for byte, and every registration pins that same version — so reading `mcps/slack-mcp/` is reading what executes. Its two dependencies are `^`-ranged and resolve at launch; the pin narrows the unpinned surface to them, it does not remove it. `tests/vendored-pins.test.sh --upstream mcps/slack-mcp` proves the copy against the published package.

| Server | Source | Status |
|---|---|---|
| `atlassian-mcp` | `uvx mcp-atlassian==0.23.1` at runtime | **pinned** — the version verified against a live Jira, 2026-09-25 |
| Google Workspace server | `uvx workspace-mcp` at runtime | **unpinned** — resolved from the registry at launch, so a session discloses the version and what it declares before connecting it |
| `obsidian-mcp` | `npx @mauricio.wolff/mcp-obsidian@latest` | **unpinned** — resolved from the registry at launch, so a session discloses the version and what it declares before connecting it |
| `stitch-mcp` | `npx @_davideast/stitch-mcp` | **unpinned** — resolved from the registry at launch, so a session discloses the version and what it declares before connecting it |
| `slack-mcp` | `npx -y @jtalk22/slack-mcp@5.0.0`, the same package vendored in `mcps/slack-mcp/` | **pinned** (dependencies `^`-ranged) — acts as you in Slack |

**Why three rows still say `unpinned`.** A pin is written only once the version has been verified running, because **a guessed pin is worse than a recorded gap** — it reads as a verified version and is not one. Atlassian and Slack left the list on 2026-09-25, each pinned to the version smoke-tested against a live account; the GitHub server was retired the same day rather than pinned. The rest stay tracked in the lint's `KNOWN_UNPINNED` ratchet: an entry leaves by being pinned, never by being deleted, and any *new* unpinned invocation fails the build.

Two of the original six were invisible to that lint until this section was first written. `mcps/setup.sh` probes reachability with `npx -y <pkg> --help` and `uvx <pkg> --help`, and the lint skipped any line containing `--help` as documentation — but a `--help` probe downloads and executes whatever the registry publishes, exactly like a real launch. **An escape hatch wide enough to hide a real invocation is not a false-positive fix; it is a blind spot.**

**What `reviewed` claims, precisely:** someone read those lines on that date and this table describes what they do. It does **not** claim a later version behaves the same — that is what pinning is for, and pinning gives **reproducibility**: the code you ran yesterday is the code that runs tomorrow.

---

## Governance is not enforcement

[`INTENT.md`](./INTENT.md) records how much autonomy you want per domain. **Adherence to it is soft** — it shapes behaviour, it cannot compel it. Hard limits come from Claude Code's own permission system, and a headless run needs `--permission-mode` beside any tool allowlist or the allowlist is advisory (`CLAUDE.md` § Spawning Sessions, measured).

**AIOS's defaults favour capability, and tightening them is something you do deliberately.** A reasonable critique is that this is backwards — that secure defaults should be the baseline and autonomy the conscious opt-in. If your machine holds credentials that matter, treat [`FORTRESS.md`](./FORTRESS.md)'s containment rungs as the starting point rather than the advanced chapter.

---

## What is already in place

These are the controls you inherit without configuring anything — worth knowing, because most of them are invisible when they work.

- **AIOS never sends your credentials anywhere.** It has no backend of its own and no telemetry of your vault. A session that reads a token file does send it to Anthropic as model input, like anything else it reads; § [What leaves your machine](#what-leaves-your-machine) lists every channel.
- **Live session cookies are gitignored** (`.gitignore:41`) — they cannot be committed by accident, which is the realistic way such a file leaks.
- **32 credential-leak checks run in CI** on every change, plus a personalization guard that fails the build if operator-specific content reaches canonical.
- **Vendored MCPs record their upstream** in a `.upstream-sync` file (repo, commit, date), so what was taken and when is auditable.
- **Dependency pins exist and are now enforced** — `tests/lint-mcp-pinning.py` fails the build on any new unpinned invocation.
- **The desktop app is Developer-ID signed and Apple-notarized**, with signature verification in its updater and signed-build verification in CI before publishing.
- **[`FORTRESS.md`](./FORTRESS.md) documents a six-layer containment architecture** for running autonomous agents — network isolation, ecosystem lockdown, SSH hardening, permission gates, one-way data flow, recovery. It also states the thing most such documents omit: *a second machine does nothing about badly scoped credentials.* Isolation limits blast radius; it does not fix authorization.
- **[`INTENT.md`](./INTENT.md) says plainly that its own adherence is soft** and that hard limits require Claude Code's permission system. A governance document that admits it is not enforcement is doing its job.
- **Private disclosure process** — see the org-level SECURITY policy.

**If any of this rules AIOS out for your machine, that is a legitimate conclusion. With great AI powers come great AI responsibilities. This is why AIOS is designed to be *yours* — so you can always decide what to connect, and what to leave out of reach of your AI.**


---

## Uninstall

How to remove what AIOS adds. Do it in this order, and do the last step even if you skip others: **deleting a file never revokes access, only the provider can.** `/aios:uninstall` walks it on your machine: it inventories what is present, shows each removal and runs it only on your yes, and backs up the vault before touching it. Nothing below should be deleted without you seeing it first.

1. **Quit the AIOS App** and remove it (macOS: drag `AIOS.app` to the Trash; its settings live in `~/Library/Application Support/AIOS`; on Windows and Linux, the App's own uninstaller and its settings folder). Remove the **AIOS Glass** extension from your editor if you installed it.
2. **Remove the Claude Code wiring.**
   - In `~/.claude/settings.json`: the hooks whose commands name `aios/hooks/`, the `statusLine` if it runs `context-monitor.py`, and `cleanupPeriodDays` if AIOS set it. Every installer run that wrote the file left a backup beside it (`settings.json.bak-aios-<time>`); the oldest is your file from before AIOS, if the installer made the first change.
   - The plugin: `claude plugin uninstall aios@the-aios`, then `claude plugin marketplace remove the-aios`.
   - The skills AIOS linked into `~/.claude/skills/`: the links that point into your AIOS checkout's `skills/` folder.
   - The MCP servers AIOS registered in `~/.claude.json` (`claude mcp list` shows them; `claude mcp remove <name>` removes one), and the folder trust for `~/.aios/run` in the same file.
   - **Your session transcripts** in `~/.claude/projects/` hold everything your sessions read, mail included, and AIOS asked Claude Code to keep them for years. Delete the ones you no longer want, and remove `cleanupPeriodDays` so the default applies again.
3. **Remove the shell wiring.** In `~/.zshrc` or `~/.bashrc` (Windows: your PowerShell `$PROFILE`), delete the blocks between `# ==== claude-spawn-wrappers` and `# ==== END claude-spawn-wrappers ====`, and between `# ==== claude-primary-session` and its `END` line, **and any API keys you exported there**. Remove `~/.local/bin/aios-commit` (Windows: `~/bin/aios-commit.cmd`) and the `~/aios` link if you made one.
4. **Stop background jobs.** The quota watcher keeps rotating Claude accounts until it is removed.
   - macOS: `launchctl list | grep claude-quota-watch` finds it (it may carry your organisation's name instead of `com.aios`); `launchctl unload` its plist in `~/Library/LaunchAgents/`, then delete the file.
   - Linux: `systemctl --user disable --now aios-claude-quota-watch.timer`, then delete the `.service` and `.timer` files.
   - Windows: `pwsh -File hooks/claude-identity/install-quota-watch.ps1 -Uninstall`.
   - Any Slack token-refresh job you set up from `mcps/slack-mcp`.
5. **Remove local state:** `~/.aios/` (the spawn inbox, surfaces, boards, run folders, bus logs).
6. **Remove credentials on disk:**
   - `~/.google_workspace_mcp/` and `~/.workspace-mcp/` (OAuth state and downloaded mail attachments);
   - `~/.slack-mcp-tokens.json` (the live Slack tokens), `~/.slack-mcp-meta.json`, `~/.slack-mcp-workflows.json`, and on macOS the Keychain items named `slack-mcp-server` (Keychain Access, search for it);
   - `~/.config/aios-secrets/`;
   - the browser cookies imported for the Playwright connector, under `mcps/playwright-mcp/auth/` inside the vault;
   - the extra Claude accounts used for switching: `~/.claude/identities/` and the `~/.claude-acct-*` folders;
   - `~/.notebooklm/` (a signed-in Google browser session), `~/.claude/spotify-cache.json`, `~/.stitch-mcp/`;
   - any other token or session file a connector created; each connector's README in `mcps/` names its own.
7. **Decide about your vault.** `~/aios` holds your notes and their history, and its remote is your backup. It is yours, not the framework's: keep it, archive it, or delete it, but only on purpose. If you keep it, the cookie files in step 6 are inside it.
8. **Revoke access at every provider (required).**
   - Google: your account's *Third-party apps & services* page; remove each AIOS connector. If you used NotebookLM, also sign that browser session out (*Your devices* in the Google account).
   - Slack: sign out the session the connector used, or revoke the app.
   - GitHub: delete the personal access tokens and OAuth apps you made for it.
   - Each site whose cookies you imported (Substack, LinkedIn, X and the like): sign out everywhere.
   - Claude: sign out each account you added for switching.
   - Any other connector: its own *connected apps* page.

   Until this step is done, a copied token or cookie keeps working.
