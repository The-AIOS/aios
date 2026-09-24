#!/usr/bin/env bash

# ── Resolve a python that RUNS (Windows) ─────────────────────────────────────
# Same probe as tests/buffer-status.test.sh: on Windows `python3` may be the
# Microsoft Store alias, which exits without running anything.
PYBIN=""
for _cand in python3 python "py -3"; do
  if $_cand -c 'import sys' >/dev/null 2>&1; then PYBIN="$_cand"; break; fi
done
if [ -z "$PYBIN" ]; then
  echo "SKIP: no working Python found (tried python3, python, py -3)" >&2
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# hooks/pipeline-executor.py — the calendar LOOKAHEAD reaches /today, dated
#
# Until this change the multi-day window was fetched only for /close-day, so
# /today saw one day of live calendar and took every later date from the vault.
# When a meeting moved, the vault's copies kept the old date and nothing
# errored. The lookahead now runs for every command, and it is rendered with a
# `**YYYY-MM-DD (Weekday)**` header per day — a flat list of bare `14:00 – 18:00`
# lines cannot say WHICH day, which is the one thing a lookahead is for.
#
# Properties under test (no network — the renderer is a pure function):
#   * events group under one header per day, in order, headers never repeat
#   * the weekday is English and locale-independent
#   * the day of a timed event follows its local instant, same rule as the sort
#   * a single-day render (dated=False) carries no headers
#   * the per-calendar cap scales with the window instead of truncating at 50
#   * the header the executor prints is the one today.md and close-day.md quote
#   * the lookahead is no longer gated on close-day
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

H="hooks/pipeline-executor.py"
[ -f "$H" ] || { printf '  FAIL  %s missing\n' "$H"; exit 1; }

run_py(){ $PYBIN - "$@" <<'PYEOF'
import importlib.util, io, re, sys
spec = importlib.util.spec_from_file_location("pe", "hooks/pipeline-executor.py")
pe = importlib.util.module_from_spec(spec); spec.loader.exec_module(pe)

checks = []
def eq(label, got, want):
    checks.append((label, got == want, f"got {got!r}, want {want!r}"))

def ev(summary, start, end=None, uid=None):
    if len(start) == 10:
        s, e = {"date": start}, {"date": end or start}
    else:
        s, e = {"dateTime": start}, {"dateTime": end or start}
    return {"summary": summary, "start": s, "end": e, "iCalUID": uid or summary}

ME = "me@example.com"
def order(events, cal=ME, name="Primary"):
    return [(pe._event_key(e), (cal, name, e)) for e in events]

# Offsets carried on the instants, timezone_name=None: renders each event in its
# own offset, so the test needs no tz database (absent on stock Windows Python).
events = [
    ev("Review", "2026-09-26T09:00:00+02:00", "2026-09-26T10:00:00+02:00"),
    ev("Standup", "2026-09-24T09:00:00+02:00", "2026-09-24T09:15:00+02:00"),
    ev("Offsite", "2026-09-24"),
    ev("Planning", "2026-09-24T14:00:00+02:00", "2026-09-24T15:00:00+02:00"),
    ev("Retro", "2026-09-26T16:00:00+02:00", "2026-09-26T17:00:00+02:00"),
]
out = pe._render_calendar(order(events), ME, None, dated=True)
lines = out.split("\n")
headers = [l for l in lines if l.startswith("**")]

# 1. One header per day, in order, never repeated.
eq("one header per day, chronological",
   headers, ["**2026-09-24 (Thursday)**", "**2026-09-26 (Saturday)**"])
# 2. Each event lands under its own day, all-day first.
eq("events sit under their day, all-day first",
   [l for l in lines if l.strip()],
   ["**2026-09-24 (Thursday)**",
    "- All day — Offsite",
    "- 09:00 – 09:15 — Standup",
    "- 14:00 – 15:00 — Planning",
    "**2026-09-26 (Saturday)**",
    "- 09:00 – 10:00 — Review",
    "- 16:00 – 17:00 — Retro"])
# 3. No leading blank line before the first header.
eq("block does not open with a blank line", lines[0], "**2026-09-24 (Thursday)**")

# 4. Single-day render: no headers at all (every line is trivially today).
flat = pe._render_calendar(order(events[1:2]), ME, None, dated=False)
eq("dated=False carries no day header", flat, "- 09:00 – 09:15 — Standup")

# 5. The day of a timed event follows its LOCAL instant (00:30 local on the
#    25th, written as 22:30Z on the 24th). Needs a tz database; skipped without.
try:
    from zoneinfo import ZoneInfo
    ZoneInfo("Europe/Madrid")
    have_tz = True
except Exception:
    have_tz = False
if have_tz:
    late = pe._render_calendar(order([ev("Late call", "2026-09-24T22:30:00Z", "2026-09-24T23:00:00Z")]),
                               ME, "Europe/Madrid", dated=True)
    eq("header follows the local instant, not the raw string",
       late.split("\n")[0], "**2026-09-25 (Friday)**")
else:
    print("SKIP\tlocal-instant header (no tz database on this Python)")

# 6. English weekdays, whatever the process locale.
import locale
try:
    locale.setlocale(locale.LC_TIME, "")
except Exception:
    pass
eq("weekday is English", [pe._weekday_name(d) for d in
   ("2026-09-21", "2026-09-22", "2026-09-23", "2026-09-24", "2026-09-25", "2026-09-26", "2026-09-27")],
   ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"])
eq("malformed day degrades, never raises", pe._weekday_name("not-a-date"), "?")

# 7. The per-calendar cap scales with the window.
eq("single day keeps the 50 cap",
   pe._per_calendar_cap("2026-09-24T00:00:00+02:00", "2026-09-24T23:59:59+02:00"), 50)
eq("15-day window: 25/day",
   pe._per_calendar_cap("2026-09-24T00:00:00+02:00", "2026-10-08T23:59:59+02:00"), 250)
eq("7-day window: 25/day",
   pe._per_calendar_cap("2026-09-24T00:00:00+02:00", "2026-09-30T23:59:59+02:00"), 175)
eq("cap never exceeds the API page ceiling",
   pe._per_calendar_cap("2026-09-01T00:00:00Z", "2026-12-31T23:59:59Z"), 250)

# 8. The header the executor prints is the header the docs quote — exactly.
src = io.open("hooks/pipeline-executor.py", encoding="utf-8").read()
m = re.search(r'LOOKAHEAD_DAYS = (\d+)', src)
days = m.group(1) if m else "?"
printed = f"## Google Calendar — Next {days} days (AUTHORITATIVE — reconcile vault dates against this)"
checks.append(("executor prints the AUTHORITATIVE lookahead header",
               'f"## Google Calendar — Next {LOOKAHEAD_DAYS} days (AUTHORITATIVE — reconcile vault dates against this)"' in src,
               "header text changed in the executor"))
for doc in ("plugins/aios/commands/today.md", "plugins/aios/commands/close-day.md"):
    text = io.open(doc, encoding="utf-8").read()
    checks.append((f"{doc.split('/')[-1]} quotes the printed header verbatim", printed[3:] in text,
                   f"expected: {printed}"))
    stale = re.findall(r"Google Calendar — Next (\d+) days", text)
    checks.append((f"{doc.split('/')[-1]} names no other lookahead length",
                   all(d == days for d in stale), f"found {stale}, executor uses {days}"))

# 9. The lookahead is fetched for every command, not only close-day.
checks.append(("lookahead is not gated on close-day",
               re.search(r'if is_close_day:\s*\n\s*futures\["calendar_next_week"\]', src) is None
               and 'futures["calendar_next_week"] = pool.submit(' in src,
               "calendar_next_week is still fetched only for close-day"))
checks.append(("lookahead is rendered dated",
               re.search(r'time_max_week,\s*\n[^)]*dated=True', src) is not None,
               "the lookahead call does not pass dated=True"))

for label, good, detail in checks:
    print(("OK\t" if good else "NO\t") + label + ("" if good else "\t" + detail))
PYEOF
}

# The probe's own exit status is load-bearing: if the helpers do not exist,
# python aborts and a loop that only reads stdout would report 0/0 and pass.
OUT="$(run_py)"; RC=$?
if [ "$RC" -ne 0 ]; then
  no "probe ran to completion" "python exited $RC -- helpers missing or module unloadable"
  printf '%s\n' "$OUT" | sed 's/^/        /'
else
  while IFS=$'\t' read -r verdict label detail; do
    [ -z "$verdict" ] && continue
    case "$verdict" in
      OK) ok "$label" ;;
      SKIP) printf '  SKIP  %s\n' "$label" ;;
      *) no "$label" "${detail:-}" ;;
    esac
  done <<< "$OUT"
  [ $((PASS + FAIL)) -eq 0 ] && no "probe emitted checks" "no checks ran -- silent no-op"
fi

printf '\n  %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
