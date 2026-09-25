#!/usr/bin/env bash
# tests/close-day-derivation-and-sources.test.sh
#
# Four places where /close-day read less than it meant to, or decided by the wrong clock:
#   1. The ecosystem.md redraw waited for `updated:` to pass 21 days — but every atomic append
#      resets `updated:`, so a map receiving a note every few weeks was never redrawn.
#   2. Tier A runs first and excises the Reinforced entries it routes; Tier B's growth.md
#      feed-in then read "Reinforced entries in session-insights.md" — already gone.
#   3. Session reports were looked up by "today's date" while closing yesterday after midnight.
#   4. The first project snapshot read `limit:40` per note and stamped the snapshot current.
#
# Each property is checked, then proven able to fail by a mutated copy that must break exactly it.
#
# Run:  bash tests/close-day-derivation-and-sources.test.sh
#       COMMAND_FILE=<path> bash tests/close-day-derivation-and-sources.test.sh   (audit another copy)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="${COMMAND_FILE:-$ROOT/plugins/aios/commands/close-day.md}"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/cdds.XXXXXX"); trap 'rm -rf "$TMP"' EXIT

printf '/close-day — the redraw clock, the Tier B feed-in, the report date, the snapshot read\n'

p_redraw_scope(){ grep -q '\*\*`ecosystem.md`\*\* gets a \*\*full-map re-derivation\*\*' "$1" && grep -q "this clock is \`ecosystem.md\`'s alone" "$1"; }
p_redraw_clock(){ grep -q 'whenever its own \*\*`rederived:`\*\* frontmatter date is older than the aggregate threshold `hooks/observed-staleness.py` applies (`AGGREGATE_DAYS`), or absent' "$1" && grep -q '— \*\*not\*\* `updated:`. Every atomic append in step 3 sets `updated:` to today' "$1"; }
p_redraw_sets_both(){ grep -q 'After a redraw, set \*\*both\*\* `rederived:` and `updated:` to today' "$1"; }
p_old_trigger_gone(){ ! grep -q 'whenever the staleness alarm (below) marks it past its aggregate threshold' "$1"; }
p_tierb_reads_routed(){ grep -q "both those still in \`session-insights.md\` and those the Tier A pass above routed out of it today" "$1"; }
p_tierb_reads_markers(){ grep -q 'read those where they landed, via today.s markers in the buffer beginning `<!-- ROUTED {date} (Tier A)` — follow each marker.s `\[\[target\]\]` link' "$1"; }
p_dev_report_date(){ grep -q "session-report-{YYYY-MM-DD}-\*.md\` (\*\*the date being closed\*\*" "$1"; }
p_agent_report_date(){ grep -q '`{YYYY-MM-DD}` is \*\*the date being closed\*\*, not the clock.s date' "$1"; }
p_no_todays_date(){ ! grep -q "session-report-{YYYY-MM-DD}-\*.md\` (today's date" "$1"; }
p_snapshot_sections(){ grep -q 'read each section \*\*in full\*\* from its offset to the next `## ` heading' "$1"; }
p_no_limit40(){ ! grep -q 'use `limit:40` per note' "$1"; }
PROPS="redraw_scope redraw_clock redraw_sets_both old_trigger_gone tierb_reads_routed tierb_reads_markers dev_report_date agent_report_date no_todays_date snapshot_sections no_limit40"
failing(){ local out="" n; for n in $PROPS; do "p_$n" "$1" || out="$out $n"; done; printf '%s' "${out# }"; }
for n in $PROPS; do "p_$n" "$SPEC" && ok "$n" || no "$n"; done

mut(){ # $1 label  $2 perl substitution  $3 the one property that must now fail
  cp "$SPEC" "$TMP/m.md"; perl -0pi -e "$2" "$TMP/m.md"
  if cmp -s "$SPEC" "$TMP/m.md"; then no "control '$1': mutation did not apply (anchor moved)"; return; fi
  got=$(failing "$TMP/m.md"); [ "$got" = "$3" ] && ok "control '$1': breaks exactly $3" || no "control '$1': expected only [$3], got [$got]"
}
mut "redraw keyed on updated again"  's/whenever its own \*\*`rederived:`\*\* frontmatter date/whenever its **`updated:`** frontmatter date/'         redraw_clock
mut "redraw stamps only updated"     's/After a redraw, set \*\*both\*\* `rederived:` and `updated:` to today/After a redraw, set `updated:` to today/' redraw_sets_both
mut "Tier B reads the buffer only"   's/both those still in `session-insights\.md` and those the Tier A pass above routed out of it today/in `session-insights.md`/' tierb_reads_routed
mut "marker lookup removed"          's/: that pass runs first and excises what it routes, so read those where they landed, via today.s markers in the buffer beginning `<!-- ROUTED \{date\} \(Tier A\)` — follow each marker.s `\[\[target\]\]` link to read the entry where it landed —//' tierb_reads_markers
mut "clock widened to any aggregate" 's/\*\*`ecosystem\.md`\*\* gets a \*\*full-map re-derivation\*\*/an aggregate file gets a **full-map re-derivation**/' redraw_scope
mut "agent reports by clock date"    's/`\{YYYY-MM-DD\}` is \*\*the date being closed\*\*, not the clock.s date/`{YYYY-MM-DD}` is the current date/' agent_report_date
mut "snapshot by line budget"        's/read each section \*\*in full\*\* from its offset to the next `## ` heading/read the first lines of each section/' snapshot_sections

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
