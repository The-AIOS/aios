#!/usr/bin/env bash
# tests/today-carries-and-probes.test.sh
#
# /today's two morning probes and its carry rules, where the answer did not follow the input:
#   1. The close-day precondition excluded only today's date, so a future-dated note won; a
#      missing or unreadable calendar folder read as a first run; and the guard then let
#      /close-day pick "the most recent note" — today's, once /7plan had created it.
#   2. The backup probe checked `origin` unless a push target was configured, and read a
#      missing URL as "ok".
#   3. Carry escalation had three rules for the same untagged carry; the drop check compared
#      counts; the last-note search looked two months back.
#   4. A task written in several places was carried from its open copies after one copy was
#      marked done, re-opening finished work each morning; the drop check would have re-added it.
#
# Both probes are EXTRACTED from today.md and run against temp vaults, under bash and under zsh
# (the session shell). The carry rules are checked as properties, and each property is proven
# able to fail by a mutated copy that must break exactly it.
#
# Run:  bash tests/today-carries-and-probes.test.sh
#       COMMANDS_DIR=<dir> bash tests/today-carries-and-probes.test.sh   (audit another copy)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CMDS="${COMMANDS_DIR:-$ROOT/plugins/aios/commands}"
SPEC="$CMDS/today.md"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
have(){ [ "$1" = "$2" ] && ok "$3" || no "$3" "got [$1], wanted [$2]"; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/today.XXXXXX"); trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

printf '/today — the precondition and backup probes, and the carry rules\n'

# fixed-string match on each probe's opening words (-e: the pattern starts with "-")
probe(){ grep -m1 -F -e "$1" "$SPEC" | sed -E 's/^- `Bash\(//; s/\)` — \*\*.*$//'; }
PRE=$(probe '- `Bash(cal=~/aios/vault/01\ -\ calendar;')
BAK=$(probe '- `Bash(g(){ git -C "$HOME/aios" "$@"; };')
[ -n "$PRE" ] && ok "1-. precondition probe extracted" || no "1-. could not extract the precondition probe"
[ -n "$BAK" ] && ok "2-. backup probe extracted" || no "2-. could not extract the backup probe"

SHELLS="bash"; command -v zsh >/dev/null 2>&1 && SHELLS="bash zsh"
today=$(date +%Y-%m-%d); y=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d yesterday +%Y-%m-%d)
future=$(date -v+5d +%Y-%m-%d 2>/dev/null || date -d '+5 days' +%Y-%m-%d)
m(){ printf '%s' "${1%-*}"; }

# ---------------------------------------------------------------------------------------------
# 1. precondition
# ---------------------------------------------------------------------------------------------
H="$TMP/h1"; C="$H/aios/vault/01 - calendar"
mkdir -p "$C/$(m "$y")" "$C/$(m "$today")" "$C/$(m "$future")"
printf '# y\n' > "$C/$(m "$y")/$y.md"                 # yesterday, NOT closed
printf '# t\n' > "$C/$(m "$today")/$today.md"         # today, pre-created by /7plan
printf '# f\n' > "$C/$(m "$future")/$future.md"       # a future plan
for sh in $SHELLS; do
  have "$(HOME="$H" $sh -c "$PRE" 2>&1)" "close-day-precondition: MISSING ($y) — must run /close-day first" "1a[$sh]. yesterday unclosed, today and a future note present → MISSING for yesterday"
done
printf '## Close of Day\n' >> "$C/$(m "$y")/$y.md"
have "$(HOME="$H" bash -c "$PRE" 2>&1)" "close-day-precondition: closed ($y)" "1b. …closed once yesterday has its heading (the future note never wins)"
case "$(HOME="$TMP/nowhere" bash -c "$PRE" 2>&1)" in "close-day-precondition: no-calendar-folder"*) ok "1c. a missing calendar folder says so";; *) no "1c. missing folder misread";; esac
if [ "$(id -u)" != 0 ]; then
  H="$TMP/h1u"; C="$H/aios/vault/01 - calendar"; mkdir -p "$C/$(m "$y")"; printf '# y\n' > "$C/$(m "$y")/$y.md"; chmod 000 "$C/$(m "$y")"
  out=$(HOME="$H" bash -c "$PRE" 2>/dev/null)
  case "$out" in "close-day-precondition: calendar-unreadable"*) ok "1d. an unreadable month folder says so, never 'no-prior-note'";; *) no "1d. unreadable folder misread" "$out";; esac
  chmod 755 "$C/$(m "$y")"
else
  ok "1d. running as root — permissions cannot be denied, unreadable case skipped"
fi
grep -q 'with the date the guard detected' "$SPEC" && ok "1e. /today hands /close-day the detected date" || no "1e. /today still lets /close-day pick 'the most recent note'"
grep -q 'if invoked with a date' "$CMDS/close-day.md" && ok "1f. /close-day closes exactly the date it is given" || no "1f. /close-day ignores a given date"

# ---------------------------------------------------------------------------------------------
# 2. backup — resolved the way `git push` resolves it
# ---------------------------------------------------------------------------------------------
mkrepo(){ rm -rf "$1"; mkdir -p "$1/aios"; git -C "$1/aios" init -q; git -C "$1/aios" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i; }
br(){ git -C "$1/aios" symbolic-ref --short HEAD; }
FW=https://github.com/The-AIOS/aios.git; PRIV=https://example.invalid/me/vault.git
for sh in $SHELLS; do
  H="$TMP/b1"; mkrepo "$H"; git -C "$H/aios" remote add private "$PRIV"
  have "$(HOME="$H" $sh -c "$BAK" 2>&1)" "backup: ok" "2a[$sh]. a lone private remote not named origin → ok (git pushes to it)"
  H="$TMP/b2"; mkrepo "$H"; git -C "$H/aios" remote add mirror "$FW"
  have "$(HOME="$H" $sh -c "$BAK" 2>&1)" "backup: framework-origin (mirror)" "2b[$sh]. a lone remote that IS the framework → framework-origin, naming it"
  H="$TMP/b3"; mkrepo "$H"; git -C "$H/aios" remote add a "$PRIV"; git -C "$H/aios" remote add b "$PRIV"
  have "$(HOME="$H" $sh -c "$BAK" 2>&1)" "backup: none (push remote 'origin' has no URL)" "2c[$sh]. several remotes, none for push, none named origin → none (was: ok)"
  git -C "$H/aios" config "branch.$(br "$H").pushRemote" a
  have "$(HOME="$H" $sh -c "$BAK" 2>&1)" "backup: ok" "2d[$sh]. …ok once a push remote is configured"
  H="$TMP/b4"; mkrepo "$H"; git -C "$H/aios" remote add origin "$PRIV"; git -C "$H/aios" remote add up "$FW"; git -C "$H/aios" config "branch.$(br "$H").pushRemote" up
  have "$(HOME="$H" $sh -c "$BAK" 2>&1)" "backup: framework-origin (up)" "2e[$sh]. pushing to the framework through a remote not named origin → names that remote"
  H="$TMP/b6"; mkrepo "$H"; git -C "$H/aios" remote add origin "$PRIV"; git -C "$H/aios" remote set-url --add --push origin "$PRIV"; git -C "$H/aios" remote set-url --add --push origin "$FW"
  have "$(HOME="$H" $sh -c "$BAK" 2>&1)" "backup: framework-origin (origin)" "2h[$sh]. a second push URL that is the framework → framework-origin (git pushes to both)"
  H="$TMP/b5"; mkdir -p "$H/aios"; git -C "$H/aios" init -q
  have "$(HOME="$H" $sh -c "$BAK" 2>&1)" "backup: none" "2f[$sh]. no remote at all → none"
done
grep -q 'remote remove {remote}' "$SPEC" && ok "2g. the offered fix removes the remote the probe named, not origin" || no "2g. the offered fix still removes 'origin'"

# ---------------------------------------------------------------------------------------------
# 3. carry rules — properties, each proven able to fail
# ---------------------------------------------------------------------------------------------
p_all_months(){ grep -q 'across \*\*every\*\* month folder under `01 - calendar/`' "$1"; }
p_no_two_months(){ ! grep -q 'If no daily note exists in the current month, check the previous month' "$1"; }
p_per_item(){ grep -q "For each unique unchecked \`- \[ \]\` item of the previous note (same dedup key as the extraction), confirm it is placed in today's note" "$1"; }
p_no_count(){ ! grep -q 'previous_unique > today_placed' "$1"; }
p_parked_exit(){ grep -q '\*\*parked\*\* (matched `## Explicitly NOT doing` — removed by design)' "$1"; }
p_hidden_verified(){ grep -q "\*\*compass-hidden\*\* (target > 14 days — confirm it is in its project note's to-dos; if it is not, it is not hidden, it is lost" "$1"; }
p_table_applies(){ grep -q 'the count-based table above applies. That table exists for exactly these carries: untagged, no target, no window' "$1"; }
p_no_exempt(){ ! grep -q 'apply to explicit-target items only, not raw age' "$1"; }
p_done_twin(){ grep -q '\*\*Then drop any open line whose done twin is in the same note:\*\* if a line with the same core identity (same dedup key) is `\[x\]` or `~~struck~~` anywhere in that note' "$1"; }
p_done_exit(){ grep -q '\*\*done elsewhere\*\* (a `\[x\]` or struck twin with the same identity in the previous note' "$1"; }
p_twin_partial(){ grep -q 'an `\[x\]` that notes what is still open is partial work and does not count' "$1"; }
p_twin_multipart(){ grep -q 'for a multi-part task only a struck title counts, never struck sub-items alone' "$1"; }
p_twin_recurring(){ grep -q 'a recurring task (daily, per meeting, per time slot) is closed only for the instance that was marked' "$1"; }
p_twin_reopen(){ grep -q 'an open line written after the done one as an explicit reopening stays open' "$1"; }
p_exit_limits(){ grep -q 'that closes the whole task, under the same limits as the extraction above — re-check them here; a twin that fails them is not an exit' "$1"; }
p_twin_uncertain(){ grep -q 'When the match is uncertain (similar wording, a different deliverable, a different instance), carry it and say so rather than drop it' "$1"; }
PROPS="all_months no_two_months per_item no_count parked_exit hidden_verified table_applies no_exempt done_twin done_exit twin_partial twin_multipart twin_recurring twin_reopen twin_uncertain exit_limits"
failing(){ local out="" n; for n in $PROPS; do "p_$n" "$1" || out="$out $n"; done; printf '%s' "${out# }"; }
for n in $PROPS; do "p_$n" "$SPEC" && ok "3. $n" || no "3. $n"; done
mut(){ # $1 label  $2 perl substitution  $3 the one property that must now fail
  cp "$SPEC" "$TMP/m.md"; perl -0pi -e "$2" "$TMP/m.md"
  if cmp -s "$SPEC" "$TMP/m.md"; then no "control '$1': mutation did not apply (anchor moved)"; return; fi
  got=$(failing "$TMP/m.md"); [ "$got" = "$3" ] && ok "control '$1': breaks exactly $3" || no "control '$1': expected only [$3], got [$got]"
}
mut "all-months search removed"   's/take the latest `YYYY-MM-DD\.md` dated before today across \*\*every\*\* month folder under `01 - calendar\/`/take the latest daily note/' all_months
mut "per-item sentence removed"   's/For each unique unchecked `- \[ \]` item of the previous note \(same dedup key as the extraction\), confirm it is placed in today.s note, or that it left on purpose: //' per_item
mut "parked exit removed"         's/\*\*parked\*\* \(matched `## Explicitly NOT doing` — removed by design\) or //' parked_exit
mut "hidden verification removed" 's/ — confirm it is in its project note.s to-dos; if it is not, it is not hidden, it is lost: put it there or in Parking//' hidden_verified
mut "done-twin rule removed"      's/\*\*Then drop any open line whose done twin is in the same note:\*\*[^*]*?does not carry\. //' done_twin
mut "done-elsewhere exit removed" 's/or \*\*done elsewhere\*\* \([^)]*\) //' "done_exit exit_limits"
mut "partial-[x] limit removed"   's/an `\[x\]` that notes what is still open is partial work and does not count; //' twin_partial
mut "multi-part limit removed"    's/for a multi-part task only a struck title counts, never struck sub-items alone; //' twin_multipart
mut "recurring limit removed"     's/a recurring task \(daily, per meeting, per time slot\) is closed only for the instance that was marked; //' twin_recurring
mut "reopen limit removed"        's/; and an open line written after the done one as an explicit reopening stays open//' twin_reopen
mut "exit limits removed"         's/ that closes the whole task, under the same limits as the extraction above — re-check them here; a twin that fails them is not an exit//' exit_limits
mut "uncertain guard removed"     's/When the match is uncertain \([^)]*\), carry it and say so rather than drop it\. //' twin_uncertain
mut "table sentence removed"      's/ — and the count-based table above applies\. That table exists for exactly these carries: untagged, no target, no window\.//' table_applies

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
