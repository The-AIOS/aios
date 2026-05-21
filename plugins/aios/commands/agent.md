---
tags:
  - vault-commands
  - command
  - on-demand
description: Load an agent's expertise into the current session (temporary hat), list agents, or schedule agents
allowed-tools: mcp__obsidian__*, Bash(ls *), Bash(cat *), RemoteTrigger, CronCreate, CronList, CronDelete, Read
argument-hint: "agent name, 'list', 'schedule {name}', 'schedule list', 'schedule stop {name}'"
---

# /agent — Wear a Temporary Hat (+ Schedule)

Load a specialized agent's instructions into the current session without spawning a new one. Your identity stays the same — you're putting on a temporary hat, not changing who you are. Also manages agent scheduling.

## How it works

**No argument or `list`:** Show the agent registry.
**With a name:** Find the agent, load its instructions, apply them to the current task.
**`schedule {name}`:** Schedule an agent to run on its configured cadence.
**`schedule list`:** Show all scheduled agents.
**`schedule stop {name}`:** Remove a scheduled agent.

## Steps

> **Before executing:** Read `USER.md` → `## Command personalizations` → `### /agent` for any user overrides. Also read `INTENT.md` (if it exists) — autonomy levels per venture determine whether the agent acts autonomously or drafts for review.

### If no argument or argument is "list":

1. Read `agents/_index.md` (canonical registry across all bundles) and `agents/custom/_index.md` (if it exists)
2. Display both registry tables — bundled agents first (grouped by bundle), then custom agents (if any)
3. Tell the user: "Pick one and run `/agent {name}`, or just describe what you need and I'll match."

### If argument is provided:

1. **Find the agent** — the argument can be a name, a keyword, or a full task description:
   - **Exact match:** glob `agents/**/{name}.md` — first match wins. `agents/custom/{name}.md` always takes precedence over bundled ones (operator extensions override).
   - **Keyword/fuzzy match:** No exact file → read `agents/_index.md` (canonical registry) and `agents/custom/_index.md` (if it exists), scan both registries. Compare argument against agent names, purposes, domains, and match keywords. Pick the closest match if confidence is high.
   - **Task description match:** If the argument is a sentence or phrase (e.g. "find leads in Ecuador", "review this contract", "draft a status report"), interpret the intent and match to the agent whose purpose and domain best fit the task. The task description becomes the agent's first assignment after loading.
   - **No match:** Tell the user no matching agent was found. Show the registry so they can pick one.

2. **Read the agent file** — load everything: Purpose, When to invoke, Tools required, Instructions, Output format, Constraints.

3. **Announce the hat:**
   > "Putting on the **{agent name}** hat. {one-line purpose from agent file}. Your session identity hasn't changed — I'll follow these instructions for the current task. Say 'take off the hat' when you're done."

4. **Follow the agent's Instructions section** as your operating guide for subsequent messages. Apply its constraints, use its output format, respect its tool requirements.

5. **Stay in character until:**
   - The user says "take off the hat", "done", "back to normal", or similar
   - The user runs another `/agent` command (swap hats)
   - The user runs `/close-session` (natural end)

## When hat comes off

When the user ends the agent mode:
> "Hat's off — back to normal. {brief summary of what was done while wearing it}."

**Capture the work:** If at the vault root, offer to update today's daily note with what the agent shipped. If in a standalone project session, offer to run `/close-session` so the work bridges back to the vault.

**Proactive close — don't wait for the user to remember.** When you believe the agent's task is complete (deliverable produced, clear stopping point reached, or the user signals satisfaction), proactively offer: *"Hat's coming off — should I take it off and capture this in `/close-session`?"* Don't sit idle waiting for the user to say "done." New users without ritual discipline lose work in silent-idle mode — the system's compounding loop (agent → close-session → close-day → daily note + project notes) only fires if you actively close.

Resume your original session identity and behavior.

---

## Schedule mode

### `/agent schedule {name}`

1. **Find the agent** (same matching logic as above)
2. **Read the `## Schedule` section** from the agent file. If empty or says "on-demand", tell the user: "This agent has no schedule configured. Add a cron expression to its `## Schedule` section, or provide one now."
3. **Parse the schedule** into a cron expression. The agent file may use natural language ("Daily 07:00", "Weekly Monday", "Every Friday 09:00") — convert to 5-field cron. If ambiguous, ask the user to confirm.
4. **Create a RemoteTrigger** with:
   - `name`: `agent-{name}` (e.g. `agent-sales-lead-hunter`)
   - `description`: The agent's Purpose from its file
   - `cron`: The parsed cron expression
   - `prompt`: A self-contained prompt that tells the triggered session what to do:
     ```
     You are a scheduled agent run. Glob `agents/**/{name}.md` (custom/ takes precedence over bundled) and follow its Instructions section.
     Execute your task autonomously. When done, call /close-session with a summary of what you did,
     what's unresolved, and which project it maps to. Do not wait for user input.
     Respect the agent's Constraints section strictly.
     If your task involves sending emails, updating CRMs, or any external action — produce drafts only, never execute.
     ```
5. **Confirm to the user:**
   > "Scheduled **[[{name}]]** — runs `{cron human-readable}`. Trigger ID: `{id}`. Use `/agent schedule stop {name}` to remove."

### `/agent schedule list`

1. Call `RemoteTrigger` with action `list`
2. Filter triggers whose name starts with `agent-`
3. Display as a table:

| Agent | Schedule | Last run | Trigger ID |
|-------|----------|----------|------------|
| [[{name}]] | {cron human-readable} | {last_run or "never"} | {id} |

If no scheduled agents: "No agents scheduled. Run `/agent schedule {name}` to set one up."

### `/agent schedule stop {name}`

1. Call `RemoteTrigger` with action `list`
2. Find the trigger with name `agent-{name}`
3. Call `RemoteTrigger` with action `update` and set `enabled: false` (or delete if the API supports it)
4. Confirm: "Stopped **[[{name}]]** schedule. Trigger `{id}` disabled."

### Schedule safety rules

- **Draft mode by default.** Scheduled agents that interact with external systems (email, CRM, Slack) must produce drafts, not execute. The user reviews and sends manually. This is non-negotiable for unattended runs.
- **Constraints are amplified.** In scheduled mode, the agent's `## Constraints` section is treated as hard rules, not guidelines. If a constraint says "never send emails directly," a scheduled run must never attempt it.
- **Results land in the vault.** The `/close-session` at the end writes a session report. `/close-day` picks it up and routes it.
- **One trigger per agent.** If the user schedules an agent that's already scheduled, update the existing trigger instead of creating a duplicate.

---

## Important

- **Do NOT change `CLAUDE_AGENT_NAME`** — the env var stays as-is. This is a behavioral overlay, not an identity change.
- **Do NOT skip the Session Start Ritual** — if context hasn't been loaded yet, load it before applying the agent hat.
- **The agent's Instructions section is the soul** — follow it closely, but you still have access to the full vault context your session already loaded.
- **Stack with vault context** — the agent hat adds expertise on top of your existing vault knowledge. A `/agent lawyer` in a buddai session means you have both the vault's strategic context AND the lawyer's legal framework.
