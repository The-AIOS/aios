---
name: '{{agent-name}}'
description: 'Use when {{trigger condition}}. {{One-sentence purpose}}.'
tools: '*'
tags:
  - agent
  - '{{domain}}'
created: '{{date}}'
updated: '{{date}}'
status: active
---
# {{title}}

## Purpose
<!-- One sentence: what this agent does, for whom -->

## When to invoke
<!-- Trigger conditions: what kind of tasks match this agent? -->
- Task contains keywords: ...
- Domain: ...
- Example tasks: ...

## Tools required
<!-- Which MCPs and tools this agent needs -->

## Skills
<!-- OPTIONAL — delete this section if no registered skill genuinely adds methodology.
     Name the registered skills (skills/ + ~/.claude/skills after `bash skills/setup.sh`)
     this agent should lean on, so the right methodology fires reliably. Only add a skill
     that supplies something the prompt itself doesn't already encode — don't bolt generic
     skills onto an agent whose craft is self-contained (that dilutes it). Skills auto-load
     by description; naming them here is a reliability nudge, not a hard dependency. -->
- `<skill-name>` — when to use it

## Instructions
<!-- The natural language prompt that gets loaded when this agent is spawned.
     This is the "soul" of the agent — write it as a role briefing.
     The agent reads this, then executes the assigned task. -->

## Output format
<!-- What the agent produces when done -->
- Where results go (Gmail drafts, vault note, Slack message, PR, etc.)
- Report format for close-session
<!-- Note: work capture (update daily note or close-session) is handled by CLAUDE.md and /agent command — no need to add it here -->

## Constraints
<!-- What this agent should NOT do -->

## Schedule
<!-- Optional: recurring schedule if this agent runs on a cadence -->
<!-- e.g. "Daily 07:00 — scan for new leads", "Weekly Friday — draft content summary" -->
<!-- Leave empty for on-demand agents -->
