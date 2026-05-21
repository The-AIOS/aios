# claude-identity

Multi-account Claude Code identity manager + quota autopilot. One tool that:

1. **Saves, restores, and rotates** between multiple Anthropic accounts (Keychain + `~/.claude.json` identity metadata). Never touches bundled MCPs.
2. **Caches** the `rate_limits` object from Claude Code by piggybacking on the statusLine process (the only surface that receives it), written to `~/.claude/rate-limit-cache.json`. After every cache write the cache writer fires `_watch.py` in the background (rate-limited to once per 30s) for fast threshold-crossing detection.
3. **Watches** that cache from a launchd agent every 30 minutes as a safety net — fires the same `_watch.py` so sessions where the statusLine pipe is broken or absent still get rotation eventually. Crosses the threshold? Rotates accounts so an overnight agent or long-running session can keep working instead of hitting the cap.

## How it works (data flow)

```
┌───────────────────┐
│  Claude Code API  │
│    responses      │
└─────────┬─────────┘
          │ rate_limits in internal state
          ▼
┌───────────────────┐       bash -c 'tee >(...) | ctx-monitor.py'
│    statusLine     │──────────┬──────────────────────────┐
│  fires on every   │          │                          │
│     refresh       │          ▼                          ▼
└───────────────────┘   ┌──────────────┐         ┌──────────────────┐
                        │ _cache.py    │         │ context-monitor  │
                        │ extracts     │         │ renders visible  │
                        │ rate_limits  │         │ statusline text  │
                        │ + email      │         └──────────────────┘
                        └──────┬───────┘
                               ▼
                    ┌──────────────────────────┐    fire-and-forget
                    │ ~/.claude/               │    Popen, ≤1× per 30s
                    │ rate-limit-cache.json    │────────────────────┐
                    └──────────┬───────────────┘                    │
                               │                                    │
                               │                                    │
                               ▼                                    ▼
                    ┌──────────────────────────┐   safety-net,  ┌────────────────┐
                    │ _watch.py (launchd)      │◀──every 30min──│  fast path     │
                    │ - read cache             │                │  (statusLine   │
                    │ - if stale > 30min: skip │                │  → _cache.py)  │
                    │ - if cooldown <15min:    │                └────────────────┘
                    │     skip                 │
                    │ - apply thresholds       │
                    │ - call switch if needed  │
                    └──────────┬───────────────┘
                               │
                        ┌──────┴──────┐
                        ▼             ▼
                   ┌─────────┐   ┌────────────────┐
                   │ Keychain│   │ ~/.claude.json │
                   │  swap   │   │  identity swap │
                   └─────────┘   └────────────────┘
```

**Key property:** statusLine fires multiple times per second during active use, so the cache is effectively live. The cache writer kicks `_watch.py` in fire-and-forget mode after every cache write, rate-limited to once per 30s — sub-30s detection of a rapid burn without spawning a process per render. The 30-min launchd safety net catches sessions where the statusLine pipe is broken or absent (and avoids pinning the Mac awake during sleep — the prior 60s interval kept DarkWake cycles from completing).

---

## Setup

> **For Claude (running this section during `/aios:update`):** these are instructions for *you*, the teammate's Claude session, to walk them through setup interactively. Don't dump the whole list at the user — execute one step at a time, ask the questions inline, write the files for them, run the commands. The user's job is to answer questions and confirm; your job is to do the work. Skip steps that are already done (detect state first). **Step 6 is the last automated step** — it requires restarting Claude Code, which ends this `/aios:update` session; finish step 6, tell the user to relaunch, and let them run step 7 manually.
>
> **Hard preconditions — check both before any step runs:**
>
> 1. **macOS only.** The autopilot uses `security` (Keychain), `launchctl`, `~/Library/LaunchAgents/`, and `osascript` — all macOS-specific. If `uname -s` ≠ `Darwin`, tell the user: *"This autopilot is macOS-only — it relies on Keychain Services and launchd. The scripts are now in your repo but won't run on Linux/Windows. Skipping setup."* Then **skip the rest of setup entirely**.
> 2. **≥ 2 Anthropic accounts.** This autopilot only brings value with multiple accounts in rotation. If step 1 (below) establishes the user has fewer than 2, **skip steps 2 through 7 entirely** — the scripts stay dormant in their repo until they configure ≥ 2 accounts in `USER.md`. Don't try to run capture, plist install, or statusLine wire on a single-account user.

Paths below assume the vault is at `~/obsidian`. If you cloned elsewhere, either symlink `~/obsidian → /your/path` or substitute the full path.

### 1. Configure Anthropic accounts in USER.md (interactive)

**State to detect:**
- Read `~/obsidian/USER.md` (or wherever the user's `USER.md` lives — it's at the repo root of their local clone).
- Look for `## Anthropic accounts (quota management)` section. Parse any existing `N. \`email\`` lines.

**If the section already has ≥ 2 accounts:** show the list and ask: *"You already have {N} accounts configured: {list}. Add more, replace the list, or skip this step?"* Take action accordingly. If they say skip, move to step 2.

**If the section is missing or has < 2 accounts:** ask the user, one question at a time:

1. *"Do you run multiple Anthropic accounts to manage the 5h/7d rate caps? (y/n)"*
   - **If no →** the autopilot is dormant by design without ≥ 2 accounts. Tell the user: *"OK — skipping autopilot setup. The `hooks/claude-identity/` scripts are in your repo and stay inert until you add ≥ 2 accounts to USER.md. To activate later: re-run setup after you add a second account, or read this README to set it up by hand."* Then **stop processing setup entirely** — do NOT continue to step 2.
   - **If yes →** continue with the next two questions.
2. *"How many accounts do you want to register for rotation? (need at least 2 for the autopilot to be useful)"* — store as N. If the user answers `1` or `0` here, treat it as the "no" branch above.
3. Loop `i` from 1 to N: *"Account {i} email:"* — collect each.

**Then write the section into their USER.md.** `USER.md` lives at the repo root, **outside `vault/`** — so do NOT use `mcp__obsidian__patch_note` (the Obsidian MCP only works inside `vault/`). Use the `Edit` tool (read `USER.md`, find a unique anchor like the last line of the previous section, replace with that anchor + the new section). If `USER.md` doesn't exist, use `Write` to create it with the section. The exact content to insert:

```markdown
## Anthropic accounts (quota management)

> `hooks/claude-identity/claude-identity.sh` parses the numbered list below as rotation slots. Order defines rotation. The parser requires backticks around each email — `N. \`email\``.

1. `{email_1}` — primary
2. `{email_2}` — overflow
{...etc for N accounts}
```

Confirm what was written: *"Added {N} accounts to USER.md → ## Anthropic accounts. Order defines rotation."*

### 2. Capture each account's identity (semi-manual — Keychain requires graphical context)

**State to detect:** for each email in USER.md, check whether `~/.claude/identities/{email}/` exists. Run `ls ~/.claude/identities/ 2>/dev/null` and compare.

**For each account already captured:** report *"✓ {email} already captured — skipping."*

**For each missing account, explain to the user (Claude can't fully automate this):**
> *"Capturing `{email}` requires you to be logged into that Anthropic account in this Claude Code session, because macOS Keychain access needs a graphical context. I can't automate the `/login`. The flow is:*
>
> 1. *Run `/login` and pick `{email}` (or sign in for the first time).*
> 2. *Confirm here and I'll run `claude-identity.sh switch --capture` for you.*
> 3. *macOS will prompt — click "Always Allow".*
>
> *Want to do this now, or skip and capture all accounts manually later?"*

If user wants to skip: tell them they can run `~/obsidian/hooks/claude-identity/claude-identity.sh switch --capture` after each `/login` later. Move on.

If user goes through the flow: after each `/login` confirmation, run:
```bash
~/obsidian/hooks/claude-identity/claude-identity.sh switch --capture
```
Verify the capture succeeded with `claude-identity.sh list`. Repeat for each account.

> **Note:** `/login` switches the active session, but the running Claude Code (this session) keeps its old token in memory and may behave inconsistently. Tell the user that's expected; the captures still land correctly because the Keychain rewrite is what matters.

### 3. Install shell aliases (interactive)

**State to detect:** identify the user's shell:
```bash
echo $SHELL
```
Pick the matching rc file (`~/.zshrc` for zsh, `~/.bashrc` for bash). Read it. Check whether `claude-whoami` and `claude-switch` are already defined (`grep -E '^(claude-whoami|claude-switch)\(\)' {rcfile}`).

**If both already present:** *"✓ shell aliases already installed."*

**If missing:** ask *"Install `claude-whoami` and `claude-switch` aliases in {rcfile}? (y/n)"* — on yes, append the block below to the rc file. The rc file lives outside the vault — use `Bash` with a heredoc append (atomic, preserves existing content), NOT the Obsidian MCP:

```bash
cat >> ~/.zshrc <<'EOF'

# claude-identity quota autopilot
claude-whoami() { ~/obsidian/hooks/claude-identity/claude-identity.sh whoami; }
claude-switch() { ~/obsidian/hooks/claude-identity/claude-identity.sh switch "$@"; }
EOF
```

(Substitute `~/.bashrc` if the user is on bash.) Then tell the user: *"Run `source {rcfile}` (or open a new shell) to load them."*

### 4. Install the spawn wrapper (optional — for named worker sessions)

**State to detect:** check whether `spawn()` already exists in the user's rc file. The current spawn wrapper template is in the team repo's `CLAUDE.md` → "Spawning sessions" section.

**If `spawn` is present and current:** skip silently.

**If missing or outdated:** ask *"Install the spawn wrapper for named worker sessions (e.g. `spawn accountant`)? It auto-detects IDE (Antigravity / VS Code / Cursor) and falls back to Terminal.app. (y/n)"*

On yes:
1. Read the spawn wrapper template from the team repo's `CLAUDE.md` (or `/tmp/vault-update-check/CLAUDE.md` if running during `/aios:update`) — the section that contains the `spawn() {` function definition.
2. Append it to the user's rc file via `Bash` heredoc:
   ```bash
   cat >> ~/.zshrc <<'WRAPPER'
   {paste the spawn() function block here verbatim}
   WRAPPER
   ```
   (Same caveat: rc file is outside the vault — use `Bash` heredoc append, not Obsidian MCP. Use `~/.bashrc` if the user is on bash.)
3. Tell the user to `source` the rc file.

This is optional — `claude-identity` works fine without it; you just get a Terminal.app window after a swap-respawn instead of an IDE tab.

### 5. Customize and install the launchd plist (interactive)

**State to detect:** check whether a `com.*.claude-quota-watch.plist` is already loaded:
```bash
launchctl list | grep claude-quota-watch
```

**If already loaded:** confirm with the user — *"You already have `{label}` loaded. Reload with the new code, or skip?"* If reload: `launchctl unload` then `launchctl load` from the bundled plist.

**If not loaded:** ask the user *"What org or handle for the launchd Label? (default: `me` (or your initials); otherwise pick a short identifier — your initials, your company slug, etc.)"* — store as `{org}`.

To change the org name: copy the bundled plist to `~/Library/LaunchAgents/com.{org}.claude-quota-watch.plist` and update the `<key>Label</key>` field via `Edit` (the Label must match the filename). Otherwise just `cp` the bundled plist as-is.

```bash
# (Claude runs these — substituting {org})
cp ~/obsidian/hooks/claude-identity/com.{org}.claude-quota-watch.plist \
   ~/Library/LaunchAgents/com.{org}.claude-quota-watch.plist
# (to set a custom org name) edit the Label inside the copied plist
launchctl load ~/Library/LaunchAgents/com.{org}.claude-quota-watch.plist
launchctl kickstart -k gui/$(id -u)/com.{org}.claude-quota-watch
```

Show the user the kickstart output — it should be quiet (silent success). Then `tail -1 ~/.claude/quota-watch.log` to confirm the agent fired one tick. (It will say `no cache yet — skip (is the Stop hook installed?)` because step 6 hasn't run yet — that's expected.)

### 6. Wire the cache writer to your statusLine — LAST automated step

**State to detect:** read `~/.claude/settings.json` and check whether `statusLine.command` already exists.

> **STOP.** Before running this, tell the user explicitly: *"This is the last step I can run for you. Wiring the statusLine requires restarting Claude Code, which ends this setup session. After I run the snippet, you'll need to: (a) close this Claude Code session, (b) launch a fresh one, (c) run the verify commands in step 7 yourself. Ready? (y/n)"*

If user is not ready: tell them they can configure manually later by pasting one of the snippets below. End setup here.

**Sub-decision — which renderer to use:**

- **No existing statusLine →** use the bundled `context-monitor.py` automatically. It's richer than Claude Code's default: shows context %, 5h/7d rate limits with countdown, active account local-part (so you see `j` vs `cc` after a swap), git branch + change count, and color-coded warnings as you approach limits. Run the **default snippet** below.
- **Existing statusLine present →** show it to the user (`d["statusLine"]["command"]` from `~/.claude/settings.json`) and ask: *"You already have a statusLine wired. Want to (1) replace it with the bundled `context-monitor.py` (richer — context %, 5h/7d, active account, git status, color-coded warnings), or (2) keep yours and just add the cache writer in parallel?"*
  - **(1) Replace →** run the **replace snippet** below (forces `context-monitor.py` as the renderer).
  - **(2) Keep →** run the **default snippet** below (preserves theirs, just wraps with `tee` so the cache writer also receives stdin).

**Default snippet** (preserves any existing statusLine, falls back to `context-monitor.py` if none):
```bash
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude/settings.json")
d = json.load(open(p)) if os.path.exists(p) else {}
cache_cmd = os.path.expanduser("~/obsidian/hooks/claude-identity/claude-identity.sh") + " cache"
default_statusline = "python3 " + os.path.expanduser("~/obsidian/hooks/claude-identity/context-monitor.py")
existing = d.get("statusLine", {}).get("command", "") or default_statusline
d["statusLine"] = {
    "type": "command",
    "command": f"bash -c 'tee >({cache_cmd} > /dev/null) | {existing}'"
}
with open(p, "w") as f:
    json.dump(d, f, indent=2)
print("statusLine wired:", d["statusLine"]["command"])
PY
```

**Replace snippet** (forces the bundled `context-monitor.py` as the renderer, regardless of existing statusLine):
```bash
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude/settings.json")
d = json.load(open(p)) if os.path.exists(p) else {}
cache_cmd = os.path.expanduser("~/obsidian/hooks/claude-identity/claude-identity.sh") + " cache"
default_statusline = "python3 " + os.path.expanduser("~/obsidian/hooks/claude-identity/context-monitor.py")
d["statusLine"] = {
    "type": "command",
    "command": f"bash -c 'tee >({cache_cmd} > /dev/null) | {default_statusline}'"
}
with open(p, "w") as f:
    json.dump(d, f, indent=2)
print("statusLine wired:", d["statusLine"]["command"])
PY
```

Then say: *"Done. statusLine is wired. Now: close this Claude Code session and relaunch. Once you're back, run step 7 manually to verify everything is healthy. Setup is complete after that."*

> **Why `bash -c`:** Claude Code runs the statusLine command directly via `execve`, not through a shell. Process substitution (`>(...)`) is bash-only, so the wrapper is required. Also: `~` does NOT expand — the snippet uses `os.path.expanduser` to write absolute paths.

### 7. Verify (manual — runs after Claude Code relaunch)

After relaunching Claude Code, paste these into your shell:

```bash
~/obsidian/hooks/claude-identity/claude-identity.sh list   # all accounts saved ✓
launchctl list | grep claude-quota-watch                   # com.{org}.claude-quota-watch present
cat ~/.claude/rate-limit-cache.json                        # 5h/7d snapshot — should populate within seconds
tail -3 ~/.claude/quota-watch.log                          # 1-min cadence ticks
```

If `quota-watch.log` still says `no cache yet — skip (is the Stop hook installed?)`, the statusLine wiring (step 6) didn't take. Re-check `~/.claude/settings.json` `.statusLine.command` for the `tee >(...)` wrapper, and confirm Claude Code was actually restarted (a single CTRL-D often isn't enough — the parent terminal needs a fresh `claude` invocation).

---

## Subcommands

| Command | Purpose |
|---|---|
| `claude-whoami` | Current account + next in rotation |
| `claude-switch` | Rotate to next account in USER.md (wraps) |
| `claude-switch {email}` | Jump to a specific account |
| `claude-switch --capture` | Save current identity |
| `claude-switch --list` | Show all configured + saved state |
| `claude-switch --help` | Swap-specific usage |
| `claude-identity.sh cache` | Stop-hook entrypoint (reads stdin) |
| `claude-identity.sh watch` | Launchd entrypoint (decides + swaps) |

## Threshold tuning

Defaults trigger a swap at **98%** on either the 5h or 7d window. We use 98 (not 99 or 100) because the comparison is `>=` and Claude Code's reported usage tends to plateau at exactly 100 once you hit the limit — at which point the swap is too late, the session is already throttled. 98 swaps just before saturation. If you want earlier safety (shared machines, teammates still learning), drop to 85-95 via env vars. Override via the plist (add a `<key>EnvironmentVariables</key>` block) or your shell for manual testing:

```bash
export CLAUDE_QUOTA_5H=98       # rotate when 5h pct >= this
export CLAUDE_QUOTA_7D=98       # rotate when 7d pct >= this
```

## Rotation behavior — topology-independent

The watcher does **pure rotate-only**: when the current account hits its cap threshold, advance to the next account in USER.md's `## Anthropic accounts` list. Round-robin alternation. Works for any number of accounts (1, 2, N) and any number of machines (1, 2, N).

No "primary" / "come-home" semantics. Earlier versions returned to a preferred account when the current one fell below a lower threshold, but that logic assumed a specific user topology (≥2 accounts + a designated "home" account) that doesn't generalize. Removed 2026-04-23 after the come-home fired during active work with zero material benefit.

**If you want to force a specific account** (e.g., machine A back to `primary@example.com` so machine B can use `secondary@example.com` exclusively): run `claude-identity.sh switch primary@example.com` manually. That's the escape hatch.

**Cross-machine coordination is not solved here.** If two machines share an account pool, both can end up on the same account and compete for its caps. Future work: a shared state file over git / iCloud that both watchers read to coordinate. Until then, the manual escape hatch is the only lever.

## Files written

| Path | Purpose | Perms |
|---|---|---|
| `~/.claude/identities/{email}/keychain.json` | Full `Claude Code-credentials` blob | 600 |
| `~/.claude/identities/{email}/oauthAccount.json` | Account metadata | 600 |
| `~/.claude/identities/{email}/userID.txt` | 64-char user ID | 600 |
| `~/.claude/rate-limit-cache.json` | Latest quota snapshot from Stop hook | 600 |
| `~/.claude/quota-watch.log` | Watcher's per-tick decision log | 644 |
| `~/.claude/swap-log.jsonl` | Append-only log of every auto-swap | 644 |
| `~/.claude.json.bak-claude-switch` | Rollback snapshot of last swap | 644 |

None of these should ever be committed — `~/.claude/` is outside the vault by design.

## Troubleshooting

**`no cache yet — skip (is the Stop hook installed?)`** in quota-watch.log
→ The Stop hook isn't firing. Verify it's in `~/.claude/settings.json` and restart Claude Code.

**`cache stale (Ns) — no active session; skip`**
→ Cache is older than 30 min; no Claude session has fired a Stop hook recently. Expected during long idle periods.

**Swap ran but my running Claude Code session seems stuck on the old account**
→ Claude Code caches the OAuth token in memory at session start. The Keychain swap affects NEW spawns. Restart your session (or wait for the token to refresh naturally).

**Keychain prompts every run, even after "Always Allow"**
→ Keychain Access > `Claude Code-credentials` > right-click > Access Control. Ensure the `security` binary is listed, or loosen to "Allow all applications".

## Why this exists

Anthropic rate limits are per-account (5h rolling + 7d rolling). Running a single account means hitting the cap and pausing for hours. With two accounts and this tool, the current one rotates to the other automatically when you're near the cap — you (or any long-running agent) keep working. Bundled MCPs (Google Workspace, Slack, GitHub, etc. at `mcps/*`) are never disturbed because the swap only touches the `claudeAiOauth` portion of the Keychain + identity metadata in `~/.claude.json`, not the MCP server registrations.

## Lessons learned the hard way

Hard-won findings from the first implementation pass. Documented here so teammates don't rediscover them.

### 1. Hooks do NOT receive `rate_limits`

We initially wired this as a `Stop` hook assuming hook input would include the same `rate_limits` object the statusline sees. It doesn't. Empirically observed Stop hook payload keys (2026-04-21):
```
session_id, transcript_path, cwd, permission_mode,
hook_event_name, stop_hook_active, last_assistant_message
```
No `rate_limits`. Likely the same for `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`, etc. — hooks are designed for message/tool metadata, not session rate state. If you're building ANYTHING that needs `rate_limits`, you MUST piggyback on the statusLine (the only Claude Code surface that gets it).

### 2. Claude Code does NOT expand `~` in command strings

Any command written as `~/path/to/thing` in `settings.json` (under `hooks` or `statusLine`) will silently fail — Claude Code hands the string to `execve` directly, not through a shell that would expand tilde. Always use absolute paths (`/Users/YOU/...`) or a Python one-liner with `os.path.expanduser()` that writes the absolute path into the JSON.

### 3. Claude Code does NOT run commands through bash

The statusLine/hook command is `execve`d directly, not `bash -c`-wrapped. Bash-only features like process substitution (`>(...)`), `$(...)` command substitution, heredocs, and arrays DO NOT work unless you explicitly wrap the whole thing in `bash -c '...'`. If your statusline is coming out blank, this is probably why.

### 4. The running session keeps its token in memory

When `claude-switch` runs mid-session (auto or manual), it swaps the Keychain + `~/.claude.json` identity, but your RUNNING Claude Code session holds the OLD account's OAuth token in memory. It keeps hitting the API as the old account until the token refreshes naturally (~1h) — at which point the refresh uses the NEW Keychain credentials and may fail because the refresh token belongs to the old account. The session will prompt you to log in again or simply error.

**Implications:**
- Auto-swaps are best-effort — they ensure your NEXT spawn uses the new account, but the current session keeps burning the old account's quota.
- To cleanly hand over: restart the session (new terminal + new `claude` spawn), or let the token refresh fail naturally.
- The 15-min cooldown is not a bug — it's a thrashing guard. During cooldown, the running session's old-token reports will reflect against the NEW `oauthAccount` email in the cache. Without cooldown, we'd swap back immediately into a ping-pong loop.

### 5. Tee-based statusLine piggyback is the cleanest pattern

For anyone building other "observe the statusline payload as a side effect" features, the `bash -c 'tee >(your-sidecar) | your-real-statusline'` pattern is the right tool. The sidecar process runs concurrently with the visible statusline renderer, both see the same stdin, neither interferes with the other. Keep the sidecar fast (<100ms) since statusLine fires aggressively during typing. Ours writes a ~200-byte JSON file and exits.

### 6. Reload plist after edits

`launchctl load` reads the plist ONCE. If you edit `StartInterval` or the command, you must `launchctl unload` then `launchctl load` again — reloading the file isn't enough. Use `launchctl kickstart -k gui/$(id -u)/com.{org}.claude-quota-watch` to force one immediate tick after reload for quick validation.
