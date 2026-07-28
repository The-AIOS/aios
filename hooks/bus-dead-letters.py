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

CONTRACT (relied on by the commands that call it)
-------------------------------------------------
  * no dead letters      -> print exactly `bus-dead-letters: none`
  * each dead letter     -> one line with to / action / reason / at
  * unreadable file      -> still reported BY NAME, with the reason why
  * exit code            -> always 0; finding nothing is not a failure

Retirement is not delivery: a `.undelivered` file means the work definitively did
NOT happen and nobody was told. See CLAUDE.md § Spawning Sessions.

Usage:  python3 hooks/bus-dead-letters.py [inbox-dir]
"""

import glob
import json
import os
import sys

DEFAULT_INBOX = "~/.aios/spawn-inbox"


def main(argv):
    inbox = os.path.expanduser(argv[1] if len(argv) > 1 else DEFAULT_INBOX)
    files = sorted(glob.glob(os.path.join(inbox, "*.undelivered")))

    if not files:
        print("bus-dead-letters: none")
        return 0

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
