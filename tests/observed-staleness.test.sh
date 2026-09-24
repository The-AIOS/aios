#!/usr/bin/env bash

# ── Resolve a python that RUNS (Windows) ─────────────────────────────────────
# On Windows `python3` is a Microsoft Store App Execution Alias that satisfies
# every existence probe, exits 49 and produces nothing. Same probe as
# tests/buffer-status.test.sh. $PYBIN is used UNQUOTED so `py -3` word-splits.
PYBIN=""
for _cand in python3 python "py -3"; do
  if $_cand -c 'import sys' >/dev/null 2>&1; then PYBIN="$_cand"; break; fi
done
if [ -z "$PYBIN" ]; then
  echo "SKIP: no working Python found (tried python3, python, py -3)" >&2
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# hooks/observed-staleness.py — the observed-context staleness alarm, as code
#
# The threshold half of this alarm was always reliable; the EXEMPTION half —
# which files have no clock — lived in prose, was re-derived by hand every
# morning, and was eventually disbelieved. These checks pin the properties the
# hook exists for:
#   * a file past its threshold is flagged (exit 1), aggregates at 21d, others 30d
#   * `restated: true` and `status: historical-snapshot` have no clock, and are
#     PRINTED rather than silently dropped (an invisible exemption is a muted alarm)
#   * a missing / unparseable `updated:` is exit 2 and never a green line — a
#     checker that reports "all fresh" because it could not read a stamp is the
#     defect class this hook exists to reduce
#   * output survives a non-UTF-8 console (the hook prints emoji)
#   * it never writes
# Every check that asserts a verdict has a control that must produce the other one.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
H=hooks/observed-staleness.py
[ -f "$H" ] || { echo "  FAIL $H missing"; exit 1; }
TODAY=2026-09-24

note(){ # note <dir> <file> <frontmatter-lines...>
  local d="$1" f="$2"; shift 2
  mkdir -p "$d"
  { echo "---"; for l in "$@"; do echo "$l"; done; echo "---"; echo; echo "# body"; } > "$d/$f"
}
run(){ $PYBIN "$H" "$@" --today "$TODAY"; }

echo "── a fresh vault is clean ──"
D="$T/fresh"
note "$D" patterns.md "updated: 2026-09-20"
note "$D" ecosystem.md "updated: 2026-09-10"
note "$D" _index.md "type: index"
out=$(run "$D" 2>&1); rc=$?
[ "$rc" = "0" ] && ok "all within threshold → exit 0" || no "exit $rc on a fresh vault" "$out"
case "$out" in *"nothing stale"*) ok "says so in words" ;; *) no "no 'nothing stale' line" "$out" ;; esac
case "$out" in *"_index.md"*) no "_index.md was measured" "an index is not an observation" ;; *) ok "_index.md is skipped" ;; esac

echo "── past threshold is flagged, and aggregates run on the tighter clock ──"
D="$T/stale"
note "$D" patterns.md "updated: 2026-08-20"     # 35d > 30d
note "$D" ecosystem.md "updated: 2026-08-31"    # 24d > 21d (aggregate)
note "$D" growth.md "updated: 2026-08-31"       # 24d < 30d (ordinary)
out=$(run "$D" 2>&1); rc=$?
[ "$rc" = "1" ] && ok "something crossed → exit 1" || no "exit $rc, expected 1" "$out"
case "$out" in *patterns.md*35d*) ok "patterns.md flagged at 35d" ;; *) no "patterns.md not flagged" "$out" ;; esac
case "$out" in *ecosystem.md*24d*"threshold 21d"*) ok "aggregate flagged at 24d against 21d" ;; *) no "aggregate threshold not applied" "$out" ;; esac
case "$out" in *growth.md*) no "control: growth.md at 24d was flagged against a 30d threshold" "$out" ;; *) ok "control: an ordinary file at 24d is not flagged" ;; esac

echo "── the two no-clock shapes are exempt, and printed ──"
D="$T/exempt"
note "$D" vault-routine.md "restated: true" "updated: 2025-01-01"
note "$D" frozen-record.md "status: historical-snapshot" "updated: 2025-01-01"
note "$D" patterns.md "updated: 2026-09-20"
out=$(run "$D" 2>&1); rc=$?
[ "$rc" = "0" ] && ok "ancient restated + frozen files do not alarm → exit 0" || no "exit $rc, expected 0" "$out"
case "$out" in *vault-routine.md*"no clock (restated"*) ok "restated file is listed as exempt" ;; *) no "restated exemption is silent" "$out" ;; esac
case "$out" in *frozen-record.md*"no clock (frozen"*) ok "historical-snapshot file is listed as exempt" ;; *) no "frozen exemption is silent" "$out" ;; esac
# Control: the SAME ancient stamp without the exemption must alarm, or the check
# above cannot tell an exemption from a threshold that never fires.
note "$D" frozen-record.md "status: active" "updated: 2025-01-01"
rc=$(run "$D" >/dev/null 2>&1; echo $?)
[ "$rc" = "1" ] && ok "control: same file without the exemption alarms" || no "control: exit $rc, expected 1"

echo "── a stamp it cannot read is exit 2, never a green line ──"
D="$T/nostamp"
note "$D" patterns.md "updated: 2026-09-20"
note "$D" profile.md "type: claude-context"
out=$(run "$D" 2>&1); rc=$?
[ "$rc" = "2" ] && ok "missing updated: → exit 2" || no "exit $rc, expected 2" "$out"
case "$out" in *"✅"*) no "printed a ✅ while a file could not be measured" "$out" ;; *) ok "no green line on an incomplete run" ;; esac
case "$out" in *profile.md*"cannot measure"*) ok "names the file it could not measure" ;; *) no "unmeasured file not named" "$out" ;; esac
note "$D" profile.md "updated: last week"
rc=$(run "$D" >/dev/null 2>&1; echo $?)
[ "$rc" = "2" ] && ok "non-ISO updated: → exit 2" || no "non-ISO stamp exit $rc, expected 2"
rc=$(run "$T/does-not-exist" >/dev/null 2>&1; echo $?)
[ "$rc" = "2" ] && ok "missing directory → exit 2" || no "missing directory exit $rc, expected 2"

echo "── JSON is parseable and carries the verdict ──"
js=$(run "$T/stale" --json 2>/dev/null)
st=$(printf '%s' "$js" | $PYBIN -c 'import sys,json;print(",".join(sorted(json.load(sys.stdin)["stale"])))')
[ "$st" = "ecosystem.md,patterns.md" ] && ok "--json lists the stale files" || no "--json stale list: '$st'"

echo "── survives a console that cannot encode emoji ──"
# Exit status alone cannot tell: a UnicodeEncodeError traceback ALSO exits 1,
# which is the stale verdict's code. So require the verdict text on stdout.
out=$(PYTHONIOENCODING=cp1252 $PYBIN "$H" "$T/stale" --today "$TODAY" 2>/dev/null)
case "$out" in *"past threshold"*) ok "cp1252 stdout: the verdict is still printed" ;;
  *) no "cp1252 stdout: no verdict printed" "the report crashes on a non-UTF-8 console" ;; esac

echo "── it never writes ──"
before=$(cat "$T/stale/patterns.md" | cksum)
run "$T/stale" >/dev/null 2>&1
after=$(cat "$T/stale/patterns.md" | cksum)
[ "$before" = "$after" ] && ok "files are byte-identical after a run" || no "the hook modified a file"

echo "── the commands call the hook, through uv ──"
grep -q 'uv run ~/aios/hooks/observed-staleness.py' plugins/aios/commands/today.md \
  && ok "today.md runs the hook through uv" || no "today.md does not run the hook"
grep -q 'uv run ~/aios/hooks/observed-staleness.py' plugins/aios/commands/close-day.md \
  && ok "close-day.md runs the hook through uv" || no "close-day.md does not run the hook"
grep -q 'python3 ~/aios/hooks/observed-staleness.py' plugins/aios/commands/*.md \
  && no "a command runs the hook through python3" "on Windows that name runs nothing, silently" || ok "no command calls it through python3"

echo "── a fresh install is not an error: an explicitly empty stamp has no clock yet ──"
# The framework ships its observed files as seeds with `updated: ""`. Reporting those as
# "cannot measure" put a wall of red on every new operator's first /today. An empty stamp
# is "not started"; a MISSING key is still an error (the control below).
fr="$(mktemp -d)"
printf -- '---\nupdated: ""\n---\n# seed\n' > "$fr/patterns.md"
printf -- '---\nupdated: "2026-09-20"\n---\n# real\n' > "$fr/growth.md"
$PYBIN hooks/observed-staleness.py "$fr" --today 2026-09-24 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "a seed with updated: \"\" reads as not started (exit 0)" || no "a fresh-install seed was reported as an error" "exit $rc"
printf -- '---\ntype: claude-context\n---\n# no stamp at all\n' > "$fr/profile.md"
$PYBIN hooks/observed-staleness.py "$fr" --today 2026-09-24 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "control: a file with NO updated: key still cannot be measured (exit 2)" || no "control: a missing stamp stopped being an error" "exit $rc"
rm -rf "$fr"

printf '\n── %s passed, %s failed ──\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
