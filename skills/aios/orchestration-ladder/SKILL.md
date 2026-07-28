---
name: orchestration-ladder
description: Choose the right orchestration primitive for delegated work — a single agent, parallel agents, or a dynamic workflow — using the agent → parallel → workflow ladder, plus the spawn-vs-subagent axis (interactive-and-independent vs. harness-tracked-and-harvested), plus which MODEL/tier the worker runs on. ALSO the reference for talking to other sessions through the AIOS Glass spawn-inbox command bus. Use when deciding how to delegate a task, whether to fan work out, whether you need the result back in-session, which model or tier a delegated worker should run on, when a plan starts sprouting file-sentinels and monitor loops (the tell you picked the wrong primitive), when orienting to dynamic workflows for the first time, and whenever one session must reach another — "send a message to session X", "say hi to <session>", "message/nudge/ping a running agent", "reply to the session that spawned me", "hand this off to another session", "check who is running / which sessions are live", "kill or close a worker", or spawning an interactive worker (all of which go through the spawn-inbox, never a direct `spawn` call — the auto-mode classifier gates that). The "which tool — which model — and how do sessions talk to each other?" lens.
---

# The Orchestration Ladder — which primitive runs delegated work

Delegating work is not one decision. It's two, asked in order:

1. **How much structure does the work need?** → climb the ladder: single agent → parallel agents → dynamic workflow.
2. **Do you need the result back in *this* session?** → the spawn-vs-subagent axis, orthogonal to the ladder.

Most misfires come from answering neither and reaching for whatever primitive is top-of-mind. This skill makes both explicit.

## The ladder (lowest → highest structure)

| Rung | Primitive | Reach for it when | Don't when |
|---|---|---|---|
| 1 | **Single agent** | One coherent task with one owner. A worker with isolated context does it end-to-end. | The work is really N independent tasks (→ rung 2) or a repeatable multi-stage pipeline (→ rung 3). |
| 2 | **Parallel agents** | **2+ independent tasks with no shared state and no sequential dependency.** Different subsystems, different bugs, different research angles — investigated concurrently. | Tasks share state, must run in order, or one's output feeds the next (that's a workflow, not a fan-out). |
| 3 | **Dynamic workflow** | A **multi-step pipeline** where stages have order/dependencies, you want it **repeatable and harness-orchestrated**, and the result must return to the caller. Fan-out *inside* a stage is still rung 2 — a workflow is the deterministic scaffolding around the stages. | A one-off single task (rung 1) or a flat set of independent tasks (rung 2) — a workflow there is ceremony without payoff. |

**Climb only as far as the work demands.** Start at rung 1; move up only when the work genuinely has independence (→ 2) or ordered multi-stage structure worth making repeatable (→ 3). Over-orchestrating a simple task is the same failure as under-orchestrating a complex one — the cost just shows up later.

The parallel-agents rung has its own dedicated skill for *how* to do it well (crafting isolated context per agent, one agent per problem domain): **`dispatching-parallel-agents`**. This skill is the *when*; that skill is the *how*.

## The orthogonal axis — spawn vs. subagent (do you need the result back?)

At rungs 1–2 you still choose *how* the worker runs. This is a **separate** decision from the ladder, and conflating them is the most common orchestration mistake:

- **Independent interactive worker** = a **new session** in its own IDE tab / Terminal window, its own Remote-Control endpoint. The launcher does **NOT** control it and does **NOT** get its result back (you poll files / git / read its surface). *How you launch one depends on WHO launches it:*
  - **You're an agent (a Claude session):** you **cannot call `spawn`** — Claude's auto-mode classifier gates it as "launch an autonomous agent" (silent red-dot), and its osascript palette-drive leaks keystrokes. **Request it through AIOS Glass:** if `~/.aios/spawn-inbox/` exists, write `~/.aios/spawn-inbox/<name>.json` = `{"name","task","model"|"tier"?}`; Glass fulfils it natively (`vscode.createTerminal`). No Glass → hand it to the operator (button / paste), **never blind-call `spawn` and wait.** (Full contract: CLAUDE.md → Spawning Sessions.)
  - **The operator:** the Glass **"Spawn a session"** button, or types `spawn {name} "{task}"` in a terminal.
  - **Use an independent worker for:** interactive sessions the operator drops into live (wallets, decks, symposiums), and judgment/research work the operator watches unfold (visible-spawn default — see `dispatching-parallel-agents` and the operator's preferences).

- **Background subagent (Agent tool) OR dynamic workflow** = runs **UNDER the current session**. The harness tracks it, **notifies you on completion, and returns its result directly**. (The Agent tool's `model` accepts specialist models too, so a background specialist subagent is possible.)
  - **Use for:** anything where **you must orchestrate and harvest the output yourself** — autonomous / overnight work reviewed later, fan-outs whose results you consolidate, any result that must come back inline.

### The tell you picked the wrong primitive

> If your plan needs a **file-sentinel plus a pgrep/monitor loop** to detect when a delegated session finished — **you wanted a subagent (or workflow), not a spawn.** The harness already gives you completion + result for free; rebuilding that around a `spawn` is a primitive mismatch, not a limitation of the model you spawned.

The exception the operator may set: when they're *present* and want to *watch* the work, a visible independent worker (agent → Glass inbox, operator → button/typed) is right even though you can't harvest it. When they're *away* and delegated work to *review the output later*, a background subagent whose result you surface is right. The operator's explicit call overrides the default.

## The command bus — how sessions actually reach each other

The spawn-inbox is not spawn-only: it is a **command bus with three verbs**, and it is how one session talks to another at all. Drop a `*.json` file in `~/.aios/spawn-inbox/` (filename arbitrary but distinct; Glass consumes and deletes it):

- **spawn** (the default — no `action` key): `{"name":"designer","task":"design the hero","tier":"mechanical"}` — `task` is the optional first prompt; `"model":"<id>"` or `"tier":"mechanical"|"judgment"` route the worker by cognitive load. A name already live is *revealed*, not duplicated.
- **send**: `{"action":"send","name":"designer","prompt":"ship it"}` — delivers a prompt into that live session's terminal. **One line, and mind the ceiling: a `prompt` over ~1024 bytes is NOT delivered as text.** Both fulfillers write it to `~/.aios/bus-payloads/<name>-<ts>.md` and type one pointer line instead — *"Read `<file>` and follow the full instructions inside it. That file IS the message… Do not act on this line alone."* **Receiving one: read the file, act on that, never on the pointer alone.** The 1024 figure selects the *mechanism*; it is **not** the true ceiling, which differs per surface and isn't always measurable from outside. Truncation is silent everywhere — an over-long prompt arrives looking complete, and a cut tail can drop exactly the constraint that mattered — so treat length as a protocol invariant: split a long brief into sequential sends, or write the payload file yourself and point at it.
- **kill**: `{"action":"kill","name":"designer"}` — closes its terminal (shell + claude + respawn loop).

**Addressing — the registry is the only truth.** Live sessions and their real names come from `~/.claude/sessions/*.json` (each: `name` · `pid` · `status` · `sessionId` · `cwd`). **Never `pgrep`, never a terminal tab title.** A *resumed* session keeps whatever its tab was called, so matching by process or tab name silently fails — it makes a live peer look dead, and the usual outcome is wrongly declaring a session closed. Glass resolves the target by **pid → process ancestry**, which is why messaging a long-lived coordinator works.

**Replying to whoever requested you.** A spawned worker answers its coordinator with `send` to the coordinator's registry name; the reply lands there as a new prompt. That closes the loop — real multi-turn conversation between sessions, no polling.

**Failure modes worth knowing** (each cost a real bug):

- Keep `prompt` on **one line** — multi-line text is typed into a terminal as multiple Enters.
- The request file vanishing means Glass **picked it up**, not that the work succeeded. To verify what a session actually did, read its transcript: `~/.claude/projects/*/<sessionId>.jsonl` (`sessionId` from its registry file) — status alone won't tell you.
- `send`/`kill` reach terminals in the Glass window that consumed the request; with several IDE windows open, whichever wins the race acts.
- Malformed or name-less requests are ignored (logged to the *AIOS Glass* output channel) — a silent no-op, so check the channel if nothing happens.

The always-current reference lives in the inbox itself: **`~/.aios/spawn-inbox/README.md`**, written by Glass on activation (the component that implements the dispatch is the one that documents it, so it can't drift). If that file is absent, Glass isn't installed → there is no watcher and no bus; hand the spawn to the operator.

## Choosing the model for the worker (Calibrate-Don't-Choose)

Every primitive lets you pick the worker's model — a third decision, orthogonal to the ladder and the axis. Match it to the task's **cognitive load**: mechanical / deterministic work → the cheaper, faster tier; real reasoning, verification, synthesis → frontier. Default is to inherit the session model; change it deliberately, not reflexively.

| Primitive | How to set the model |
|---|---|
| **Subagent** (Agent tool) | `model` param (`opus` / `sonnet` / `haiku` / `fable`); `subagent_type` for a specialist. |
| **Dynamic workflow** (`agent()`) | `agent(prompt, {model, effort})` **per stage** — cheap model + low `effort` for mechanical stages (grep, transform, sweep); frontier + high/`max` effort for the verify / judge / synthesis stages. Mixing tiers within one workflow is the norm, not the exception. |
| **Spawn** (via Glass inbox) | `"model":"<id>"` **or** `"tier":"mechanical"\|"judgment"` in the request JSON → Glass passes `--model` / `--tier` to the worker. (Operator-typed: `spawn --model <id>` / `spawn --tier mechanical`.) |

One lens across all three: *the model is a spend↔quality dial on each unit of delegated work.* Cheap where the work is mechanical, frontier where it's judgment — this is `Calibrate Don't Choose` (operating principles) applied to delegation. Don't pay frontier rates for a file sweep; don't cheap out on a synthesis or a verify pass.

## Decision flow

```dot
digraph orchestration {
  "Delegating work" [shape=oval];
  "N independent tasks, no shared state?" [shape=diamond];
  "Ordered multi-stage pipeline, want it repeatable?" [shape=diamond];
  "Need the result back in THIS session?" [shape=diamond];
  "Operator watching live / interactive?" [shape=diamond];

  "Parallel agents (rung 2)" [shape=box];
  "Dynamic workflow (rung 3)" [shape=box];
  "Single agent (rung 1)" [shape=box];
  "Independent worker (agent → Glass inbox · operator → button/typed)" [shape=box];
  "Background subagent (harness-tracked, returns result)" [shape=box];

  "Delegating work" -> "Ordered multi-stage pipeline, want it repeatable?";
  "Ordered multi-stage pipeline, want it repeatable?" -> "Dynamic workflow (rung 3)" [label="yes"];
  "Ordered multi-stage pipeline, want it repeatable?" -> "N independent tasks, no shared state?" [label="no"];
  "N independent tasks, no shared state?" -> "Parallel agents (rung 2)" [label="yes"];
  "N independent tasks, no shared state?" -> "Single agent (rung 1)" [label="no"];

  "Single agent (rung 1)" -> "Need the result back in THIS session?";
  "Parallel agents (rung 2)" -> "Need the result back in THIS session?";
  "Need the result back in THIS session?" -> "Background subagent (harness-tracked, returns result)" [label="yes"];
  "Need the result back in THIS session?" -> "Operator watching live / interactive?" [label="no / not sure"];
  "Operator watching live / interactive?" -> "Independent worker (agent → Glass inbox · operator → button/typed)" [label="yes"];
  "Operator watching live / interactive?" -> "Background subagent (harness-tracked, returns result)" [label="no"];
}
```

## Dynamic workflows — orientation

A **dynamic workflow** is the top rung: programmatic, multi-step orchestration the harness runs *under* your session and whose result returns to you. Reach for it when the work is a **pipeline** — stages with a defined order and dependencies (extract → analyze → cross-reference → write), especially one you'll run **more than once** and want deterministic rather than improvised each time.

Orientation notes:

- **Fan-out is a stage, not the shape.** A workflow can dispatch parallel agents *inside* a stage (rung 2 nested in rung 3), then gather them before the next stage. The workflow is the ordered scaffolding; the fan-out is one step of it.
- **Repeatability is the payoff.** If you'll do this exact pipeline once, a single coordinating session that dispatches subagents by hand is simpler. If it recurs (a weekly digest, an ingest pipeline, a multi-source research sweep), encoding it as a workflow makes it consistent and cheap to re-run.
- **The result comes back.** Like a subagent and unlike a `spawn`, a workflow reports completion and returns output to the caller — no sentinels.
- **Mind the plumbing.** Passing arguments *into* a workflow can be finicky (arguments may not thread cleanly through an external script path); when in doubt, prefer in-workflow constants or explicit parameters over relying on ambient arg-passing, and verify the workflow actually received what you sent.

## Anti-patterns

- **Fan-out with dependencies.** Parallel agents on tasks where B needs A's output → you'll serialize them by hand anyway. That's a workflow (or a single ordered agent), not a fan-out.
- **Spawn-then-poll.** Spawning an independent session and building a monitor loop to harvest it. Use a subagent/workflow — the harness harvests for free.
- **Agent calling `spawn` directly.** An agent that runs `spawn <name>` hits Claude's auto-mode classifier gate (silent red-dot "tool use rejected") — and even un-sandboxed, the osascript palette-drive leaks/drops keystrokes. Agents **request via the Glass spawn-inbox** (`~/.aios/spawn-inbox/<name>.json`) or hand the spawn to the operator; blind-calling `spawn` and waiting for a terminal is the silent-failure trap that hyperfrustrated operators.
- **Workflow for a one-off single task.** Ceremony without payoff. Rung 1 with a subagent is enough.
- **Climbing for its own sake.** Reaching rung 3 because it feels thorough. Match the rung to the work's real structure; higher rungs cost setup and comprehension.
- **Ignoring the operator's presence.** Backgrounding work the operator wanted to watch, or spawning a visible session for work they wanted harvested silently overnight. The presence signal decides the axis.

## Relationship to other lenses

- **`dispatching-parallel-agents`** — the execution manual for rung 2 (how to craft isolated context, one agent per domain, when NOT to parallelize).
- **`leverage-points` / `team-archetypes`** — decide *where* to intervene and *with what posture*; this skill decides *with what orchestration mechanism* once you know the work.
- **`comprehension-debt`** — the more you orchestrate (especially rung 3, autonomous), the faster agent output outruns the operator's understanding. Climbing the ladder raises throughput *and* the debt; keep the gate honest.
