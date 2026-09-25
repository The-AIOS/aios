#!/usr/bin/env bash
# tests/close-session-order-and-fields.test.sh
#
# Three instructions in /close-session contradicted each other:
#   1. Step 9's checklist demanded direct observed-context writes with no `--auto` exception,
#      while § Non-interactive mode forbids exactly those writes under `--auto`.
#   2. Step 5 appends AND commits the block; steps 8 and 9 then asked questions whose answers
#      belong in that block. The helper only appends — it cannot amend.
#   3. The block format said "Skip" for empty fields; § Rules said "Don't skip sections".
#
# Each check is a function of the file it reads, so the same checks run against mutated copies
# at the end — proving they fail when the property they name is broken.
#
# Run:  bash tests/close-session-order-and-fields.test.sh
#       COMMAND_FILE=<path> bash tests/close-session-order-and-fields.test.sh   (audit another copy)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="${COMMAND_FILE:-$ROOT/plugins/aios/commands/close-session.md}"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/csof.XXXXXX"); trap 'rm -rf "$TMP"' EXIT

# --- sections ---------------------------------------------------------------------------------
step(){ awk -v s="$2" -v e="$3" 'index($0,s)==1{f=1} f&&index($0,e)==1&&!index($0,s){exit} f' "$1"; }
step8(){ step "$1" '8. **Comprehension ledger' '9. **Self-update verification**'; }
step9(){ step "$1" '9. **Self-update verification**' '10. **Commit any observed-context'; }
blockA(){ awk '/^### Session block format \(Mode A\)/{f=1} f&&/^### "File answers back" check/{exit} f' "$1"; }
reportB(){ awk '/^### Session report format \(Mode B\)/{f=1} f&&/^### Mode B rules/{exit} f' "$1"; }
line_of(){ grep -n -m1 -F "$2" "$1" | cut -d: -f1; }

# --- the properties, each returning 0 when it holds ------------------------------------------
p_auto_exception(){ step9 "$1" | grep -q '`session-insights.md`, the other observed files, and `antifragile.md` — is satisfied by the candidates'; }
p_routing_scoped(){ step9 "$1" | grep -q 'Logging is not routing\*\* (interactive closes; under `--auto` the captured candidates \*are\* the routing'; }
p_ask_before_append(){ local a b; a=$(line_of "$1" '4.7. **Ask before you write**'); b=$(line_of "$1" '5. **Append the session block via the race-safe helper'); [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; }
ask47(){ step "$1" '4.7. **Ask before you write**' '5. **Append the session block'; }
p_ask_holds_offer(){ ask47 "$1" | grep -q "That's everything that shipped this session"; }
p_ask_most_useful(){ ask47 "$1" | grep -q 'ask \*"What was most useful for you in this session?"\*'; }
p_ask_recap_first(){ local r o; r=$(ask47 "$1" | grep -n -m1 'Recap first' | cut -d: -f1); o=$(ask47 "$1" | grep -n -m1 "Then offer, don't quiz" | cut -d: -f1); [ -n "$r" ] && [ -n "$o" ] && [ "$r" -lt "$o" ]; }
p_step8_no_offer(){ ! step8 "$1" | grep -q -E "That's everything that shipped this session|Recap first|Then offer, don't quiz"; }
p_step8_verifies(){ step8 "$1" | grep -q 'Never repeat the recap or the offer here'; }
p_no_skip_fields(){ ! { blockA "$1"; reportB "$1"; } | grep -q -E 'Skip (if not asked|the field entirely|entirely if nothing)'; }
p_A_most_useful(){ blockA "$1" | grep -q '^\*\*Most useful:\*\* .*Write "None — not asked"'; }
p_A_candidates(){ [ "$(blockA "$1" | grep -A1 -E '^\*\*Observed \(Tier (A|B) candidates\):\*\*' | grep -c 'Write "None" when nothing surfaced')" = "2" ]; }
p_B_most_useful(){ reportB "$1" | awk '/^## Most useful/{getline; print}' | grep -q 'Write "None — not asked"'; }
p_B_observed(){ reportB "$1" | awk '/^## Observed \(Tier B candidates\)/{f=1;next} f&&/^## /{exit} f' | grep -q 'Write "None" when nothing surfaced'; }
p_rules_none(){ grep -q "Don't skip sections, but write \"None\"" "$1"; }

run_all(){ # $1 file  $2 mode: report | count
  local f="$1" n=0 name
  for name in $PROPS; do
    if "p_$name" "$f"; then [ "$2" = report ] && ok "$name"; else n=$((n+1)); [ "$2" = report ] && no "$name"; fi
  done
  [ "$2" = count ] && printf '%s' "$n"
}
PROPS="auto_exception routing_scoped ask_before_append ask_holds_offer ask_most_useful ask_recap_first step8_no_offer step8_verifies no_skip_fields A_most_useful A_candidates B_most_useful B_observed rules_none"
failing(){ local f="$1" out="" name; for name in $PROPS; do "p_$name" "$f" || out="$out $name"; done; printf '%s' "${out# }"; }

printf '/close-session — questions before the block, verify-only step 8, --auto in the checklist, one rule for empty fields\n'
run_all "$SPEC" report

# --- negative controls: each mutation must break EXACTLY the property it targets -------------
# Every property runs on every mutated copy, and the set that fails must equal the expected one:
# a control that breaks two properties proves neither is isolated.
mut(){ # $1 label  $2 perl substitution  $3 the one property that must now fail
  cp "$SPEC" "$TMP/m.md"; perl -0pi -e "$2" "$TMP/m.md"
  if cmp -s "$SPEC" "$TMP/m.md"; then no "control '$1': mutation did not apply (anchor moved)"; return; fi
  got=$(failing "$TMP/m.md")
  [ "$got" = "$3" ] && ok "control '$1': breaks exactly $3" || no "control '$1': expected only [$3] to fail, got [$got]"
}
mut "offer back in step 8"          's/(8\. \*\*Comprehension ledger[^\n]*\n)/$1\n   > *"☝️ That'"'"'s everything that shipped this session."*\n/'   step8_no_offer
mut "--auto exception dropped"      's/ \*\*Under `--auto`, every observed-context item above[^\n]*//'                      auto_exception
mut "Mode B observed loses None"    's/(## Observed \(Tier B candidates\)[\s\S]*?) *Write "None" when nothing surfaced\.//' B_observed
mut "4.7 moved after step 5"        's/(4\.7\. \*\*Ask before you write\*\*[\s\S]*?)(5\. \*\*Append the session block via the race-safe helper[^\n]*\n)/$2$1/' ask_before_append
mut "most-useful question removed"  's/ If the session was substantive \(>30 min, meaningful work\), ask \*"What was most useful for you in this session\?"\*//' ask_most_useful
mut "recap removed from 4.7"        's/\n   \*\*b1\. Recap first[^\n]*\n//' ask_recap_first

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
