#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The containment ladder, its probes, and the agent-bus section
#
# WHY A SUITE FOR A DOCUMENT
# FORTRESS.md now emits a SAFETY CLAIM: a reader (or a session running its probe
# block) concludes which containment rung they are on. A probe that silently
# fails and reads as a clean pass tells an operator they are contained when they
# are not — the worst available failure, and worse than printing nothing.
#
# FIVE PROBES WERE WRONG ON A LIVE MACHINE, ALL TOWARD A FALSE READING:
#   1. `command -v tailscale` misses a GUI install — reported ABSENT on a machine
#      that reaches its fortress over Tailscale daily; the binary lives inside
#      /Applications/Tailscale.app and is never on PATH.
#   2. `ls ~/.config/aios-secrets/*.env` is FATAL under zsh: an unmatched glob
#      aborts the command before ls runs, so 2>/dev/null cannot help. It died on
#      exactly the machine it exists to describe.
#   3. An unguarded call to hooks/openrouter.py printed a traceback on a vault
#      that had not pulled it — reads as a broken machine, not a missing update.
#   4. `git worktree list` always prints the main tree, so a raw count of 1 marks
#      rung 3 satisfied for everybody.
#   5. `pfctl` without sudo prints nothing and exits non-zero — not-readable,
#      never "no firewall".
#
# It also pins two things the roadmap asked for and that are easy to lose in a
# later edit: the cheap always-on rung between "one laptop" and "two Macs", and
# the agent-bus section — the doc described the walls and not the one door that
# actually works across machines.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
DOC=FORTRESS.md
HK=plugins/aios/commands/housekeeping.md
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

echo "── the ladder exists and resolves the reference pointing at it ──"
grep -qi 'containment ladder' "$DOC" && ok "FORTRESS.md defines the containment ladder" \
  || no "no ladder in FORTRESS.md" "MODEL-ROUTING.md links to it — the reference would dangle"
grep -qF 'containment ladder' MODEL-ROUTING.md && ok "MODEL-ROUTING.md still points here" || no "the inbound reference vanished"
for r in 'Rung 0' 'Rung 1' 'Rung 2' 'Rung 3' 'Rung 4' 'Rung 5'; do
  grep -qF "$r" "$DOC" && ok "$DOC names $r" || no "$DOC is missing $r"
done
grep -qiE 'cheap always-on box' "$DOC" && ok "the cheap always-on rung exists between laptop and two-Macs" \
  || no "no cheap rung" "the ladder jumps from free straight to ~\$600, which is the gap it exists to close"
grep -qiE 'most of the real risk reduction is rungs 1 and 2' "$DOC" \
  && ok "states the cheap rungs carry most of the value" || no "lost the point that rungs 1-2 matter most"
grep -qiE 'rung 5 is not a goal|ladder ends at 3|not as contained as rung 5' "$DOC" \
  && ok "does not present the top rung as the finish line" || no "reads as a brochure for the \$600 build"
grep -qiE 'weakest link' "$DOC" && ok "rung = weakest link, not priciest component" \
  || no "a fortress owner with keys in a shell rc could read as rung 5"

echo "── the probes live in ONE place and are the fixed versions ──"
grep -qiE 'Which rung am I on' "$DOC" && ok "probe block is in FORTRESS.md" || no "no probe block in the doc"
# REGRESSION 1 — the tailscale GUI install
grep -qF '/Applications/Tailscale.app' "$DOC" && ok "tailscale probe checks the app bundle too" \
  || no "tailscale probe only checks PATH" "reports absent on a machine that uses it daily"
# REGRESSION 2 — the zsh-fatal glob, scoped to executable text (a whole-file grep
# fires on the reading-note that documents it; that shape has bitten 7x here).
if sed 's/^ *- \*\*.*//' "$DOC" | grep -qE '^\s*ls ~/\.config/aios-secrets/\*'; then
  no "the zsh-fatal glob is back in the probe block" "zsh aborts before ls runs"
else ok "no bare glob into ls in the probe block"; fi
printf 'ls ~/.config/aios-secrets/*.env\n' > "$T/planted"
grep -qE '^\s*ls ~/\.config/aios-secrets/\*' "$T/planted" \
  && ok "control: that check DOES fire on a planted bad probe" || no "CONTROL FAILED — check is vacuous"
grep -qF "find ~/.config/aios-secrets" "$DOC" && ok "uses find instead" || no "the find form is missing"
# REGRESSIONS 3-5
grep -qF 'test -f ~/aios/hooks/openrouter.py' "$DOC" && ok "rail probe is file-guarded" || no "unguarded rail probe"
grep -qE 'worktree list.*wc -l\) - 1' "$DOC" && ok "worktree count subtracts the main tree" || no "raw worktree count"
# Markdown emphasis sits between the words ("**not-readable**, never *no
# firewall*"), so match with the inline markers allowed rather than assuming
# plain prose — the pattern must survive the doc being formatted.
grep -qiE 'not-readable[*_ ]*,? *never' "$DOC" \
  && ok "pfctl-without-sudo is called not-readable, not 'no firewall'" \
  || no "unreadable firewall could read as absent"
grep -qiE 'exclude it from the verdict' "$DOC" && ok "unrunnable probes are excluded from the verdict" \
  || no "nothing says to exclude a probe that could not run"

echo "── the agent bus: the door, not just the walls ──"
n=$(grep -c -iE 'spawn-inbox|agent bus|pull-based' "$DOC")
[ "$n" -ge 3 ] && ok "the bus is documented ($n references)" \
  || no "FORTRESS.md still describes only the walls" "the bus is how work actually crosses machines"
grep -qiE 'zero inbound surface' "$DOC" && ok "the zero-inbound design invariant is stated" \
  || no "the invariant that makes the bus fortress-compatible is missing"
grep -qiE 'no cloud transit' "$DOC" && ok "says why a file bus over the native relay" \
  || no "does not answer why not the built-in cross-session messaging"
grep -qiE 'no authentication and no requester identity' "$DOC" \
  && ok "states the bus is unauthenticated" \
  || no "the missing-auth warning is gone" "a shared inbox is remote code execution"
grep -qiE 'Do not share a spawn-inbox' "$DOC" && ok "warns against sharing an inbox" || no "no warning against sharing"

echo "── the periodic check is a housekeeping bucket, not a new command ──"
grep -qF 'Bucket 28' "$HK" && ok "Bucket 28 exists" || no "no containment bucket"
grep -qiE 'do not re-derive it here' "$HK" && ok "the bucket defers to the doc for the probes" \
  || no "the bucket may re-derive the probes" "a second copy is a second implementation"
sed -n '/Bucket 28/,/^#### /p' "$HK" | grep -qiE 'READ-ONLY' \
  && ok "the bucket is read-only" || no "the bucket could edit a shell rc"
[ ! -f plugins/aios/commands/fortress.md ] && ok "no /aios:fortress command (consolidated into the doc + bucket)" \
  || no "a new command surface exists" "the ladder is documentation; the periodic check is a bucket"
truth=$(ls plugins/aios/commands/*.md 2>/dev/null | grep -v _index | wc -l | tr -d ' ')
grep -qF "**$truth commands" README.md && ok "README command count matches disk ($truth)" \
  || no "README command count disagrees with disk" "expected $truth"

echo
echo "── $PASS passed, $FAIL failed ──"
[ "$FAIL" -eq 0 ]
