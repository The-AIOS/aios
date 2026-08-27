#!/usr/bin/env bash
# tests/cold-start-interview.test.sh
#
# Guards AI-122's acceptance criteria for /aios:cold-start-interview.
#
# WHY A TEST AND NOT A REVIEW
# ---------------------------
# AI-122 re-times friction out of first-run without removing capability. Both halves of that are
# regressible by a single well-meaning edit:
#
#   · someone re-adds a connector question to Step 1 because it "belongs with the other identity
#     questions", and the #1 measured freak-out is back;
#   · someone tidies Step 11 away as "duplicated content", and the re-timing silently becomes a
#     feature deletion — which is the exact failure this design was shaped to avoid.
#
# So the criteria are asserted, not remembered.
#
# THE VOCABULARY CRITERION IS MEASURED ON SPOKEN COPY, DELIBERATELY.
# "The word MCP appears zero times before the closing section" cannot mean *zero times in the file*,
# because the file must be able to EXPLAIN that rule to the Claude executing it — and a test that
# forbids documenting its own rule is a test that gets deleted. So it counts occurrences inside
# fenced blocks (the words the operator actually reads) before Step 11, and separately reports the
# prose count so a reviewer can see it is meta rather than leakage.
#
# Run:  bash tests/cold-start-interview.test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
F="$ROOT/plugins/aios/commands/cold-start-interview.md"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
# Both helpers RETURN 0 explicitly. Without it, `no "msg"` with no detail arg ends on a failed
# `[ -n "" ]` test and returns 1 — so an `a && no ... || ok ...` chain prints BOTH. That happened on
# this suite's first run: one check reported FAIL and PASS simultaneously.
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

echo "── 1. the file is present and structurally intact ──"
[ -f "$F" ] && ok "command file exists" || { no "missing"; exit 1; }
for step in '### Pre-step' '### Step 0' '### Step 1' '### Step 2' '### Step 3' '### Step 10' '### Step 11'; do
  grep -q "^$step" "$F" && ok "$step present" || no "$step missing"
done

echo "── 2. A1 · connector vocabulary — spoken copy is clean before Step 11 ──"
python3 - "$F" <<'PY'
import re, sys
L=open(sys.argv[1],encoding='utf-8').read().split('\n')
i11=next(i for i,l in enumerate(L) if l.startswith('### Step 11'))
pat=re.compile(r'\bMCPs?\b'); fenced=0; infence=False; prose=0
for n,l in enumerate(L):
    if l.strip().startswith('```'): infence = not infence; continue
    if n<i11:
        if infence: fenced += len(pat.findall(l))
        else:        prose  += len(pat.findall(l))
print(f"SPOKEN={fenced} PROSE={prose}")
PY
read -r counts < <(python3 - "$F" <<'PY'
import re, sys
L=open(sys.argv[1],encoding='utf-8').read().split('\n')
i11=next(i for i,l in enumerate(L) if l.startswith('### Step 11'))
pat=re.compile(r'\bMCPs?\b'); fenced=0; infence=False
for n,l in enumerate(L):
    if l.strip().startswith('```'): infence = not infence; continue
    if infence and n<i11: fenced += len(pat.findall(l))
print(fenced)
PY
)
[ "$counts" = "0" ] && ok "zero 'MCP' in spoken copy before Step 11 (A1)" \
  || no "'MCP' appears $counts time(s) in spoken copy before Step 11"
grep -q 'the word is \*\*"connectors"\*\*\|Say "connectors", never "MCP"' "$F" \
  && ok "the replacement vocabulary is stated in the file" || no "vocabulary rule not stated"

echo "── 3. nothing was REMOVED — the re-timing destinations exist ──"
# Every capability pulled out of the critical path must have a named destination.
grep -q '^### Step 11 — Connectors' "$F" && ok "Step 11 (connectors) exists — the destination for Steps 6+7" \
  || no "Step 11 missing: the re-timing has nowhere to land, which makes it a deletion"
n_services=$(awk '/^### Step 11/,/^## Output/' "$F" | grep -cE '^[0-9]+\. \*\*')
[ "$n_services" -ge 10 ] && ok "all $n_services bundled services preserved in Step 11" \
  || no "only $n_services services listed — value props were lost, not moved"
grep -q 'does NOT end here' "$F" && ok "Step 10 hands off instead of ending the interview" \
  || no "the interview still ends at Step 10 — connectors would never be offered"
grep -qE 'Depth' "$F" && ok "the Depth tier is named (de-mandated, not deferred)" || no "Depth tier missing"
grep -q '5h/7d' "$F" && ok "the multi-account item still exists (re-timed to Day-7, not dropped)" \
  || no "the multi-account capability disappeared entirely"

echo "── 4. Step 1 stays short — the friction that started this ──"
q=$(awk '/^### Step 1 —/,/^### Step 2 —/' "$F" | grep -cE '^[0-9]+\. \*\*')
[ "$q" -le 2 ] && ok "Core Step 1 asks $q question(s) (≤2)" \
  || no "Step 1 is back to $q questions — a connector question has crept in"
# Only NUMBERED question lines count. Step 1 deliberately contains a table documenting that the
# Slack/GitHub question MOVED to Step 11 — and the first version of this check matched that table,
# reading the record of the removal as the removal being undone. A guard that cannot tell a thing
# from its changelog will fire on every honest edit.
if awk '/^### Step 1 —/,/^### Step 2 —/' "$F" | grep -E '^[0-9]+\. ' | grep -qiE 'slack|github|calendar \+ tasks'; then
  no "a connector question is back in Step 1 (numbered question line)"
else
  ok "no connector question among Step 1's numbered questions"
fi

echo "── 5. A2 · the vault connector is registered silently, never asked ──"
grep -q 'mcp-obsidian@latest' "$F" && ok "obsidian registration is present" || no "obsidian registration missing"
grep -q 'Never ask the operator about it' "$F" && ok "explicitly marked never-ask" || no "not marked never-ask"
awk '/^### Step 11/,/^## Output/' "$F" | grep -qi 'obsidian' \
  && no "obsidian is listed as a connector — it is infrastructure, must not appear" \
  || ok "obsidian is absent from the connectors list (infrastructure, not a connector)"

echo "── 6. both entry paths are handled ──"
grep -q 'ENTRY=app' "$F" && ok "app-vs-terminal entry detection present" || no "no entry detection"
grep -q 'Never mention SETUP.md to an App-path operator\|never send them to it' "$F" \
  && ok "app-path operators are never routed into SETUP.md" || no "SETUP.md routing rule missing"

echo "── 7. CONTROL — the criterion must be able to fail ──"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/csi.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
python3 - "$F" "$TMP/broken.md" <<'PY'
import sys
L=open(sys.argv[1],encoding='utf-8').read().split('\n')
i11=next(i for i,l in enumerate(L) if l.startswith('### Step 11'))
# inject a spoken-copy violation into Step 0's fenced block
for i,l in enumerate(L[:i11]):
    if l.strip().startswith('```') :
        L.insert(i+1, "  MCPs set up for your daily tools"); break
open(sys.argv[2],'w',encoding='utf-8').write('\n'.join(L))
PY
bad=$(python3 - "$TMP/broken.md" <<'PY'
import re, sys
L=open(sys.argv[1],encoding='utf-8').read().split('\n')
i11=next(i for i,l in enumerate(L) if l.startswith('### Step 11'))
pat=re.compile(r'\bMCPs?\b'); fenced=0; infence=False
for n,l in enumerate(L):
    if l.strip().startswith('```'): infence = not infence; continue
    if infence and n<i11: fenced += len(pat.findall(l))
print(fenced)
PY
)
[ "$bad" -gt 0 ] && ok "CONTROL FIRES: a spoken 'MCP' before Step 11 is detected ($bad)" \
  || no "CONTROL DID NOT FIRE — section 2 cannot see a violation, so it proves nothing"


# ─────────────────────────────────────────────────────────────────────────────
# 4 · CROSS-SURFACE CONSISTENCY
#
# Four documents describe this same first run: README.md (the funnel), START-HERE.md
# (post-clone), SETUP.md (which Claude EXECUTES), and the interview itself. SETUP.md
# alone carries the sequence TWICE — once addressed to Claude, once to the operator.
#
# They drifted during this very change: the connectors step and the interview's
# duration were corrected in one copy and not the other, so a first-timer read a
# promise the executor no longer made. Nothing detected it; a human reread did.
# These assertions are that reread, made mechanical.
# ─────────────────────────────────────────────────────────────────────────────
SURFACES="README.md START-HERE.md SETUP.md CHEATSHEET.md TOOLS.md plugins/aios/commands/cold-start-interview.md"

# 4a — the retired contract must not survive anywhere. Whichever copy keeps it is
#      the one a newcomer might read.
for claim in '15-25 min' '~20 min' 'Steps 0-10' 'installs MCPs' 'pulls your Calendar + Tasks + Slack'; do
  hits=""
  for f in $SURFACES; do
    [ -f "$f" ] || continue
    grep -qF "$claim" "$f" && hits="$hits $f"
  done
  [ -z "$hits" ] && ok "retired claim absent from every surface: \"$claim\"" \
    || no "retired claim still live: \"$claim\"" "in:$hits — a surface promising the old flow is worse than no surface"
done

# 4b — SETUP.md is the file the entry prompt actually runs. It must not fire the
#      connectors pass, nor ask the two questions that moved. Matching only a LIVE
#      invocation: the file must stay free to explain, in prose, why it doesn't.
# NOTE: the block is an HTML <details>, NOT a '>' blockquote. The first version of
#       this guard matched '^> ### .*Reading this as Claude' and selected ZERO lines,
#       so it passed by measuring nothing — reintroducing the exact invocation did not
#       make it fire. The line-count assertion below is what makes that visible.
CLAUDE_BLOCK=$(awk '/<summary>.*Reading this as Claude/,/<\/details>/' SETUP.md)
CB_STEPS=$(printf '%s\n' "$CLAUDE_BLOCK" | grep -cE '^[0-9]+\. ')
[ "${CB_STEPS:-0}" -ge 8 ] \
  && ok "the Claude-facing block is locatable and has $CB_STEPS numbered steps" \
  || no "cannot locate the Claude-facing block in SETUP.md (found ${CB_STEPS:-0} steps)" \
       "every assertion scoped to it would pass by measuring nothing"

# The step that REPLACED the invocation says "Do NOT invoke `/aios:mcps-setup` here"
# and is itself a numbered line, so a naive '^[0-9]+\. .*invoke' fires on the fix.
# Strip negated lines first: a guard that cannot tell a thing from its own changelog
# fires on every honest edit, and gets muted.
if printf '%s\n' "$CLAUDE_BLOCK" \
     | grep -E '^[0-9]+[a-z]?\. ' \
     | grep -viE 'do not|don.t|never|no longer|used to' \
     | grep -qF 'invoke `/aios:mcps-setup`'; then
  no "SETUP.md still invokes /aios:mcps-setup as a numbered step" "connectors belong to interview Step 11, after the first /today"
else
  ok "SETUP.md does not invoke the connectors pass during setup"
fi
grep -qF 'Do you use more than one Anthropic account?' SETUP.md \
  && no "SETUP.md still asks the multi-account question" "unanswerable on day one; the Day-7 check-in owns it" \
  || ok "SETUP.md no longer asks the multi-account question"

# 4c — removal without a named destination is how re-timing decays into deletion.
#      SETUP must point at where each moved thing went.
grep -qF 'Step 11' SETUP.md \
  && ok "SETUP.md names interview Step 11 as the connectors' destination" \
  || no "SETUP.md drops connectors with no destination" "a reader cannot tell 'later' from 'gone'"
grep -qiE 'Day-7|Day 7' SETUP.md \
  && ok "SETUP.md names the Day-7 check-in as the multi-account destination" \
  || no "SETUP.md drops the multi-account question with no destination" ""

# 4d — the interview's own self-description is read by every session that lists
#      commands. It drifted too, and it is the least likely copy to be reread.
grep -qE '5-minute Core|~5 ?min' "$F" \
  && ok "the interview's description states the Core contract it actually offers" \
  || no "the interview's description does not state its own Core contract" "the description is what a session sees before opening the file"


# ─────────────────────────────────────────────────────────────────────────────
# 5 · ONE OWNER PER STEP, AND ONE ACTOR
#
# SETUP.md and this interview are ONE flow with ONE trigger: the operator says
# "Set up my AI-OS from <repo>" and their Claude session executes everything,
# SETUP.md invoking the interview at its step 10. The operator never runs either.
#
# Two consequences are asserted here. First: a step that appears in both files runs
# twice, and only some of those are legitimate. Second: no operator-facing document
# may instruct the operator to run something their session runs for them.
# ─────────────────────────────────────────────────────────────────────────────

# 5a — the Obsidian bridge had FOUR registration sites with TWO different argument
#      sets (SETUP hardcoded ~/aios/vault; this file uses the resolved install path).
#      Because this file's registration is guarded by "skip if already registered",
#      whichever copy ran first won permanently — including when it was the wrong one.
#      Exactly one EXECUTABLE site is allowed, and it is this one. SETUP.md may still
#      document the command for manual repair; it may not run it as a step.
if grep -qE '^\s*(\|\|)?\s*claude mcp add obsidian' "$F"; then
  ok "the interview registers the Obsidian bridge (the single owner, both doors)"
else
  no "the interview no longer registers the Obsidian bridge" "an App-path operator never passes through SETUP.md, so this is their only pass"
fi
if awk '/<summary>.*Reading this as Claude/,/<\/details>/' SETUP.md | grep -qF 'claude mcp add obsidian'; then
  no "SETUP.md's executable sequence registers the Obsidian bridge again" \
     "two owners, two argument sets, and a skip-if-present guard that makes the first one permanent"
else
  ok "SETUP.md's executable sequence does not re-register the Obsidian bridge"
fi

# 5b — the twice-run path check must be SILENT when it has nothing to do. It runs a
#      second time on the terminal path, and the Pre-step promises the operator sees
#      none of it. An echo on the no-op branch breaks that promise on every terminal
#      install — the common case.
PRE=$(awk '/^### Pre-step/,/^### Step 0/' "$F")
if printf '%s\n' "$PRE" | grep -qE 'echo "path-portability: (already at|symlink already)'; then
  no "the Pre-step path check speaks on a no-op branch" \
     "it runs twice on the terminal path; the Pre-step promises the operator reads none of it"
else
  ok "the Pre-step path check is silent unless it acted or needs a decision"
fi

# 5c — the wrapper installer runs in BOTH files and that one is deliberate: it reads
#      USER.md, which does not exist until this interview writes it. SETUP.md must say
#      so, or a future dedup pass deletes whichever copy it happens to find second —
#      the same instinct that is correct for 5a is wrong here, so the difference has
#      to be written down rather than rediscovered.
if grep -qiE 'runs this a second time, on purpose|do not "deduplicate"' SETUP.md; then
  ok "SETUP.md marks the wrapper re-run as deliberate, not redundant"
else
  no "SETUP.md does not explain why the wrapper installer runs twice" \
     "an unexplained duplicate invites a cleanup that removes the identity-aware run"
fi

# 5d — the operator is never the actor. "Run SETUP.md" and "Run /aios:cold-start-
#      interview" both describe things their Claude session does; a reader who tries
#      to obey either is looking for a command that was never theirs to type.
BAD=""
for f in README.md START-HERE.md SETUP.md CHEATSHEET.md TOOLS.md; do
  [ -f "$f" ] || continue
  grep -qiE 'Run `SETUP\.md`|Run `/?(aios:)?cold-start-interview' "$f" && BAD="$BAD $f"
done
[ -z "$BAD" ] \
  && ok "no operator-facing doc tells the operator to run what their session runs" \
  || no "operator-facing doc(s) still instruct the operator to run the flow:$BAD" \
       "the operator types one sentence; everything after it is their Claude session"


# 5e — NO CODA. SETUP.md step 10 hands control to this interview and does not get it
#      back: the interview fires the first /today, offers connectors, and closes on
#      "Welcome to The AIOS." Anything SETUP.md invokes after step 10 therefore lands
#      AFTER the operator has been told they are finished — and it lands worst on the
#      one who chose the ~5-minute start. Three separate steps did exactly this before
#      being retired (mcps-setup, the orientation hat, company/collaborate).
#
#      A first version of this guard filtered the lines by PROSE ("skip anything that
#      says 'do not' or 'the interview already owns'"). That fails open: a live step
#      whose sentence happens to mention the interview owning something gets excused,
#      which is exactly what a half-finished edit produces. So the rule is positional
#      instead — each retired step must OPEN with its retirement marker. Prose after
#      the marker cannot buy an exemption.
CODA_BAD=""
for n in 11 12 13; do
  line=$(awk '/<summary>.*Reading this as Claude/,/<\/details>/' SETUP.md | grep -E "^${n}\. " | head -1)
  [ -n "$line" ] || continue
  case "$line" in
    "$n. **Do NOT"*|"$n. ~~"*|"$n. Do NOT"*) : ;;
    *) CODA_BAD="$CODA_BAD
  step $n: $(printf '%s' "$line" | cut -c1-72)" ;;
  esac
done
if [ -z "$CODA_BAD" ]; then
  ok "SETUP.md invokes nothing after handing off to the interview (no coda)"
else
  no "SETUP.md invokes something after the interview has already closed" "$CODA_BAD"
fi


# ─────────────────────────────────────────────────────────────────────────────
# 6 · THE FULL TOUR MUST DESCRIBE ITSELF HONESTLY
#
# The Step 0 offer used to read: "The full tour — same start, plus the deeper
# setup: your agent team, companies, plugins, the graphical app." Three of those
# four were wrong, and an operator spotted it inside a single message:
#
#   - "your agent team"    — Step 4 says all six bundles ship in the clone and
#                            closes with "nothing to install or demote". Step 0
#                            had ALREADY said the agents ship built. Offering them
#                            as a tour extra contradicts both.
#   - "companies"          — Step 5 explicitly DEFERS setup ("we'll skip setup
#                            now"). It explains; it does not set anything up.
#   - "the graphical app"  — that is AIOS Glass, an EXTENSION inside a code
#                            editor. The AIOS App is a separate program. And an
#                            App-path operator is already looking at a graphical
#                            surface, so the phrase sells them what they hold.
#
# A tour that oversells is not a warmer tour — the operator who takes it finds
# the promised things already installed and wonders what they actually got.
# ─────────────────────────────────────────────────────────────────────────────

# 6a — no spoken copy may conflate Glass with the App. Prose that states this very
#      rule is allowed, so the check is scoped to fenced blocks, as in section 2.
GBAD=$(awk '/^```/{f=!f;next} f' "$F" | grep -inE 'the graphical app|the desktop app|plugins, the app' || true)
[ -z "$GBAD" ] \
  && ok "no spoken copy calls the Glass panel an app" \
  || no "spoken copy conflates AIOS Glass with the AIOS App" "$(printf '%s' "$GBAD" | head -2)"

# 6b — the tour must not offer the agents as though taking it is how you get them.
TOUR=$(awk '/^### Step 0/,/^### Step 1/' "$F" | awk '/^```/{f=!f;next} f')
printf '%s\n' "$TOUR" | grep -qiE 'your agent team' \
  && no "the Step 0 tour offers 'your agent team' as a tour extra" \
        "the same message already said the agents ship built; Step 4 is orientation, not acquisition" \
  || ok "the Step 0 tour does not sell the operator agents they already have"

# 6c — Step 8 installs a plugin set and its own text calls that NOT optional. It sat
#      in the opt-in tier, so every operator choosing the quick start silently got
#      none of it. That is deletion wearing re-timing's clothes — the one failure
#      mode this whole change exists to prevent. It needs nothing from the operator,
#      so Core must run it.
if grep -qE '^\| \*\*Core\*\*.*\*\*8 \(silent\)\*\*' "$F"; then
  ok "Core runs Step 8, so the quick start does not silently lose the plugin set"
else
  no "Step 8 is not in the Core path" "its own text says plugins are NOT optional; leaving it in Depth deletes it for every quick-start operator"
fi
if grep -qE '^\| \*\*Depth\*\*.*plus 4 · 5 · 8 · ' "$F"; then
  no "Step 8 is still listed as Depth-only" "it would run twice, or not at all, depending on which row is believed"
else
  ok "Step 8 is no longer listed as Depth-only (one tier owns it)"
fi

# 6d — and what Core runs silently must not be spoken as marketplace commands. The
#      old block read out '/plugin marketplace add anthropics/skills (138K⭐)' and a
#      '+ role-specific selections' line: star counts and @-scoped package names an
#      operator cannot evaluate, in the register this change removes from first-run.
S8=$(awk '/^### Step 8 —/,/^### Step 8\.5/' "$F" | awk '/^```/{f=!f;next} f')
printf '%s\n' "$S8" | grep -qE '/plugin (marketplace add|install)|⭐' \
  && no "Step 8's spoken copy reads marketplace commands aloud" \
        "useful output for the executor, not for a first-timer; keep it as reference prose" \
  || ok "Step 8's spoken copy names no marketplace commands"


# ─────────────────────────────────────────────────────────────────────────────
# 7 · THE SURFACE IS DETECTED, NOT GUESSED AND NOT ASKED
#
# The first version probed the filesystem: does ~/.aios/surfaces/app.json exist,
# does /Applications/AIOS.app exist. Both fail in the direction that matters, and
# both were measured failing on a live machine on 2026-08-27:
#
#   - glass.json was PRESENT with a DEAD pid while the App was genuinely running.
#     A presence check reports "IDE" to an operator sitting in the App.
#   - app.json's pid was live AND five hops up that session's ancestry — which the
#     presence check cannot distinguish from "the App is merely installed".
#
# The protocol's own answer (~/.aios/spawn-inbox/README.md) is a liveness-checked
# walk of your own process ancestry, comparing PIDS — never process names, since
# Glass runs inside whatever editor the operator happens to use.
# ─────────────────────────────────────────────────────────────────────────────
PRE=$(awk '/^### Pre-step/,/^### Step 0/' "$F")

# 7a — the liveness check is the whole difference between detection and a guess.
printf '%s\n' "$PRE" | grep -qF 'os.kill(d["pid"], 0)' \
  && ok "surface detection liveness-checks the announced pid" \
  || no "surface detection does not liveness-check" "a surface file outlives its process; glass.json was measured present-and-dead"

# 7b — and it must walk ancestry, not merely find a live surface somewhere on the box.
# NOTE: this first read `grep -qE 'while p and p != 1|parent(p)'`. The alternation
#       made it pass on a stubbed walk, because `p = parent(p)` survives inside a
#       loop replaced by `if False:` — the helper existing is not the walk running.
#       Both halves are required now: the climb AND the reassignment.
if printf '%s\n' "$PRE" | grep -qF 'while p and p != 1' \
   && printf '%s\n' "$PRE" | grep -qF 'p = parent(p)'; then
  ok "surface detection walks this session's own ancestry"
else
  no "surface detection does not walk ancestry" "a live surface elsewhere on the machine did not launch this session"
fi

# 7c — the retired probes must not come back as a 'simplification'.
BADPROBE=$(printf '%s\n' "$PRE" | grep -nE '^\s*(if )?\[ -[fd] "?\$HOME/\.aios/surfaces|-d "?/Applications/AIOS\.app' || true)
[ -z "$BADPROBE" ] \
  && ok "no install-path or file-presence probe stands in for detection" \
  || no "a file-presence / install-path probe is back" "$(printf '%s' "$BADPROBE" | head -2)"

# 7d — three surfaces, three behaviours. A binary app/terminal split cannot express
#      the case that matters most: an operator already inside Glass being offered an
#      install of Glass, which tells them plainly that nothing looked at their machine.
for e in 'ENTRY=app' 'ENTRY=glass' 'ENTRY=terminal'; do
  grep -qF "$e" "$F" && ok "the flow branches on $e" || no "no branch for $e" "the surface split is not three-way"
done

# 7e — Glass must never be offered to an operator detected THROUGH Glass.
S85=$(awk '/^### Step 8\.5/,/^### Step 9/' "$F")
printf '%s\n' "$S85" | grep -qiE 'ENTRY=glass' \
  && ok "Step 8.5 handles the already-in-Glass case explicitly" \
  || no "Step 8.5 does not branch on ENTRY=glass" "it would walk an operator through installing the panel they are looking at"

# 7f — Step 2 writes about_me.md, which the AIOS App watches to learn the operator's
#      name. Trimming it out of Core would silently regress a fix in another repo.
grep -qE 'about_me\.md.*(watch|greeting)|greeting.*about_me\.md' "$F" \
  && ok "the App's dependency on about_me.md is recorded where it can be seen" \
  || no "nothing records that the App reads about_me.md for its greeting" "a future Core trim would regress an operator-reported fix in aios-app"


# ─────────────────────────────────────────────────────────────────────────────
# 8 · EVERY TIER-TABLE SHORTHAND MUST BE DEFINED SOMEWHERE
#
# The Core row reads "Pre-step -> 0 -> 1 (trimmed) -> 2 -> 3-light -> 8 (silent)
# -> 10 -> 11". Each parenthetical is an INSTRUCTION to the session running Core.
# "3-light" was named there and defined nowhere, so Core would have run the full
# Step 3 — which asks an autonomy level per domain across five-plus domains, and
# is by itself longer than the five minutes the operator was promised for all of
# it. A label that names a variant without defining it does not shorten anything;
# it just makes the table look like a decision that was taken.
# ─────────────────────────────────────────────────────────────────────────────
grep -qE '`3-light`.*what Core actually runs|### `3-light`' "$F" \
  && ok "3-light is defined, not only named in the tier table" \
  || no "3-light is named in the tier table but never defined" "Core would run the full Step 3 — per-domain autonomy, longer than the whole promised Core"

# 8b — and the one-question version must not quietly authorise outbound actions.
#      An operator answering "just do it" in minute four is talking about tidying
#      files, not about email going out in their name.
S3=$(awk '/^### Step 3 —/,/^### Step 4/' "$F")
printf '%s\n' "$S3" | grep -qiE 'pin anything irreversible|irreversible or outward-facing to draft' \
  && ok "3-light pins irreversible and outward-facing actions to draft regardless of the answer" \
  || no "3-light applies one global answer to everything" "a minute-four yes about tidying files would authorise outbound mail in the operator's name"

printf '\nRESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
