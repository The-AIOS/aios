#!/usr/bin/env python3
"""model-switch-log.py — record when a session's model changes under it (PostModelSwitch hook).

WHY. An unattended worker can be moved to another model without anyone watching — a fallback when
the requested model is unavailable or rate-limited, a switch mid-session. The work then runs on a
model nobody chose, and nothing reports it. This hook appends one line per switch so
/close-session, /close-day and the App can say so.

FORMAT (the shape readers build against): ~/.aios/model-switch.jsonl, one JSON object per line:

    {"at": "2026-10-11T21:40:00Z", "session_id": "<id>", "name": "<registry name or empty>",
     "from": "<model id or empty>", "to": "<model id>", "requested": "<model id or empty>",
     "reason": "<string or empty>"}

  - `at` is UTC, ISO 8601, written by this hook (never taken from the payload).
  - `name` is the session's registry name from ~/.claude/sessions/*.json, empty when unnamed.
  - Unknown values are empty strings, never omitted keys, so readers can index every field.

  - `requested` is the model the session asked for; `from` -> `to` is the switch itself. A row where
    `to` differs from `requested` is the one to read: the work finished on a model nobody chose.
  - `reason` is the payload's `source` (what caused the switch, e.g. a user /model or a fallback).

Payload (checked against Claude Code 2.1.296): `from_model`, `to_model`, `requested_model`,
`source`, plus the common `session_id`. Older spellings are still read, so a renamed field degrades
to an empty string rather than a lost row. It never raises and exits 0 always: a log must not
break a session. Wired in SETUP §10 as Hook F. Guarded by tests/model-switch-log.test.sh.
"""
import datetime
import glob
import json
import os
import sys

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

LOG = os.environ.get("AIOS_MODEL_SWITCH_LOG") or os.path.expanduser("~/.aios/model-switch.jsonl")


def pick(d, *keys):
    for k in keys:
        v = d.get(k)
        if isinstance(v, str) and v:
            return v
        if isinstance(v, dict):
            v = v.get("id") or v.get("model")
            if isinstance(v, str) and v:
                return v
    return ""


def registry_name(session_id):
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    for f in glob.glob(os.path.join(cfg, "sessions", "*.json")):
        try:
            with open(f, encoding="utf-8") as fh:
                d = json.load(fh)
        except Exception:
            continue
        if d.get("sessionId") == session_id:
            return d.get("name") or ""
    return ""


def report(argv):
    """--report [--since YYYY-MM-DD] [--session ID]: one line per switch that left a session on a
    model other than the one it asked for. Prints nothing when there is none, so a caller can
    render silence as "nothing to say". Read by /close-session and /close-day."""
    since = argv[argv.index("--since") + 1] if "--since" in argv[:-1] else ""
    sid = argv[argv.index("--session") + 1] if "--session" in argv[:-1] else ""
    try:
        with open(LOG, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return
    for ln in lines:
        try:
            r = json.loads(ln)
        except ValueError:
            continue
        if since and (r.get("at") or "") < since:
            continue
        if sid and r.get("session_id") != sid:
            continue
        if r.get("requested") and r.get("to") == r.get("requested"):
            continue  # switched back to what it asked for: nothing to flag
        print("%s  %s  %s -> %s  (asked for %s; %s)" % (
            r.get("at", ""), r.get("name") or r.get("session_id") or "(unnamed)",
            r.get("from") or "?", r.get("to") or "?", r.get("requested") or "?", r.get("reason") or "no reason given"))


def main():
    if "--report" in sys.argv:
        report(sys.argv)
        sys.exit(0)
    try:
        d = json.load(sys.stdin)
        sid = pick(d, "session_id", "sessionId")
        row = {
            "at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "session_id": sid,
            "name": registry_name(sid) if sid else "",
            "from": pick(d, "from_model", "previous_model", "old_model", "from"),
            "to": pick(d, "to_model", "new_model", "model", "to"),
            "requested": pick(d, "requested_model"),
            "reason": pick(d, "reason", "trigger", "source"),
        }
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(row) + "\n")
    except Exception:
        pass
    sys.exit(0)


if __name__ == "__main__":
    main()
