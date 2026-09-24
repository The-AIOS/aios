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

| `spawn --tier` | Model | Use it for | Effort to start from |
|---|---|---|---|
| `frontier` | Claude Fable 5.1 | Your hardest problems: long-running agents in production, code migration, multi-step reasoning, and tasks needing creative thinking and full autonomy | `high` (`xhigh`/`max` for the hardest runs) |
| `judgment` **(default)** | Claude Opus 5.5 | Reasoning-intensive work — legal, financial analysis, research, other complex domains — and production coding | `high` |
| `scale` | Claude Sonnet 5 | General-purpose workloads at scale, across coding and knowledge work | `medium` |
| `fast` | Claude Haiku 4.5 | High-frequency, latency-sensitive tasks; sub-agents inside an orchestration | `low` |

**Effort is the second knob, and for current models it is the one to turn first.** Claude 5-generation models always reason before replying, so *"think carefully"* in a prompt only adds latency; to get more or less thinking, change effort: `claude --effort low|medium|high|xhigh|max` (checked against the installed binary, not assumed). The column above is where to start, not a rule. `spawn` does not pass `--effort` yet, so a spawned worker runs at the binary's default; set it inside the session with `/effort`, or run `claude --effort …` directly.

**Fast mode is not a rung.** It is the same model, answering faster, at a higher price per token — worth it for back-and-forth work where you read every reply, wasted on an unattended worker. Toggle it with `/fast`.

**A flagged message can move a session to an older model — silently, and for the rest of the session.** Opus 5.5 carries stricter safety classifiers, and the check covers the whole conversation, files and search results included, so a turn from much earlier can trigger it. When it fires, Claude Code switches the session to an older model and **stays there**. A `judgment` worker can therefore finish its job on a lower rung, and nothing in its launch arguments will say so. Two consequences:

- **Check what actually ran, not what you asked for:** `/model` shows the session's current model, and each reply's model is recorded in the session transcript. Launch arguments only prove what was *requested*.
- **Decide the behaviour for unattended work deliberately.** The setting is `/config` → *"Switch models when a message is flagged"*. Interactively, switching keeps you working; for a routine or worker whose output you will trust without watching it, you may prefer it to stop instead of finishing on a model you did not choose.

Omitting `--tier` gives you `judgment`. That is deliberate: the default should be the rung that is
right when nobody thought about it, and under-powering a reasoning task fails silently — you get an
answer, it is just worse, and nothing tells you.

**`judgment` is a pin, not an inherit — so it has a maintenance duty.** `hooks/resolve-tier`
answers it with an empty `--model` (the binary's default), but the launcher every AIOS session
starts through passes `--model` explicitly, at 1M context, because `settings.json` and `/model` are
not reliable carriers of that choice to spawned children. In practice the rung **is** the literal in
`install-wrappers.sh` / `.ps1`, and it outranks a model the operator saved with `/model`. When
Anthropic ships a new Opus, that literal moves in the same PR as this row — `tests/model-routing.test.sh`
fails the build if the table and the two wrappers stop naming the same model. (It went stale once:
Opus 5.5 shipped while every AIOS session was still launched on Opus 5, and nothing reported it.)

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
# Prompt FIRST, then flags — `--tools` is variadic and will swallow a prompt that
# follows it. `--tools ""` means no tool exists at all; `--setting-sources`,
# `--strict-mcp-config` and the explicit permission mode are each required: see below.
claude -p 'ok' --model "$ID" --output-format json \
  --tools "" --setting-sources user,project --strict-mcp-config \
  --permission-mode default 2>&1 | head -c 200
# real id  → JSON with non-zero total_cost_usd and non-zero input tokens
# bad id   → the literal string  [claude-code:unrecognized_model]
```

> **An allowlist is not containment — the tools that exist are.** Reported privately by an operator, 2026-09-21, and reproduced on Claude Code 2.1.281 with a canary: `--allowedTools` only *pre-approves*, and it is **additive** to every allow rule in the settings that load. `.claude/settings.local.json` is where each interactive *"allow always"* click accumulates — one daily-used vault had 98 rules, including a home-wide `Read` and `Bash(python3 *)` — so the previous recipe (`--allowedTools NoSuchTool --strict-mcp-config --permission-mode default`) **read a file outside the project**. Measured: that recipe plus one inherited `Read` rule → leaked · adding `--setting-sources user,project` → held · `--tools ""` → held · the same recipe with no local rule → held (the control: the inherited rule is the whole cause). So:
>
> - **`--tools "<list>"`** sets which tools exist (`""` = none). Size it to the job; it is the part an inherited rule cannot widen.
> - **`--setting-sources user,project`** drops the local layer where *"allow always"* accumulates.
> - **Keep `ToolSearch` in `--tools` whenever MCP servers are loaded** — without it every MCP schema is inlined and the run dies with *"Prompt is too long"*.
> - **A job that must run `Bash` needs the OS sandbox too, configured three ways, because its defaults do not contain a headless run.** Reported privately by an operator, 2026-09-24, and reproduced on 2.1.281 with canaries:
>   - **`"autoAllowBashIfSandboxed": false`.** It defaults to `true`, and then the sandbox approves *every* Bash command: a command that was not on `--allowedTools` ran under `--permission-mode default` with `permission_denials: []`. Set to `false`, the same command was denied, as it is with no sandbox.
>   - **`"filesystem": {"denyRead": [...]}` naming every credential folder.** Sandboxed Bash reads outside the project by default. A `permissions.deny` rule of `Read(<folder>/**)` did **not** stop `cat` there; only `denyRead` did. Name your secrets folder **and every MCP token folder** — `~/.config/aios-secrets` and `~/.google_workspace_mcp` at least (§ Where credentials live in [`SECURITY.md`](./SECURITY.md) lists the rest). A token folder matters as much as a key: the network allowlist lets the job reach that token's own API, so a read is also a way out.
>   - **The same folders in `"denyWrite"`.** Writes outside the project are already denied by default; this keeps them denied if someone later widens `allowWrite`.
>
>   ```json
>   { "sandbox": { "enabled": true, "autoAllowBashIfSandboxed": false,
>       "filesystem": { "denyRead":  ["~/.config/aios-secrets", "~/.google_workspace_mcp"],
>                       "denyWrite": ["~/.config/aios-secrets", "~/.google_workspace_mcp"] } } }
>   ```
>
>   And read-only commands inside the working directory are auto-approved, so run such a job from a directory holding only what it needs.
>
> **Why a probe that only says `ok` carries these flags.** Reported by an operator, 2026-08-31, after auditing their own fleet. Any shipped `claude -p` invocation should name the tools it actually needs — this one needs none — because the cost of adding it is a flag and the cost of retrofitting it across a fleet is a weekend. Three of the four obvious ways to do this **do not work**: `--allowedTools ""` is swallowed by the variadic flag · `--permission-mode manual` does **not** block (Bash still runs) · `--disallowedTools Bash` is a denylist, so `Write`, `Edit` and `Agent` survive it. (These were written when the allowlist was the recommended form; the note above supersedes it with `--tools`.)
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
