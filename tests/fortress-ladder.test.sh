#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The containment ladder, and the probes that decide which rung you are on
#
# WHY A SUITE FOR A DOC AND A COMMAND
# /aios:fortress emits a SAFETY CLAIM. A probe that silently fails and is read
# as a clean pass tells an operator they are contained when they are not — the
# worst available failure here, and worse than printing nothing. Three of the
# probes below were wrong on their first live run and every one of them failed
# in the direction of a false pass:
#
#   1. `ls ~/.config/aios-secrets/*.env` — zsh ABORTS the command on an unmatched
#      glob before ls runs, so redirecting ls's stderr does nothing. It died on
#      exactly the machine it exists to describe: the one with no secrets yet.
#   2. An unguarded call to hooks/openrouter.py printed a Python traceback on a
#      vault that had not pulled the hook — reads as a broken machine rather than
#      a missing update, which sends the operator to the wrong fix.
#   3. `git worktree list` always prints the main tree, so the raw count of 1
#      would have read as "a worktree exists" and satisfied rung 3 for everyone.
#
# This suite also pins the doc contract, because the ladder's value is that it
# tells most operators to STOP before spending money — an easy sentence to lose
# in a later edit of a document whose subject is a $600 build.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
CMD=plugins/aios/commands/fortress.md
DOC=FORTRESS.md
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

echo "── the ladder exists and resolves the reference that points at it ──"
grep -qi 'containment ladder' "$DOC" && ok "FORTRESS.md defines the containment ladder" \
  || no "FORTRESS.md has no ladder" "MODEL-ROUTING.md links to it — the reference would dangle"
for r in 'Rung 0' 'Rung 1' 'Rung 2' 'Rung 3' 'Rung 4'; do
  grep -qF "$r" "$DOC" && ok "$DOC names $r" || no "$DOC is missing $r"
done
grep -qiE 'most of the real risk reduction is rungs 1 and 2' "$DOC" \
  && ok "the doc says the cheap rungs carry most of the value" \
  || no "the doc lost the point that rungs 1-2 matter most" "without it this is a brochure for a \$600 build"
grep -qiE 'rung 4 is not a goal|ladder ends at 3|never present rung 4 as the finish line' "$CMD" \
  && ok "the command refuses to push everyone to rung 4" \
  || no "nothing stops the command from selling hardware to a single-laptop operator"

echo "── REGRESSION: the zsh unmatched-glob probe ──"
# Scoped to lines that would EXECUTE — a whole-file grep fires on the comment
# that documents the bug, which is the sixth time that shape has bitten in this
# repo. Strip comment lines first, then look.
if sed 's/#.*//' "$CMD" | grep -qF "ls ~/.config/aios-secrets/"; then
  no "the zsh-fatal glob probe is back in executable text" "zsh aborts before ls runs; 2>/dev/null cannot help"
else
  ok "no bare glob into ls for the secrets dir (comments excluded)"
fi
# Control: the scoping must not have made the check unable to see anything.
printf 'x\nls ~/.config/aios-secrets/*.env\n' > "$T/planted.md"
if sed 's/#.*//' "$T/planted.md" | grep -qF "ls ~/.config/aios-secrets/"; then
  ok "control: the check DOES fire when the bad probe is genuinely present"
else
  no "CONTROL FAILED — the check cannot see the defect it looks for" "the assertion above is vacuous"
fi
grep -qF "find ~/.config/aios-secrets" "$CMD" && ok "uses find (pattern is an argument, not a glob)" \
  || no "the secrets probe no longer uses find"
# Prove the claim rather than asserting it: run BOTH forms under zsh against a
# directory that does not exist, and require the old one to fail.
if command -v zsh >/dev/null 2>&1; then
  if zsh -c "ls $T/nope/*.env" >/dev/null 2>&1; then
    no "CONTROL FAILED — the old glob form did NOT fail under this zsh" "the regression above proves nothing here"
  else ok "control: the old glob form genuinely fails under zsh"; fi
  zsh -c "find $T/nope -name '*.env' -maxdepth 1 2>/dev/null | wc -l" >/dev/null 2>&1 \
    && ok "the find form survives a missing directory under zsh" || no "the find form failed under zsh"
else
  ok "zsh unavailable — control skipped (not counted as a pass of the probe itself)"
fi

echo "── REGRESSION: the rail probe is guarded ──"
grep -qF 'test -f ~/aios/hooks/openrouter.py' "$CMD" \
  && ok "the rail probe file-tests before invoking python" \
  || no "an absent hook would print a traceback" "reads as a broken machine, not a missing update"
grep -qF 'rail:not-installed' "$CMD" && ok "not-installed is a distinct answer from inert" \
  || no "'not installed' and 'inert' are conflated" "they imply different next steps"

echo "── REGRESSION: the worktree off-by-one ──"
grep -qE 'worktree list.*wc -l\) - 1|- 1 \)\)' "$CMD" \
  && ok "the worktree count subtracts the main tree" \
  || no "raw worktree count used" "always >=1, so rung 3 would read as satisfied for everyone"

echo "── the command must not claim what it could not measure ──"
grep -qiE 'exclude it from the rung verdict|cannot run, say so' "$CMD" \
  && ok "unreadable probes are excluded from the verdict" \
  || no "nothing tells the command to exclude unmeasurable probes"
grep -qiE 'not-readable, never \*no firewall\*|never \*no firewall\*' "$CMD" \
  && ok "pfctl-without-sudo is called out as not-readable" \
  || no "an unreadable firewall probe could read as 'no firewall'"
grep -qiE 'weakest link' "$CMD" && ok "the rung is the weakest link, not the priciest component" \
  || no "nothing prevents a mini-owner with keys in .zshrc reading as rung 4"

echo "── hands-off boundaries ──"
for s in '~/.ssh/' 'keychain' 'showing the diff'; do
  grep -qF "$s" "$CMD" && ok "boundary stated: $s" || no "the command never protects: $s"
done

echo "── it is discoverable ──"
grep -qF '`fortress`' CLAUDE.md && ok "listed in CLAUDE.md's command index" || no "not in the command list"

echo
echo "── $PASS passed, $FAIL failed ──"
[ "$FAIL" -eq 0 ]
