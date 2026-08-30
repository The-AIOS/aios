---
tags:
  - aios
  - command
  - onboarding
description: First-touch interview for a freshly-cloned AIOS vault. Walks the new operator through USER.md, declared context, bundle install choices, MCP setup, and optional Anthropic plugins. Run once, immediately after `git clone`.
allowed-tools: mcp__obsidian__*, Read, Write, Edit, Bash(git:*), Bash(gh:*), Bash(npx:*), Bash(claude:*), Bash(ls:*), Bash(cat:*), Bash(stat:*)
argument-hint: "(no arguments — fully interactive)"
---

# /cold-start-interview — First Session After You Clone AIOS

A guided conversation — ~5 minutes to working, deeper setup on request — that turns a freshly-cloned AIOS template into your personalized vault. Walks you through identity (`USER.md`), declared context (`about_me`, `personal_voice`, `working_style`, `INTENT.md`), bundle install choices (which of the 6 agent bundles you need), connector setup, optional Anthropic plugins, and your first `/today` run.

> **When to run:** immediately after `git clone git@github.com:The-AIOS/aios.git ~/aios` (or equivalent). Run once. If you skip it, the system still works — you'll just spend more time figuring things out yourself.


> **Never infer the operator's identity from a framework file.** Every vault ships the same
> `CLAUDE.md`, `README.md` and templates, so anything found in them belongs to the framework's
> author, not to the person you are interviewing. A setup session once offered a newcomer the
> author's Substack as a candidate for their own site — it asked rather than assumed, which was
> right, but it should not have been a candidate at all. Identity comes from what the operator
> tells you and from `context/declared/`, nowhere else.

## When to use

Immediately after the first clone of an AIOS vault — turns the freshly-cloned template into the operator's personalized vault. A guided conversation, not a form. Opens by offering a **~5-minute Core** (identity, declared context, a light INTENT.md, then the operator's first `/today`) or the **full tour** (Core plus a walk through the agents that already shipped, companies and shared workspaces, the AIOS Glass panel for a code editor, and a guided orientation). Core runs Steps 0-3, **8 silently**, 10, 11 — Step 10 fires the first `/today`, Step 11 then offers connectors one service at a time. Depth Steps 4, 5, 8.5, 9 are offered on request, at any point, including weeks later. Nothing is removed; the timing moved. Run once; re-runnable to revisit any section.


## Detection

The command is safe to run multiple times — it detects what's already configured and skips. But the most useful first invocation is on a vault where:

- `USER.md` still has template placeholders (`{{full name}}`, `{{your-email}}`)
- `vault/00 - notes/context/declared/about_me.md` is the template scaffold (not filled in)
- No daily notes exist yet in `vault/01 - calendar/`
- `agents/custom/_index.md` registry is empty

If all of those are TRUE → fresh vault → run the full interview. If some are filled → ask the operator which sections they want to revisit.

**The third case, and the one this command promises out loud twice: they came back for the tour.** Step 0 says *"the full tour is one sentence away whenever you want it"* and Step 11's close says *"say 'show me the full tour' any time, today or next month."* When an operator takes either of those up — or invokes this command again on a vault where Core is plainly already done — **do not offer to revisit their identity.** They did not come back to re-answer who they are; that framing makes a returning operator feel they are starting over, and it is the wrong read of a request we invited.

Run **Depth only** — Steps **4 · 5 · 8.5 · 9** — skip Core entirely, and open by placing them:

```
Your identity, context and trust settings are already in place, so none of
that needs touching. This is the deeper half — the parts that are easier to
show than to describe.

Four things, and you can stop after any of them.
```

> **Do not say *"the part I said I'd show you"* unless you know it was offered.** Two different doors reach
> this branch and only one of them was ever promised a tour: the operator who heard Step 11's closing offer
> and came back for it, **and** the operator who found a button. The AIOS App ships a **"Deepen your
> context (cold-start interview)"** action, and it is also one of the three commands **exempt from the
> App's readiness gate** — because, in the App's own words, *"the interview writes the context the gate
> wants."* So this command gets invoked on partially-configured vaults by a surface that never made any
> promise, sometimes by an operator who set their vault up before the tour existed at all. The copy above
> works for both; a callback to a conversation that never happened is a small thing that reads as the
> system confusing them with someone else.

Then run those four steps in order. `ENTRY` still governs Step 8.5 exactly as it does in a first run — detect it again rather than assuming the surface has not changed, because it may well have (an operator who set up in a terminal and later installed the App is the common case, not the exotic one).

**Why this is written down rather than left to judgment:** the deferred tour is a *promise with a named trigger phrase*, and until this paragraph existed nothing mapped that phrase to an action. Detection would have offered to revisit filled-in sections — technically a re-run, and not at all what was asked for. A promise whose landing is undefined is the same defect as re-timing a step to a destination that does not exist; it just fails later, and in front of an operator who trusted the offer enough to come back.

## Steps

### Pre-step — Silent setup (runs before the welcome; the operator sees none of this)

Three things happen before you say hello. **None of them is a question.** None produces output the
operator has to read *unless it needs a human decision* — which, in practice, is only the path conflict
in (c). If any fails, note it and carry on — a first-timer must never open on an error.

**(a) Which door did they come through?** Detect it, because the wording of several later steps depends
on it and getting it wrong is its own friction:

**Do not guess this from what is installed — walk your own process ancestry.** Each AIOS surface
announces its process-tree root at `~/.aios/surfaces/<surface>.json`; you belong to whichever one is an
**ancestor of your own pid**. This is the protocol's own detection snippet (`~/.aios/spawn-inbox/README.md`
is its authority) and it must be used as written, because the two shortcuts both fail in the direction
that matters:

- **A surface file's presence proves nothing** — it stays on disk after the surface exits, so it must be
  liveness-checked (`os.kill(pid, 0)`). Measured on a live machine 2026-08-27: `glass.json` was present
  with a **dead** pid while the App was genuinely running. A presence check would have reported "IDE" to
  an operator sitting in the App.
- **An install path proves less** — `/Applications/AIOS.app` existing says the operator *owns* the App,
  not that it launched *this session*. Someone with the App installed who opens a plain terminal is a
  terminal-path operator, and telling them otherwise skips a step they needed.
- **Never match on process *name*.** Glass runs inside whatever editor the operator uses, so a name list
  breaks the day they switch editors. Compare **pids**.

```bash
ENTRY=$(python3 - <<'PY'
import json, os, glob, subprocess
def parent(pid):
    r = subprocess.run(["ps","-o","ppid=","-p",str(pid)], capture_output=True, text=True)
    return int(r.stdout) if r.stdout.strip() else 0
live = {}
for f in glob.glob(os.path.expanduser("~/.aios/surfaces/*.json")):
    try:
        d = json.load(open(f))
        os.kill(d["pid"], 0)          # announced but dead => not running
        live[d["pid"]] = d["surface"]
    except Exception:
        pass
p = os.getpid()
while p and p != 1:
    if p in live:
        print(live[p]); break
    p = parent(p)
else:
    print("terminal")                 # no match is a legitimate answer, not an error
PY
) || ENTRY=terminal
```

Three answers, and each one changes what you say later:

| `ENTRY` | Where they are | What it means for you |
|---|---|---|
| `app` | Inside the **AIOS App**, which launched this session | **They never read SETUP.md** — the App ran that phase for them. Never mention it, never link it. They already have a graphical surface, so **skip Step 8.5 entirely**. Treat Step 1's wrapper install as a *first* install. |
| `glass` | Inside a **code editor** with the **AIOS Glass panel already installed and running** | They are demonstrably an editor user, and Glass is **already there** — Step 8.5 must not offer to install what announced itself thirty seconds ago. Point at the panel instead. |
| `terminal` | A plain terminal — no AIOS surface in the ancestry | They followed SETUP.md, so referring to it is fair game and Step 1's wrapper install is a *refresh*. Glass is a genuine offer here, and the only branch where asking *"do you work in a code editor?"* is the right move rather than a question you could have answered yourself. |

**Say what you detected, once, in one clause — it is the cheapest trust you will ever buy.** An operator
who is told *"I can see you're in the App"* learns, in four words and with no claim they have to take on
faith, that this thing looks at their actual machine. Do not make a performance of it and never present it
as a question. If detection fails, treat it as `terminal` and say nothing at all — a wrong guess announced
confidently costs more than the whole gain.

This is the canonical half of the routing rule: **a first-timer arriving through the app must never be
linked into the 654-line manual.** SETUP.md stays the reference for the manual path and is not changed.

**(b) Register the vault connector, silently.** The AIOS edits notes through an Obsidian MCP. It is
**infrastructure, not a connector** — a published npm package, no tokens, no account, nothing to
decide — so it is never a question and never appears in the Step 11 list:

```bash
# Idempotent: skip if already registered. No tokens, no prompts, no output the operator must read.
claude mcp list 2>/dev/null | grep -q '^obsidian:' \
  || claude mcp add obsidian -- npx @mauricio.wolff/mcp-obsidian@latest "$INSTALL_PATH/vault" 2>/dev/null \
  || true
```

If it fails, say nothing and continue — vault writes still work through the filesystem; this only makes
them cleaner. **Never ask the operator about it.** (`A2`: on a fresh install, vault edits work and the
operator was never consulted.)

**(c) Path portability.** Ensure the framework's hardcoded `~/aios/` references resolve to the actual install. **This is idempotent and deliberately runs on both doors** — the setup sequence already did it for a terminal-path operator, and an App-path operator never ran that sequence, so this is their only pass. It stays quiet unless it actually did something or needs a decision:

```bash
# Resolve the actual repo path (cold-start-interview runs from the cloned repo root)
INSTALL_PATH="$(pwd)"
CANONICAL="$HOME/aios"

# SILENT on every path that needs no decision. This step runs a second time for
# terminal-path operators (the setup sequence already did it), and on the App path it
# is the only pass — so it must be safe to run twice AND produce nothing to read when
# there is nothing to do. CONFLICT is the sole case a human has to resolve, so it is
# the sole case that speaks.
if [ "$INSTALL_PATH" = "$CANONICAL" ]; then
  :   # already at ~/aios
elif [ -L "$CANONICAL" ] && [ "$(readlink "$CANONICAL")" = "$INSTALL_PATH" ]; then
  :   # symlink already points here — the terminal path's second run lands here
elif [ -e "$CANONICAL" ]; then
  echo "path-portability: CONFLICT — ~/aios exists and points elsewhere. Operator must resolve before continuing."
else
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      # Git Bash on Windows: `ln -s` does NOT create a real link — by MSYS default
      # (unless MSYS=winsymlinks:nativestrict is exported) it silently creates a
      # STALE DIRECTORY COPY. The operator then runs the framework against a frozen
      # pre-migration snapshot while the real install drifts ahead — every update
      # appears to land but nothing changes. Caught on a Windows operator 2026-05-26.
      # Fix: create a real Windows directory junction instead of a symlink.
      cmd //c mklink /J "$(cygpath -w "$CANONICAL")" "$(cygpath -w "$INSTALL_PATH")" \
        && echo "path-portability: created ~/aios junction → $INSTALL_PATH" \
        || echo "path-portability: junction failed — use the PowerShell snippet below (run as Developer Mode / elevated)"
      ;;
    *)
      ln -s "$INSTALL_PATH" "$CANONICAL" && echo "path-portability: created ~/aios → $INSTALL_PATH"
      ;;
  esac
fi
```

**On CONFLICT** (the `~/aios` path exists and points elsewhere): surface this to the operator immediately and ask whether to back up the existing path (`mv ~/aios ~/aios.backup-$(date +%Y%m%d)`) or skip the symlink (operator commits to running the framework from a non-default path, knowing some references will need manual translation). **Default: do not auto-resolve conflicts** — operator decides. **On Windows, also flag a stale `~/aios` directory copy** (a non-junction folder that looks like a link but isn't) as a CONFLICT to resolve — `ls ~/aios` showing pre-migration content while the real install moved on is the signature.

**On Windows PowerShell** (where `ln -s` isn't available natively — and as the fallback if the Git Bash junction above fails), use:
```powershell
$Install = (Get-Location).Path
$Canonical = "$HOME\aios"
if ((Test-Path $Canonical) -and -not (Get-Item $Canonical).Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
  Write-Host "path-portability: CONFLICT — $Canonical exists as a real folder"
} elseif (-not (Test-Path $Canonical)) {
  # Try symlink first (needs Developer Mode); fall back to junction
  try { New-Item -ItemType SymbolicLink -Path $Canonical -Target $Install -ErrorAction Stop | Out-Null }
  catch { cmd /c mklink /J "$Canonical" "$Install" }
}
```

After this check passes, proceed to the welcome message below.

---

### Step 0 — Welcome + framing

**Voice for this whole command — read this before you speak.** You are not running a form. You are
having a conversation with someone who may never have opened a terminal on purpose, and this is the
moment they decide whether the AIOS is for them. Lead with what becomes *possible*, not with a
checklist of artifacts. Give them explicit permission to interrupt and to not understand something —
that single sentence converts a first-timer's fear into a question, and a question is something you
can answer. Never make them feel behind. **The word "MCP" does not appear anywhere before the
connectors pass at Step 11** — the word is **"connectors"**, and even that waits until they have
seen the system work.

Say something in this spirit — your words, not a script:

```
Hello! Welcome to The AIOS.

This is a framework for getting far more out of AI than a chat window
gives you. The idea is simple: you shouldn't need to be technical, or
write clever prompts, to do genuinely ambitious work.

What that looks like in practice — the AIOS ships with a team of agents
already built. They draft and polish real documents, run deep research,
build presentations, handle legal and finance reading, and yes, write
and ship software for you, with no engineering knowledge required on
your side.

I'm going to guide you through setting this up — a conversation rather
than an install. Nothing to download, nothing technical, no commands to
type. Interrupt me whenever you like. If something I say doesn't land,
just ask; questions are welcome here and they make the setup better.

What we're really doing here is teaching me about you. That's the part
that compounds: every session, the AIOS knows more about how you work,
and starts doing things you didn't think to ask for.

Two ways to start:

  A quick start  — about five minutes of questions, then you'll see it
                   working on your actual day.
  The full tour  — the same start, plus the parts that are easier to
                   show than to describe: the agents you already have
                   and which ones fit the way you work, how to bring in
                   a company or a shared workspace when you need one,
                   and a proper walk through the whole map with a guide.

Nothing is locked behind the tour. Everything in it is either already
installed or one sentence away — the tour is me showing you around, and
I'll offer it again at the end. It will still be there next month.

Which sounds better?
```

**Add one surface-specific line to that tour description, from `ENTRY` — never the hedge.** The earlier
copy read *"a visual panel if you work inside a code editor"*, which asks the operator to answer a
question you have already answered. Insert it as the **last item of the tour list above**, right before *"Nothing is locked behind the tour"*:

- **`ENTRY=terminal`** → append `and a visual panel for your code editor, if you use one.` This is the
  only branch where the conditional is honest, because a plain terminal genuinely does not tell you
  whether they also work in an editor.
- **`ENTRY=glass`** → append `and a proper introduction to the AIOS panel already open beside you.`
- **`ENTRY=app`** → **append nothing.** They are looking at the graphical surface. Listing a second one
  as a tour benefit is the exact confusion this change removed.

WAIT for their answer.

**Tier the flow from their answer — this is `A3`, and it exists because "this interview is super long" was the #2 measured friction.**

| Tier | Steps | Feels like |
|---|---|---|
| **Core** (default) | Pre-step → 0 → **1 (trimmed)** → 2 → **3-light** → **8 (silent)** → 10 → **11 (connectors)** | ~5 minutes of questions, then the system working on their real day |
| **Depth** (on request, any time) | Core **plus** 4 · 5 · 8.5 · 9 | The full orientation walk |

> **Why Step 8 is in Core and Steps 8.5 / 9 are not — the line is "do the operator's hands have to move?", not importance.** Step 8 declares in its own text that *"plugins are NOT optional in cold-start"* and installs a recommended set **without asking**, so parking it behind an opt-in tier did not defer it — it **deleted it** for every operator who chose the quick start, which is the exact failure this whole change exists to avoid. It needs nothing from the operator, so it belongs in Core, silently, like the vault-bridge registration in the Pre-step.
>
> Steps **8.5** (the visual panel) and **9** (the guided walk) also call themselves non-optional, and they stay in Depth for a different reason: **both need the operator's attention and their hands** — an extensions view, a window reload, a panel dragged into place; or two to three minutes of being walked through a map. Neither can be done *for* them, so neither can be silent, so putting either before the first `/today` breaks the five-minute promise the operator just accepted. They are named explicitly in Step 11's closing message instead, which is a standing offer rather than a coda — Step 11 *mentions* what is waiting; it never fires it.

**Depth is de-mandated, not deferred.** Nothing in it is withheld or postponed to another day — it is one sentence away at any moment, including mid-Core (*"actually, show me the whole thing"*), and Step 11 offers it again. An operator who picks Core and never asks has lost **no capability**: every deferred item is either offered later in this same session or reachable by a command they will be told about.

### Step 1 — Identity + USER.md scaffold

Walk through `USER.md` section by section:

1. **Identity table** — ask the operator's primary session name. **Lead with what it IS: this is the name of their primary assistant — the one they will work with every day — and it can be changed later from Settings.** The shell shorthand is real (typing `{name}` in any terminal launches `claude --remote-control --model claude-opus-5[1m] --name {name}` with respawn-on-quota-swap, saving 60+ keystrokes a launch) but it is the *second* thing to say, and to an operator who arrived through the App it may never matter at all — they have a button. **The earlier copy had this exactly backwards**, opening with the keystroke saving and then demoting the naming as "the bonus, not the point". For someone meeting the system on question one, the naming IS the point, the shortcut is the part they may never use, and — reported from a real first install — nothing told them the choice could be revisited, which makes the very first question feel permanent.

   Phrase the question something like: *"This is the name of your assistant — the one you'll be working with every day. You can change it later from Settings, so pick whatever feels right now. `claude` or `assistant` are perfectly good if you want plain. Some people go with a name — Jarvis, Friday, Samantha, HAL, Cortana, TARS all work. Short, memorable, yours."*

   Mention the terminal shorthand **after** they answer, as a small bonus rather than the reason: it becomes a one-word command that launches this session with everything already set. **Skip it entirely when `ENTRY=app`** — they have a button, and describing a terminal shortcut to someone who may never open a terminal is the same misjudgement as offering an App operator a second graphical surface (Step 0).

   **Role string is OS-detected, not hardcoded.** Default the role to a machine-agnostic "Primary session" baseline. Only add OS-specificity ("MacBook primary", "Windows primary", etc.) if the operator explicitly signals a multi-machine setup. Single-machine operators (99% of fresh clones) see clean "Primary session — AI partner" without machine-class jargon.

2. **Their email** — one question, in plain words: *"What email should I use for you?"* Record it as the primary account in `USER.md`. Nothing else here.

   > **RE-TIMED, not removed — the multi-account rate-limit question moves to the Day-7 check-in.**
   > It used to sit here, at minute two, phrased *"do you use more than one Anthropic account to manage
   > the 5h/7d rate limits?"* — with a `launchctl` install behind it. It was the **most expert-coded
   > moment in the interview**, and a first-timer cannot answer it: on day one they have not hit a cap,
   > so the question has no meaning yet. It is the one deferral whose need genuinely takes a week to
   > appear, which is why it is the **only** item routed to Day 7 rather than to Step 11 today.
   > Step 10 already schedules that check-in; the payload is specified there.

**That is the whole of Core Step 1 — two questions.** Everything below belonged to Step 1 and has been
re-timed. **Read the destination, not just the removal:** each item is offered later *in this same
session* (Step 11), or in the Depth tier, or at the Day-7 check-in. Nothing is dropped.

| Was asked here | Now asked | Why there |
|---|---|---|
| Organization / company | **Depth Step 5** (or `/aios:company` any time) | Already deferred before this change; unchanged |
| *"Primary Google email — Calendar + Tasks + Drive + Gmail"* | **Step 11**, after the first `/today` | A connector question wearing plain words. It is unanswerable until they have *seen* the empty calendar — then it answers itself |
| *"Slack workspace? Gmail? GitHub username?"* | **Step 11**, after the first `/today` | The **#1 measured freak-out**: asked what they use before they know what any of it is for |
| Growth routines (Reading / Writing) | **Depth Step 9**, or whenever a routine comes up | Was already marked *"defer; can configure later"* — it was being asked *and* deferred, which is the worst of both |

Edit USER.md inline as the operator answers. Show the diff before applying.

**After the Identity table is captured — bind the shorthand to their name.**

> **Two entry paths, and the wording must not assume either.** An operator who came through
> **SETUP.md** already has wrappers installed (its wrapper-install step ran before `USER.md` existed, so the
> shorthand fell back to the default `claude` function) — for them this is a *refresh*. An operator who
> came through **the AIOS App** never ran SETUP.md at all — for them this is the *first* install, and
> calling it a "re-run" is confusing at best. The Pre-step detects which path they are on; use the word
> that matches. Never mention SETUP.md to an App-path operator: **the app is their installer**, and
> routing a first-timer into a 654-line manual is the opposite of this command's job.

Run it silently and report the outcome in one line — do not show them the command unless they ask.
**OS-conditional** — pick the right installer for the operator's machine:

```bash
# macOS / Linux (zsh or bash)
bash ~/aios/hooks/claude-identity/install-wrappers.sh
```

```powershell
# Windows (PowerShell)
pwsh -File ~\aios\hooks\claude-identity\install-wrappers.ps1
```

Both installers are idempotent (timestamped backup → strip prior banner → append fresh banner with the new name → verify). Output confirms the detected name: *"✓ Primary session name: {name} (from USER.md)"*. Then tell the operator: *"Wrapper refreshed. Open a new terminal and type `{name}` — that's your shorthand now."* The shell function activates on next shell start; existing terminals can `source ~/.zshrc` (or restart pwsh) to pick it up immediately.

**Rule for this whole step:** one question at a time. The operator should feel walked by the hand, not interrogated. Use sensible defaults. Defer any action that involves cycling Claude's auth (the multi-account capture is the canonical example — always deferred to `/today`).

### Step 2 — Declared context (4 files, fast pass)

> **This step is load-bearing for a surface outside this repo — do not trim it out of Core.** The AIOS
> App reads the operator's name from `vault/00 - notes/context/declared/about_me.md` and *watches that
> directory* so its greeting changes from *"Good morning"* to *"Good morning, {name}"* the moment this
> step writes the file. That was an operator-reported bug in the App (the name used to appear only when
> something else happened to trip a different watcher, so the App greeted a stranger through the whole
> interview while the onboarding agent was already using their name). Their own name appearing is the most
> legible proof to a first-timer that the setup actually worked — so `about_me.md` must be written in
> **Core**, not deferred to Depth.

**Opening — offer the pre-fill path BEFORE the per-file questions:**

```
Before we walk through the 4 declared files one at a time — got
existing material I can pre-fill these from? Options:

  (a) URL — your personal site, LinkedIn, About page, public bio
  (b) File path — an existing About-Me doc, resume, manifesto
  (c) Paste content directly — anything you have in any format
  (d) None — interview from scratch, one question per file

(For operators with public material, a-then-refine is usually
 5x faster than asking "who are you?" from cold.)
```

If a pre-fill source is provided, Claude fetches it once and uses it to draft EACH of the 4 files (about_me, personal_voice, working_style, about_business). For each file, show the draft + offer (a) accept / (b) edit / (c) ask the original question fresh. **Be honest about source limits** — `working_style.md` rhythm (morning vs evening) is usually NOT in public material; explicitly tell the operator what was inferred vs what needs their input.

If no pre-fill source, ask the 4 questions one at a time:

1. **`about_me.md`** — *"In one paragraph: who are you, what do you do, what are you building?"*
2. **`personal_voice.md`** — *"How would a friend describe how you communicate? (warm / direct / poetic / precise / etc.)"*
3. **`working_style.md`** — *"When do you do your best creative work — morning / afternoon / evening? Any other patterns Claude should know about how you operate?"*
4. **`about_business.md`** (if applicable) — *"Are you building one or more ventures? Brief description of each."*

**Per-file skip option (load-bearing):** every file ask must offer *"or skip + I'll observe and pick it up from our first weeks together"*. This isn't a cop-out for the operator — it's a real backstop. The Tier B observation pass in `/close-day` (introduced 2026-05-23) runs the digest every close-day and proposes updates to declared/observed files when content surfaces from accumulated sessions. Operators who skip declared context at cold-start aren't permanently disadvantaged; they're trusting the observation loop to fill it in.

Skip optional files (`role-expectations.md`, `psychometric-profile.md`) unless the operator asks for them.

**Surface the psychometric-profile graduation step** — say something like: *"There's an optional 6th declared file — `psychometric-profile.md` — that captures assessment-based self-knowledge (MBTI, Strengths, Saboteurs, neurochemistry, etc.). It's the highest-leverage declared file for voice calibration when you have it — even 1-2 free assessments (Saboteurs, Quiggle, online MBTI) + a synthesis paragraph dramatically sharpen how the AI frames work, nudges, and energy. Template is at `templates/aios/psychometric-profile-template.md`. Want to start one now (~5 min for 1 lens), schedule it for a week-2 follow-up, or skip?"* Default to "schedule" — operators rarely have assessments ready at cold-start.

### Step 3 — `INTENT.md` (trust contract)

INTENT.md is the highest-leverage file for compounding trust.

> ### `3-light` — what Core actually runs (this is the definition; the tier table only names it)
>
> The tier table says Core runs **`3-light`**, and for a while that label was the only mention of it
> anywhere — so a session running Core had no way to know what to leave out and would have run the full
> walk below. That matters more here than anywhere else in Core: item 1 asks for an autonomy level **per
> domain**, and there are five or more domains, so the full version is on its own longer than the five
> minutes the operator was promised for the whole thing.
>
> **In Core, ask ONE question** — the global posture, in plain words, with no jargon and no list of domains:
>
> ```
> Last thing before you see it work. When I can do something for you —
> draft a reply, tidy a file, prepare a document — would you rather I
> just do it and tell you what I did, or show you first and wait?
>
> Either is fine, and you can change it any time, for everything or
> for one kind of task.
> ```
>
> Then write `INTENT.md` yourself from that single answer:
>
> - Apply their choice as the **global default** across domains.
> - **Regardless of what they chose, pin anything irreversible or outward-facing to draft-first** —
>   sending email to other people, publishing, and anything that spends money. Then tell them, in one
>   line: *"I've kept myself on show-you-first for anything that leaves your name somewhere — email out,
>   anything published. You can loosen that whenever you want."* An operator answering *"just do it"* in
>   minute four is answering about tidying files; they are not authorising outbound mail in their name,
>   and reading it that way would be the single most expensive misread in this file.
> - Take the **defaults** for *just cause* and *focus priorities* (items 2 and 3 below) without asking.
>   Step 3's own text already says the default framing *"is fine for most operators"*, so asking costs two
>   questions and changes nothing.
> - Leave a line in the file naming what was defaulted, so the operator can see what to revisit.
>
> **Depth runs the full walk below** — per-domain autonomy, just cause, the pillars. Nothing here is
> dropped; it is one question now and the rest whenever they ask, which is the same trade as everywhere
> else in Core.

**The full walk (Depth, or on request at any time):**

1. **Autonomy levels** — for each domain (draft messages, external emails, code commits, content publishing, calendar scheduling, etc.), ask: *"autonomous / draft / ask?"* Defaults are conservative ("draft" everywhere); operator opens up as trust grows.
2. **Just cause** — *"In one sentence: why does your work matter beyond revenue?"*
3. **Focus priorities** — *"The four AIOS pillars are Creation / Amplify / Knowledge / Superhuman. Want to customize the framing?"* Default is fine for most operators.

Don't try to fill out venture-level overrides yet — those come once the operator has mounted at least one company (Step 5).

### Step 4 — Agent bundles (informational — all 6 ship by default)

All 6 bundles ship in the AIOS clone. This step is mental-model setting + signal which bundles are HOT for the operator. **Don't ask the operator to "install" or "demote" anything — those are mechanically vague terms.** Instead, classify each bundle as HOT (with one-line reason matching this operator's declared work) or NOT-YET-HOT (with the value it WOULD bring later as an invitation).

| Bundle | HOT for this operator IF | NOT-YET-HOT framing |
|---|---|---|
| `aios/sales/` | Handles leads, writes proposals, manages a sales pipeline | "value if needed: proposal templates + lead-tracker when you start consulting on the side" |
| `aios/strategy/` | Does market research or strategic advisory | "value if needed: market-research agents + competitive-positioning frameworks" |
| `aios/finance-legal/` | Runs a business with invoicing, contracts, or compliance exposure | "value if needed: invoice templates + contract review when accounting load picks up" |
| `aios/engineering/` | Writes code, ships products, reviews PRs | "value if needed: dev session reports + code review agents when you start building" |
| `aios/communication/` | Publishes content, gives presentations, sends emails (almost everyone) | rarely NOT-HOT — default install |
| `aios/personal/` | Wants growth-companion, study-buddy, decision-journaler, etc. | rarely NOT-HOT — default install |

**No action required from the operator at this step.** Just close with: *"Nothing to install or demote — bundles ship in the clone; `/today` surfaces what's relevant based on your declared work."*

### Step 5 — Companies + collaboration spaces (informational — defer setup)

AIOS comes with two adjacent primitives for shared infrastructure beyond your personal vault. **Do NOT try to set either up during cold-start** — both require git connector working (configured in Step 6) AND substrate choice (GitHub/Drive) AND their own interview flows (~10 min each). Setting one up mid-onboarding is a momentum-killing detour. Cover them informationally + defer.

```
The AIOS bundles two workspace primitives. We'll skip setup now —
both deserve their own beats post-cold-start.

1. /aios:company — mount your venture-context (positioning, gtm,
   pricing, brand, agents specific to a venture). Each venture lands
   at vault/00 - notes/context/ventures/{venture}/. Multi-company
   supported — you might mount Acme + your-startup + a client.

2. /aios:collaborate — scaffold shared-with-teammates workspaces
   (partner Drive folders, co-founder GitHub repos, local sync
   folders). Bidirectional content, multiple writers. Distinct
   from /aios:company (which is one-way pulled-in canonical context).

When you finish cold-start, tell me "let's mount my company" or
"let's set up a collaboration space" and we'll do it together —
each takes ~10 min on its own.
```

No questions asked at this step. Operator just acknowledges + moves to Step 6.

### Steps 6 + 7 — moved, not removed → see **Step 11 (connectors)**

> **This is the heart of `AI-122`.** MCP setup and the Stitch question used to live here, on the
> critical path, *before the operator had seen a single thing work*. Step 6 opened by **defining the
> word "MCP"** — which is the tell: if a step has to explain its own vocabulary before it can ask its
> question, it is in the wrong place in the conversation.
>
> **Nothing here was deleted.** The definition, all ten services and their value props, and the entire
> guided auth flow are preserved and now run at **Step 11**, immediately after the first `/today` — the
> moment the operator has *watched their calendar come up empty*, which is the only moment the question
> "want me to connect your calendar?" answers itself. The Stitch ask becomes conditional rather than
> universal (it was already written that way for the `n` case).
>
> **Why later-today and not Day-7:** the value is legible the instant the ritual runs, and the
> motivation the ritual creates expires. A week-later offer is a removal with a polite sentence on top.

### Step 8 — Plugins (announce + install-all-by-default)

Plugins are NOT optional in cold-start. The new operator doesn't know what each plugin does yet — making them DECIDE upfront forces knowledge they don't have. Same pattern as bundles (ship by default) and connectors (bulk-install Phase 1): **announce the recommended set, install them, surface what landed.** Operators can disable any plugin later if they notice it as noise.

> **In Core, run this SILENTLY and report it in the one short paragraph below — never show the operator the marketplace commands.** The `✓ /plugin marketplace add …` list that used to be spoken here is exactly the register this whole change removes from first-run: star counts, `@`-scoped package names and a `+ role-specific selections` line the operator cannot evaluate. It is useful output **for you**, and it stays below as your install reference. In **Depth**, where the operator asked to be shown around, walking the actual list is fair and welcome.

**The standard install set** (based on the universal + role-specific selection from declared context in Steps 2-4) — *your* reference, not a script to read aloud:

```
I've added a few capability packs in the background, picked from what
you just told me — nothing for you to choose, and nothing you have to
remember. They give me stronger habits for writing, reviewing and
research. If you ever want to see or change what's there, just ask.
```

**Role-specific augmentation** (read declared/observed context to decide):

| Operator signal | Add to install set |
|---|---|
| Engineering / build heavy (multi-repo codebase, GitHub presence, dev project notes) | `code-review@claude-plugins-official`, `pr-review-toolkit@claude-plugins-official`, `feature-dev@claude-plugins-official`, `security-guidance@claude-plugins-official` |
| Finance / accounting heavy (invoicing, contracts, tax work) | `npx plugins add anthropics/financial-services` (26K⭐ — 10 vertical agents) |
| Legal exposure (compliance, contracts, advisory) | `npx plugins add anthropics/claude-for-legal` (7.4K⭐) |
| Knowledge-work heavy (writing, research, study, content publishing) | `npx plugins add anthropics/knowledge-work-plugins` (12K⭐) |
| Life sciences / healthcare | `npx plugins add anthropics/life-sciences` OR `anthropics/healthcare` |

**After install, surface what landed** — list new slash commands available in the next session (e.g., `/superpowers`, `/claude-md-health`, `/code-review`, `/security-review`, `/verify`, etc.). Close with: *"You can disable any of these later via `/plugin list` if they feel like noise. Claude won't fire them unless relevant."*

**Edge case — operator says "skip plugins entirely"** before the install fires: respect it. The default is install-all-by-recommended-set, but explicit "skip" wins.

### Step 8.5 — Install AIOS Glass — the panel that lives inside a code editor

> **Say "AIOS Glass", or say "a visual panel inside your editor" — never "the app".** Glass is an **extension** that runs inside Antigravity / VS Code. The **AIOS App** is a separate, standalone program. Calling Glass *"the graphical app"* (which the Step 0 offer used to do) is wrong twice over: it is not an app, and an operator who arrived **through** the App already has a graphical surface open in front of them, so the phrase reads as if they are being sold what they are currently looking at.
>
> **`ENTRY` from the Pre-step decides this step. Do not ask what you already detected.**
> - **`ENTRY=app`** → **skip it entirely**, one line and move on: *"You've already got the AIOS App, which is this same idea in its own window — Glass is the version that lives inside a code editor, so there's nothing to do here."* Walking an App operator through installing a second surface is friction with no payoff.
> - **`ENTRY=glass`** → **Glass is already installed and running — it is how you detected them.** Offering to install it would tell the operator, in the clearest possible way, that this system does not look at their machine. Skip steps 1 and 2 below; the panel exists and is open. Do step 3 only (help them place it beside the editor, which first-timers genuinely miss) and say what you know: *"I can see the AIOS panel is already open in your editor — let's just get it sitting where you'll actually use it."*
> - **`ENTRY=terminal`** → the one branch where a question is right, because this is the one thing the ancestry walk cannot tell you: a plain terminal says nothing about whether they *also* work in an editor. Ask in plain words, then install if yes.

**When it does apply, install it together — walk them through it, don't soft-offer-and-skip.** Glass is a core surface of the AIOS, not an optional extra. Same posture as Step 9 and the bundle/plugin installs: the default is *do it now, together* — there's no fake "skip / later" gate (skipping it leaves a new operator, especially a non-terminal one, without the surface that makes the AIOS usable — exactly the gap that strands them). **What it is:** a docked panel inside the IDE that turns the AIOS into a point-and-click surface — run rituals, launch/spawn agents, browse skills + commands, mount companies, manage spaces, all without typing terminal commands. *Glass, not engine* — it triggers the existing rituals through Claude, reimplements nothing.

Walk them through it now (don't just name it — installing isn't opening):
1. Extensions view (`⌘⇧X` / `Ctrl+Shift+X`) → search **"AIOS Glass"** → **Install** (auto-installs the **Foam** dependency + auto-updates) → reload the window.
2. **Open it:** click the **`AIOS Glass`** item in the **bottom status bar** (or `⌘⇧P` → *AIOS Glass: Open Panel*). This trips up first-timers — confirm they see the panel.
3. **Move it to the secondary (right) side bar** so it sits beside their editor (`⌘⌥B` to toggle the secondary side bar, then drag the AIOS Glass view over). Now panel + files + terminals are all visible at once.

**Calibration (use the persona from `onboarding-aios`/declared context) — this tunes the *pace*, not *whether*:** for **`exec` / `knowledge` / non-terminal** operators, slow down and confirm each step lands (this is the surface that decides whether they use the AIOS or bounce off the terminal — do NOT let them skip it). For **`software`** operators, move faster (terminal-comfortable), but still install it — the agent-orchestrator + spaces surfaces are worth it. Stock Microsoft VS Code users sideload the `.vsix` — full install incl. CLI + troubleshooting: [aios-glass INSTALL.md](https://github.com/The-AIOS/aios-glass/blob/main/INSTALL.md). Full walkthrough also in `START-HERE.md` → Step 4. Only honor an explicit, insistent "skip" — and flag that they'll be operating without the front door.

### Step 9 — Introducing you to {primary-session-name}

Auto-launch the orientation companion. **No y/skip gate** — the "skip" option there is a fake choice (operator would lose orientation; defeats the purpose). Same pattern as bundles ship by default, plugins install by default. Announce + transition + execute.

Frame it as the operator's primary-session-name (e.g., `buddai`) "wearing the onboarding-aios hat" — this is more accurate than "switching hats" because the operator continues to interact with their named session; the agent's expertise is what loads.

```
You're configured. One last hat-switch before your first /today —
I'm putting on the onboarding companion to walk you through the
whole map, framed for your altitude.

(Switching to /agent onboarding-aios now...)
```

Then auto-fire `/agent onboarding-aios`. The agent's greeting MUST extract the operator's name from `vault/00 - notes/context/declared/about_me.md` (first line typically contains "I'm {Name}"  or similar). Combine with the primary session name + the agent hat. Greeting format:

> *"Hey {operator-name-from-about_me}, {primary-session-name} here wearing the onboarding-aios agent hat. Day 0 — clone is fresh, you've configured identity, bundles are all hot, plugins installed. The next move that matters: your first /today..."*

The agent then runs its full Day-0 walkthrough (persona calibration from declared context, compounding-mechanism explanation, ONE next-step). At end, returns control to the cold-start flow for Step 10.

**Why no skip option:** the orientation walk is short (~2-3 minutes), and the operator has NO ALTERNATIVE source for the same mental map. Skipping it = the operator runs /today blind + spends the next two weeks figuring out commands from CHEATSHEET piecemeal. The 2-minute orientation is the highest-leverage moment in the whole onboarding.

### Step 10 — Run your first `/today` + schedule Day-7 check-in

After the orientation walk, close the interview with the climax move: the daily ritual + a Day-7 nudge so the operator doesn't fall off the loop after Day 1. **Companies + collaborations are NOT offered here** — they were deferred to "after cold-start completes" in Step 5's informational coverage. Operator initiates with "let's mount my company" / "let's set up a collaboration space" when ready.

```
Everything compounds from here. Time to feel it.

In the next message, run:  /aios:today

It'll read everything you just told me and propose a plan for the rest
of your day.

One thing to expect: some sections will come up empty — your calendar,
your tasks. That's simply because I'm not connected to those yet, and
connecting them is the very next thing we do, once you've seen the shape
of it.

After today, the loop is:
  - morning  →  /aios:today
  - evening  →  /aios:close-day
  - sessions →  /aios:close-session

That loop is what makes Claude get smarter about YOU over time.
Skip it and the system never compounds.

I'm scheduling a Day-7 check-in — you'll get a prompt to spawn
onboarding-aios for a Week-1 review. That agent will surface what
to try next based on how you've actually been using AIOS in your
first week. (Easy to ignore if you're not in the mood; the schedule
is a nudge, not an interrupt.)

Go ahead — run it, read what it gives you, and I'll be right here.
```

Mention the Day-7 check-in in one line here — it is reassurance, not a closing move. **Never sign off in a step that hands off:** a goodbye here is the same defect as the old "interview is complete" line, because an operator who believes they are finished does not continue to Step 11. The farewell now lives at the true close. Then create the Day-7 `RemoteTrigger`. **Its payload now carries the one genuinely week-later item**, so
the deferral is a scheduled thing rather than a forgotten one:

**Write the marker — this is what makes the sentence above true.** Step 10 tells the operator *"I'm
scheduling a Day-7 check-in"*, and for one commit that was a promise with nothing behind it: no marker, no
cron, nothing reading anything. The multi-account question had been routed here, so it landed nowhere at
all — a step re-timed to a destination that did not exist, which is the one failure this whole change
exists to prevent. `/aios:today` reads this marker and surfaces the check-in on or after `due`:

```bash
printf 'due=%s\ncreated=%s\n' "$(date -v+7d +%F 2>/dev/null || date -d '+7 days' +%F)" "$(date +%F)" \
  > ~/aios/vault/.pending-day7-checkin
```

*(`date -v+7d` is BSD/macOS, `date -d` is GNU/Linux — the fallback covers both, and a failure here is
silent by design: a missing marker costs a nudge, while a visible error in the closing minute of setup
costs the whole impression.)*

The check-in prompt itself, for whoever picks it up:

> *"Spawn onboarding-aios for the Week-1 check-in. Cover: what has actually been useful this week; the
> Depth-tier steps not yet run (agent bundles, companies, plugins, Glass); any connectors still
> unconnected; and — if they have been hitting Claude's 5h/7d caps — whether a second Anthropic account
> and the quota autopilot are worth setting up now (macOS only). Ask that last one **only** if the caps
> have actually bitten; on day one it was meaningless, and if it still is, skip it."*

**Set the expectation BEFORE they run it — this ordering is load-bearing.** The copy above warns that
the calendar will be empty. Without that warning, `/today` looks broken and Step 11 opens by
apologising for a failure the previous step promised would not happen; with it, the emptiness is a
*preview of the next step* and Step 11 lands as the fix that was already announced. Same information,
opposite emotional read — and this was caught by walking the flow rather than by reading the steps.

**⚠️ The interview does NOT end here.** This line used to read *"after `/today` fires, the cold-start
interview is complete"* — and that sentence is precisely what turned deferral into deletion. Let them
read the plan `/today` produced, let the empty calendar register, **then continue to Step 11**. The
operator's own next move comes after that.

Old wording, kept for the record: operator's next move is whatever `/today` suggests — typically beginning the work the day is already underway with, or just absorbing the rhythm-establishing first daily note.

**Reminder for the executing Claude:** the company + collaboration setups DEFERRED at Step 5 are NOT forgotten — they're operator-initiated post-cold-start. If the operator next says *"let's mount my company"* or *"let's set up a collaboration space"*, route to `/aios:company` or `/aios:collaborate` respectively. Don't ask "did you mean...?" — the deferral phrasing in Step 5 is the canonical trigger.

### Step 11 — Connectors (right after the first `/today`, same conversation)

**This step is why the interview does not end at Step 10.** The old line *"After `/today` fires, the
cold-start interview is complete"* is what would have turned this whole redesign into a feature
removal: an operator told "you're done" does not come back for connectors, and the AIOS then ships
without their calendar, their Slack, or their repos — with the operator never learning those powers
existed. So the interview **continues**, in the same breath, using what they just saw.

**Open with the evidence in front of them, not with a concept:**

```
There it is — and the empty calendar I mentioned.

That's the last piece, and it's the one that changes how much I can
actually do for you. Connected, I read your real calendar and tasks
every morning, pull what needs your attention out of Slack, and can
work against your repos. Nothing changes about how you talk to me —
there's just more of your world in the room.

We do these one at a time, and only the ones you want. Each takes
about a minute: I open the right page, you click approve, I check it
worked. You never see or handle a token.

Want to start with your calendar?
```

**Then hand off to `/aios:mcps-setup`** — do not reimplement its flow here. That command already does
exactly the right thing and says so in its own Step 1 (*"Do NOT bulk-install anything"*): one service
at a time, an opt-in question before each, dependencies installed **only after** a yes, the token page
opened with `open <url>`, a real API call to validate, credentials written to a managed `~/.zshrc`
block, and **tokens never echoed back** (receipt confirmed by character count). Hand off *actively* —
invoke it — rather than naming a command and hoping they run it later.

**What is available, in the operator's language.** Say "connectors", never "MCP", and lead with what
each one *does for them*:

1. **Google Workspace** — Calendar, Tasks, Drive, Gmail, Docs, Sheets, Slides (almost every operator)
2. **Slack** — workspace OAuth (if operator uses Slack)
3. **GitHub** — PAT for repos/issues/PRs (if operator codes)
4. **Atlassian** — Jira + Confluence (if operator uses Atlassian)
5. **NotebookLM** — audio summaries (optional)
6. **Stitch** — UI generation from prompts (see Step 7 below — separate ask)
7. **Playwright** — browser automation + auto-publish (advanced, defer)
8. **Nano Banana** — Gemini image generation (cover images, visuals)
9. **PDF Generator** — branded report export (always-on)
10. **Spotify DJ** — lifestyle (optional)

**Order it by what they told you.** They gave you their email at Step 1 — start with Google Workspace,
since Calendar and Tasks are what the daily ritual reads. Then Slack if they mentioned a team, GitHub
if they mentioned code. Skip silently past anything they don't recognise; a service they've never heard
of is not a gap in their setup.

**Stitch is conditional, not universal.** Ask about it only if their answers have involved building
user interfaces. Otherwise it stays available via `/aios:mcps-setup` and is never mentioned — asking
every operator *"do you build user interfaces?"* spends a question on a `no` roughly 95% of the time.

**And close by re-opening the door to Depth:**

```
That's you set up. From tomorrow the rhythm is just:
  morning → /aios:today     evening → /aios:close-day

Two things still waiting whenever you want them, no rush:
  • The full tour — the agents you already have and which fit your
    work, companies and shared workspaces, a visual panel for your
    code editor, and a proper walk through the whole map.
    Say "show me the full tour" any time, today or next month.
  • More connectors — /aios:mcps-setup adds any of the others,
    one at a time, same as we just did.

I'll check in with you in a week to see what's actually been useful.

Welcome to The AIOS. 🌊
```

**Acceptance for this step:** an operator who answers "no thanks" to every connector still finishes
with a working AIOS, and an operator who says yes to two finishes with exactly those two working —
never ten installed, never a bulk download, never a terminal command they had to type.

## Output

Throughout the interview, the command writes to:

1. `USER.md` — identity, sources, growth routines, command personalizations
2. `vault/00 - notes/context/declared/*.md` — about_me, personal_voice, working_style, about_business
3. `INTENT.md` — autonomy levels, just cause, focus priorities
4. `vault/00 - notes/context/ventures/{company}/` — if Step 5 mounted a company

Always show diffs before writing. Operator confirms each section before applying.

## Rules

- **Never auto-fill creative content.** The operator's voice, values, just-cause — those come from them, not from defaults. Smart defaults are for SCAFFOLD only.
- **Save state between steps.** If the operator pauses mid-interview (closes the terminal, etc.), the next `/cold-start-interview` invocation should detect what was completed and offer to resume.
- **Skip aggressively — and the tier offer at Step 0 is now the default expression of this.** Some operators want the full walk; others want the 5-minute fast path. Honor: *"can we skip to MCP setup?"* — jump to Step 6 directly.
- **Always end at Step 11 with a concrete next-action.** The first `/today` is the moment the system starts compounding. Don't let the interview be the destination.
- **Document what was skipped.** At the end, surface: *"You skipped Step 3 (INTENT.md) and Step 7 (Stitch). Run `/cold-start-interview` again anytime, or fill those manually when ready."*

## Schedule

One-shot. Run immediately after cloning AIOS. Optionally re-runnable to revisit specific sections (the command detects what's already configured and asks which to update).

## See also

- [Operating Manual](https://www.the-aios.com/#manual) (www.the-aios.com/#manual) — the full system in one document (17 sections, online or PDF); the deepest single read for an operator who wants the whole picture
- [[onboarding-aios]] — Day-N AIOS orientation agent (run after Week 1, Month 1, Quarter 1 milestones)
- [[USER]] — the canonical personalization file this command writes to
- [[INTENT]] — the trust contract this command calibrates
- [[company]] — if you mount a company in Step 5
- `mcps/_index.md` — canonical connector reference (consulted in Step 11)
