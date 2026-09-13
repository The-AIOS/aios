#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# A spawned worker's context rule is stated in FOUR places — all four must agree
#
# A worker is born on two paths, and only one of them reads the wrapper:
#   · `spawn` typed in a terminal  → hooks/claude-identity/install-wrappers.sh
#                                    injects the preamble into the task file
#   · a surface fulfilling an inbox request → never reads that file, and is
#                                    governed by CLAUDE.md § Identity & Greeting
#                                    step 4 alone
#
# So the rule lives in two hand-maintained places that are read by different
# audiences at different moments. The dangerous half of the rule is the FLOOR —
# the observed files a worker reads every time regardless of the task — because
# dropping it fails silently: the worker still answers, still sounds right, and
# is simply missing the context that made the answer this operator's rather than
# merely correct. No error, no tell, and the surface-fulfilled path is the one
# with no second copy to fall back on.
#
# This asserts AGREEMENT, deriving the floor from the preamble rather than
# hardcoding a list of its own — a canonical-side list would be a third copy,
# which is the thing being prevented. It also refuses to pass vacuously on an
# empty floor, because "every file in an empty set is present" is true and
# useless.
#
# EXTENDED after review: there were FOUR copies, not two, and the two that were
# missed are the wrapper's own DEFAULT TASK on each platform — the text used when
# `spawn <name>` is called with no task. That default said "load my declared +
# observed context" while the preamble beside it said not to preload, so a
# no-task spawn wrote both instructions into one file and told the worker to do
# opposite things. Windows had no preamble at all, so the change reached two
# platforms of three. A parity suite that compares only the copies you remembered
# is the same failure it exists to prevent, one level up.
#
# Comments are STRIPPED before matching (antifragile #105): the fix's own comment
# quotes the string it removed, and a whole-file grep cannot tell an explanation
# from an instruction.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

CM="CLAUDE.md"
WR="hooks/claude-identity/install-wrappers.sh"
PS1="hooks/claude-identity/install-wrappers.ps1"

printf '\n spawned-worker context parity\n\n'

# ── the wrapper path ────────────────────────────────────────────────────────
PREAMBLE="$(sed -n '/^_spawn_task_preamble() {/,/^}/p' "$WR")"
if [ -n "$PREAMBLE" ]; then
  ok "the wrapper defines _spawn_task_preamble"
else
  no "the wrapper defines _spawn_task_preamble" "not found in $WR"
fi

if grep -q '_spawn_task_preamble; printf' "$WR"; then
  ok "the preamble is actually written into the task file"
else
  no "the preamble is actually written into the task file" \
     "defining it is not wiring it — the task file must open with it"
fi

# ── the floor must be DERIVED, not enumerated ───────────────────────────────
# This section used to check the opposite: it scraped `observed/<name>.md` out of
# the preamble and asserted CLAUDE.md named the same files. That check passed
# while the rule was wrong. An enumerated floor is a second implementation of a
# folder's contents, and both context folders VARY PER VAULT -- the framework
# ships 5 declared and 9 observed files and operators add their own. Measured on
# one live vault, a floor naming four observed files by name missed 103 entry
# titles across five other files, including the venture map and the identity
# synthesis. Same family as the Tier-1 root-docs list that silently missed three
# docs; the fix is the same one: derive it.
for pair in "CLAUDE.md:$CM" "AGENTS.md:AGENTS.md" "the wrapper:$WR" "the .ps1:$PS1"; do
  label="${pair%%:*}"; f="${pair#*:}"
  [ -f "$f" ] || { no "$label missing" "cannot check the floor"; continue; }

  # A glob over the folder, in any of the spellings the four surfaces use.
  if grep -qE 'observed/"?\*\.md|observed/\*\.md|every heading in both folders|EVERY HEADING IN BOTH FOLDERS|every file in `?observed' "$f"; then
    ok "$label derives the floor by globbing the folder"
  else
    no "$label does not glob the context folders" \
       "a floor that names files silently skips every file an operator added"
  fi

  # NEGATIVE: the enumerated floor must not come back. Allow antifragile.md to be
  # named -- it is singled out deliberately as the scan-before-commands file --
  # but naming THREE OR MORE observed files is the enumeration returning.
  NAMED=$(grep -oE 'observed/[a-z-]+\.md' "$f" | sort -u | grep -vc 'antifragile' || true)
  if [ "${NAMED:-0}" -ge 3 ]; then
    no "$label re-enumerates the floor ($NAMED observed files named)" \
       "that list is a second implementation of the folder and goes stale silently"
  else
    ok "$label does not re-enumerate observed/ as a filename list"
  fi

  # The vault-shape hazard must be STATED, not just avoided -- an unexplained
  # glob gets "tidied" back into a list by the next editor (#105).
  if grep -qiE 'vary from vault to vault|varies from vault|never a list of filenames|operators add their own' "$f"; then
    ok "$label says WHY it globs (folders vary per vault)"
  else
    no "$label globs without saying why" "the next edit collapses it back into a list"
  fi
done

# ── CLAUDE.md step 4 ────────────────────────────────────────────────────────
# Step 4 is a BLOCK, not a line: it carries sub-points (the floor, the output
# question, the unsure case). Extracting only the first line -- which the first
# version did, when step 4 happened to be one line -- silently measures a fraction
# of the rule and reports on the rest. Read to the start of step 5.
STEP4="$(awk '/^4\. After greeting/{f=1} f&&/^5\. \*\*When the task is done/{exit} f' "$CM")"
if printf '%s' "$STEP4" | grep -qiE 'always, whatever the task|floor' \
   && printf '%s' "$STEP4" | grep -qiE 'the map is enough|only what this task touches|only the files this task touches'; then
  ok "CLAUDE.md step 4 states both halves: an unconditional read and a sized one"
else
  no "CLAUDE.md step 4 must state a floor AND a sized read" "got: ${STEP4:0:120}"
fi

# ── antifragile.md is still singled out, and still ships ────────────────────
# It is the one file the ritual asks to be scanned BEFORE executing commands, so
# a floor that merely globs without naming it loses that instruction.
printf '%s' "$STEP4" | grep -q 'antifragile' \
  && ok "CLAUDE.md still singles out antifragile.md" \
  || no "antifragile.md lost its special mention" "it is the scan-before-commands file"
[ -f "vault/00 - notes/context/observed/antifragile.md" ] \
  && ok "antifragile.md ships in the template vault" \
  || no "antifragile.md missing from the template vault" "a floor pointing at a file no vault has is a dead rule"

# ── the derived floor equals what context-rungs.py calls rung 1 ─────────────
# If the tool measures a rung nobody is instructed to read, Bucket 31 reports a
# number that does not describe what sessions actually do -- which is the same
# class of defect as the stale constant the tool exists to replace.
if grep -q 'every heading in both folders' hooks/context-rungs.py; then
  ok "context-rungs.py rung 1 is the same floor CLAUDE.md prescribes"
else
  no "the tool's rung 1 and the prescribed floor have drifted" \
     "a measurement that does not measure the rule is worse than none"
fi

printf '\n  %d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

# ── the copies the first version missed ─────────────────────────────────────
echo
echo " the wrapper's DEFAULT TASK must not restate the rule"
# Strip comments first. The commit that removed the contradicting string explains
# itself in a comment that necessarily contains it (#105) -- matching raw text here
# would report a defect that is only an explanation.
code_sh="$(sed 's/^[[:space:]]*#.*//' "$WR")"
code_ps="$(sed 's/^[[:space:]]*#.*//' "$PS1")"
for pair in "sh:$code_sh" "ps1:$code_ps"; do
  label="${pair%%:*}"; body="${pair#*:}"
  if printf '%s' "$body" | grep -q 'load my declared + observed context'; then
    no "$label default task tells the worker to preload" \
       "the preamble in the same file says the opposite; a no-task spawn gets both"
  else
    ok "$label default task does not contradict the preamble"
  fi
done

echo
echo " Windows gets the preamble too, or the change reaches two platforms of three"
if grep -qiE 'Before the task' "$PS1" && grep -q 'taskPreamble' "$PS1"; then
  ok "the .ps1 injects a context preamble"
else
  no "the .ps1 writes its task file with no preamble" \
     "a Windows-spawned worker then boots with no operator context at all"
fi
# The floor must be the SAME on both platforms. It used to be compared as a LIST of
# observed filenames, which is exactly the enumeration this PR removed -- so the
# comparison is now over the floor's three load-bearing properties. A platform that
# drifts on any of them boots workers with a different floor, silently.
#   1. it globs BOTH folders rather than naming files
#   2. it singles out antifragile.md (scan-before-commands)
#   3. it says WHY it globs, so the next editor does not tidy it into a list
sig(){ # $1 = text -> a three-field signature
  local s="$1" a b c
  printf '%s' "$s" | grep -qiE '\*\.md|every heading in both folders|EVERY HEADING IN BOTH FOLDERS' && a=glob || a=LIST
  printf '%s' "$s" | grep -qi 'antifragile' && b=antifragile || b=NONE
  printf '%s' "$s" | grep -qiE 'vary from vault to vault|never a list of filenames' && c=why || c=UNEXPLAINED
  printf '%s/%s/%s' "$a" "$b" "$c"
}
sig_sh="$(sig "$PREAMBLE")"
sig_ps="$(sig "$(cat "$PS1")")"
if printf '%s' "$sig_sh" | grep -q 'LIST\|NONE\|UNEXPLAINED'; then
  no "the wrapper preamble's floor is incomplete ($sig_sh)" \
     "expected glob/antifragile/why — a LIST goes stale, NONE loses the scan rule, UNEXPLAINED gets tidied back"
elif [ "$sig_sh" = "$sig_ps" ]; then
  ok "both platforms prescribe the same floor ($sig_sh)"
else
  no "the floor differs by platform" "sh: $sig_sh | ps1: $sig_ps"
fi

echo
echo " the rule is keyed on the WORK, not on being a worker"
# The review that produced this: keying on identity makes every spawned agent
# permanently thinner than the primary session -- including the agents whose whole
# job is to sound like the operator. The discriminator must be the output.
for pair in "CLAUDE.md:$CM" "the wrapper:$WR" "the .ps1:$PS1"; do
  label="${pair%%:*}"; f="${pair#*:}"
  # Match the RULE, not the phrasing (#105). The .ps1 says "the words of the operator"
  # because it must avoid apostrophes -- it lives inside a single-quoted here-string --
  # and a check pinned to one file's wording fails on a change that is purely mechanical.
  # What must be true everywhere: the test is keyed on the OUTPUT acting for the operator.
  if grep -qiE "act on their behalf|act on behalf of the operator|words of the operator" "$f"; then
    ok "$label asks the output question"
  else
    no "$label does not state the work-shape test" \
       "without it the rule reads as 'workers get less', which is the thing being avoided"
  fi
done
grep -qiE 'unsure is not a third answer|[Uu]nsure .*read the full' "$CM" \
  && ok "CLAUDE.md resolves the unsure case toward the full ritual" \
  || no "the unsure case is unresolved" "the two errors are asymmetric; silence favours under-reading"

echo
echo " the skipped context is named as available, not merely skipped"
# Operator-raised. Without this the rule reads as a one-time boot decision, and a worker that
# discovers mid-task that it needed the voice file has no signal that reaching for it is allowed.
# Naming what was NOT read -- and that it can be opened later -- is what makes a narrowed floor
# recoverable instead of a silent ceiling.
for pair in "CLAUDE.md:$CM" "the wrapper:$WR" "the .ps1:$PS1"; do
  label="${pair%%:*}"; f="${pair#*:}"
  # Match fragments that survive LINE WRAPPING. The full sentence "NOT because it is off
  # limits" wraps between "it" and "is" in the preambles, so a single-line grep for it
  # scores zero on text that plainly contains it -- the check failed on correct files.
  # Two short, distinctive fragments, each of which fits on one line by construction.
  if grep -qi "off limits" "$f" && grep -qi "not exceptional" "$f"; then
    ok "$label tells the worker the rest is available mid-task"
  else
    no "$label does not say the unread context may be opened later" \
       "a narrowed floor with no route back is a ceiling"
  fi
done
# and it must name the scale, or "the rest" is an abstraction nobody acts on
grep -qiE '150k tokens|100k words|120k words|six figures of tokens' "$CM" \
  && ok "CLAUDE.md names how much is being skipped" \
  || no "the skipped volume is unquantified" "a worker cannot weigh a cost it cannot see"

echo
echo " the two folders are read differently -- the split that makes this work"
# Measured: a worker told to read ALL of both folders for a two-sentence task spent 38 tool
# calls and never delivered. Told to read the MAP plus declared/, it delivered in 26 -- in
# the operator's voice, applying a per-surface rule from their own files.
#
# The REASON the split holds is the asymmetry in how the two failures surface, NOT a claim
# about indexability. An earlier version of this rule asserted that declared/ "does not
# index" and shipped that into four files -- and into THIS test, which then enforced the
# falsehood. Measured, declared/ carries MORE headings per word than observed/ does. The
# conclusion survived; the reason did not. Hence both an assertion on the true reason and a
# NEGATIVE assertion below, so the false one cannot come back.
for pair in "CLAUDE.md:$CM" "the wrapper:$WR" "the .ps1:$PS1"; do
  label="${pair%%:*}"; f="${pair#*:}"
  if grep -qiE "ALL of .?context/declared|all of .vault/00 - notes/context/declared" "$f"; then
    ok "$label routes operator-voice work to declared/"
  else
    no "$label does not name declared/ as the voice-work read" "that folder is what makes output sound like them"
  fi
  # The true reason: you cannot detect the ABSENCE of a voice from inside your own output.
  # Match short fragments -- these sentences wrap differently in prose, in the .sh preamble
  # and in the .ps1 string array, and a long phrase scores zero on text that contains it.
  if grep -qi "cannot detect" "$f" && grep -qi "not theirs" "$f"; then
    ok "$label gives the real reason (the failure that does not announce itself)"
  else
    no "$label states the split without its reason" "an unexplained rule gets collapsed back on the next edit"
  fi
  # NEGATIVE: the measured-false justification must not return.
  if grep -qiE "does not index|doesn't index|indexes beautifully|titles are a better index" "$f"; then
    no "$label revives the FALSE claim that declared/ does not index" \
       "measured, declared/ is more densely headed than observed/ -- the rule is right, that reason is not"
  else
    ok "$label does not claim declared/ is unindexable"
  fi
done
grep -qiE "not need 100k words|do NOT also preload all of observed" "$WR" \
  && ok "the wrapper warns against preloading all of observed for voice work" \
  || no "nothing stops the yes-branch collapsing into read-everything" "that shape spent 38 calls and delivered nothing"

echo
echo " the floor stays UNCONDITIONAL -- the skill may hold judgment, never the floor"
# The measured failure was workers ignoring an unenforced rule (1 of 28 loaded nothing;
# 6 loaded one or two files). A floor that lives in a skill you must remember to load
# inherits exactly that failure. So: CLAUDE.md keeps the floor, the skill keeps the ladder.
SK="skills/aios/right-context/SKILL.md"
[ -f "$SK" ] && ok "the right-context skill exists" \
             || no "no right-context skill" "the hard-case ladder has nowhere to live but CLAUDE.md, which every session pays for"

if grep -qiE "every heading in both folders|grep -h '\^#|### entry titles" "$CM"; then
  ok "CLAUDE.md still carries the floor itself"
else
  no "the floor is no longer stated in CLAUDE.md" \
     "if the floor moved into a skill, a worker that never loads the skill has no floor at all"
fi

for pair in "CLAUDE.md:$CM" "the wrapper:$WR" "the .ps1:$PS1"; do
  label="${pair%%:*}"; f="${pair#*:}"
  grep -qi "right-context" "$f" \
    && ok "$label points at the skill for the hard cases" \
    || no "$label never mentions right-context" "the escalation path exists but nothing routes to it"
done

grep -q "skills/aios/right-context" skills/_index.md 2>/dev/null || grep -q "right-context" skills/_index.md \
  && ok "the skill is registered in skills/_index.md" \
  || no "skill not registered" "an unregistered skill is not resolvable by name"

echo
echo " the narrowing stays measured"
HK="plugins/aios/commands/housekeeping.md"
if grep -q "Spawned workers that loaded no operator context" "$HK"; then
  ok "housekeeping reports workers that loaded nothing"
else
  no "nothing measures whether the floor is firing" \
     "a narrowing justified by a measurement must keep being measured, or the justification expires silently"
fi
grep -qiE 'Primary sessions are the CONTROL' "$HK" \
  && ok "and that check carries its own control" \
  || no "the bucket has no control" "a scan that cannot see a primary's reads cannot be trusted about a worker's"

printf '\n%d passed · %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
