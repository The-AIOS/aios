# FORTRESS.md — Two-Machine AI Agent Architecture

> Setup manual for teammates running the AIOS across **two physical computers**: a primary MacBook (main / day-to-day driver) and a Mac mini (secondary / always-on agent host). This document is written for Claude sessions to read and execute the setup end-to-end. If you're a teammate and your Claude session is reading this for the first time, follow the section that matches the machine you're currently on.
>
> The architecture follows six defensive layers: network isolation, ecosystem lockdown, SSH hardening, permission gates, one-way data flow, and recovery mechanisms. Together they let a small operator run autonomous agents 24/7 without exposing credentials, networks, or sensitive systems.

---

## Two-machine model — what runs where

| Machine | Role | Always-on? | What runs on it |
|---|---|---|---|
| **MacBook (main)** | Day-to-day driver. The human's primary computer. | No (closes the lid, travels) | Interactive Claude Code sessions, IDE, browser, primary identity |
| **Mac mini (secondary)** | Agent host. Sits on AC power, isolated by firewall. | Yes (24/7) | Remote-controlled Claude Code workers, overnight shifts, scheduled cron agents |

The mini is named in this doc as *the mini* or *the secondary machine*. The MacBook is *the main computer* or *the main*. Teammates may give their own machines pet names (e.g. naming the mini after a person, server, or theme) — those names live in each teammate's `USER.md → ## Identity` table, not in this shared infrastructure.

---

## Architecture overview

```
MacBook (main)
    ↓ SSH + git pull (management only)
    ↓ Tailscale mesh (recovery access from anywhere)
═════════════════════════════════════════════ Firewall boundary (pf)
Mac mini (secondary)
    ↓ git push to GitHub (results only)
    ↓ Outbound HTTPS/DNS only (no inbound from local network)
```

The mini sits on the same physical Wi-Fi as the main but is firewalled at the OS level, preventing lateral movement to other devices on the network.

---

## Hardware + cost

- **Mac mini** (any recent model, plugged into AC power, kept open): ~$600 one-time
- **MacBook** (already owned by the operator): existing kit
- **Claude Code subscription** (Max tier or API budget): ~$20/month base + usage
- **Tailscale** (free tier sufficient for personal use): $0/month
- **Electricity** (24/7 mini operation): ~$5/month
- **Total monthly running cost**: ~$25

---

## SETUP — sequence the layers in this order

The setup is split into six layers. Layers 1-3 are mini-only (the fortress walls). Layer 4 runs on both machines. Layers 5-6 are coordination between them.

### Layer 1 — Network isolation (mini only)

Create `/etc/pf.conf` on the mini with these rules:

```
# Block all local network traffic except SSH from the authorized main IP
block in quick from <local_nets>
pass in quick proto tcp from 192.168.x.x port 22 to any port 22

# Allow outbound DNS and HTTPS
pass out proto udp from any to any port 53
pass out proto tcp from any to any port 80
pass out proto tcp from any to any port 443

# Local network ranges
table <local_nets> { 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12 }
```

Enable + persist:

```bash
sudo pfctl -e -f /etc/pf.conf
sudo launchctl load -w /Library/LaunchDaemons/com.apple.pfctl.plist
sudo pfctl -sr   # verify rules loaded
```

Replace `192.168.x.x` with the actual LAN IP of the MacBook. After reboot, verify the rules survived with `sudo pfctl -sr`.

**What this blocks:** ARP spoofing, local-network scans, service discovery, SSRF attacks against internal services. The mini can still reach the internet, but the rest of the local network is invisible to it.

### Layer 2 — Apple ecosystem lockdown (mini only)

Disable automatic device discovery and cross-device sync on the mini:

```bash
# Disable Handoff / Continuity
defaults write ~/Library/Preferences/com.apple.handoff.display DisableAirTransfer -bool true

# Disable AirDrop
defaults write ~/Library/Preferences/com.apple.NetworkBrowser DisableAirDrop -bool true

# Disable Bonjour advertising
defaults write ~/Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements -bool true

# Disable Bluetooth (optional but recommended for headless mini)
sudo defaults write /Library/Preferences/com.apple.Bluetooth.plist ControllerPowerState -int 0

# Disable File / Screen Sharing
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.smbd.plist
```

**Separate identity (important):**
- Create a distinct Apple ID on the mini (not the operator's primary Apple ID)
- Create a separate Google account for mini-specific services if the agents will use any
- Disable iCloud sync, Keychain sharing, Continuity, AirDrop
- Result: there are no credential paths from the mini back to the operator's primary accounts. If the mini is ever compromised, the blast radius stops there.

### Layer 3 — SSH hardening (mini only)

Generate a dedicated key pair **on the main machine**:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/agent_fortress -C "agent_access"
```

Configure `/etc/ssh/sshd_config` **on the mini**:

```
Port 22
ListenAddress 127.0.0.1
ListenAddress ::1

# Key-based auth only
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no

# Restrictions
PermitRootLogin no
AllowUsers <agent_user_account>
MaxAuthTries 3
LoginGraceTime 30s

# Disable forwarding/tunneling
AllowTcpForwarding no
AllowStreamLocalForwarding no
PermitTunnel no
X11Forwarding no
AllowAgentForwarding no

# Connection limits
ClientAliveInterval 300
ClientAliveCountMax 3
```

Authorize the public key (paste from the main's `~/.ssh/agent_fortress.pub`) into the mini's `~/.ssh/authorized_keys`:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "ssh-ed25519 AAAA... agent_access" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Reload SSH on the mini:

```bash
sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist
sudo launchctl load /System/Library/LaunchDaemons/ssh.plist
```

Test from the main:

```bash
ssh -i ~/.ssh/agent_fortress <agent_username>@<mini_local_ip>
```

### Layer 4 — Claude Code configuration (both machines)

#### Initial curated allowlist (week 1-2)

Create `~/.claude/settings.json` on both the main and the mini:

```json
{
  "permissions": {
    "allow": [
      "Bash(cd *, pwd, ls, mkdir, touch, cat, grep, find, ...)",
      "Read",
      "Edit",
      "Write",
      "WebFetch",
      "WebSearch",
      "Glob",
      "Grep"
    ],
    "deny": []
  }
}
```

#### Graduated permissions (week 3+)

After 1-2 weeks of observing what the operator actually does, expand to:

```json
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read",
      "Edit",
      "Write",
      "WebFetch",
      "WebSearch",
      "Glob",
      "Grep",
      "mcp__*"
    ],
    "deny": [
      "Bash(rm -rf /)",
      "Bash(rm -rf /*)",
      "Bash(rm -rf ~)",
      "Bash(rm -rf ~/*)",
      "Bash(sudo rm -rf *)",
      "Bash(mkfs *)",
      "Bash(dd if=*)"
    ],
    "additionalDirectories": [
      "/Users/<user>/code",
      "/Users/<user>/vault"
    ]
  }
}
```

**Key principle:** keep the deny list short. Only block catastrophic commands. Routine operations are protected by the fortress walls (Layers 1-3) and by the agent's own intent layer (Layer 5+), not by per-command approval.

### Layer 5 — One-way data flow (both machines, coordinated)

Agents on the mini **commit results to GitHub**, never directly to the main's filesystem. The main **pulls those results** when ready to review.

**On the mini** — set up the agent's working repo:

```bash
cd ~/agent-results       # or ~/vault if syncing the AIOS vault
git init                 # or git clone <your-vault-or-results-repo>
git remote add origin <your-github-repo>
git config user.email "agent@fortress"
git config user.name "Agent"
```

The mini pushes its work after each shift.

**On the main** — pull results before starting your day:

```bash
cd ~/vault
git pull origin main
```

**Critical constraint:** the mini has no direct access to email, Slack, calendar, bank accounts, or production credentials on the main. Git pull/push through GitHub is the only sync channel. If the mini is compromised, the main is not.

### Layer 6 — Recovery mechanisms (both machines)

#### Tailscale mesh setup

Install on both machines:

```bash
brew install tailscale
sudo tailscale up
```

This gives the mini a stable hostname (e.g., `mini.tailnet-name.ts.net` or just `mini` via MagicDNS) reachable from anywhere on the internet. After this, SSH to the mini works from a coffee shop, an airport, or another country:

```bash
ssh -i ~/.ssh/agent_fortress <agent_user>@mini
```

#### Bridge monitor (observability)

Create LaunchDaemon `/Library/LaunchDaemons/com.fortress.bridge-monitor.plist` on the mini to watch for session-bridge failures:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.fortress.bridge-monitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/bridge-monitor.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>3600</integer>
</dict>
</plist>
```

Create `/usr/local/bin/bridge-monitor.sh`:

```bash
#!/bin/bash
SESSION_FILE=~/.remote-control/session.json
VAULT=~/vault

if ! [ -f "$SESSION_FILE" ] || [ "$(jq -r '.status' "$SESSION_FILE")" != "connected" ]; then
    echo "$(date): Bridge down - code $(jq -r '.error_code' "$SESSION_FILE")" >> "$VAULT/logs/bridge-alerts.md"
    osascript -e 'display notification "Bridge disconnected" with title "Fortress Alert"'
fi
```

#### Session recovery helpers (on the main)

Add to the main's `~/.zshrc` or `~/.bashrc`:

```bash
# Restart an interrupted session on the mini
restart-mini() {
    ssh -i ~/.ssh/agent_fortress <agent_user>@mini \
        "claude --remote-control --name <coordinator_name> --continue"
}

# Spawn a new named worker on the mini
mini-spawn() {
    local session_name=$1
    local task=$2
    ssh -i ~/.ssh/agent_fortress <agent_user>@mini \
        "osascript -e 'tell application \"Terminal\" to do script \"cd ~/aios && spawn $session_name\"'" &
    echo "Session '$session_name' spawned on mini"
}

# Kill a worker on the mini (process-group kill, not single-PID)
mini-kill() {
    local session_name=$1
    ssh -i ~/.ssh/agent_fortress <agent_user>@mini \
        "pgrep -f 'claude.*--name $session_name' | xargs -I {} kill -KILL -- -\$(ps -o pgid= -p {} | tr -d ' ')"
}

# Open a screen share to the mini (works over Tailscale)
screen-mini() {
    open vnc://<agent_user>@mini
}
```

**Why `mini-kill` uses a process-group kill, not a single-PID kill:** the spawn wrapper runs the Claude session inside a parent zsh that lives in the spawned Terminal tab. That zsh is a respawn-loop body — if you SIGKILL only the named `claude` process, the loop respawns it within 60 seconds, defeating the kill. The negative-PGID `kill -KILL -- -PGID` form takes down the launcher zsh + claude + recovery prompt + any descendants in one syscall.

---

## INSTRUCTIONS — Per machine

This section is split into "if you're a Claude session running on the main" vs "if you're a Claude session running on the mini." Read the one that matches `$CLAUDE_AGENT_NAME` semantics and the machine hostname.

### Instructions for MacBook (main) sessions

You're running on the operator's primary computer. Your role is interactive partnership — help the operator with the work in front of them.

**At session start (every session):**

1. Run `echo $CLAUDE_AGENT_NAME` — this is your identity. Compare to USER.md `## Identity` table.
2. Read `~/aios/CLAUDE.md` end-to-end (it's small).
3. Read the user's `USER.md` (the personalization surface) and `INTENT.md` (autonomy levels).
4. Read declared context (`vault/00 - notes/context/declared/`) and observed context (`vault/00 - notes/context/observed/`).
5. Greet the operator by name (read from `about_me.md` — never hardcode).
6. Check if there's an unclosed previous daily note. If yes, `/close-day` it before proceeding.

**During the session, when the operator asks you to spawn a worker:**

If the worker should run **on the mini** (e.g., a long overnight task, a content-writer agent, a market-research deep-dive that takes hours), use the `mini-spawn` helper:

```bash
mini-spawn <worker-name> "<task description>"
```

This SSHes into the mini and launches the worker there. The mini handles it overnight; the operator wakes up to a committed result.

If the worker should run **on the main** (interactive, short-lived, needs the operator's screen), use the local `spawn` wrapper:

```bash
spawn <worker-name> "<task description>"
```

This opens a new Terminal tab on the main with the worker session.

**At session end:**

Run `/close-day` or `/close-session` to capture what happened. Push the vault. The mini will pick up your work in its next pull.

### Instructions for Mac mini (secondary) sessions

You're running on the agent host. Your role is to ship work autonomously, commit results, and report back via the vault.

**At session start (every session):**

1. Run `echo $CLAUDE_AGENT_NAME` — this is your identity (typically the coordinator name, e.g., the operator's choice for their mini's primary session).
2. Pull the latest vault: `cd ~/aios && git pull origin main` (this gets the main's latest commits, including overnight queues set by the main).
3. Read `CLAUDE.md`, `USER.md`, `INTENT.md`, declared/observed context — same as the main.
4. Read the *latest* daily note (`vault/01 - calendar/{YYYY-MM}/`). Look for a `## Mini overnight (Handoff)` section — that's your work order for the shift.
5. Greet the operator (if they're online via Remote Control) or proceed silently if it's an overnight cron-triggered run.

**Identity discipline:**

You are NOT the main computer's session. The operator works on the main with their own primary Claude identity. You are the mini's session — a different Claude instance with the same vault context but a different role. Don't claim to be the main's session. Don't write to observed context files — those are maintained by the main and are read-only for you. Coordination happens through the daily note's handoff sections, not through observed context.

**During the shift:**

- Pick the highest-priority item from the overnight queue
- Execute it autonomously per `INTENT.md` autonomy levels
- Commit progress incrementally (`git commit && git push`)
- If you finish the queue, move to the standing orders block (vault hygiene, `_index.md` snapshot refresh, etc.)
- If you hit a blocker that needs the operator's decision, write it to a `## Blocked` section in today's daily note and move to the next item

**At shift end:**

Run `/close-session` to write the results into the daily note's `## Mini overnight results` section (the section name should match whatever the team has standardized — check existing daily notes for the convention). Push the vault. The main picks up your work in its next morning pull.

### Handoff protocol — main ↔ mini coordination

The daily note is the coordination surface. Two sections handle the back-and-forth:

**In the previous day's daily note (written by the main at end of day):**

```markdown
## Mini overnight (Handoff)

> Tasks for the mini to pick up tonight, priority-ordered. Each task has a clear "done" definition.

1. [ ] <task description> — done when <verifiable condition> [ship/draft] _(project)_
2. [ ] <task description> — done when <verifiable condition> [ship/draft] _(project)_
3. [ ] <task description> — done when <verifiable condition> [ship/draft] _(project)_
```

Tags:
- `[ship]` = the mini can ship this autonomously (commit, push, mark done)
- `[draft]` = the mini drafts but waits for the main's review before declaring done

**In the next morning's daily note (auto-imported by the main from the mini's `/close-session`):**

```markdown
## Mini overnight results

> What the mini shipped, what's blocked, what needs review.

- ✅ <completed task> — <one-line result + commit hash>
- 📋 <drafted item> — needs operator review at <path/URL>
- 🔴 <blocked item> — needs <specific input/decision>
```

The main reads this at morning start via `/today`. Items with `📋` get surfaced as morning-block review tasks; items with `🔴` get flagged in the carry-forward.

---

## OVERNIGHT SHIFTS — autopilot pattern

If the operator goes to sleep, travels, or steps away for a stretch, the mini should still be productive. Three triggers keep the loop alive even without a manually-written handoff:

1. **Operator-written queue** — the explicit `## Mini overnight (Handoff)` section in the latest daily note. Highest priority; mini follows it verbatim.
2. **Auto-derived queue** — if the operator forgot to write a handoff, an orchestrator cron on the mini reads the latest daily note and derives a queue from: `## Carries forward` (top 3), `## Parking lot` (non-blocked items), active project to-dos, and the standing orders floor (vault hygiene).
3. **Standing orders** — even if both above produce nothing, the mini always runs: `_index.md` snapshot refresh on touched projects, pull-act-push hygiene, observed-snapshot chain audit, broken-link check.

Budget caps apply only to auto-derived queues (no destructive ops, no external messaging, no commits to repos the mini doesn't own). Operator-authored queues run with full autonomy per `INTENT.md`.

To pause autopilot temporarily (e.g., a week off where you don't want the mini moving things around):

```bash
touch ~/.claude/monitors/autopilot-paused
```

To resume:

```bash
rm ~/.claude/monitors/autopilot-paused
```

---

## PREVENT SYSTEM SLEEP (mini only)

Critical for 24/7 operation:

```bash
# Never sleep the system
sudo pmset -a sleep 0

# Keep disks awake
sudo pmset -a disksleep 0

# Display can sleep (saves energy, no impact on agents)
sudo pmset -a displaysleep 10

# Verify
pmset -g custom
```

Claude Code spawns `caffeinate -i -t 300` during active sessions, but `pmset` is the system-level policy that ensures the mini never sleeps when idle between tasks.

---

## TERMINAL VS IDE — run Claude Code in a terminal, not an IDE, on the mini

```bash
# SSH into mini
ssh -i ~/.ssh/agent_fortress <agent_user>@mini

# Launch the coordinator session
claude --remote-control --name <coordinator_name>
```

**Why Terminal, not VS Code?** Permission prompts in VS Code appear as IDE dialogs invisible to remote users. Terminal sessions route prompts through Remote Control, allowing approval from the operator's phone or laptop. For the main, either works — but for the mini, Terminal is mandatory.

---

## CHECKLIST — before going to production

### Executive verification
- [ ] Mini runs on isolated machine (not the operator's laptop)
- [ ] Mini cannot see other devices on the network (`ping 192.168.x.x` from mini fails)
- [ ] Mini asks permission before catastrophic commands (verify deny list)
- [ ] Plugin ecosystem is vetted (no open registries with untrusted code)
- [ ] Data flow is one-way (mini pushes results, main pulls — no shared filesystem)
- [ ] Blast radius understood if the mini is compromised (no credential paths back to the main)

### Technical implementation
- [ ] `pf` firewall rules block local network on the mini (persist across reboot via launchd)
- [ ] Ecosystem lockdown: Handoff, AirDrop, Bluetooth disabled on the mini
- [ ] SSH: key-only auth, specific IP, no forwarding, 3 auth attempts on the mini
- [ ] Claude Code: permission-gated with deny list for catastrophic commands on both
- [ ] Terminal sessions on the mini (not IDE)
- [ ] `pmset` prevents system sleep on the mini (`sleep 0`, `disksleep 0`)
- [ ] Tailscale mesh configured on both machines
- [ ] Bridge monitor LaunchDaemon running on the mini
- [ ] Recovery helpers (`restart-mini`, `mini-spawn`, `mini-kill`, `screen-mini`) in the main's `~/.zshrc`
- [ ] Intent framework document (`INTENT.md`) created and read at session start by both machines
- [ ] Pre-travel recovery test passed (spawn/kill/restart without issues)

---

## TROUBLESHOOTING

### "Bridge dropped, session unreachable"
- Check bridge monitor logs: `~/vault/logs/bridge-alerts.md` on the mini
- Use Tailscale fallback: `ssh -i ~/.ssh/agent_fortress <agent_user>@mini`
- Restart with `restart-mini`

### "Permission prompt invisible, session blocked"
- Ensure Claude Code runs in Terminal on the mini, not VS Code or other IDE
- Verify `--remote-control` flag is set
- Check Remote Control web interface is accessible from the main

### "Mini cannot see other network devices" (this is intended)
- Verify `pfctl -sr` shows rules are loaded
- Test with `ping 192.168.x.x` from mini (should fail = good)
- Test with `curl https://api.anthropic.com` from mini (should succeed = good)

### "Mini didn't pick up overnight handoff"
- Check `~/.claude/monitors/queue-orchestrator.log` on the mini — did the cron fire? Which daily note did it pick as latest?
- Check `~/.claude/monitors/autopilot-paused` — is autopilot paused?
- Check the latest daily note in `vault/01 - calendar/` — does it have a `## Close of Day` section? If not, the cron may have waited for the day to close.
- `git log --all --oneline --since="2 days ago"` in the vault — what did the mini actually commit?

---

## RECOVERY — what to do if the mini is compromised

The architecture is built so compromise of the mini does NOT compromise the main. But if you detect an issue:

1. **From the main, SSH into the mini and stop all sessions:**
   ```bash
   ssh -i ~/.ssh/agent_fortress <agent_user>@mini "pkill -f 'claude'"
   ```
2. **Audit recent git activity:**
   ```bash
   cd ~/vault && git log --all --since="2 days ago" --author="Agent"
   ```
3. **Revoke the mini's GitHub deploy keys** (GitHub web UI → repo settings → deploy keys)
4. **Rotate the SSH key:**
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/agent_fortress_new -C "agent_access"
   # Copy new public key to mini via console (not SSH)
   ```
5. **Re-image the mini from a clean macOS install** if compromise is suspected to be at the OS level.

The fortress design ensures step 5 is rarely needed — the firewall + identity separation contain most compromises to the mini itself.

---

## REFERENCES

- Security sources: CrowdStrike, Palo Alto Networks, Snyk Labs, MITRE ATLAS, Microsoft Security, Cisco, Trend Micro, Aikido Security, drduh macOS Security Guide
- Substack source (background reading): `chuycepeda.substack.com/p/the-fortress-how-to-run-ai-agents`
- Related infrastructure files in this repo: `CLAUDE.md` (session start ritual), `USER.md` (per-user identity + sources), `INTENT.md` (autonomy levels + decision boundaries), `SETUP.md` (general AIOS setup)
