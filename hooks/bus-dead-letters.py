#!/usr/bin/env python3
"""Report spawn-inbox dead letters — requests the command bus could NOT deliver.

WHY THIS IS A SCRIPT AND NOT A SHELL ONE-LINER
----------------------------------------------
Scanning a directory for `*.undelivered` in shell has two idioms and each one
breaks in a different shell, in opposite directions:

  for x in $(ls dir/*.undelivered)   # relies on word-splitting an unquoted var.
                                     # bash splits on newlines; ZSH DOES NOT — it
                                     # hands you every path joined into one string,
                                     # so N files are read as 1 bogus filename and a
                                     # `|| echo "(unparseable)"` swallows the error.
  for x in dir/*.undelivered         # relies on an unmatched glob being harmless.
                                     # bash passes the literal pattern through (an
                                     # `-e` guard catches it); ZSH treats it as a
                                     # HARD ERROR and aborts before any guard runs —
                                     # and "no dead letters" is the common case.

Both failures are silent-looking: the first prints one plausible line per run while
telling you nothing, which is a false negative inside the feature built to end
silent failure. Python globs without word-splitting and returns an empty list
instead of erroring, so behaviour is identical on any shell and any OS.

Keeping it in a file (rather than inline `python3 -c "…"`) also means permission
matching sees a short, stable command prefix, and /today · /close-day ·
/housekeeping can share ONE implementation instead of drifting into three.

TWO FAILURE SHAPES, NOT ONE (the second added 2026-09-07)
---------------------------------------------------------
A request can fail to reach a session in two distinguishable ways, and only one of
them used to be reported:

  <name>.json.undelivered  a surface CLAIMED it, tried, and gave up. Retirement is
                           not delivery: the work did not happen and nobody was told.
  <name>.json              NOBODY EVER CLAIMED IT. On pickup a surface renames the
                           file to `<name>.json.holding`, so a plain `.json` still
                           sitting there after minutes means no fulfiller took it —
                           the operator quit the App, closed the IDE, or never had a
                           surface. It is never dead-lettered (retirement needs a
                           surface to perform it), so nothing surfaced it at all.

Measured 2026-09-07: a request addressed to a surface whose pid had been dead three
weeks sat unclaimed and completely invisible, while an identical one addressed to the
live surface was picked up in ~1s. The `.holding` rename is what makes this safe to
report — a legitimate wait (up to HOLD_STALE_MS, 45 min) is a `.holding` file and is
never flagged here, so this cannot become the check that always fires.

CONTRACT (relied on by the commands that call it)
-------------------------------------------------
  * nothing wrong        -> print exactly `bus-dead-letters: none`
  * each dead letter     -> one line with to / action / reason / at
  * each unclaimed req   -> one `bus-unclaimed:` line with to / action / age
  * unreadable file      -> still reported BY NAME, with the reason why
  * exit code            -> always 0; finding nothing is not a failure

A fresh request is NOT an anomaly: only files older than UNCLAIMED_AFTER_S are
reported, so the normal ~1s window between writing a request and its pickup never
shows up. See CLAUDE.md § Spawning Sessions.

Usage:  python3 hooks/bus-dead-letters.py [inbox-dir]
"""

import glob
import json
import os
import sys
import time

DEFAULT_INBOX = "~/.aios/spawn-inbox"

# Grace period before an unclaimed request is worth mentioning. Pickup is ~1s in
# practice; 5 min is far outside that and far inside RETIRE_TTL_MS (10 min), so a
# stuck request is raised BEFORE the protocol would retire it rather than after.
UNCLAIMED_AFTER_S = 300


def _age(path):
    try:
        return time.time() - os.path.getmtime(path)
    except OSError:
        return None


def _fmt_age(secs):
    if secs is None:
        return "?"
    m = int(secs // 60)
    return "%dm" % m if m < 60 else "%dh%dm" % (m // 60, m % 60)


def unclaimed(inbox):
    """Plain *.json files nobody renamed to .holding, older than the grace period."""
    out = []
    for path in sorted(glob.glob(os.path.join(inbox, "*.json"))):
        secs = _age(path)
        if secs is None or secs < UNCLAIMED_AFTER_S:
            continue
        name = os.path.basename(path)
        try:
            with open(path, encoding="utf-8") as fh:
                doc = json.load(fh)
            doc = doc if isinstance(doc, dict) else {}
            # A hand-written `_claim` is not a real claim (the rename is), but if one
            # is present the file is at least mid-protocol — say so rather than guess.
            out.append(
                "bus-unclaimed: to=%s action=%s age=%s%s"
                % (
                    doc.get("name", "?"),
                    doc.get("action", "spawn"),
                    _fmt_age(secs),
                    " (carries _claim but was never renamed)" if doc.get("_claim") else "",
                )
            )
        except Exception as exc:
            out.append("bus-unclaimed: %s (unreadable: %s)" % (name, exc))
    return out


def main(argv):
    inbox = os.path.expanduser(argv[1] if len(argv) > 1 else DEFAULT_INBOX)
    files = sorted(glob.glob(os.path.join(inbox, "*.undelivered")))
    stuck = unclaimed(inbox)

    if not files and not stuck:
        print("bus-dead-letters: none")
        return 0

    for line in stuck:
        print(line)

    for path in files:
        name = os.path.basename(path)
        try:
            with open(path, encoding="utf-8") as fh:
                doc = json.load(fh)
            if not isinstance(doc, dict):
                raise ValueError("top level is %s, expected object" % type(doc).__name__)
            und = doc.get("_undelivered") or {}
            print(
                "bus-dead-letter: to=%s action=%s reason=%s at=%s"
                % (
                    doc.get("name", "?"),
                    doc.get("action", "spawn"),
                    und.get("reason", "unrecorded"),
                    und.get("at", "?"),
                )
            )
        except Exception as exc:
            # Report it, never skip it — an unreadable dead letter is still a task
            # owed, and carrying the reason is what makes the cause visible in one
            # run instead of needing a debugger.
            print("bus-dead-letter: %s (unreadable: %s)" % (name, exc))

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
