#!/usr/bin/env bash
# tests/lock-claim-exclusive.test.sh
#
# Guards the CLAIM step of every AIOS directory lock: aios-snapshot, aios-commit, aios-note-append
# (and, by lint, the spawn lock and /aios:update's run lock).
#
# WHAT THIS IS PROTECTING
# -----------------------
# The locks were `mkdir`, on the promise that mkdir is atomic. It is a syscall that is; the
# command need not be. Ubuntu 26.04 ships uutils mkdir 0.10.0 as /usr/bin/mkdir, and on the CI
# runner it gave several racers success for the same folder (6 of 40 rounds of 50 racers had
# more than one winner, up to 10; GNU mkdir 9.4 on ubuntu-24.04: 0 of 40). Two holders at once
# is exactly what each lock exists to prevent -- the snapshot suite lost 1-2 of 6 archives there.
#
# The fix keeps the folder (every observer reads "folder exists" as "held") and makes OWNERSHIP
# the creation of a pid file under `set -C`: bash opens it O_EXCL itself, whichever mkdir the
# system ships, so exactly one racer can create it.
#
# HOW THIS REPRODUCES IT ON ANY MACHINE
# A `mkdir` shim on PATH behaves the way the runner's did: it checks, waits 50 ms, then creates
# tolerating "already exists". Six writers race each hook with a hold injected inside the lock,
# and every holder logs in/out, so the defect is measured directly as the most holders at once.
# The pre-fix hooks (pinned) run as the control and must show more than one -- a race this test
# cannot see would certify nothing.
#
# Run:  bash tests/lock-claim-exclusive.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/lockclaim.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
PIN=2a3f389b6562eaf7394e2ec9cd5dc9b380a312d4   # last commit before the claim step

PYBIN=""
for _c in python3 python "py -3"; do $_c -c 'import sys' >/dev/null 2>&1 && { PYBIN="$_c"; break; }; done
[ -n "$PYBIN" ] || { echo "SKIP: no working Python found"; exit 0; }

REAL_MKDIR=$(command -v mkdir)
mkdir -p "$TMP/shim"
cat > "$TMP/shim/mkdir" <<SHIM
#!/usr/bin/env bash
# Non-atomic mkdir: any option -> the real one; a bare mkdir checks, waits, then creates
# tolerating "already exists" -- several racers can all report success.
case "\${1:-}" in -*) exec "$REAL_MKDIR" "\$@" ;; esac
[ \$# -eq 1 ] || exec "$REAL_MKDIR" "\$@"
[ -e "\$1" ] && { echo "mkdir: cannot create directory '\$1': File exists" >&2; exit 1; }
sleep 0.05
"$REAL_MKDIR" -p "\$1"
SHIM
chmod +x "$TMP/shim/mkdir"

echo "── 1. the instrument: the shim really lets several racers win ──"
wins=0
for r in 1 2 3 4 5; do
  for i in $(seq 1 20); do ( PATH="$TMP/shim:$PATH" mkdir "$TMP/probe$r" 2>/dev/null && echo win ) & done > "$TMP/probe$r.out"
  wait
  [ "$(grep -c win "$TMP/probe$r.out")" -gt 1 ] && wins=$((wins+1))
done
[ "$wins" -ge 1 ] && ok "CONTROL FIRES: the shim gave >1 winner in $wins of 5 rounds" \
  || no "the shim never gave two winners" "every lock result below would prove nothing"

# Hooks under test: the working tree (new) and the pinned pre-fix tree (old).
# Since #309 the helpers live in hooks/vault/ and find the scanner one level up, in hooks/git/.
cp -R "$ROOT/hooks/vault" "$TMP/new"; cp -R "$ROOT/hooks/git" "$TMP/git"
HAVE_OLD=0
if git -C "$ROOT" cat-file -e "$PIN:hooks/aios-commit" 2>/dev/null; then
  mkdir -p "$TMP/old" && git -C "$ROOT" archive "$PIN" hooks | tar -x -C "$TMP/old" && mv "$TMP/old/hooks" "$TMP/oldh" && HAVE_OLD=1
fi
[ "$HAVE_OLD" = 1 ] || echo "  SKIP  pre-fix control: $PIN not present"

# Instrument: wrap acquire/release so each holder logs in/out and holds the lock 0.3 s.
instrument(){ # $1 hooks dir · $2 hook name
  "$PYBIN" - "$1/$2" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = 'acquire; LOCKED=1'
i = s.find('\n' + a)
assert i >= 0, "acquire anchor moved -- fix this test"
w = ('\neval "orig_$(declare -f acquire)"; acquire(){ orig_acquire; echo in >> "$AIOS_T_LOG"; sleep 0.3; }'
     '\neval "orig_$(declare -f release)"; release(){ [ "$LOCKED" = 1 ] && echo out >> "$AIOS_T_LOG"; orig_release; }')
open(p, "w").write(s[:i] + w + s[i:])
PY
}
maxheld(){ awk '/in/{n++; if(n>m)m=n} /out/{n--} END{print m+0}' "$1" 2>/dev/null || echo 0; }

race(){ # $1 hooks dir · $2 hook → "max_holders entries"
  local H="$1" h="$2" r i log
  r=$(mktemp -d "$TMP/r.XXXXXX"); log="$r/holders"; : > "$log"
  case "$h" in
    aios-snapshot)
      mkdir -p "$r/vault/00 - notes/logs/observed-snapshots/2026-08"
      printf 'base\n' > "$r/vault/00 - notes/logs/observed-snapshots/2026-08/2026-08-14-obs.md"
      for i in 1 2 3 4 5 6; do mkdir -p "$r/w$i"; printf 'content-%s\n' "$i" > "$r/w$i/obs.md"; done ;;
    aios-note-append)
      printf '# note\n' > "$r/n.md"
      for i in 1 2 3 4 5 6; do printf 'block-%s\n' "$i" > "$r/b$i"; done ;;
    aios-commit)
      git -C "$r" init -q; git -C "$r" config user.name t; git -C "$r" config user.email t@t
      echo seed > "$r/seed"; git -C "$r" add seed; git -C "$r" commit -qm seed
      for i in 1 2 3 4 5 6; do echo "f$i" > "$r/f$i"; done ;;
  esac
  for i in 1 2 3 4 5 6; do
    case "$h" in
      aios-snapshot) AIOS_T_LOG="$log" PATH="$TMP/shim:$PATH" "$H/aios-snapshot" --root "$r" --date 2026-08-14 "$r/w$i/obs.md" >/dev/null 2>&1 & ;;
      aios-note-append) AIOS_T_LOG="$log" PATH="$TMP/shim:$PATH" "$H/aios-note-append" --note "$r/n.md" --block-file "$r/b$i" -m "x$i" --no-push >/dev/null 2>&1 & ;;
      aios-commit) ( cd "$r" && AIOS_T_LOG="$log" PATH="$TMP/shim:$PATH" "$H/aios-commit" --no-push -m "c$i" -- "f$i" >/dev/null 2>&1 ) & ;;
    esac
  done
  wait
  case "$h" in
    aios-snapshot) i=$(cat "$r/vault/00 - notes/logs/observed-snapshots/2026-08/"*obs.md | grep -c '^content-') ;;
    aios-note-append) i=$(grep -c '^block-' "$r/n.md") ;;
    aios-commit) i=$(git -C "$r" log --format=%s | grep -c '^c[1-6]$') ;;
  esac
  echo "$(maxheld "$log") $i"
}

echo "── 2. under a non-atomic mkdir, each lock still has ONE holder at a time ──"
for h in aios-snapshot aios-note-append aios-commit; do
  instrument "$TMP/new" "$h"
  read -r MAXH N <<<"$(race "$TMP/new" "$h")"
  { [ "$MAXH" = 1 ] && [ "$N" = 6 ]; } \
    && ok "$h: never more than 1 holder, all 6 writers landed" \
    || no "$h: $MAXH holders at once, $N of 6 landed" "the claim step did not make the lock exclusive"
  if [ "$HAVE_OLD" = 1 ]; then
    instrument "$TMP/oldh" "$h"
    worst=0; best=6
    for t in 1 2 3; do
      read -r MAXH N <<<"$(race "$TMP/oldh" "$h")"
      [ "$MAXH" -gt "$worst" ] && worst=$MAXH; [ "$N" -lt "$best" ] && best=$N
      [ "$worst" -gt 1 ] && break
    done
    [ "$worst" -gt 1 ] \
      && ok "OLD $h: $worst holders at once, $best of 6 landed (the defect, reproduced)" \
      || no "OLD $h: the race did not reproduce in 3 tries" "the control proves nothing if it cannot fail"
  fi
done

echo "── 3. lint: every mkdir mutex claims ownership with a noclobber file ──"
# A lock added later with a bare `mkdir` would be exclusive on GNU and BSD and silently not on
# uutils 0.10. Any mkdir whose failure is branched on (the mutex shape) must carry `set -C`.
BAD=$(grep -rnE '(! *\{? *mkdir|mkdir [^|&;]*2>/dev/null *(\|\||&&))' "$ROOT/hooks" "$ROOT/plugins/aios/commands" 2>/dev/null \
  | grep -vE 'mkdir -[pm]' | grep -v 'set -C' || true)
[ -z "$BAD" ] && ok "no mkdir lock without a noclobber claim (hooks/, plugins/aios/commands/)" \
  || no "mkdir lock(s) without a noclobber claim:" "$BAD"

printf '\nRESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
