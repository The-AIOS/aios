#!/usr/bin/env bash
# tests/aios-health.test.sh
#
# hooks/aios-health.py is routine health (contract from #171): one small file per scheduled
# job, written at the END of a completed run, with a deadline. A job that fails is reported; a job
# that stops running is reported too, because its deadline passes with nothing written. This proves
# both, plus the reader's rules (silent when fine, unreadable files reported, never "didn't run"),
# and that the quota watcher writes its own verdict.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/aios-health.py"
W="$ROOT/hooks/claude-identity/_watch.py"
PYBIN="${PYBIN:-python3}"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export AIOS_HEALTH_DIR="$T/health"
# The watcher is imported below: never let a test reach the desktop notifier (watch-notify-isolation).
export AIOS_QUOTA_NOTIFY=0
hw(){ $PYBIN "$H" "$@"; }
rep(){ $PYBIN "$H" report; }
# Rewrite a stored file's stamps, to stand in for time passing.
age(){ $PYBIN - "$AIOS_HEALTH_DIR/$1.json" "$2" "$3" <<'PY'
import json, sys
p, w, u = sys.argv[1:]
r = json.load(open(p)); r["written_at"] = w; r["valid_until"] = u
json.dump(r, open(p, "w"))
PY
}

echo "── no checks, nothing said ──"
out=$(rep); rc=$?
[ -z "$out" ] && [ "$rc" = 0 ] && ok "no health directory: silent, exit 0" || no "reported with no checks" "$out"

echo "── a healthy job is silent; a failed one is said ──"
hw write job-a ok --valid-for 90m --detail "all good"
[ -z "$(rep)" ] && ok "ok within its deadline: silent" || no "an ok job was reported" "$(rep)"
[ -z "$(ls -A "$AIOS_HEALTH_DIR" | grep '\.tmp$')" ] && ok "no temp file left behind (atomic replace)" || no "temp files left" "$(ls -A "$AIOS_HEALTH_DIR")"
hw write job-a fail --valid-for 90m --detail "could not read the cache"
case "$(rep)" in *"job-a: fail: could not read the cache"*) ok "a failed run is reported with its detail" ;; *) no "fail not reported" "$(rep)" ;; esac
hw write job-a warn --valid-for 90m --detail "slow"
case "$(rep)" in *"job-a: warn: slow"*) ok "a warning is reported" ;; *) no "warn not reported" "$(rep)" ;; esac

echo "── a job that stopped running is caught by its deadline ──"
hw write job-a ok --valid-for 90m
age job-a 2026-01-01T08:00:00Z 2026-01-01T09:30:00Z
out=$(rep)
case "$out" in *"job-a: no result since"*) ok "past its deadline: \"no result since ...\"" ;; *) no "an overdue job was not reported" "$out" ;; esac
case "$out" in *"did not run"*|*"didn't run"*) no "the reader claimed the job did not run" "$out" ;; *) ok "never claims the job did not run (it may have run and failed to write)" ;; esac
hw write job-a fail --valid-for 90m --detail "boom"; age job-a 2026-01-01T08:00:00Z 2026-01-01T09:30:00Z
case "$(rep)" in *"no result since"*"(last result: fail: boom)"*) ok "overdue after a failure keeps the last result as history" ;; *) no "last failure lost" "$(rep)" ;; esac

echo "── registered at install: a job that never runs shows up ──"
hw write job-b pending --valid-for 45m --detail "installed"
case "$(rep)" in *job-b*) no "a pending job still within its deadline was reported" "$(rep)" ;; *) ok "pending, not yet due: silent" ;; esac
age job-b 2026-01-01T08:00:00Z 2026-01-01T08:45:00Z
case "$(rep)" in *"job-b: installed but no completed run yet"*) ok "pending past its deadline: installed but never completed" ;; *) no "a never-run job is invisible" "$(rep)" ;; esac

echo "── an unreadable file is reported, never skipped ──"
printf 'not json' > "$AIOS_HEALTH_DIR/bad-json.json"
printf '{"name":"x","state":"ok"}' > "$AIOS_HEALTH_DIR/missing-field.json"
printf '{"name":"x","state":"great","detail":"","written_at":"2026-01-01T08:00:00Z","valid_until":"2026-01-01T09:00:00Z"}' > "$AIOS_HEALTH_DIR/bad-state.json"
printf '{"name":"x","state":"ok","detail":"","written_at":"2026-01-01T09:00:00Z","valid_until":"2026-01-01T08:00:00Z"}' > "$AIOS_HEALTH_DIR/backwards.json"
out=$(rep)
for n in bad-json missing-field bad-state backwards; do
  case "$out" in *"unreadable health file: $n"*) ok "unreadable: $n" ;; *) no "unreadable file skipped: $n" "$out" ;; esac
done
case "$out" in *"job-a"*) ok "other checks still render beside unreadable ones" ;; *) no "an unreadable file hid the others" "$out" ;; esac

echo "── arguments are refused, not guessed ──"
hw write "Bad Name" ok --valid-for 1h 2>/dev/null; [ $? = 2 ] && ok "a bad name exits 2" || no "bad name accepted"
hw write job-c great --valid-for 1h 2>/dev/null; [ $? = 2 ] && ok "an unknown state exits 2" || no "bad state accepted"
hw write job-c ok --valid-for 0m 2>/dev/null; [ $? = 2 ] && ok "a zero deadline exits 2" || no "zero duration accepted"
hw write job-c ok --valid-for soon 2>/dev/null; [ $? = 2 ] && ok "an unreadable duration exits 2" || no "bad duration accepted"
[ ! -e "$AIOS_HEALTH_DIR/job-c.json" ] && ok "a refused write leaves no file" || no "a refused write wrote a file"

echo "── retiring a check removes it ──"
hw retire job-b; [ ! -e "$AIOS_HEALTH_DIR/job-b.json" ] && ok "retire removes the file" || no "retire left the file"

echo "── every way to unschedule the watcher also retires its check ──"
# Registered at install as pending, so a removal that forgets to retire it reads "overdue" forever.
for f in hooks/claude-identity/com.aios.claude-quota-watch.plist hooks/claude-identity/aios-claude-quota-watch.service hooks/claude-identity/install-quota-watch.ps1; do
  # Either through the tool, or (the PowerShell installer, which has no python to rely on) by
  # removing the file the tool would remove.
  grep -q 'aios-health.py retire quota-watch\|Remove-Item .*health.quota-watch\.json' "$ROOT/$f" \
    && ok "$(basename "$f") retires quota-watch on removal" || no "$(basename "$f") removes the watcher but leaves its health check"
done

echo "── the quota watcher writes its own verdict ──"
PYW=""; for c in python3.13 python3.12 python3.11 python3.10 python3; do
  command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' 2>/dev/null && { PYW="$c"; break; }
done
if [ -z "$PYW" ]; then echo "  - skip: no python >= 3.9 to import _watch.py"
else
  for crashed in False True; do
    out=$(HOME="$T/home" AIOS_HEALTH_DIR="$T/wh-$crashed" "$PYW" - "$W" "$crashed" <<'PY'
import importlib.util, json, os, sys
s = importlib.util.spec_from_file_location("w", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
m.CRASHED = sys.argv[2] == "True"; m.LAST_LOG = "cache stale; skip"
m.record_health()
r = json.load(open(os.path.join(os.environ["AIOS_HEALTH_DIR"], "quota-watch.json")))
print(r["state"], r["detail"])
PY
)
    want=$([ "$crashed" = True ] && echo "fail cache stale; skip" || echo "ok cache stale; skip")
    [ "$out" = "$want" ] && ok "watcher run (crashed=$crashed) records: $want" || no "watcher health wrong (crashed=$crashed)" "$out"
  done
  grep -q '    main(sys.argv\[1\])$' "$W" && grep -A1 '    main(sys.argv\[1\])$' "$W" | grep -q 'record_health()' \
    && ok "the watcher records health right after a completed run" || no "record_health is not called after main()"
fi

echo
printf -- '-- %d passed, %d failed --\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
