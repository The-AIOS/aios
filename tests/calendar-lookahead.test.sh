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
#   * the lookahead merges every configured account, de-duplicated and tagged
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

# 6b. A multi-day all-day event sits under EVERY day it covers (#243). end.date is
#     exclusive: Wed 23 to Sat 26 is Wed, Thu, Fri. Listing it on Wednesday only
#     made Thursday and Friday read as free in a block marked AUTHORITATIVE.
from datetime import date
conf = ev("Conference", "2026-09-23", "2026-09-26")
call = ev("Call", "2026-09-24T09:00:00+02:00", "2026-09-24T09:30:00+02:00")
multi = pe._render_calendar(order([conf, call]), ME, None, dated=True,
                            window=(date(2026, 9, 23), date(2026, 10, 7)))
eq("a 3-day all-day event is listed on each of its days",
   [l for l in multi.split("\n") if l.strip()],
   ["**2026-09-23 (Wednesday)**",
    "- All day — Conference (day 1 of 3)",
    "**2026-09-24 (Thursday)**",
    "- All day — Conference (day 2 of 3)",
    "- 09:00 – 09:30 — Call",
    "**2026-09-25 (Friday)**",
    "- All day — Conference (day 3 of 3)"])
# An event that began before the window shows from the window's first day,
# numbered from its real start; days past the window are not listed.
early = pe._render_calendar(order([ev("Trip", "2026-09-20", "2026-09-26")]), ME, None, dated=True,
                            window=(date(2026, 9, 23), date(2026, 9, 24)))
eq("an event that began before the window starts at the window, numbered from its start",
   [l for l in early.split("\n") if l.strip()],
   ["**2026-09-23 (Wednesday)**", "- All day — Trip (day 4 of 6)",
    "**2026-09-24 (Thursday)**", "- All day — Trip (day 5 of 6)"])
# The single-day block keeps one row, and says which day of the span today is.
today_only = pe._render_calendar(order([ev("Trip", "2026-09-20", "2026-09-26")]), ME, None,
                                 window=(date(2026, 9, 23), date(2026, 9, 23)))
eq("the today block keeps one row and names the day of the span",
   today_only, "- All day — Trip (day 4 of 6)")
# A one-day all-day event is unchanged: no span tag.
eq("a one-day all-day event carries no span tag",
   pe._render_calendar(order([ev("Holiday", "2026-09-23", "2026-09-24")]), ME, None, dated=True,
                       window=(date(2026, 9, 23), date(2026, 9, 30))).split("\n")[1],
   "- All day — Holiday")
checks.append(("the fetch passes its window to the renderer",
               "window=(_date_only(time_min), _date_only(time_max))" in
               io.open("hooks/pipeline-executor.py", encoding="utf-8").read(),
               "google_calendar_events does not pass window="))

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

# 10. The lookahead merges every account into one block (fake Google, no network).
#     Shared meetings appear once, as the primary's; further accounts' events are
#     tagged with their label; one unreadable account is an error line, not a lost block.
import types
CALS = {
    "P": [("me@example.com", True, "me@example.com")],
    "Q": [("me@personal.example", True, "me@personal.example")],
    "A": [("me@acme.example", True, "me@acme.example"), ("team@acme.example", False, "Team")],
}
EVENTS = {
    "me@example.com": [ev("Board", "2026-09-24T10:00:00Z", "2026-09-24T11:00:00Z", uid="shared-1")],
    "me@personal.example": [ev("Board", "2026-09-24T10:00:00Z", "2026-09-24T11:00:00Z", uid="shared-1"),
                            ev("Dentist", "2026-09-25T08:00:00Z", "2026-09-25T09:00:00Z")],
    "me@acme.example": [ev("Acme sync", "2026-09-26T15:00:00Z", "2026-09-26T16:00:00Z")],
    "team@acme.example": [ev("Acme standup", "2026-09-27T12:00:00Z", "2026-09-27T12:15:00Z")],
}
class _X:
    def __init__(self, v): self.v = v
    def execute(self):
        if isinstance(self.v, Exception): raise self.v
        return self.v
class _Svc:
    def __init__(self, key): self.key = key
    def calendarList(self):
        cals = CALS[self.key]
        return types.SimpleNamespace(list=lambda **k: _X({"items": [
            {"id": i, "primary": prim, "summary": name} for i, prim, name in cals]}))
    def events(self):
        return types.SimpleNamespace(list=lambda calendarId, **k: _X({"items": EVENTS[calendarId]}))
def _build(api, ver, credentials=None, cache_discovery=False):
    if credentials == "BROKEN": raise RuntimeError("token expired")
    return _Svc(credentials)
disc = types.ModuleType("googleapiclient.discovery"); disc.build = _build
sys.modules.setdefault("googleapiclient", types.ModuleType("googleapiclient"))
sys.modules["googleapiclient.discovery"] = disc
pe._load_google_creds = lambda path: path
merged = pe.google_calendar_events(
    "P", "me@example.com", "2026-09-24T00:00:00Z", "2026-10-07T23:59:59Z", dated=True,
    timezone_name="UTC",
    also=[("personal", "Q", "me@personal.example"), ("Acme.Labs", "A", "me@acme.example")])
rows = [l for l in merged.split("\n") if l.startswith("- ")]
eq("a meeting on two accounts appears once, untagged (the primary's)",
   [r for r in rows if "Board" in r], ["- 10:00 – 11:00 — Board"])
eq("a personal-only event is tagged [personal]",
   [r for r in rows if "Dentist" in r], ["- 08:00 – 09:00 — Dentist  _[personal]_"])
eq("a labelled account's own calendar is tagged with its label",
   [r for r in rows if "Acme sync" in r], ["- 15:00 – 16:00 — Acme sync  _[Acme.Labs]_"])
eq("a labelled account's other calendar names label and calendar",
   [r for r in rows if "standup" in r], ["- 12:00 – 12:15 — Acme standup  _[Acme.Labs · Team]_"])
partial = pe.google_calendar_events(
    "P", "me@example.com", "2026-09-24T00:00:00Z", "2026-10-07T23:59:59Z", dated=True,
    timezone_name="UTC", also=[("Acme.Labs", "BROKEN", "me@acme.example")])
checks.append(("an unreadable further account is one error line; the primary still renders",
               "account 'Acme.Labs' (me@acme.example) could not be read: token expired" in partial
               and "Board" in partial, partial))
# 11. The same meeting seen through two accounts whose calendars report different offsets
#     (+02:00 on one, Z on the other: the same instant) is still one meeting.
EVENTS["me@example.com"].append(ev("Offsite", "2026-09-28T08:00:00Z", "2026-09-28T09:00:00Z", uid="shared-2"))
EVENTS["me@personal.example"].append(ev("Offsite", "2026-09-28T10:00:00+02:00", "2026-09-28T11:00:00+02:00", uid="shared-2"))
tz_merged = pe.google_calendar_events(
    "P", "me@example.com", "2026-09-24T00:00:00Z", "2026-10-07T23:59:59Z", dated=True,
    timezone_name="UTC", also=[("personal", "Q", "me@personal.example")])
eq("a shared meeting in two offsets appears once",
   len([l for l in tz_merged.split("\n") if "Offsite" in l]), 1)

# 12. A further account that is slow is an error line inside the block, and the block still
#     arrives well inside the executor's own timeout: the accounts are read side by side,
#     so one slow token cannot take the primary's events down with it.
import time as _t
_real_build = disc.build
def _slow_build(api, ver, credentials=None, cache_discovery=False):
    if credentials == "SLOW":
        _t.sleep(3)
    return _real_build(api, ver, credentials=credentials, cache_discovery=cache_discovery)
disc.build = _slow_build
pe.ACCOUNT_FETCH_DEADLINE = 1
CALS["SLOW"] = CALS["Q"]
_t0 = _t.monotonic()
slow = pe.google_calendar_events(
    "P", "me@example.com", "2026-09-24T00:00:00Z", "2026-10-07T23:59:59Z", dated=True,
    timezone_name="UTC", also=[("personal", "SLOW", "me@personal.example")])
_took = _t.monotonic() - _t0
disc.build = _real_build
checks.append(("a slow further account is an error line, and the primary still renders",
               "account 'personal' (me@personal.example) could not be read" in slow and "Board" in slow,
               repr(slow[-240:])))
checks.append(("the merged block does not wait for the slow account", _took < 2.5, f"took {_took:.1f}s"))

checks.append(("the executor passes the further accounts to the lookahead",
               "timezone_name=render_tz, also=lookahead_also" in src
               and 'lookahead_also.append(("personal", creds_personal' in src,
               "calendar_next_week is not given also=lookahead_also"))

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
