#!/usr/bin/env bash
# Regression test for the AIOS commit primitives — aios-commit, aios-note-append, secret-scan.
# Locks the correctness properties hand-verified during the AI-2 build so a future edit can't
# silently regress them (the --cached no-op bug is the canonical example: it only surfaced on a
# real, always-dirty vault, never on a clean dry-run). Canonical-only (not synced to operator
# vaults); run in CI by .github/workflows/validate.yml and manually via:  bash tests/aios-commit.test.sh
#
# NOTE on the secret-scan test: the fake token is assembled at RUNTIME from a split prefix, so no
# secret-shaped literal ever appears in this file — it won't trip GitHub push protection or
# aios-commit's own self-scan when THIS file is committed.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AC="$ROOT/hooks/aios-commit"
ANA="$ROOT/hooks/aios-note-append"
SCAN="$ROOT/hooks/git/secret-scan.sh"
PASS=0; FAIL=0
ok(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
no(){ echo "  ✗ $1"; FAIL=$((FAIL+1)); }

for f in "$AC" "$ANA" "$SCAN"; do [ -x "$f" ] || { echo "::error::missing/!exec: $f"; exit 1; }; done

newrepo(){ local d; d=$(mktemp -d); git -C "$d" init -q; git -C "$d" config user.email t@t.io; git -C "$d" config user.name t; echo "$d"; }

echo "── aios-commit: refuses no-path (never -A) ──"
R=$(newrepo); ( cd "$R"; echo x>f; git add -A; git commit -qm init
  "$AC" -m "no path" --no-push >/dev/null 2>&1 && exit 1 || exit 0 ) && ok "errors with no path and no --vault" || no "should error with no path"
rm -rf "$R"

echo "── aios-commit: no-op guard fires with an unrelated dirty file (the --cached bug) ──"
R=$(newrepo); ( cd "$R"; echo v1>tracked; echo o>unrel; git add -A; git commit -qm init
  echo DIRTY>unrel; H0=$(git rev-parse HEAD)
  "$AC" -m "noop" --no-push -- tracked >/dev/null 2>&1
  [ "$H0" = "$(git rev-parse HEAD)" ] ) && ok "no commit when named path unchanged (dirty unrelated present)" || no "no-op guard failed → empty commit"
rm -rf "$R"

echo "── aios-commit: commits ONLY named paths, leaves unrelated dirty ──"
R=$(newrepo); ( cd "$R"; echo v1>tracked; echo o>unrel; git add -A; git commit -qm init
  echo v2>tracked; echo DIRTY>unrel
  "$AC" -m "scoped" --no-push -- tracked >/dev/null 2>&1
  n=$(git show --stat --format='' HEAD | grep -c '|')
  [ "$n" = "1" ] && git status --porcelain unrel | grep -q '^ M' ) && ok "scoped: 1 file committed, unrelated stays dirty" || no "scope leak"
rm -rf "$R"

echo "── aios-commit --vault: space-path committed, machine-local excluded ──"
R=$(newrepo); ( cd "$R"; mkdir -p "vault/00 - notes" .glass vault/.obsidian
  echo a>"vault/00 - notes/n.md"; echo b>.glass/state.json; echo c>vault/.obsidian/workspace.json; git add -A; git commit -qm init
  echo a2>>"vault/00 - notes/n.md"; echo b2>.glass/state.json; echo c2>vault/.obsidian/workspace.json
  "$AC" --vault -m "vault" --no-push >/dev/null 2>&1
  S=$(git show --stat --format='' HEAD)
  echo "$S" | grep -q "vault/00 - notes/n.md" && ! echo "$S" | grep -q "\.glass" && ! echo "$S" | grep -q "workspace.json" ) \
  && ok "--vault: space-path in, .glass + workspace.json out" || no "--vault scope wrong"
rm -rf "$R"

echo "── secret-scan: blocks a secret-shaped token ──"
R=$(newrepo); ( cd "$R"; P="sk-""ant-"; printf 'key = %s%s\n' "$P" "$(printf 'a%.0s' $(seq 30))" > leak.txt
  "$SCAN" leak.txt >/dev/null 2>&1 && exit 1 || exit 0 ) && ok "blocks a fake sk-ant- token" || no "missed a secret"
rm -rf "$R"

echo "── secret-scan: clean file passes ──"
R=$(newrepo); ( cd "$R"; echo "just prose, nothing secret" > clean.txt; "$SCAN" clean.txt >/dev/null 2>&1 ) && ok "clean file passes" || no "false positive on clean file"
rm -rf "$R"

echo "── aios-note-append: inserts the block BEFORE the marker ──"
R=$(newrepo); ( cd "$R"; printf 'top\n\n## Close of Day\nfooter\n' > note.md; git add -A; git commit -qm init
  printf '\n## Session A\nbody\n' > blk.md
  "$ANA" --note note.md --before "## Close of Day" -m "s" --no-push --block-file blk.md >/dev/null 2>&1
  awk '/## Session A/{s=NR} /## Close of Day/{c=NR} END{exit !(s>0 && c>0 && s<c)}' note.md ) \
  && ok "note-append inserts before the marker (ordered)" || no "note-append marker insert failed"
rm -rf "$R"

echo "── aios-note-append: appends at end when marker absent ──"
R=$(newrepo); ( cd "$R"; printf 'only a header\n' > note.md; git add -A; git commit -qm init
  printf '\n## Session B\nbody\n' > blk.md
  "$ANA" --note note.md --before "## Close of Day" -m "s" --no-push --block-file blk.md >/dev/null 2>&1
  tail -3 note.md | grep -q "## Session B" ) && ok "note-append falls back to end-append" || no "end-append failed"
rm -rf "$R"

# ─────────────────────────────────────────────────────────────────────────────
# Empty-array expansion class (#6). On bash 3.2 — the bash macOS ships at /bin/bash,
# and what `#!/usr/bin/env bash` resolves to on a stock Mac — `"${arr[@]}"` on an EMPTY
# array is an unbound variable under `set -u`, so the script ABORTS mid-operation.
# Both cases below aborted before the fix; neither was covered by the tests above,
# because every call there passes --no-push (so NOPUSH is never empty) and the CI
# `primitives` job runs on ubuntu/bash 5 (where the plain form is harmless).
# Run under the 3.2 lane in validate.yml, these are the regression guard for the class.
# ─────────────────────────────────────────────────────────────────────────────

echo "── aios-commit: ROOT commit, no HEAD yet (PARENTS empty) ──"
R=$(newrepo); ( cd "$R"; echo v1>f
  "$AC" -m "root" --no-push -- f >/dev/null 2>&1
  git rev-parse HEAD >/dev/null 2>&1 && git show --stat --format='' HEAD | grep -q 'f' ) \
  && ok "first commit in a fresh repo succeeds (empty PARENTS[@])" || no "root commit failed — PARENTS[@] unbound"
rm -rf "$R"

echo "── aios-note-append: default path, NO --no-push (NOPUSH empty — the /close-session path) ──"
R=$(newrepo); ( cd "$R"; printf 'top\n' > note.md; git add -A; git commit -qm init
  printf '\n## Session C\nbody\n' > blk.md
  H0=$(git rev-parse HEAD)
  # No remote configured: aios-commit commits, then defers the push. Assert HEAD ADVANCED and the
  # block is in the COMMITTED tree — not merely that note.md appears in the last commit, which the
  # init commit already satisfies (that weaker assertion passed against the unpatched hook, i.e. it
  # proved nothing). Pre-fix, the expansion aborts *after* the write and *before* the commit, so the
  # block is on disk but HEAD never moves — and the instinctive retry duplicates it.
  "$ANA" --note note.md -m "s" --block-file blk.md >/dev/null 2>&1
  [ "$H0" != "$(git rev-parse HEAD)" ] && git show HEAD:note.md | grep -q "## Session C" ) \
  && ok "note-append commits on the default push path (empty NOPUSH[@])" || no "note-append aborted — NOPUSH[@] unbound; block written to disk but never committed"
rm -rf "$R"

echo ""
echo "── RESULT: $PASS passed, $FAIL failed  (bash $BASH_VERSION) ──"
[ "$FAIL" = "0" ] || exit 1
