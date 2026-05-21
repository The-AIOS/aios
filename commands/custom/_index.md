---
tags:
  - commands
  - custom
  - index
created: '2026-05-21'
updated: '2026-05-21'
---
# Custom Commands — Your Personal Registry

> Your custom slash commands. These survive `/aios:update` — bundled commands at the parent `commands/` folder get replaced, but `custom/` is yours.
>
> Create commands here as `.md` files with frontmatter (tags, description, allowed-tools). Same format as bundled commands (see existing `commands/*.md` for examples). They invoke as `/aios:{your-command-name}`.

## Why custom?

If you create a command with the same name as a bundled one, the matcher resolves `custom/` first. This is how you customize without forking — leave the bundled command alone, write your own version in `custom/`, and `/aios:{name}` uses yours.

## Registry

<!-- Add a row when you create a new command. -->

| Command | Purpose | Invocation |
|---------|---------|------------|

