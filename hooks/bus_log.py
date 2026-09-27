#!/usr/bin/env python3
"""bus_log.py — remember every prompt the spawn inbox is asked to type into a session.

WHY. The AIOS App and Glass deliver a `send` / `spawn` / `resume` request by TYPING its text into
the target session's terminal. The transcript then records that text exactly like the operator
typing: origin.kind "human", promptSource "typed". So `guard-outward-action.py`, which trusts
human-typed records, would read an hourly routine's prompt that happens to contain "sent" as the
operator asking to send. The transcript record cannot tell the two apart; this log can.

Every request text is fingerprinted into ~/.aios/bus-sent.jsonl ($AIOS_BUS_LOG overrides) when
it is written, and the gate refuses to count a "typed" message whose fingerprint is in the log.
Two capture points, so no writer is missed:
  --hook   PreToolUse on Write|Edit: a Claude session writing ~/.aios/spawn-inbox/*.json.
           Synchronous, so the text is logged before the file exists and pickup cannot beat it.
  --sweep  a watcher on the inbox directory (macOS: a launchd WatchPaths job) for scripts that
           write request files directly. Reads *.json and *.json.holding.
It never blocks anything: exit 0 always. Stdlib only.
"""
import hashlib
import json
import os
import re
import sys
import time

for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        try:
            _stream.reconfigure(encoding="utf-8", errors="replace")
        except (ValueError, OSError):
            pass

LOG = os.environ.get("AIOS_BUS_LOG") or os.path.expanduser("~/.aios/bus-sent.jsonl")
INBOX = os.path.expanduser("~/.aios/spawn-inbox")
KEEP_SECONDS = 14 * 86400


def norm(text):
    return re.sub(r"\s+", " ", (text or "")).strip().lower()


def fp(text):
    return hashlib.sha256(norm(text)[:2000].encode()).hexdigest()[:24]


def texts_of(req):
    return [v for k in ("prompt", "task") for v in [req.get(k)] if isinstance(v, str) and v.strip()]


def _entries():
    try:
        with open(LOG, encoding="utf-8") as f:
            for line in f:
                try:
                    yield json.loads(line)
                except ValueError:
                    continue
    except OSError:
        return


def record(req, via):
    have = {e.get("fp") for e in _entries()}
    os.makedirs(os.path.dirname(LOG) or ".", exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as f:
        for t in texts_of(req):
            h = fp(t)
            if h in have:
                continue
            f.write(json.dumps({"at": int(time.time()), "fp": h, "to": req.get("name"),
                                "action": req.get("action", "spawn"), "via": via,
                                "head": norm(t)[:80]}) + "\n")
            have.add(h)


def is_bus_prompt(text):
    """True when this exact text (whitespace and case aside) went through the inbox in 14 days."""
    if not text:
        return False
    h, cutoff = fp(text), time.time() - KEEP_SECONDS
    return any(e.get("fp") == h and e.get("at", 0) >= cutoff for e in _entries())


def main():
    try:
        if "--hook" in sys.argv:
            data = json.load(sys.stdin)
            ti = data.get("tool_input") or {}
            path = os.path.expanduser(ti.get("file_path", ""))
            if path.startswith(INBOX + os.sep) and path.endswith(".json"):
                body = ti.get("content") or ti.get("new_string") or ""
                try:
                    record(json.loads(body), "session-write")
                except ValueError:
                    record({"prompt": body}, "session-write-raw")
        elif "--sweep" in sys.argv:
            for n in os.listdir(INBOX):
                if n.endswith(".json") or n.endswith(".json.holding"):
                    try:
                        with open(os.path.join(INBOX, n), encoding="utf-8") as f:
                            record(json.load(f), "inbox-watch")
                    except (OSError, ValueError):
                        pass
    except Exception:
        pass  # never block a write, never fail a watcher
    sys.exit(0)


if __name__ == "__main__":
    main()
