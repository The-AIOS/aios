#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The declared spawn-inbox contract against the number the surfaces really stamp
#
# skills/aios/orchestration-ladder/inbox-contract.json declares the current
# contract, and tests/inbox-contract-number.test.sh keeps CLAUDE.md and the skill
# in step with it. That still leaves the declaration itself hand-typed: if the
# App and Glass move to the next contract, nothing inside this repo changes and
# every local check stays green (#409).
#
# The stamp is written by the surfaces, and their source is not in this repo. So
# this suite READS it: `export const INBOX_CONTRACT = N;` in src/core/sendQueue.ts
# on the default branch of The-AIOS/aios-app and The-AIOS/aios-glass. A surface
# never overwrites a README stamped with a higher contract than its own, so the
# number an agent finds on a machine running both is the HIGHER of the two — that
# is what the declaration must equal.
#
# Three outcomes, and they are kept apart on purpose:
#   exit 0   both surfaces were read and the declaration matches
#   exit 1   both were read and it does not match — or a file was read and the
#            stamp was not in it (the instrument broke, which is a verdict too)
#   exit 75  a surface could not be reached. That is NOT a verdict: nothing was
#            compared. It is reported as INCONCLUSIVE and never as a pass.
#
# Reading a local checkout instead of the network:
#   AIOS_APP_SRC=/path/to/aios-app  AIOS_GLASS_SRC=/path/to/aios-glass
# Until the shared package publishes a cases file with this number, the source
# is the only place it exists (The-AIOS/aios-app#226).
#
# Written for bash 3.2. Needs curl only when a surface is read over the network.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
SELF="tests/inbox-contract-stamp.test.sh"
PASS=0; FAIL=0; UNREAD=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }
unread(){ UNREAD=$((UNREAD+1)); printf '  ????  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

DECL="${AIOS_CONTRACT_DECL:-skills/aios/orchestration-ladder/inbox-contract.json}"
RAW="${AIOS_SURFACE_RAW_BASE:-https://raw.githubusercontent.com/The-AIOS}"
REL="src/core/sendQueue.ts"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

CUR="$([ -f "$DECL" ] && grep -oE '"current" *: *[0-9]+' "$DECL" | grep -oE '[0-9]+$' | sort -u | tr '\n' ' ' | sed 's/ $//')"
stamp_in(){ grep -oE '^export const INBOX_CONTRACT *= *[0-9]+' "$1" | grep -oE '[0-9]+$' | sort -u | tr '\n' ' ' | sed 's/ $//'; }

# read_surface <repo> <local-dir-or-empty>  → sets GOT to a number, or to '' with WHY set
# to "unreachable" (no verdict) or "broken" (read, and the stamp is not there).
read_surface(){
  repo="$1"; dir="$2"; GOT=''; WHY=''; FROM=''
  if [ -n "$dir" ]; then
    FROM="$dir/$REL"
    [ -f "$FROM" ] || { WHY=broken; return 0; }
    cp "$FROM" "$TMP/$repo.ts"
  else
    FROM="$RAW/$repo/main/$REL"
    command -v curl >/dev/null 2>&1 || { WHY=unreachable; return 0; }
    code="$(curl -sSL --max-time 20 --retry 2 -o "$TMP/$repo.ts" -w '%{http_code}' "$FROM" 2>/dev/null)" || { WHY=unreachable; return 0; }
    case "$code" in
      200) : ;;
      404) WHY=broken; return 0 ;;          # reached, and the file is not where this suite reads it
      *)   WHY=unreachable; return 0 ;;
    esac
  fi
  GOT="$(stamp_in "$TMP/$repo.ts")"
  case "$GOT" in ''|*' '*) GOT=''; WHY=broken ;; esac
}

echo "── 1. the declaration ──"
case "$CUR" in
  ''|*' '*) no "$DECL does not declare exactly one current contract (read: '${CUR}')"
            printf '\n%d passed · %d failed\n' "$PASS" "$FAIL"; exit 1 ;;
  *)        ok "declared current contract: $CUR" ;;
esac

echo "── 2. what each surface stamps ──"
HIGH=''
for pair in "aios-app:${AIOS_APP_SRC:-}" "aios-glass:${AIOS_GLASS_SRC:-}"; do
  repo="${pair%%:*}"; dir="${pair#*:}"
  read_surface "$repo" "$dir"
  if [ -n "$GOT" ]; then
    ok "$repo stamps contract $GOT ($FROM)"
    { [ -z "$HIGH" ] || [ "$GOT" -gt "$HIGH" ]; } && HIGH="$GOT"
  elif [ "$WHY" = broken ]; then
    no "$repo was read and no single INBOX_CONTRACT was found in it ($FROM)" \
       "the file moved or the symbol was renamed: this suite can no longer read the stamp, so fix where it reads from"
  else
    unread "$repo could not be reached ($FROM)" "nothing was compared for this surface"
  fi
done

echo "── 3. the declaration equals the higher stamp ──"
if [ "$FAIL" -gt 0 ]; then
  :
elif [ -n "$HIGH" ] && [ "$HIGH" -gt "$CUR" ]; then
  # True whatever the unread surface says: the higher stamp can only be this or more.
  no "a surface stamps contract $HIGH and $DECL declares $CUR" \
     "the documents lag behind the code. Read what contract $HIGH adds, then raise the number in $DECL and in the sentence CLAUDE.md and the skill repeat (tests/inbox-contract-number.test.sh names both)"
elif [ "$UNREAD" -gt 0 ]; then
  :
elif [ "$HIGH" -lt "$CUR" ]; then
  no "$DECL declares contract $CUR and no surface stamps more than $HIGH" \
     "the declaration is the contract IN FORCE, the one an agent finds stamped; a contract only specified here is not current yet"
else
  ok "declared $CUR = stamped $HIGH"
fi

if [ -z "${AIOS_STAMP_CONTROL:-}" ]; then
  echo "── 4. CONTROL — each outcome is reachable, from fixtures, with no network ──"
  fx(){ mkdir -p "$TMP/$1/src/core"; printf '%s\n' "$2" > "$TMP/$1/src/core/sendQueue.ts"; }
  run(){ AIOS_STAMP_CONTROL=1 AIOS_CONTRACT_DECL="$DECL" AIOS_APP_SRC="${1:-}" AIOS_GLASS_SRC="${2:-}" \
         AIOS_SURFACE_RAW_BASE="${3:-$RAW}" bash "$SELF" >/dev/null 2>&1; echo $?; }
  fx same  "export const INBOX_CONTRACT = $CUR;"
  fx ahead "export const INBOX_CONTRACT = $((CUR+1));"
  fx gone  "export const SOMETHING_ELSE = $CUR;"
  DEAD="http://127.0.0.1:9"   # the discard port: refused at once, no network involved
  R="$(run "$TMP/same" "$TMP/same")";  [ "$R" = 0 ]  && ok "control: both surfaces on $CUR → pass" \
    || no "control: two surfaces stamping $CUR gave exit $R, expected 0"
  R="$(run "$TMP/same" "$TMP/ahead")"; [ "$R" = 1 ]  && ok "control: one surface on $((CUR+1)) → fail" \
    || no "control: a surface ahead of the declaration gave exit $R, expected 1" "this suite cannot see the drift it exists for"
  R="$(run "$TMP/same" "$TMP/gone")";  [ "$R" = 1 ]  && ok "control: stamp missing from a file that was read → fail" \
    || no "control: an unreadable stamp gave exit $R, expected 1"
  R="$(run "$TMP/same" "" "$DEAD")";   [ "$R" = 75 ] && ok "control: one surface unreachable → inconclusive (75), not a pass" \
    || no "control: an unreachable surface gave exit $R, expected 75" "a check that did not run must not read as green"
  R="$(run "$TMP/ahead" "" "$DEAD")";  [ "$R" = 1 ]  && ok "control: one ahead, the other unreachable → fail" \
    || no "control: a surface ahead with the other unreachable gave exit $R, expected 1"
fi

printf '\n%d passed · %d failed · %d not read\n' "$PASS" "$FAIL" "$UNREAD"
[ "$FAIL" -eq 0 ] || exit 1
if [ "$UNREAD" -gt 0 ]; then
  echo "INCONCLUSIVE: a surface could not be read, so the declared contract was NOT checked against it."
  exit 75
fi
exit 0
