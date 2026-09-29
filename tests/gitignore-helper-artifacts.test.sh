#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# A --vault commit never carries the framework helpers' own locks, temps or backups
#
# WHY
# Several hooks write runtime files INSIDE the vault tree, beside the note they
# protect: aios-note-append's per-note lock and atomic-write temp, aios-snapshot's
# directory lock and temp, route-insight.py's pre-write backup (kept on success).
# `aios-commit --vault` adds untracked files through `--exclude-standard`, so
# .gitignore is the only thing between those files and a commit. Observed on a
# live vault: a close commit carried two route-insight backups of an observed
# file. The framework's .gitignore now names every one of them.
#
# Three parts:
#   1. Drift guard: each artifact name checked here is still the name its helper
#      writes. Rename one in a hook and this fails, instead of the ignore rule
#      silently matching nothing.
#   2. Control: in a scratch repo with NO .gitignore, a real --vault commit does
#      pick the artifacts up. Proves part 3 is able to fail.
#   3. With the repo's .gitignore, the same --vault commit carries the notes and
#      snapshots and none of the artifacts.
#   4. The superpowers rule also holds at the repo root, where --vault never
#      looks, without swallowing the vendored skill folder.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
ROOT="$(pwd)"
AC="$ROOT/hooks/aios-commit"

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  ✗ %s\n      %s\n' "$1" "${2:-}"; }

[ -x "$AC" ] || { echo "::error::missing or not executable: $AC"; exit 1; }

echo "── 1. each artifact name is still what its helper writes ──"
src(){ # file needle label
  if grep -qF -- "$2" "$1"; then ok "$3"
  else no "$3" "'$2' no longer appears in $1 — update .gitignore and this suite together"; fi
}
src hooks/aios-note-append '.aios-lock"'            "aios-note-append locks <note>.aios-lock"
src hooks/aios-note-append '.aiostmp"'              "aios-note-append writes <note>.aiostmp"
src hooks/aios-snapshot    '/.aios-snapshot.lock"'  "aios-snapshot locks .aios-snapshot.lock"
src hooks/aios-snapshot    '/.aios-snapshot.$$.tmp"' "aios-snapshot writes .aios-snapshot.<pid>.tmp"
src hooks/route-insight.py '.routebak-'             "route-insight.py backs up to <file>.routebak-<ts>"
src skills/superpowers/brainstorming/visual-companion.md '.superpowers/' "superpowers keeps state in .superpowers/"

OBS='vault/00 - notes/context/observed'
SNAP='vault/00 - notes/logs/observed-snapshots/2026-01'
DAY='vault/01 - calendar/2026-01'

ARTIFACTS=(
  "$DAY/2026-01-01.md.aios-lock/pid"
  "$DAY/2026-01-01.md.aios-lock.reclaim/pid"
  "$DAY/2026-01-01.md.aiostmp"
  "$SNAP/.aios-snapshot.lock/pid"
  "$SNAP/.aios-snapshot.lock.reclaim/pid"
  "$SNAP/.aios-snapshot.4242.tmp"
  "$OBS/session-insights.md.routebak-20260101-120000"
  "vault/.superpowers/brainstorm/1-2/content/screen.html"
)
CONTENT=(
  "$DAY/2026-01-01.md"
  "$OBS/session-insights.md"
  "$SNAP/2026-01-01-profile.md"
  "$SNAP/2026-01-01b-profile.md"
)

# Build a scratch repo with one tracked note (so HEAD exists), then drop every
# artifact and every content file in as new untracked files, and run the real
# --vault commit. $1 = path of a .gitignore to install, or "" for none.
commit_with(){
  local r; r=$(mktemp -d)
  git -C "$r" init -q
  git -C "$r" config user.email t@t.io; git -C "$r" config user.name t
  mkdir -p "$r/vault"; echo seed > "$r/vault/seed.md"
  [ -n "$1" ] && cp "$1" "$r/.gitignore"
  git -C "$r" add -A; git -C "$r" commit -qm init
  local p
  for p in "${ARTIFACTS[@]}" "${CONTENT[@]}"; do
    mkdir -p "$r/$(dirname "$p")"; echo x > "$r/$p"
  done
  ( cd "$r" && "$AC" --vault --no-push -m "sweep" >/dev/null 2>&1 ) || { echo "COMMIT-FAILED"; rm -rf "$r"; return; }
  git -C "$r" -c core.quotePath=false show --name-only --format='' HEAD
  rm -rf "$r"
}

echo "── 2. control: with no .gitignore, --vault commits the artifacts ──"
OUT="$(commit_with "")"
if [ "$OUT" = "COMMIT-FAILED" ]; then
  no "control: the --vault commit ran" "aios-commit --vault failed in the scratch repo; nothing below can be trusted"
else
  n=0
  for p in "${ARTIFACTS[@]}"; do printf '%s\n' "$OUT" | grep -qxF "$p" && n=$((n+1)); done
  if [ "$n" -eq "${#ARTIFACTS[@]}" ]; then ok "control: all ${#ARTIFACTS[@]} artifacts are committed when nothing ignores them"
  else no "control: all ${#ARTIFACTS[@]} artifacts are committed when nothing ignores them" "only $n were — the scratch setup changed; fix it before trusting part 3"; fi
fi

echo "── 3. with this repo's .gitignore, --vault commits the notes and no artifact ──"
OUT="$(commit_with "$ROOT/.gitignore")"
if [ "$OUT" = "COMMIT-FAILED" ]; then
  no "the --vault commit ran" "aios-commit --vault failed in the scratch repo"
else
  for p in "${ARTIFACTS[@]}"; do
    if printf '%s\n' "$OUT" | grep -qxF "$p"; then no "not committed: $p" "the --vault commit carried a helper artifact"
    else ok "not committed: $p"; fi
  done
  for p in "${CONTENT[@]}"; do
    if printf '%s\n' "$OUT" | grep -qxF "$p"; then ok "committed: $p"
    else no "committed: $p" "a real note or snapshot is now ignored — a rule is too broad"; fi
  done
fi

echo "── 4. the superpowers rule also covers the repo root, outside the --vault sweep ──"
if git check-ignore -q --no-index -- ".superpowers/sdd/plan/state.json"; then ok "ignored: .superpowers/ at the repo root"
else no "ignored: .superpowers/ at the repo root" "git check-ignore does not match it"; fi
if git check-ignore -q --no-index -- "skills/superpowers/brainstorming/SKILL.md"; then no "not ignored: skills/superpowers/" "the rule swallowed the vendored skill itself"
else ok "not ignored: skills/superpowers/ (the vendored skill itself)"; fi

printf '\n  %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
