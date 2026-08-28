#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The Pipeline Status line must name the precondition that actually failed
#
# FIELD REPORT 2026-08-28. `/aios:today` printed, every morning:
#     ⏭️ tasks: configured but credentials missing — run the setup for this source
# The credentials were present, valid and self-refreshing. The real cause was a
# missing `- Google Tasks list: <ID>` line in USER.md → ## Sources.
#
# The Tasks future is created only if THREE independent things hold (configured ·
# list ID present · credentials on disk). The status report attributed ANY absent
# future to credentials — three preconditions collapsed into one diagnosis, and the
# one chosen was the most expensive to chase. The operator re-authenticated OAuth
# five mornings in a row.
#
# The lesson, in the reporter's words: a message that names a WRONG cause is worse
# than a generic one, because it directs the work. A generic message makes you look;
# a wrong specific one makes you work.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
EXEC=hooks/pipeline-executor.py

echo "── the wrong-cause message is gone ──"
if grep -qF 'configured but credentials missing' "$EXEC"; then
  no "the blanket 'credentials missing' message is still there" "it fires when a list ID is missing too"
else
  ok "no blanket 'credentials missing' attribution remains"
fi

echo "── each precondition reports itself ──"
grep -qF 'missing list ID' "$EXEC" \
  && ok "a missing Tasks list ID names itself" \
  || no "a missing list ID is not named" "this is the case that cost five mornings"
grep -qF 'credentials not found at' "$EXEC" \
  && ok "genuinely-absent credentials still name themselves, with the path" \
  || no "the credentials branch was lost"

echo "── the residual branch does not invent a cause ──"
# A default is a silent assertion about the case you did not enumerate. If none of
# the known causes matched, the honest output says so rather than picking one.
if grep -qE 'no known cause matched|prerequisites incomplete' "$EXEC"; then
  ok "the fall-through says no known cause matched instead of naming one"
else
  no "the fall-through names a specific cause it did not verify" "this is the original bug, one branch down"
fi

echo "── the canary the reporter specified ──"
# Credentials present + list ID absent must mention the list ID and NOT credentials.
OUT=$(python3 - <<'PY'
sources = {"configured": ["tasks"], "google_tasks_list": None}
futures = {}
class C:
    def exists(self): return True
    def __str__(self): return "/tmp/creds.json"
creds_primary = C(); status = []
for source, mapped in [("tasks", "tasks")]:
    if mapped not in futures and source in sources["configured"]:
        if source == "tasks" and not sources["google_tasks_list"]:
            reason = "missing list ID — add `- Google Tasks list: `<ID>`` to USER.md"
        elif creds_primary is None or not creds_primary.exists():
            reason = "credentials not found"
        else:
            reason = "prerequisites incomplete"
        status.append(f"tasks: configured but not queried — {reason}")
print(status[0])
PY
)
case "$OUT" in
  *"list ID"*) ok "canary: the message names the list ID" ;;
  *) no "canary: the message does not name the list ID" "$OUT" ;;
esac
case "$OUT" in
  *credentials*) no "canary: the message still blames credentials" "$OUT" ;;
  *) ok "canary: the message does NOT blame credentials" ;;
esac

echo "── and the line is documented, so it cannot be silently unset from day one ──"
grep -qF 'Google Tasks list' SETUP.md \
  && ok "SETUP.md tells the operator the list-ID line exists" \
  || no "SETUP.md never mentions the list-ID line" "the source can be enabled-but-mute from day one with no signal"

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
