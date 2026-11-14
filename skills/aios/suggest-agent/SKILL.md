---
name: suggest-agent
description: Suggest the one agent (hat) that fits what the operator is asking, in one fixed line, and act only on their yes. Use when a request clearly falls in a specialist's field the operator has an agent for (accounting, invoices, contracts, legal review, decks, proposals, posts, code review, security, research, meeting prep and the rest of agents/_index.md), when the session is wearing no hat or the work has turned to another hat's field mid-session, or when the operator asks "is there an agent for this?". Suggests at most one agent and nothing when none fits well. Never opens a session or loads an agent without a yes. NOT for skills (Claude Code already matches those) and NOT for picking a whole team (that is a team plan).
---

# Suggest an agent

The operator has agents in `agents/`: an accountant, a lawyer, a deck builder, a code reviewer and more. Skills find the model on their own; agents don't. Nobody knows an agent exists until someone names it. This skill names it, once, at the moment it fits, and leaves the choice to the operator.

The same line is how a session changes hat mid-task (CLAUDE.md § Identity step 2): one rule for both, and one line the AIOS App can show as a button and as a hat change in its chat view.

## When to suggest

Suggest when **all** of these hold:

1. The request, or where the work has just turned, falls clearly in one agent's field. Clearly means you could say in five words why that agent fits.
2. The session is not already wearing that agent (check the hat you announced when you greeted, or the last one the operator accepted).
3. It is the first time this hat fits this piece of work. A declined suggestion is not repeated for the same work in the same session.

Do not suggest for greetings, small talk, one-line factual answers, or work any session does equally well without the agent (renaming a file, a quick lookup). **A wrong suggestion is worse than none.** When two agents fit about equally, suggest neither and carry on.

## How to find the agent

Read `agents/_index.md`, and `agents/custom/_index.md` if it exists, every time. Do not rely on a list you remember: a new agent is suggestible the moment it has a row, with no edit to this skill. Match the request against each agent's name, purpose and keywords; an agent's `aliases:` (kind words like `deck`) count as part of its name. `custom/` overrides a bundled agent of the same name.

## The line (exact — the App parses it)

Write it on a line of its own, exactly in this shape:

```
Suggested agent: accountant (invoices and bookkeeping). Wear it here, or open it as its own session?
```

- `Suggested agent: ` then the agent's name as its file names it (lowercase, hyphens), then a space and, in parentheses, why it fits in at most eight words, then `. Wear it here, or open it as its own session?`
- Nothing else on that line: no bold, no backticks, no emoji. Translate nothing on this line, whatever language the conversation is in; say anything else around it in the operator's language.
- One per reply, at most. Then stop and wait; do not start the work in the meantime if the answer changes how you would do it.

For surfaces that render it (the AIOS App turns it into a button and a hat change in its chat view), the pattern is:

```
^Suggested agent: ([a-z0-9][a-z0-9-]*) \((.{1,80})\)\. Wear it here, or open it as its own session\?$
```

## The wearing line (exact — the App shows the current hat from it)

Whenever this session **puts a hat on**, write one more fixed line on its own:

```
Wearing agent: accountant.
```

- At session start, after CLAUDE.md § Identity step 2 picked a hat (any rung but *None*), as part of the greeting.
- After a yes to "here", once `/aios:agent {name}` has loaded it.
- Same rules as the suggestion line: the agent's file name, nothing else on the line, never translated, no markdown. Write it once per change, never to restate the current hat.

The last such line in a transcript is the session's current hat, which is how a resumed session shows it again. Pattern:

```
^Wearing agent: ([a-z0-9][a-z0-9-]*)\.$
```

## What a yes does

- **"here"** (or a plain yes): wear the hat in this session. Run `/aios:agent {name}`, write the wearing line, and continue the work. Use this when the work is part of what this session is already doing.
- **"open"**: start it as its own session through the spawn inbox, never by calling `spawn` (see the `orchestration-ladder` skill). Name it role first, `{agent}-{subject}` (`accountant-acme`, no dates), and put the task and where its output goes in the brief. Use this when the work will outlive this conversation or should run beside it.
- **No, or no answer:** carry on without the hat, and do not suggest it again for this work.

Recommend one of the two when you suggest, if one is clearly better, in the sentence before the line. Never both open a session and wear the hat.

## Hooks

Not in this slice. Scripts in `hooks/` (transcription, video watching, file conversion) are surfaced today by the skills that use them, such as `watch-video`.
