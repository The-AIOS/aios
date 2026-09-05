# MODEL-ROUTING.md — which model for which task, and where the boundary is

Every AIOS session runs on a Claude model, and every spawned worker inherits one. That choice is
not cosmetic: on the same trivial prompt, the top and bottom of the ladder below differ by roughly
**22× in cost**. Most work does not need the top, and some work is wasted on the bottom.

This file answers two separate questions that are easy to conflate:

1. **Which Claude model should do this task?** → § The ladder
2. **May a non-Claude model do it at all, and if so how?** → § The containment boundary

If you only read one section, read the boundary. The ladder costs money when you get it wrong; the
boundary costs credentials.

---

## The ladder

Anthropic's own guidance, expressed as the four rungs AIOS exposes. **Pick by the shape of the
work, not by importance** — "important" is what tempts you to the top rung for a file sweep.

| `spawn --tier` | Model | Use it for |
|---|---|---|
| `frontier` | Claude Fable 5.1 | Your hardest problems: long-running agents in production, code migration, multi-step reasoning, and tasks needing creative thinking and full autonomy |
| `judgment` **(default)** | Claude Opus 5 | Reasoning-intensive work — legal, financial analysis, research, other complex domains — and production coding |
| `scale` | Claude Sonnet 5 | General-purpose workloads at scale, across coding and knowledge work |
| `fast` | Claude Haiku 4.5 | High-frequency, latency-sensitive tasks; sub-agents inside an orchestration |

Omitting `--tier` gives you `judgment`. That is deliberate: the default should be the rung that is
right when nobody thought about it, and under-powering a reasoning task fails silently — you get an
answer, it is just worse, and nothing tells you.

**`--tier mechanical` still works and still resolves to Claude Sonnet 4.6.** It predates this
ladder and is kept byte-identical, because changing what an existing flag resolves to would change
the cost and behaviour of work already running in operators' routines. Treat `scale` as its
successor for new work; `mechanical` will keep working.

### Acting on the ladder

- **A spawned worker:** `spawn --tier fast transcriber "..."` (Windows: `-Tier fast`)
- **One specific model, outside the ladder:** `spawn --model claude-fable-5-1 name "..."` —
  overrides `--tier`, exports `CLAUDE_MODEL` **for that spawn's launcher only**. Never export
  `CLAUDE_MODEL` in your shell rc to achieve this; miss the revert and every future terminal is
  pinned.
- **A subagent inside a session:** the Agent tool's `model` parameter takes the same ids.
- **Inside a workflow:** per-agent, same ids.

### Verify an id before you trust it

Model ids churn. An id AIOS does not recognise **does not fail loudly** — Claude Code reports
`[claude-code:unrecognized_model]` on stderr and then produces **zero tokens at zero cost**, which
means *"the spawn worked"* is worthless as evidence on its own. The check that can actually fail:

```bash
# Prompt FIRST, then flags — `--allowedTools` is variadic and will swallow a
# prompt that follows it. Both guard flags are required, and so is the explicit
# permission mode: see the note below.
claude -p 'ok' --model "$ID" --output-format json \
  --allowedTools NoSuchTool --strict-mcp-config --permission-mode default 2>&1 | head -c 200
# real id  → JSON with non-zero total_cost_usd and non-zero input tokens
# bad id   → the literal string  [claude-code:unrecognized_model]
```

> **Why a probe that only says `ok` carries an allowlist.** Reported by an operator, 2026-08-31, after auditing their own fleet. Any shipped `claude -p` invocation should name the tools it actually needs — this one needs none — because the cost of adding it is a flag and the cost of retrofitting it across a fleet is a weekend. Three of the four obvious ways to do this **do not work**: `--allowedTools ""` is swallowed by the variadic flag · `--permission-mode manual` does **not** block (Bash still runs) · `--disallowedTools Bash` is a denylist, so `Write`, `Edit` and `Agent` survive it. The allowlist naming a tool that does not exist, plus `--strict-mcp-config`, is the form that holds.
>
> **And it holds only if you also pass `--permission-mode` explicitly.** Measured 2026-09-04 on a machine whose `~/.claude/settings.json` sets `permissions.defaultMode: "auto"`: the allowlist form alone **created a file**, with `permission_denials: []`. Adding `--permission-mode default` (or `plan`) blocked it. A machine-level auto mode silently outranks the flag — which is consistent with the vendor's own position that auto mode is a convenience feature backed by a best-effort classifier, **not a security boundary**.
>
> **You cannot verify any of this by asking the agent what tools it has.** Under a restrictive allowlist it still lists `Bash` and `Write`, because it is describing its *schema* rather than its *permissions*. **Only an absent side effect is evidence** — did a file appear, did the command run. Every claim in this note was measured that way.

Note what `modelUsage` in that JSON is **not**: it echoes the id you *requested*, so a bogus id
appears there verbatim and looks confirmed. Cost and token counts are the discriminating signal.
Every id in the table above was verified this way, against a deliberately-bogus control that
failed as expected.

---

## The containment boundary

A non-Claude model can be **called by** an AIOS session. It can never **be** one. Three rules, in
descending order of how much damage getting them wrong does.

### 1 · Never put a third-party proxy in the request path

There is a class of tool that makes Claude Code believe it is talking to Anthropic while routing
elsewhere. They work, which is the problem. Every AIOS session holds live credentials — Gmail,
Drive, Slack, a vault with your private context in it — and such a proxy sits in the request path
of all of them. **This is a no in canonical AIOS**, and it is named here rather than left to be
discovered, because reaching for one is the natural next step after wanting a cheaper model.

If you want a different model, call it as a tool (§3). That gets you the model without putting
anyone between your session and Anthropic.

### 2 · `spawn --model` takes Claude ids only — by design, not by accident

`spawn` passes `--model` straight through to the `claude` binary, and Claude Code runs Claude
models. So `spawn --model claude-fable-5-1` works and `spawn --model some-other-vendor-model`
cannot.

That is the right shape rather than a limitation to route around. It keeps non-Claude models away
from the MCP tool catalog and away from vault writes — which is exactly where the function-calling
literature finds they degrade: reported measurements show small and open models losing up to ~91%
of function-calling accuracy as the tool catalog grows (LongFuncEval). AIOS sessions carry a large
tool catalog. **Third-party models get text work; Claude keeps the agentic work.**

### 3 · The rail is text-in, text-out — and it leaves your machine

`hooks/openrouter.py` is the sanctioned way to call a non-Claude model. It takes a prompt, returns
text, and touches nothing else: no MCP tools, no vault writes, no credentials beyond its own key.

**It also sends whatever you pass it to a third party.** That is not a caveat, it is the whole
mechanism, and it is the one thing in this file that the rest of AIOS is built to avoid — the
vault is local, the MCPs authenticate independently, and nothing ships your context off-machine
unless you ask. So the rail is **opt-in and silent until configured**: no key present, no calls,
and it says which file to create rather than guessing. Before you pass it something, ask what you
would be comfortable having left your machine. Prose drafts are usually fine. Client
material, anything under an NDA, financial records, and personal context are usually not. See
[`FORTRESS.md`](./FORTRESS.md) for the containment ladder this sits on the outermost rung of.

---

## Judge independence — do not let a model grade its own family

**The rule:** when a model's output is being *scored*, the scorer must come from a different model
family than the author. A judge cannot dock points for a systematic tendency it shares. Nothing
about the score looks wrong from the inside; the bias is invisible by construction.

**Why this is in a framework doc and not a footnote:** it is easy to build, it runs for months
without complaining, and the same mistake is sitting in public. Reported by an operator who found
it in their own verify layer, and checkable by anyone: EQ-Bench, a leading creative-writing
leaderboard, uses a Claude model as its judge and ranks a Claude model first. Surge's
Hemingway-bench — 5,000+ blind pairwise comparisons judged by professional human writers — asks a
similar question with a different judge and produces a different winner. Same question, different
ruler, different answer. The point is not which leaderboard is right. It is that a same-family
judge cannot be the evidence.

**What this means in AIOS, concretely:**

- **Prefer measurement to judgment.** The [`voice-gate`](./skills/aios/voice-gate/SKILL.md) skill
  scores prose against the operator's own published corpus by *counting* — tells per 1,000 words,
  paragraph bursts, position zones. It is deterministic, so the judge-independence problem cannot
  arise. Where a countable proxy exists, count it.
- **When you genuinely need a model to judge, cross the family.** That is a use for the rail in §3
  — and the reason the de-biasing and the cheap-lane happen to be the same piece of code.
- **Never `claude -p` as the scorer of Claude-authored prose quality.** Using `claude -p` as a
  *reader* is fine and AIOS does it (`hooks/video-watch.py` captions video frames with it). The
  line is authorship: reading an artifact Claude did not write is measurement; grading one Claude
  wrote is a family judging itself.

This is a sibling of a class AIOS already carries: **an instrument that shares the bias of the
thing it measures.** The other well-worn form is a check that asserts success from its position in
a pipeline rather than from anything about the artifact. Both feel like verification and neither is.

---

## When the answer is "not a different model"

Two cheaper answers to try first, because "route it to another model" is a satisfying conclusion
that is often not the cheapest one:

- **A lower rung of the same ladder.** Most work that feels like it needs a different vendor
  actually needs `scale` or `fast` instead of `judgment`.
- **Nothing at all.** A deterministic script beats every model on a task with a countable answer,
  costs nothing, and cannot drift. `voice-gate` is that argument made concrete.

Reach for the rail when the task genuinely wants a different family — a judge that must be
independent, or a text lane where another vendor is materially better or cheaper at your volume.
"Materially" is worth measuring at your own volume before you build anything: an evaluation that
prompted much of this file concluded, for its author's actual output, that moving the prose off
Claude would have saved **$73 a year** — so the prose stayed, and only the routing question
survived.

---

*See also: [`FORTRESS.md`](./FORTRESS.md) (containment ladder) · [`TOOLS.md`](./TOOLS.md) (the full
menu) · [`hooks/_index.md`](./hooks/_index.md) (what each hook is for) ·
[`CLAUDE.md`](./CLAUDE.md) § Spawning Sessions (the tier flag in context).*
