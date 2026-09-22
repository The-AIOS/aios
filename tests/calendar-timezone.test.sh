#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# hooks/pipeline-executor.py — calendar times land in the operator's timezone
#
# Google does not return one shape for `dateTime`. A calendar that carries a
# timezone yields a local offset (`2026-09-22T15:00:00+02:00`). A calendar
# SUBSCRIBED from an ICS feed (`…@import.calendar.google.com` — an Outlook/M365
# mirror is the common case) is normalised to UTC and yields `…T13:00:00Z`,
# because a subscribed feed is not the account's to place. Both encode the same
# correct instant.
#
# The renderer used to slice the string (`dateTime[:16]`), which reads the UTC
# instant as if it were already local. Every mirrored event then rendered
# shifted by the account's own offset — measured at −2h on a live Europe/Madrid
# vault, across an entire working week.
#
# What makes it worth a gate rather than a note: it fails SILENTLY and
# SELECTIVELY. The native calendars beside it stay correct, so the day's plan
# looks internally consistent and nothing about the output says it is wrong.
#
# Properties under test: a Z-instant renders in the operator's timezone; an
# offset-instant is untouched; the same instant written both ways renders
# identically (the mirror/native pair must collapse to one time); the DAY
# boundary is decided by the local instant, not by the raw string; and a
# malformed value degrades instead of taking the day's plan down.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

H="hooks/pipeline-executor.py"
[ -f "$H" ] || { printf '  FAIL  %s missing\n' "$H"; exit 1; }

run_py(){ python3 - "$@" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("pe", "hooks/pipeline-executor.py")
pe = importlib.util.module_from_spec(spec); spec.loader.exec_module(pe)

checks = []
def eq(label, got, want):
    checks.append((label, got == want, f"got {got!r}, want {want!r}"))

TZ = "Europe/Madrid"

# 1. ICS-subscribed mirror: stored UTC, must render local.
eq("Z-instant renders local (summer, +02:00)",
   pe._local_hhmm("2026-09-21T10:10:00Z", TZ), "12:10")
eq("Z-instant renders local (winter, +01:00)",
   pe._local_hhmm("2026-01-21T10:10:00Z", TZ), "11:10")

# 2. Native calendar: already local, must be untouched.
eq("offset-instant untouched",
   pe._local_hhmm("2026-09-22T15:00:00+02:00", TZ), "15:00")

# 3. The mirror/native duplicate pair must agree. This is the property that
#    makes de-duplication possible at all: two spellings of one instant.
eq("mirror and native agree on one instant",
   pe._local_hhmm("2026-09-22T13:00:00Z", TZ),
   pe._local_hhmm("2026-09-22T15:00:00+02:00", TZ))

# 4. An event whose TZID field is foreign (an ICS mirror carries the source's
#    raw TZID — Africa/Ceuta, America/New_York) must still render by its
#    instant. Trusting that field is how a New York TZID becomes a 6h error.
eq("foreign TZID field does not steer rendering",
   pe._local_hhmm("2026-09-23T14:00:00Z", TZ), "16:00")

# 5. Day boundary: 00:30 local on the 22nd is stored as 22:30Z on the 21st.
#    Sorting on the raw string files it under the 21st.
inst = pe._event_instant("2026-09-21T22:30:00Z", TZ)
eq("day boundary follows the local instant", inst.strftime("%Y-%m-%d"), "2026-09-22")

# 6. Degrade, never raise.
eq("malformed value degrades to slicing", pe._local_hhmm("not-a-date", TZ), "")
eq("empty value degrades", pe._local_hhmm("", TZ), "")
eq("unknown timezone does not raise",
   pe._local_hhmm("2026-09-21T10:10:00Z", "Mars/Olympus"), "10:10")

# 7. The renderer must not go back to slicing.
src = open("hooks/pipeline-executor.py").read()
checks.append(("renderer does not slice dateTime[:16]",
               'start.get("dateTime", "")[:16].split("T")' not in src,
               "the string-slicing renderer is back"))
checks.append(("google_calendar_events accepts timezone_name",
               "def google_calendar_events(" in src and "timezone_name" in src,
               "timezone never reaches the calendar renderer"))

# 8. NO TIMEZONE CONFIGURED must be no worse than before this converter existed.
#    Converting to the "UTC" default shifted every meeting on a calendar the operator
#    OWNS (which reports a local offset) by that offset. None = the event's own offset.
eq("unconfigured: an owned event renders in its own offset",
   pe._local_hhmm("2026-09-22T14:00:00-05:00", None), "14:00")
eq("unconfigured: a subscribed (UTC) event is no worse than before",
   pe._local_hhmm("2026-09-22T19:00:00Z", None), "19:00")
# CONTROL — the old behaviour (the "UTC" default) must give a DIFFERENT answer, or
# check 8 cannot tell the fallback from the regression it replaces.
eq("control: the UTC default would shift that owned event to 19:00",
   pe._local_hhmm("2026-09-22T14:00:00-05:00", "UTC"), "19:00")

# 9. parse_sources records whether the timezone was actually set.
import tempfile, pathlib
def parsed(text):
    d = pathlib.Path(tempfile.mkdtemp()); f = d / "USER.md"; f.write_text(text, encoding="utf-8")
    pe.SOURCES_PATH = f
    return pe.parse_sources()
cfg = parsed("## Sources\n### General\n- Timezone: `America/Chicago`\n")
eq("a real Timezone line is configured", (cfg["timezone"], cfg.get("timezone_configured")), ("America/Chicago", True))
cfg = parsed("## Sources\n### General\n")
eq("an absent line is NOT configured (and queries keep UTC)", (cfg["timezone"], cfg.get("timezone_configured")), ("UTC", False))
cfg = parsed("## Sources\n### General\n- *Timezone: `America/Your_Timezone`*\n")
eq("the template's italic placeholder is NOT read as configured", cfg.get("timezone_configured"), False)

# 10. The three calendar RENDER calls use the configured-or-None value; the Slack recap
#     and the query window keep the raw value. (Source-level: the wiring, not behaviour —
#     behaviour is checks 8-9.)
checks.append(("calendar render calls use render_tz, not the raw default",
               src.count("timezone_name=render_tz") == 3 and 'timezone_name=sources["timezone"]' not in src,
               "a render call still passes the UTC default straight through"))

for label, good, detail in checks:
    print(("OK\t" if good else "NO\t") + label + ("" if good else "\t" + detail))
PYEOF
}

# The probe's own exit status is load-bearing. Against the pre-fix renderer the
# helpers do not exist, python aborts, and a loop that only reads stdout would
# report "0 passed, 0 failed" and exit 0 -- a gate that certifies the very bug it
# exists to catch. So: capture the status, and require that checks actually ran.
OUT="$(run_py)"; RC=$?
if [ "$RC" -ne 0 ]; then
  no "probe ran to completion" "python exited $RC -- helpers missing or module unloadable"
  printf '%s\n' "$OUT" | sed 's/^/        /'
else
  while IFS=$'\t' read -r verdict label detail; do
    [ -z "$verdict" ] && continue
    if [ "$verdict" = "OK" ]; then ok "$label"; else no "$label" "${detail:-}"; fi
  done <<< "$OUT"
  [ $((PASS + FAIL)) -eq 0 ] && no "probe emitted checks" "no checks ran -- silent no-op"
fi

printf '\n  %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
