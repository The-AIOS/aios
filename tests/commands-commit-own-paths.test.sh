#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# /today and /aios:housekeeping commit the paths they wrote; /close-day keeps
# its own writes apart from its sweep.
#
# `aios-commit --vault` commits every changed path under vault/. In a vault that
# several sessions write at once, that includes their uncommitted, unfinished
# work — which then shipped under "Daily plan", "Housekeeping" or "Close day",
# attributed to the session that ran the command. Housekeeping's own Phase 4
# said "commit the exact change — don't expand scope" two screens above its
# `--vault`.
#
# Checks:
#   1. today.md, housekeeping.md, 7plan.md, compact.md and graduate.md (#343) invoke aios-commit with named paths and
#      never with --vault.
#   2. close-day.md commits its own writes by name FIRST, then sweeps with
#      --vault under a subject that says "Sweep" — never a --vault "Close day".
#   3. RUN: the commit line /today prescribes is extracted, placeholders filled,
#      and run with this repo's aios-commit against a fixture vault holding a
#      peer's uncommitted file. The commit must contain the note and NOT the
#      peer's file; the CONTROL runs the old --vault line on the same fixture
#      and must sweep the peer's file in, or check 3 proves nothing.
# ─────────────────────────────────────────────────────────────────────────────
set -u
cd "$(dirname "$0")/.." || exit 1
REPO="$(pwd)"
C="$REPO/plugins/aios/commands"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; return 0; }

echo "== commands commit their own paths =="
# CLAUDE.md § Session End and § Git & Commit Conventions are what a session follows at every close (#343).
if grep -nE 'aios-commit --vault' "$REPO/CLAUDE.md" >/dev/null; then
  no "CLAUDE.md prescribes aios-commit --vault for a session's own work" "$(grep -nE 'hooks/vault/aios-commit --vault' "$REPO/CLAUDE.md" | head -1)"
else
  ok "CLAUDE.md: a session commits the paths it wrote, never --vault"
fi

# ── 1. today + housekeeping: named paths, no --vault ─────────────────────────
TMP0="$(mktemp -d)"
# Prints every aios-commit invocation in <file> that uses --vault or names no `-- "vault/` path.
# Judged per line, so a line holding TWO invocations is refused outright: one good call on it
# would otherwise vouch for a pathless one beside it.
bad_calls(){
  grep -E 'hooks/vault/aios-commit ' "$1" | grep -v '^allowed-tools:' | while IFS= read -r l; do
    n=$(printf '%s\n' "$l" | grep -o 'hooks/vault/aios-commit ' | wc -l | tr -d ' ')
    [ "$n" -gt 1 ] && { printf '%s\n' "$l"; continue; }
    case "$l" in
      *--vault*) printf '%s\n' "$l" ;;
      *' -- "vault/'*) : ;;
      *) printf '%s\n' "$l" ;;
    esac
  done
}
for f in today housekeeping 7plan compact graduate; do
  bad=$(bad_calls "$C/$f.md")
  if [ -z "$(grep -E 'hooks/vault/aios-commit ' "$C/$f.md" | grep -v '^allowed-tools:')" ]; then
    no "$f.md: no aios-commit invocation found"
  elif [ -n "$bad" ]; then
    no "$f.md has an aios-commit call that sweeps or names no paths" "$(printf '%s\n' "$bad" | head -1)"
  else
    ok "$f.md: every aios-commit call names vault paths, none uses --vault"
  fi
done

# The check is per call: one good call must not vouch for a bad one beside it.
cp "$C/today.md" "$TMP0/today-mut.md"
printf '\n- `cd ~/aios && ~/aios/hooks/vault/aios-commit -m "Daily plan {date}"`\n' >> "$TMP0/today-mut.md"
[ -n "$(bad_calls "$TMP0/today-mut.md")" ] \
  && ok "MUTANT: a pathless call added beside a good one is caught" \
  || no "MUTANT: a pathless call beside a good one passes"
# …and on the SAME line as the good one.
sed 's|^\(- `cd ~/aios \&\& ~/aios/hooks/vault/aios-commit -m "Daily plan {date}" -- .*\)$|\1 then `cd ~/aios \&\& ~/aios/hooks/vault/aios-commit -m "Daily plan {date}"`|' \
  "$C/today.md" > "$TMP0/today-mut2.md"
if cmp -s "$C/today.md" "$TMP0/today-mut2.md"; then
  no "MUTANT (same line) could not be built"
else
  [ -n "$(bad_calls "$TMP0/today-mut2.md")" ] \
    && ok "MUTANT: a pathless call on the same line as a good one is caught" \
    || no "MUTANT: a pathless call on the same line as a good one passes"
fi

# ── 2. close-day: own writes by name, then a sweep that says so ──────────────
own=$(grep -n 'aios-commit -m "Close day {date}" -- "vault/' "$C/close-day.md" | head -1 | cut -d: -f1)
swp=$(grep -n 'aios-commit --vault -m "Sweep ' "$C/close-day.md" | head -1 | cut -d: -f1)
[ -n "$own" ] && ok "close-day commits its own writes by name under 'Close day'" \
  || no "close-day has no named-path 'Close day' commit"
[ -n "$swp" ] && ok "close-day's --vault sweep has a subject that says 'Sweep'" \
  || no "close-day has no labelled sweep"
if [ -n "$own" ] && [ -n "$swp" ] && [ "$own" -lt "$swp" ]; then
  ok "own writes are committed before the sweep"
else
  no "the sweep is not after close-day's own commit" "own=${own:-none} sweep=${swp:-none}"
fi
grep -q 'aios-commit --vault -m "Close day' "$C/close-day.md" \
  && no "close-day still sweeps under 'Close day'" \
  || ok "no --vault commit is labelled 'Close day'"

# ── 3. RUN today's line against a vault with a peer's uncommitted file ───────
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP" "$TMP0"' EXIT
fixture(){
  rm -rf "$TMP/home"; mkdir -p "$TMP/home/aios/vault/01 - calendar/2026-10" "$TMP/home/aios/vault/00 - notes" "$TMP/home/aios/hooks"
  V="$TMP/home/aios"
  git -C "$V" init -q
  git -C "$V" config user.email t@example.com; git -C "$V" config user.name Test; git -C "$V" config commit.gpgsign false
  # the helper resolves its siblings from the vault it lives in
  mkdir -p "$V/hooks/git" "$V/hooks/vault"
  cp "$REPO/hooks/vault/aios-commit" "$V/hooks/vault/"; cp "$REPO/hooks/git/secret-scan.sh" "$V/hooks/git/"
  echo seed > "$V/vault/seed.md"; git -C "$V" add -A; git -C "$V" commit -q -m init
  echo "# today" > "$V/vault/01 - calendar/2026-10/2026-10-11.md"     # this run's write
  echo "half done" > "$V/vault/00 - notes/peer-wip.md"                 # another session's
}
fill(){ printf '%s' "$1" | sed 's/^[^`]*`//; s/`.*$//; s|{YYYY-MM}|2026-10|g; s|{YYYY-MM-DD}|2026-10-11|g; s|{date}|2026-10-11|g'; }
committed(){ git -C "$TMP/home/aios" show --name-only --format= HEAD; }
runline(){ env -u CLAUDE_CODE_SESSION_ID HOME="$TMP/home" sh -c "$1 --no-push" >"$TMP/out" 2>&1; }

line=$(grep -m1 'aios-commit -m "Daily plan {date}" -- ' "$C/today.md")
if [ -z "$line" ]; then
  no "today.md: no named-path 'Daily plan' commit to run"
else
  cmd=$(fill "$line")
  # --no-push goes before the paths separator
  cmd=$(printf '%s' "$cmd" | sed 's| -- | --no-push -- |')
  fixture
  env -u CLAUDE_CODE_SESSION_ID HOME="$TMP/home" sh -c "$cmd" >"$TMP/out" 2>&1
  files=$(committed)
  if printf '%s\n' "$files" | grep -q '2026-10-11.md' && ! printf '%s\n' "$files" | grep -q 'peer-wip'; then
    ok "RUN: today's commit holds the note and not the peer's file"
  else
    no "RUN: today's commit is wrong" "committed: $(printf '%s' "$files" | tr '\n' ' ') · $(tail -2 "$TMP/out")"
  fi
  git -C "$TMP/home/aios" ls-files --others --exclude-standard | grep -qx 'vault/00 - notes/peer-wip.md' \
    && ok "RUN: the peer's file is left uncommitted for its owner" \
    || no "RUN: the peer's file did not stay uncommitted"

  fixture
  runline 'cd ~/aios && ~/aios/hooks/vault/aios-commit --vault -m "Daily plan 2026-10-11"'
  committed | grep -q 'peer-wip' \
    && ok "CONTROL: the old --vault line sweeps the peer's file in" \
    || no "CONTROL: the old --vault line did not sweep the peer's file — check 3 proves nothing" "$(tail -2 "$TMP/out")"
fi

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
