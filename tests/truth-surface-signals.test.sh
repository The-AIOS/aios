#!/usr/bin/env bash
# tests/truth-surface-signals.test.sh
#
# Three checks in the framework decide what to trust by reading a signal. This suite
# asserts they read the RIGHT one, because all three failure modes are silent: none
# errors, none logs, each returns a confident wrong answer that looks like a pass.
#
# PART A — a keyed item's truth surface is found by grepping for `type: roadmap` +
# `status: live`. hooks/aios-snapshot archives with `cp -p`, so every archived copy of
# a roadmap carries that frontmatter and answers the probe exactly like the real file.
# An unscoped probe returns the archives too, and an archive is always the staler
# answer. Measured on a live vault: one key resolved to 19 files, 18 of them snapshots,
# and all 18 disagreed with the roadmap. Every site that probes must exclude logs/.
#
# WHY A TEST AND NOT A SENTENCE. The rule is one line in CLAUDE.md; the probe is
# written out at four separate sites, and a fifth is one command away. Writing this
# suite found the fourth site (close-day's existence gate) that the spec that
# commissioned it had missed — which is the whole argument for the mechanism.
#
# PART C — the observed-context staleness alarm applies a clock to every file in
# observed/, assuming they accumulate. A RESTATED file (a spec rewritten in place)
# does not, so the clock alarms precisely when that file is correct. Files declare
# `restated: true`; every alarm site must honour it, and a restated file must still
# have a write trigger, or the flag is just a mute button.
#
# Run:  bash tests/truth-surface-signals.test.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

cd "$REPO" || exit 1

# ── Part A ───────────────────────────────────────────────────────────────────────────
# Sites are DERIVED, never listed: any instruction surface naming `type: roadmap` is a
# site. Enumerating them is the mistake this suite exists to catch — a list cannot know
# about the site added next week.
#
# Templates and CHANGELOG are excluded for a stated reason, not by omission: a template
# DECLARES that frontmatter in its own header (it is the thing being found, not a search
# for it), and CHANGELOG is history, which must never be rewritten to satisfy a guard.
SITES="$(grep -rl 'type: roadmap' --include='*.md' CLAUDE.md plugins/aios/commands 2>/dev/null | sort)"

if [ -n "$SITES" ]; then ok "found $(printf '%s\n' "$SITES" | grep -c .) instruction surface(s) naming type: roadmap"
else no "no instruction surface mentions type: roadmap" "the derivation is broken; every verdict below is vacuous"; fi

# A site is scoped when at least ONE line CO-LOCATES `type: roadmap` with the logs
# exclusion. Co-location is the whole assertion, and it is chosen over two alternatives
# that were both tried and rejected against real mutations:
#
#   · A file-level `grep -q logs/` is VACUOUS. These files mention `00/logs/` for
#     unrelated reasons (the File Placement Router, snapshot destinations), so a file
#     passes with the exclusion stripped straight out of its probe — measured: reverting
#     today.md's exclusion still reported 6 passed, 0 failed.
#   · Requiring EVERY `type: roadmap` line to be scoped is too strict and fails clean.
#     Not every mention is a probe: commands also REFERENCE the check made earlier
#     ("when the vault has no live `type: roadmap` files"), and no verb heuristic
#     separated the two cleanly when measured across all five sites.
#
# Co-location is the honest middle: it cannot be satisfied by an incidental mention
# elsewhere in the file, and it does not demand scoping language on a back-reference.
scoped() { grep -qE 'type: roadmap' "$1" && grep -E 'type: roadmap' "$1" | grep -q 'logs'; }

UNSCOPED=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  scoped "$f" || UNSCOPED="$UNSCOPED $f"
done <<EOF
$SITES
EOF

if [ -z "$UNSCOPED" ]; then
  ok "every roadmap-resolution site excludes logs/"
else
  no "roadmap probe not scoped away from logs/ in:$UNSCOPED" \
     "a snapshot carries type: roadmap + status: live, so this probe returns archives beside the real file and the archive is always staler"
fi

# Control: prove the scoped() predicate can answer NO. Without this the loop above
# passes against any tree, which is the failure mode of a guard nobody mutated.
CTRL="$(mktemp "${TMPDIR:-/tmp}/aios-sig.XXXXXX")"
printf 'Grep for `type: roadmap` across `00 - notes/`.\n' > "$CTRL"
scoped "$CTRL" && no "control: an unscoped probe was reported as scoped" "this suite cannot fail" \
                || ok "control: an unscoped probe is detected as unscoped"
rm -f "$CTRL"

# ── Part C ───────────────────────────────────────────────────────────────────────────
# Every site that applies the staleness clock must honour the restated flag. Derived the
# same way: any command naming the alarm's own threshold is a site.
ALARM="$(grep -rl 'aggregate Tier B' --include='*.md' plugins/aios/commands 2>/dev/null | sort)"

if [ -n "$ALARM" ]; then ok "found $(printf '%s\n' "$ALARM" | grep -c .) staleness-alarm surface(s)"
else no "no command carries the staleness alarm" "the derivation is broken"; fi

UNHONOURED=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -q 'restated' "$f" || UNHONOURED="$UNHONOURED $f"
done <<EOF
$ALARM
EOF

if [ -z "$UNHONOURED" ]; then
  ok "every staleness-alarm site honours restated: true"
else
  no "staleness alarm ignores restated: true in:$UNHONOURED" \
     "a restated file is a spec rewritten in place — unchanged means correct, so a clock on it alarms on success, every month, forever"
fi

# The flag is only half. A file exempted from the clock with no write trigger has no
# exit condition at all — that is muting an alarm, not fixing one. Assert every observed
# file canonical ships has a row in CLAUDE.md § III's trigger table.
#
# This is also the general form of the defect that started this: the table had a row for
# eight of nine observed files, and the ninth was the restated one. Run against the tree
# before that fix, this assertion fails by name.
MISSING=""
for f in "vault/00 - notes/context/observed/"*.md; do
  b="$(basename "$f")"
  [ "$b" = "_index.md" ] && continue
  grep -q "| \`$b\`" CLAUDE.md || MISSING="$MISSING $b"
done

if [ -z "$MISSING" ]; then
  ok "every shipped observed file has a trigger row in CLAUDE.md § III"
else
  no "no trigger row for:$MISSING" \
     "a file with no write trigger has no defined condition under which a session should touch it"
fi

printf '\n-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
