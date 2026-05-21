---
tags: [hooks, custom, index]
created: '2026-05-21'
---
# Custom Hooks

> Your custom event hooks. These survive `/aios:update` — bundled hooks in the parent `hooks/` folder get replaced, but `custom/` is yours.

Add `.py` / `.sh` scripts here that respond to Claude Code events (UserPromptSubmit, etc.) or implement pipeline steps for your custom commands. Document each in the registry table below.

## Registry

| Hook | Purpose | Triggered by |
|------|---------|--------------|
