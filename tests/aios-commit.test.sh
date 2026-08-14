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

echo "── aios-commit --untrack: gitignore-an-already-tracked-path (the case git add cannot express) ──"
R=$(newrepo); ( cd "$R"; mkdir .glass; echo '{"f":14}' > .glass/shell.json; echo k > keep.txt
  git add -A; git commit -qm init
  # the real-world shape: file MODIFIED, then path IGNORED, with a sibling actor's staged work present
  echo '.glass/' > .gitignore; echo '{"f":15}' > .glass/shell.json
  echo sib > sibling.txt; git add sibling.txt
  # --no-push BEFORE `--`: everything after `--` is a pathspec (git convention), so a flag
  # placed there would be treated as a file and the staging step would fail.
  "$AC" -m "untrack" --no-push --untrack .glass -- .gitignore >/dev/null 2>&1
  # removal recorded · untrack STICKS in the real index · file survives on disk · sibling untouched
  [ "$(git ls-tree -r --name-only HEAD | grep -c '^\.glass/')" = 0 ] \
    && [ "$(git ls-files .glass/ | wc -l | tr -d ' ')" = 0 ] \
    && [ -f .glass/shell.json ] \
    && [ "$(git show --name-only --format= HEAD | grep -c sibling)" = 0 ] \
    && git ls-files --cached sibling.txt | grep -q . ) \
  && ok "--untrack: removal committed, sticks in the index, file kept on disk, sibling's staging preserved" \
  || no "--untrack broken (re-added by git add, or index not synced so the untrack won't stick, or sibling swept)"
rm -rf "$R"

echo "── aios-commit --untrack ONLY (no paths): must NOT degenerate into git add -A ──"
R=$(newrepo); ( cd "$R"; echo t > tracked.txt; git add tracked.txt; git commit -qm init
  echo s1 > stray1.txt; echo s2 > stray2.txt            # must never be swept
  "$AC" -m "untrack only" --untrack tracked.txt --no-push >/dev/null 2>&1
  [ "$(git show --name-only --format= HEAD | grep -c stray)" = 0 ] \
    && [ "$(git show --name-status --format= HEAD | tr -d ' \t\n')" = "Dtracked.txt" ] ) \
  && ok "--untrack-only commits just the removal; untracked strays not swept (empty-pathspec guard holds)" \
  || no "--untrack-only swept the tree — `git add --all --` with no pathspec stages EVERYTHING"
rm -rf "$R"

# The real-index sync used ONE `git add --all -- <every path>` call. That form is all-or-nothing:
# a single pathspec matching nothing (the `git mv old new` case — caller passes both, `old` is
# gone from worktree AND index) exits 128 and stages NOTHING. The error was swallowed, so commit
# and push succeeded, HEAD held the new content, the index held the old, and `git status` showed
# `MM` forever — read as unpushed work that did not exist. Found on 3 live repos 2026-07-30.
echo "── aios-commit: index sync survives a pathspec that matches nothing (the git-mv MM bug) ──"
R=$(newrepo); ( cd "$R"; echo gpl > LICENSE; echo old > NOTICE; git add -A; git commit -qm init
  echo new > NOTICE                                        # modified, NOT staged
  git mv LICENSE LICENSE-TEMPLATE                           # 'LICENSE' now matches nothing
  "$AC" -m "renamed" --no-push -- NOTICE LICENSE LICENSE-TEMPLATE >/dev/null 2>&1
  # the commit must carry the new NOTICE *and* the real index must agree with HEAD afterwards
  git show HEAD:NOTICE 2>/dev/null | grep -qx new \
    && [ -z "$(git diff --cached --name-only HEAD -- NOTICE LICENSE LICENSE-TEMPLATE)" ] \
    && [ -z "$(git status --porcelain -- NOTICE LICENSE-TEMPLATE)" ] ) \
  && ok "dead pathspec doesn't abort the sync: NOTICE committed AND index clean (no phantom MM)" \
  || no "index sync aborted on a non-matching pathspec — status will show phantom MM"
rm -rf "$R"

# NO test for the stale-index NOTE itself, deliberately. With the per-path sync above there is no
# longer a way to leave the index lagging without also breaking the commit: every mechanism that
# stops `git add` writing the index (read-only .git, unreadable file) equally stops the lock, the
# throwaway index, or update-ref. Attempted via `chmod -w .git` — the whole run fails, so the test
# would assert on an artificial state that no real failure produces. The NOTE stays in the hook as
# a BACKSTOP (a per-path add can still fail for reasons not enumerated here), but an untestable
# backstop is documented as one rather than given a test that proves nothing.
echo "── aios-commit: the sync verifies itself (assertion present, not just attempted) ──"
grep -q 'index still lags HEAD' "$AC" && grep -q 'git diff --cached --name-only HEAD' "$AC" \
  && ok "post-sync verification + operator-facing NOTE are wired into the hook" \
  || no "the stale-index verification was removed — silent staleness can return"

# ─────────────────────────────────────────────────────────────────────────────
# Lock-failure CLASSIFICATION. `mkdir` fails for two unrelated reasons and the
# loop used to treat both as contention: an unwritable $GIT_DIR (sandboxed Bash
# tool, read-only checkout) spun 600×0.1s and then died "lock timeout (held by
# pid ?)" — blaming a process that never existed and sending the operator to
# hunt it. The `?` was the tell: there was no lock, so no pid to read.
#
# Tested by OBSERVATION, not by chmod: `chmod a-w` is a no-op against NTFS ACLs
# in Git Bash, so a permission-based test would silently pass on Windows without
# exercising anything. A regular FILE squatting on the lock path reproduces the
# same class identically on all three platforms — mkdir fails EEXIST, `[ -d ]`
# is false, so the lock is unobservable exactly as in the unwritable case.
# ─────────────────────────────────────────────────────────────────────────────

echo "── aios-commit: unusable lock path fails FAST with the real cause (not 'held by pid ?') ──"
R=$(newrepo); ( cd "$R"; echo v1>f; git add -A; git commit -qm init; echo v2>f
  G=$(git rev-parse --absolute-git-dir); : > "$G/aios-commit.lock"   # a FILE, not a dir
  S=$(date +%s)
  OUT=$("$AC" -m "unusable lock" --no-push -- f 2>&1); E=$(date +%s)
  # fast (well under the 60s spin) AND names the real cause, never a phantom pid
  [ $((E-S)) -lt 20 ] && echo "$OUT" | grep -q "NOT contention" && ! echo "$OUT" | grep -q "held by pid" ) \
  && ok "unusable lock path: fails <20s naming the real cause, no phantom pid" \
  || no "still spins to 'lock timeout (held by pid ?)' — classification regressed"
rm -rf "$R"

echo "── aios-commit: a LIVE holder is contention — must keep retrying, never early-die ──"
R=$(newrepo); ( cd "$R"; echo v1>f; git add -A; git commit -qm init; echo v2>f
  G=$(git rev-parse --absolute-git-dir); mkdir -p "$G/aios-commit.lock"
  sleep 600 & LIVE=$!; echo "$LIVE" > "$G/aios-commit.lock/pid"     # a real, running pid
  "$AC" -m "contended" --no-push -- f >/dev/null 2>&1 & AC_PID=$!
  sleep 3
  # still alive after 3s = it is patiently retrying. The early-die (~2s) must NOT
  # have fired: the lock was observed, so saw_lock pins it to the contention path.
  if kill -0 "$AC_PID" 2>/dev/null; then RES=0; else RES=1; fi
  kill "$AC_PID" "$LIVE" 2>/dev/null; wait "$AC_PID" "$LIVE" 2>/dev/null
  exit $RES ) \
  && ok "live holder: still retrying at 3s (sticky saw_lock prevents a false permission verdict)" \
  || no "early-die fired on genuine contention — the fix misclassifies a real lock"
rm -rf "$R"

echo "── aios-commit: dead holder still reclaimed (classification didn't break recovery) ──"
R=$(newrepo); ( cd "$R"; echo v1>f; git add -A; git commit -qm init; echo v2>f
  G=$(git rev-parse --absolute-git-dir); mkdir -p "$G/aios-commit.lock"
  D=$(sh -c 'echo $$')                       # a pid that has already exited
  echo "$D" > "$G/aios-commit.lock/pid"
  H0=$(git rev-parse HEAD)
  "$AC" -m "reclaim" --no-push -- f >/dev/null 2>&1
  [ "$H0" != "$(git rev-parse HEAD)" ] ) \
  && ok "dead holder reclaimed and the commit landed" || no "reclaim broken by the classification change"
rm -rf "$R"

# ── session-provenance trailer (added 2026-08-13) ────────────────────────────
# A vault is written by several Claude sessions at once and git cannot tell them
# apart (same author, same committer). Consumers asking "did *I* do this?" were
# forced to infer it from the commit SUBJECT — a convention, not a fact. This
# records it. Additive by design: no env var → no trailer, so a human at a
# terminal or an older Claude is unaffected.
R=$(mktemp -d); ( cd "$R" && git init -q . && git config user.email t@t && git config user.name t \
  && git config commit.gpgsign false && echo x > a.md && git add a.md && git commit -qm base ) >/dev/null 2>&1

( cd "$R" && echo y > a.md && CLAUDE_CODE_SESSION_ID="sess-abc-123" "$AC" --no-push -m "feat: tagged" -- a.md >/dev/null 2>&1 \
  && git log -1 --format='%B' | grep -q '^AIOS-Session: sess-abc-123$' ) \
  && ok "session trailer written when CLAUDE_CODE_SESSION_ID is set" \
  || no "session trailer missing when the env var is set"

( cd "$R" && echo z > a.md && env -u CLAUDE_CODE_SESSION_ID "$AC" --no-push -m "feat: untagged" -- a.md >/dev/null 2>&1 \
  && ! git log -1 --format='%B' | grep -q 'AIOS-Session' ) \
  && ok "no session id → no trailer (additive, never required)" \
  || no "a trailer appeared with no session id — the change must be additive"

( cd "$R" && echo w > a.md && CLAUDE_CODE_SESSION_ID='bad
AIOS-Session: forged' "$AC" --no-push -m "feat: hostile" -- a.md >/dev/null 2>&1 \
  && ! git log -1 --format='%B' | grep -q 'AIOS-Session' ) \
  && ok "a session id with illegal characters is REJECTED, not injected" \
  || no "a multi-line session id forged a trailer line"
rm -rf "$R"

# ── --vault must not say "nothing" when two reads disagree (added 2026-08-14) ─────────
#
# THE STATE: the real index holds content that is neither HEAD's nor the working tree's. Then
# `git status` (index-based) reports the path as MM, while the sweep (`diff --name-only HEAD`,
# working-tree-based) truthfully finds nothing differing from HEAD. Both reads are correct and
# they contradict each other, and the old message — "no vault changes to commit" — asserted
# something stronger than it had measured. From outside, indistinguishable from a sweep whose
# pathspec cannot reach the file, which is exactly how an operator lost a session hunting a
# sweep bug that did not exist. The sweep was byte-identical across the versions involved.
#
# Reported as "the sweep misses tracked dotfiles"; re-measured as "the index was lying". The
# reporter could not reconstruct the state, so it is constructed here — deliberately, because a
# fix for a state nobody can reproduce is a fix nobody can verify.
R=$(mktemp -d "${TMPDIR:-/tmp}/ac-idx.XXXXXX")
( cd "$R" && git init -q . && git config user.email t@t.io && git config user.name T \
  && git config commit.gpgsign false && mkdir -p vault && echo A > vault/n.md \
  && git add -A && git commit -qm base ) >/dev/null 2>&1

# Construct it: index=B, worktree back to A, HEAD=A.
( cd "$R" && echo B > vault/n.md && git add vault/n.md && echo A > vault/n.md ) >/dev/null 2>&1

( cd "$R" && [ "$(git status --porcelain -- vault/ | wc -l | tr -d ' ')" = "1" ] \
  && [ -z "$(git diff --name-only HEAD -- 'vault/')" ] ) \
  && ok "fixture: status sees 1 path the sweep truthfully does not (the state is real)" \
  || no "fixture did not build the desynced index — the assertions below prove nothing"

OUT=$( cd "$R" && "$AC" --vault --no-push -m "should not commit" 2>&1 )
printf '%s' "$OUT" | grep -q 'do not differ from HEAD' \
  && ok "--vault names the contradiction instead of claiming there is nothing" \
  || no "--vault printed a bare 'nothing to commit' over a state it could not explain: $OUT"
printf '%s' "$OUT" | grep -q 'git reset' \
  && ok "…and prescribes the remedy" || no "no remedy offered"
( cd "$R" && [ "$(git rev-list --count HEAD)" = "1" ] ) \
  && ok "…and commits nothing" || no "it committed something it should not have"

# The remedy must actually work, and must not eat the working tree.
( cd "$R" && git reset -q && [ -z "$(git status --porcelain -- vault/)" ] && [ "$(cat vault/n.md)" = "A" ] ) \
  && ok "the prescribed 'git reset' clears it and preserves the working tree" \
  || no "the advice in the message does not work — worse than no advice"
OUT=$( cd "$R" && "$AC" --vault --no-push -m "noop" 2>&1 )
printf '%s' "$OUT" | grep -q 'no vault changes to commit' \
  && ok "genuinely clean still prints the plain message" || no "clean case regressed: $OUT"

# CONTROL: machine-local noise is excluded by the sweep, so it must not trigger the warning —
# otherwise the two reads are taken over different path sets, which is its own mismatch.
( cd "$R" && mkdir -p vault/.obsidian && echo '{}' > vault/.obsidian/workspace.json \
  && git add -f vault/.obsidian/workspace.json && git commit -qm ws \
  && echo '{"a":1}' > vault/.obsidian/workspace.json && git add vault/.obsidian/workspace.json \
  && echo '{}' > vault/.obsidian/workspace.json ) >/dev/null 2>&1
OUT=$( cd "$R" && "$AC" --vault --no-push -m "noise" 2>&1 )
printf '%s' "$OUT" | grep -q 'no vault changes to commit' \
  && ok "a desynced EXCLUDED path does not trigger the warning (same scope both sides)" \
  || no "excluded machine-local noise raised the warning: $OUT"

# CONTROL: a real change must still commit — the guard sits on the empty-PATHS branch only.
( cd "$R" && git reset -q && echo C > vault/n.md \
  && "$AC" --vault --no-push -m "real" >/dev/null 2>&1 \
  && [ "$(git show HEAD:vault/n.md)" = "C" ] ) \
  && ok "a real change still commits normally" || no "the normal --vault path regressed"
rm -rf "$R"

echo ""
echo "── RESULT: $PASS passed, $FAIL failed  (bash $BASH_VERSION) ──"
[ "$FAIL" = "0" ] || exit 1
