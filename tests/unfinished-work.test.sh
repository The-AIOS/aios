#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# unfinished-work.sh reports a note whose `status:` says the work is still open
# when no open task links to it — and stays SILENT when one does.
#
# The silent half is the point: /close-day runs this every evening, and a check
# that fires on healthy state is a check the operator stops reading. So every
# way a note can legitimately be open (a task in a project note, a task in the
# newest daily note, an aliased link) gets a control that asserts silence.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
S=hooks/vault/unfinished-work.sh
[ -f "$S" ] || { echo "::error::$S missing"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mk(){ mkdir -p "$T/$1/00 - notes/projects" "$T/$1/00 - notes/reflections" "$T/$1/01 - calendar/2026-10"; }
note(){ printf -- '---\nstatus: %s\n---\nbody\n' "$3" > "$T/$1/00 - notes/reflections/$2.md"; }
run(){ AIOS_VAULT="$T/$1" bash "$S" 2>&1; }

echo "-- an empty vault is silent, at exit 0 --"
mk empty
out=$(run empty); rc=$?
[ "$out" = "unfinished-work: none" ] && ok "empty → the exact contracted line" || no "empty printed '$out'"
[ "$rc" = "0" ] && ok "exit 0" || no "exit $rc"

echo "-- a vault with no notes folder is not an error --"
out=$(run missing); rc=$?
[ "$rc" = "0" ] && ok "missing folder → exit 0" || no "missing folder exited $rc"
case "$out" in *none*) ok "missing folder → 'none'" ;; *) no "missing folder printed '$out'" ;; esac

echo "-- the real case: an open note with no task --"
mk orphan; note orphan "phase plan" proposal
printf -- '- [x] done earlier [[phase plan]]\n' > "$T/orphan/00 - notes/projects/p.md"
out=$(run orphan)
case "$out" in *"unfinished-work: reflections/phase plan.md"*) ok "reported, path relative to notes" ;; *) no "NOT reported: '$out'" "a CLOSED task is not an exit for the rest of the work" ;; esac

echo "-- CONTROL: a project-note task links it → silent --"
mk linked; note linked "phase plan" draft
printf -- '- [ ] finish phase 2 → [[phase plan]]\n' > "$T/linked/00 - notes/projects/p.md"
out=$(run linked)
[ "$out" = "unfinished-work: none" ] && ok "project task → silent" || no "flagged despite a task: '$out'"

echo "-- CONTROL: a task in the newest daily note with an aliased link → silent --"
mk daily; note daily "phase plan" "in progress"
printf -- '- [ ] keep going [[phase plan|the plan]]\n' > "$T/daily/01 - calendar/2026-10/2026-10-25.md"
out=$(run daily)
[ "$out" = "unfinished-work: none" ] && ok "daily-note task → silent" || no "flagged despite a daily task: '$out'"

echo "-- CONTROL: closed statuses, quoted values and no frontmatter are ignored --"
mk closed; note closed a merged; note closed b '"done"'; printf 'no frontmatter\nstatus: draft\n' > "$T/closed/00 - notes/reflections/c.md"
out=$(run closed)
[ "$out" = "unfinished-work: none" ] && ok "closed / no-frontmatter → silent" || no "flagged: '$out'" "a status: line outside frontmatter is body text"

echo "-- logs/, context/ and projects/ are out of scope --"
mk scope; mkdir -p "$T/scope/00 - notes/logs"
printf -- '---\nstatus: draft\n---\n' > "$T/scope/00 - notes/logs/snap.md"
printf -- '---\nstatus: open\n---\n' > "$T/scope/00 - notes/projects/live.md"
out=$(run scope)
[ "$out" = "unfinished-work: none" ] && ok "snapshots and project notes not scanned" || no "out-of-scope file flagged: '$out'"

echo "-- the operator's own status vocabulary --"
mk vocab; note vocab plan propuesta
out=$(AIOS_VAULT="$T/vocab" AIOS_OPEN_STATUSES='propuesta|borrador' bash "$S")
case "$out" in *"reflections/plan.md"*) ok "AIOS_OPEN_STATUSES is honoured" ;; *) no "custom status ignored: '$out'" ;; esac

echo "-- a retired note under _archived/ is history, never revived as a task --"
mk arch; mkdir -p "$T/arch/00 - notes/reflections/_archived"
printf -- '---\nstatus: proposal\n---\nold plan\n' > "$T/arch/00 - notes/reflections/_archived/old plan.md"
out=$(run arch)
[ "$out" = "unfinished-work: none" ] && ok "_archived/ is skipped" || no "a retired note was reported: '$out'" "close-day would turn it back into a task every night"

echo "-- a roadmap is its own truth surface, not a note waiting for a task --"
mk road; printf -- '---\ntype: roadmap\nstatus: in progress\n---\n- AB-1 open\n' > "$T/road/00 - notes/reflections/the roadmap.md"
out=$(run road)
[ "$out" = "unfinished-work: none" ] && ok "type: roadmap is skipped" || no "a roadmap was reported: '$out'"

echo "-- a link to plan-v2 is not a link to plan --"
mk prefix; note prefix "plan" draft
printf -- '- [ ] ship it → [[plan-v2]]\n' > "$T/prefix/00 - notes/projects/p.md"
out=$(run prefix)
case "$out" in *"reflections/plan.md"*) ok "a prefix-only link still reports the note" ;; *) no "[[plan-v2]] counted as a link to plan: '$out'" ;; esac
printf -- '- [ ] ship it → [[plan#phase 2]]\n' > "$T/prefix/00 - notes/projects/p.md"
out=$(run prefix)
[ "$out" = "unfinished-work: none" ] && ok "CONTROL: [[plan#heading]] is a link to plan" || no "a heading link was not counted: '$out'"

echo "-- a link by the note's path counts, not only by its basename --"
mk pathlink; mkdir -p "$T/pathlink/00 - notes/reflections/books/one"
printf -- '---\nstatus: draft\n---\nbody\n' > "$T/pathlink/00 - notes/reflections/books/one/_index.md"
printf -- '- [ ] next chapter [[reflections/books/one/_index|the book]]\n' > "$T/pathlink/00 - notes/projects/p.md"
out=$(run pathlink)
[ "$out" = "unfinished-work: none" ] && ok "[[reflections/books/one/_index|…]] links the note" || no "a path link was not counted: '$out'" "Obsidian writes a path when basenames collide"
printf -- '- [ ] next chapter [[00 - notes/reflections/books/one/_index#ch 2]]\n' > "$T/pathlink/00 - notes/projects/p.md"
out=$(run pathlink)
[ "$out" = "unfinished-work: none" ] && ok "a vault-root path with a heading links the note" || no "a full vault path was not counted: '$out'"
printf -- '- [ ] next chapter [[one/_index]]\n' > "$T/pathlink/00 - notes/projects/p.md"
out=$(run pathlink)
[ "$out" = "unfinished-work: none" ] && ok "a shorter trailing path links the note" || no "a partial path was not counted: '$out'"
printf -- '- [ ] next chapter [[books/two/_index]]\n' > "$T/pathlink/00 - notes/projects/p.md"
out=$(run pathlink)
case "$out" in *"reflections/books/one/_index.md"*) ok "CONTROL: a path to ANOTHER folder's _index does not count" ;; *) no "[[books/two/_index]] counted for books/one/_index: '$out'" ;; esac
printf -- '- [ ] next chapter [[ne/_index]]\n' > "$T/pathlink/00 - notes/projects/p.md"
out=$(run pathlink)
case "$out" in *"reflections/books/one/_index.md"*) ok "CONTROL: a path matches whole folder names, never a partial one" ;; *) no "[[ne/_index]] counted for one/_index: '$out'" ;; esac

echo
echo "-- $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]
