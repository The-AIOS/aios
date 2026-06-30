# team-archetypes — how this skill works & wires

> `SKILL.md` is the **lens** (loaded into the model when invoked). This README is the **operator-facing map** of how that lens gets triggered across AIOS. Read it if you want to understand *when* the archetype thinking actually fires — and why it's wired in four places, not one.

## What it is (one line)
A reasoning lens for composing a team — of people *or* AIOS agents — by **lifecycle posture** (Prototyper / Builder / Sweeper / Grower / Maintainer), matched to a product's stage. Boris Cherny's framing; worldview-neutral team science, same shelf as `leverage-points` and `commons-governance`.

## The core mechanic
At session start, every skill's **name + description** is in the model's context, but the **body** (`SKILL.md`) loads only when the model invokes the skill. So in every pathway below the same thing happens — *the model loads the lens and reasons with it*. What differs is **what triggers the invocation, and how reliably.** The skill never "executes"; it shapes reasoning and output.

## Two mechanisms people conflate
| | Purpose | Where it lives |
|---|---|---|
| **Archetype keyword tags** (`archetype: builder`) | Agent **discovery** — `spawn maintainer …` / *"who's my Sweeper?"* resolves to the tagged agent | `agents/_index.md` registry + agent frontmatter `keywords` |
| **The `team-archetypes` skill** | The **reasoning lens** — the model *thinks* in stage→mix | `skills/aios/team-archetypes/SKILL.md` |

Tags make agents *findable* by archetype; the skill makes the model *reason* about archetypes. They cooperate but are separate.

## The four invocation pathways (most reliable → least)

1. **Command wire — deterministic, fires every run.**
   - `/7plan` (synthesis step): for each active project, name its stage and flag where the week's planned work doesn't match the stage-appropriate mix.
   - `/emerge` (agents-that-want-to-exist step): compare each product's stage against the archetypes of agents actually deployed; surface the gap as an agent proposal.
2. **Agent `## Skills` wire — reliable whenever that agent runs.**
   - `growth-engineer` / `refactor-engineer` invoke it as a **posture self-check** ("am I the right archetype for this stage? if it's pre-PMF, route back to `technical-cofounder`").
   - `technical-cofounder` reads it to pick **Prototyper-vs-Builder mode** by stage.
3. **Semantic / description match — best-effort, depends on phrasing.** In a plain session, a question like *"my agent mix on this project feels lopsided"* matches the skill's description and the model loads it on its own. Least guaranteed — which is exactly *why* pathways 1 & 2 exist.
4. **Keyword-tag matching — not the skill at all.** `spawn sweeper …` resolves via the tags (pathway-0 discovery); no lens loads. Listed here so it's not mistaken for the skill firing.

**Why four, not one:** redundancy is deliberate. The semantic path alone is too flaky to count on, so the lens is also pinned to the commands and agents where it genuinely helps. It shows up whether you enter through a command, an agent, or a question.

## Where it's wired (current)
- **Commands:** `plugins/aios/commands/7plan.md`, `plugins/aios/commands/emerge.md` *(not `/today` — daily routing is tactical, stage→mix is strategic).*
- **Agents (`## Skills`):** `technical-cofounder`, `growth-engineer`, `refactor-engineer`.
- **Tags (`archetype:`):** all engineering agents in `agents/_index.md`.

## Adding a wire
- **New agent that should self-locate posture** → add `team-archetypes` to its `## Skills` and an `archetype: <x>` keyword in `_index.md` + frontmatter.
- **New command that composes/selects agents** → add a one-line "consult `team-archetypes` for stage→mix" at the relevant step. Only where stage actually drives the decision — don't bolt it onto tactical commands (the `/today` lesson).

See `references/cherny-archetypes-source.md` for the original framing and why this lives in the neutral core rather than a working-style template.
