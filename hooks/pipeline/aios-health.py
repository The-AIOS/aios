#!/usr/bin/env python3
"""aios-health.py — one small status file per scheduled job, with a deadline.

WHY. A job that runs with nobody watching fails two ways. It runs and fails, and the evidence sits
in a log no ritual reads. Or it stops running (an unloaded agent, a disabled timer, a reinstall
that dropped the unit), and then nothing writes anything: silence reads exactly like "fine". A
file with a deadline catches both. The job writes its verdict at the END of a completed run, and
says by when the next one is due; a reader that finds the deadline passed reports "no result
since ...", which needs nothing from the job that stopped.

The contract (proposed in #171, adopted here), one JSON file per check in ~/.aios/health/:

  {"name": "quota-watch", "state": "ok", "detail": "one line, never a secret",
   "written_at": "2026-10-16T14:00:00Z", "valid_until": "2026-10-16T15:30:00Z"}

Writer rules: write only at the end of a completed run, with the verdict; the writer sets
valid_until (next expected completion + grace), because only it knows its cadence; one owner per
name; atomic replace (temp file in the same directory, then rename). The installer that schedules
a job registers it with state "pending", so a job that never runs at all shows up as overdue.

Reader rules: past valid_until -> "no result since {written_at}", never "didn't run" (it may have
run and failed to write). An unreadable file is reported, never skipped. No directory, no files:
nothing is reported. Machine-local: never inside the vault, never committed.

USAGE
  aios-health.py write  NAME ok|warn|fail|pending --valid-for 90m [--detail "..."]
  aios-health.py report [--json]          one line per check that needs attention; nothing when all are fine
  aios-health.py retire NAME              remove a check whose job was unscheduled (do that first)

$AIOS_HEALTH_DIR overrides ~/.aios/health. Exit: 0 on success (report always exits 0: it informs,
it never blocks a ritual) · 2 on a bad argument.
"""
import argparse
import datetime as dt
import json
import os
import re
import sys
import tempfile

STATES = ("ok", "warn", "fail", "pending")
NAME = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
FIELDS = ("name", "state", "detail", "written_at", "valid_until")


def health_dir():
    return os.environ.get("AIOS_HEALTH_DIR") or os.path.join(os.path.expanduser("~"), ".aios", "health")


def now():
    return dt.datetime.now(dt.timezone.utc)


def iso(t):
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso(s):
    return dt.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)


def local(s):
    """A stored UTC stamp, shown in the reader's local time."""
    try:
        return parse_iso(s).astimezone().strftime("%Y-%m-%d %H:%M")
    except (TypeError, ValueError):
        return str(s)


def duration(s):
    m = re.fullmatch(r"(\d+)([smhd])", s.strip())
    if not m or int(m.group(1)) == 0:
        raise ValueError("duration must look like 45m, 2h or 1d, and be more than zero: %r" % s)
    return dt.timedelta(seconds=int(m.group(1)) * {"s": 1, "m": 60, "h": 3600, "d": 86400}[m.group(2)])


def check_name(name):
    if not NAME.match(name):
        raise ValueError("name must be lowercase letters, digits and dashes: %r" % name)


def write(name, state, valid_for, detail=""):
    """Atomically record a completed run's verdict. Raises ValueError on a bad argument."""
    check_name(name)
    if state not in STATES:
        raise ValueError("state must be one of %s: %r" % (", ".join(STATES), state))
    t = now()
    payload = {"name": name, "state": state, "detail": " ".join(str(detail).split())[:300],
               "written_at": iso(t), "valid_until": iso(t + duration(valid_for))}
    d = health_dir()
    os.makedirs(d, mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix="." + name + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False)
            f.write("\n")
        os.replace(tmp, os.path.join(d, name + ".json"))
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return payload


def retire(name):
    check_name(name)
    try:
        os.unlink(os.path.join(health_dir(), name + ".json"))
        return True
    except FileNotFoundError:
        return False


def rows(at=None):
    """One row per health file: {name, status, ...}. status is ok | waiting | warn | fail |
    overdue | unreadable. Never raises for a bad file: it becomes an 'unreadable' row."""
    at = at or now()
    d = health_dir()
    try:
        files = sorted(f for f in os.listdir(d) if f.endswith(".json") and not f.startswith("."))
    except FileNotFoundError:
        return []
    out = []
    for f in files:
        name = f[:-5]
        try:
            with open(os.path.join(d, f), encoding="utf-8") as h:
                rec = json.load(h)
            if not isinstance(rec, dict) or any(k not in rec for k in FIELDS) or rec["state"] not in STATES:
                raise ValueError("missing field or unknown state")
            written, until = parse_iso(rec["written_at"]), parse_iso(rec["valid_until"])
            if until <= written:
                raise ValueError("valid_until is not after written_at")
        except (OSError, ValueError, TypeError) as e:
            out.append({"name": name, "status": "unreadable", "why": str(e)[:120]})
            continue
        row = dict(rec)
        if at > until:
            row["status"] = "overdue"
        else:
            row["status"] = {"ok": "ok", "pending": "waiting"}.get(rec["state"], rec["state"])
        out.append(row)
    return out


def line(r):
    """The plain sentence a ritual prints for a check that needs attention, or None."""
    s = r["status"]
    if s == "unreadable":
        return "unreadable health file: %s (%s)" % (r["name"], r["why"])
    if s == "overdue":
        if r["state"] == "pending":
            return "%s: installed but no completed run yet (one was expected by %s)" % (r["name"], local(r["valid_until"]))
        last = "" if r["state"] == "ok" else " (last result: %s%s)" % (r["state"], ": " + r["detail"] if r["detail"] else "")
        return "%s: no result since %s%s" % (r["name"], local(r["written_at"]), last)
    if s in ("warn", "fail"):
        return "%s: %s%s (%s)" % (r["name"], s, ": " + r["detail"] if r["detail"] else "", local(r["written_at"]))
    return None


def main(argv):
    ap = argparse.ArgumentParser(prog="aios-health.py", description=__doc__.split("\n")[0])
    sp = ap.add_subparsers(dest="cmd", required=True)
    w = sp.add_parser("write"); w.add_argument("name"); w.add_argument("state")
    w.add_argument("--valid-for", required=True); w.add_argument("--detail", default="")
    r = sp.add_parser("report"); r.add_argument("--json", action="store_true")
    t = sp.add_parser("retire"); t.add_argument("name")
    a = ap.parse_args(argv)
    try:
        if a.cmd == "write":
            write(a.name, a.state, a.valid_for, a.detail)
        elif a.cmd == "retire":
            if not retire(a.name):
                print("no health file named %s" % a.name)
        else:
            rs = rows()
            if a.json:
                print(json.dumps(rs, indent=2, ensure_ascii=False))
            else:
                for r in rs:
                    s = line(r)
                    if s:
                        print("⚠️  " + s)
    except ValueError as e:
        sys.stderr.write("aios-health: %s\n" % e)
        return 2
    return 0


if __name__ == "__main__":
    for _s in (sys.stdout, sys.stderr):
        try:
            _s.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError, OSError):
            pass
    sys.exit(main(sys.argv[1:]))
