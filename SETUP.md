# SETUP.md — first-run bootstrap

> **Status: placeholder.** This file is a stub for the Phase 2 bootstrap-flow work in the [AIOS deployment plan](https://github.com/The-AIOS/aios). The real SETUP flow ships with Phase 2 (~Week 2 of execution).
>
> **What this file will do when complete:** detect your install location, capture it to your USER.md, scaffold the vault structure if missing, walk you through MCP onboarding (Google Workspace, Slack, etc.), and verify that `/today` runs end-to-end before you exit.

---

## Until the real SETUP lands — minimum viable manual setup

1. **Clone this repo** to wherever you want it (default `~/aios`, but any path works):
   ```bash
   git clone https://github.com/The-AIOS/aios.git ~/aios
   ```

2. **Create your personal vault** as a git repo (this is YOUR content; never push to The-AIOS/aios):
   ```bash
   mkdir -p ~/obsidian/vault
   cd ~/obsidian && git init
   ```

3. **Copy the templates into your vault**:
   ```bash
   cp -r ~/aios/templates/* ~/obsidian/vault/02\ -\ templates/
   ```

4. **Create your USER.md** at vault root (this is your per-user config):
   ```bash
   cp ~/aios/templates/USER.md.template ~/obsidian/USER.md
   # Edit USER.md to add your name, Google account, etc.
   ```

5. **Install Claude Code** if you haven't:
   ```bash
   npm install -g @anthropic-ai/claude-code
   ```

6. **Install the wrappers** (`spawn`, `spawn-kill`, `_claude_with_respawn`):
   ```bash
   bash ~/aios/hooks/claude-identity/install-wrappers.sh
   source ~/.zshrc  # or ~/.bashrc
   ```

7. **Run Claude Code** from your vault:
   ```bash
   cd ~/obsidian && claude
   ```

8. **Run `/today`** to verify the daily-plan flow works.

---

## Known onboarding friction (Phase 0 cleanup landing tomorrow)

- **Hardcoded `~/obsidian` paths** in 17 surfaces (commands + hooks) — being replaced with path-config-driven reads. If your vault isn't at `~/obsidian`, things break until this lands.
- **Google MCP setup** (Calendar + Tasks + Drive + Gmail) requires a personal Google Cloud Platform project + OAuth client + scope config. Time cost: 20-45 min. See `mcps/google-workspace-mcp/README.md`. Friction reduction work tracked as Phase 0.11 in the deployment plan.
- **MCP credentials** (`mcps/playwright-mcp/auth/*.json`) — must NOT be committed to git; the framework's `.gitignore` handles this but verify on your fork.

---

## What you get once setup works

- `/today` — morning plan generated from your calendar + open project threads + yesterday's unresolved items
- `/close-day` — evening capture; appends to today's daily note and updates observed context where relevant
- `/7plan` — weekly strategic plan across all your ventures
- Plus ~20 other vault commands (see `commands/` directory)
- A growing library of agents in `agents/` you can spawn via `spawn <agent-name>`
- Bundled MCPs for the most common workflows

---

## Where to ask questions

- File an issue on [github.com/The-AIOS/aios/issues](https://github.com/The-AIOS/aios/issues)
- Read the [AIOS deployment plan](https://github.com/The-AIOS/aios/blob/main/docs/deployment-plan.md) for architectural context (once Phase 2 lands)
