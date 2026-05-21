---
tags:
  - agents
  - custom
  - index
created: '2026-03-30'
updated: '2026-05-21'
---
# Custom Agents — Your Personal Registry

> Your custom agents. These survive `/aios:update` — bundled agents at sibling subfolders get replaced, but `custom/` is yours.
>
> Create agents here from [[agent-template]]. They work exactly like bundled agents — `/agent`, `spawn`, scheduling, fuzzy matching — all supported.

## Naming note

This folder was previously called `my-agents/`. Renamed to `custom/` in the 2026-05-21 restructure to disambiguate from the `aios-personal/` bundle (which is the *shared* personal-life bundle: study-buddy, growth-companion, etc.). `custom/` is for YOUR operator-specific extensions; `aios-personal/` is the canonical AIOS personal bundle.

## Override behavior

If you create a custom agent with the same name as a bundled one, the spawn wrapper resolves `custom/` first. This is how you customize without forking — leave the bundled agent alone, write your own version in `custom/`, and the wrapper uses yours.

## Registry

<!-- Add your agents here. Same format as the bundled registry tables. -->

| Agent | Purpose | Domain | Match keywords | Schedule | Status |
|-------|---------|--------|----------------|----------|--------|

## How to add a custom agent

1. Copy [[agent-template]] to `agents/custom/{your-agent-name}.md`
2. Fill in: purpose, when to invoke, tools required, instructions, output format, constraints
3. Add a row to the registry table above
4. Test: `spawn {your-agent-name} "test task"` — should resolve immediately
5. (Optional) Run `/emerge` regularly to get suggestions for new agents based on your observed patterns

See [[../_index|top-level agents registry]] for the bundle structure + naming conventions.
