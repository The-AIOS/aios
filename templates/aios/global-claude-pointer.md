---
tags:
  - aios
  - template
  - setup
description: 'The Operating system block for the operator''s global ~/.claude/CLAUDE.md: the vault contract governs inside ~/aios, the global file stands alone outside it. Offered once by /aios:cold-start-interview and /aios:update; never written without a yes.'
---

# Global CLAUDE.md pointer — the "Operating system" block

> **What this is.** Claude Code loads `~/.claude/CLAUDE.md` (your *global* instructions) in every session on
> the machine, in any folder, and in a vault session it loads `~/aios/CLAUDE.md` beside it. Nothing told a
> session which of the two wins. A preference in the global file with no scope, such as a fixed reply
> language, would quietly override the vault's contract inside the vault; outside the vault, nothing
> pointed a session to the AIOS contract when the task acted on the vault or on the operator's behalf.
>
> The block below fixes both. It is a **pointer, not an import**: an `@import` of `~/aios/CLAUDE.md` would
> load the whole vault contract into every session in every folder; this costs a few lines.
>
> **Who adds it.** `/aios:cold-start-interview` (Step 3.5, after `INTENT.md`) and `/aios:update` (the
> CHANGELOG action item) offer it once. Both follow the same rules:
>
> 1. **State.** If `~/.claude/CLAUDE.md` contains the marker line `<!-- aios:operating-system -->`, the
>    block is already there: say nothing and stop.
> 2. **Ask, once.** The file lives outside the vault, so it is never written without a yes. Show the block.
>    Recommend yes: without it, a global preference can override the vault's contract in vault sessions.
> 3. **Act.**
>    - No global file: create `~/.claude/CLAUDE.md` holding a `# Global Instructions` heading and the block.
>    - A global file exists: insert the block directly under its first `#` heading (or at the very top if it
>      has none). **Change nothing else** in the file: no rewrite, no reordering, no removed rule.
>    - Write it with the Edit or Write tool, not from Bash: a sandboxed Bash tool cannot write
>      `~/.claude/CLAUDE.md`, and a failed shell write can look like a successful one.
>    - If the vault does not live at `~/aios`, write the path where it actually lives (SETUP.md § Path
>      portability).
> 4. **Then mention, without acting:** if the global file already holds rules that only make sense in some
>    folders (a fixed reply language, a client's formatting), the operator may want to scope them. That is
>    their call, rule by rule.
>
> Copy the block exactly, from the marker line to the last bullet. The marker is how every later run knows it
> is there.

## The block

<!-- aios:operating-system -->
## Operating system
- My sessions run under the AIOS: `~/aios/CLAUDE.md` (with `~/aios/INTENT.md` as the trust contract) is the governing contract. When working in `~/aios` it loads automatically and **wins on any conflict** with this file.
- Outside `~/aios` (other repos, other folders), this file applies on its own. Read `~/aios/CLAUDE.md` only when the task touches the vault, my ventures, or acts on my behalf.
- This file holds only defaults that apply everywhere: formatting, language, shell habits. Anything vault-specific belongs in `~/aios/CLAUDE.md`, not here.
