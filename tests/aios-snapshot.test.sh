#!/usr/bin/env bash
# tests/aios-snapshot.test.sh
#
# Guards hooks/aios-snapshot — the observed-context archiver.
#
# WHAT THIS IS PROTECTING
# -----------------------
# The snapshot destination is keyed by DAY and FILENAME with no writer in it, so two sessions
# archiving the same file on the same day target the same path — and `cp` exits 0, making a
# colliding write indistinguishable from a successful one. The damage lands in the one
# artifact whose entire job is to survive, and it is only noticed later, as a hole.
#
# A written protocol existed and was correct (compare -> identical means done, different means
# next free letter). It held every time it was followed. It could not hold in two cases no
# amount of care removes: it is not atomic (two writers can pick the same free letter), and it
# only compared against the BASE name (identical content already under `b` still minted a `c`).
#
# THE CONCURRENCY TEST IS THE POINT, AND IT NEEDS A REAL WINDOW.
# A first version of this test ran 8 writers with no injected delay and the UNLOCKED control
# passed too — the decide-to-write window is microseconds when both steps are in one process,
# so the test proved nothing and would have certified the lock on the strength of a race that
# never occurred. The real protocol's window is not microseconds: the compare and the copy are
# separate steps, seconds apart. So the delay is injected into BOTH variants and the only
# difference between them is the lock. With that window the control fails loudly — measured
# 1 of 6 contents surviving unlocked, 6 of 6 locked.
#
# Run:  bash tests/aios-snapshot.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SNAP="$ROOT/hooks/aios-snapshot"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/snap-test.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
D_OF(){ echo "$1/vault/00 - notes/logs/observed-snapshots/2026-08"; }
newroot(){ local r; r=$(mktemp -d "$TMP/root.XXXXXX"); mkdir -p "$(D_OF "$r")"; echo "$r"; }

echo "── 1. present and executable ──"
[ -f "$SNAP" ] && ok "hooks/aios-snapshot exists" || no "missing"
[ -x "$SNAP" ] && ok "carries the exec bit" || no "not executable"
bash -n "$SNAP" && ok "parses" || no "syntax error"

echo "── 2. the four decisions ──"
R=$(newroot); D=$(D_OF "$R")
printf 'A\n' > "$R/obs.md"
OUT=$("$SNAP" --root "$R" --date 2026-08-14 "$R/obs.md")
case "$OUT" in snapshot*) ok "first archive → snapshot" ;; *) no "expected snapshot, got: $OUT" ;; esac
OUT=$("$SNAP" --root "$R" --date 2026-08-14 "$R/obs.md")
case "$OUT" in identical*) ok "unchanged re-run → identical, nothing written" ;; *) no "expected identical, got: $OUT" ;; esac
printf 'B\n' > "$R/obs.md"
OUT=$("$SNAP" --root "$R" --date 2026-08-14 "$R/obs.md")
case "$OUT" in collision*b-obs.md) ok "changed content → next free letter (b)" ;; *) no "expected collision …b-, got: $OUT" ;; esac
printf 'C\n' > "$R/obs.md"; "$SNAP" --root "$R" --date 2026-08-14 "$R/obs.md" >/dev/null
printf 'B\n' > "$R/obs.md"
OUT=$("$SNAP" --root "$R" --date 2026-08-14 "$R/obs.md")
case "$OUT" in
  identical*b-obs.md) ok "content matching a NON-BASE variant → identical (the manual protocol minted a duplicate here)" ;;
  *) no "expected identical against the b variant, got: $OUT" ;;
esac
[ "$(ls "$D" | grep -c obs.md)" = "3" ] && ok "exactly 3 archives, no duplicate minted" || no "archive count wrong: $(ls "$D" | tr '\n' ' ')"

echo "── 3. exit codes + hygiene ──"
"$SNAP" --root "$R" --date 2026-08-14 "$R/obs.md" >/dev/null 2>&1 \
  && ok "identical is exit 0 (success, not a no-op failure)" || no "identical exited non-zero"
"$SNAP" --root "$R" --date 2026-08-14 "$R/does-not-exist.md" >/dev/null 2>&1 \
  && no "a missing source exited 0" || ok "a missing source exits non-zero"
"$SNAP" --root "$R" --date not-a-date "$R/obs.md" >/dev/null 2>&1 \
  && no "a malformed --date was accepted" || ok "a malformed --date is rejected"
[ -d "$D/.aios-snapshot.lock" ] && no "lock left behind after exit" || ok "lock released on exit"

echo "── 4. CONCURRENCY — the reason this tool exists ──"
# Inject a realistic decide-to-write window into BOTH variants; the lock is the only difference.
python3 - "$SNAP" "$TMP" <<'PY'
import sys
src=open(sys.argv[1]).read(); tmp=sys.argv[2]
anchor='    cp -p "$src" "$cand" || break'
assert anchor in src, "anchor moved — fix this test"
locked=src.replace(anchor,'    sleep 0.4\n'+anchor,1)
open(f"{tmp}/snap-locked","w").write(locked)
un=locked.replace('acquire; LOCKED=1',': # lock disabled')
assert un!=locked, "lock line moved — fix this test"
open(f"{tmp}/snap-unlocked","w").write(un)
PY
chmod +x "$TMP/snap-locked" "$TMP/snap-unlocked"
# VERIFY THE INSTRUMENTS BEFORE USING THEM — a broken variant would report data loss in a
# tool that is fine, or safety in one that is not.
bash -n "$TMP/snap-locked" && bash -n "$TMP/snap-unlocked" \
  && [ "$(grep -c 'sleep 0.4' "$TMP/snap-locked")" = "1" ] \
  && [ "$(grep -c 'sleep 0.4' "$TMP/snap-unlocked")" = "1" ] \
  && [ "$(grep -c '^acquire; LOCKED=1' "$TMP/snap-locked")" = "1" ] \
  && [ "$(grep -c '^acquire; LOCKED=1' "$TMP/snap-unlocked")" = "0" ] \
  && ok "both test variants parse, both have the window, only one has the lock" \
  || no "test variants are malformed — every assertion below would be meaningless"

race(){ # race <variant> → prints "kept lost"
  local v="$1" r d i kept lost
  r=$(newroot); d=$(D_OF "$r")
  printf 'base\n' > "$d/2026-08-14-obs.md"     # force everyone onto the next-free-letter path
  for i in 1 2 3 4 5 6; do mkdir -p "$r/w$i"; printf 'content-%s\n' "$i" > "$r/w$i/obs.md"; done
  for i in 1 2 3 4 5 6; do ( "$TMP/snap-$v" --root "$r" --date 2026-08-14 "$r/w$i/obs.md" >/dev/null 2>&1 ) & done
  wait
  kept=$(cat "$d"/*obs.md 2>/dev/null | grep -c '^content-')
  lost=$((6 - kept))
  echo "$kept $lost"
}
read -r U_KEPT U_LOST <<<"$(race unlocked)"
read -r L_KEPT L_LOST <<<"$(race locked)"
printf '        unlocked kept %s/6 · locked kept %s/6\n' "$U_KEPT" "$L_KEPT"
[ "$L_KEPT" = "6" ] && ok "LOCKED: 6 concurrent writers, all 6 contents survive" \
  || no "the lock did not prevent loss — $L_LOST of 6 contents lost"
[ "$U_LOST" -gt 0 ] && ok "CONTROL FIRES: unlocked loses $U_LOST of 6 — the race is real and this test can see it" \
  || no "CONTROL DID NOT FIRE — unlocked lost nothing, so the locked result proves nothing"

printf '\nRESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
