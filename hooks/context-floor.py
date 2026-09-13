#!/usr/bin/env python3
"""Emit the context FLOOR in one call: the map, plus what was learned most recently.

    python3 hooks/context-floor.py            # the floor, ready to read
    python3 hooks/context-floor.py --recent 8 # widen the recency slice
    python3 hooks/context-floor.py --json

WHY THE FLOOR IS NOT JUST TITLES
--------------------------------
A floor of headings alone tells a session what EXISTS and nothing about what was
learned. A session can then hold every title in the vault and still behave exactly
like one that read nothing -- which makes the compounding the whole system is built
on structurally invisible at startup. Every close-session and close-day appends to
these files; if the next session never reads what was appended, the loop does not
close.

WHY RECENCY, AND WHY BOUNDED
----------------------------
The two context folders differ in kind, and it is not prose-vs-entries:

    declared/   is RESTATED. Operator-authored identity. Stable, rewritten in
                place, no chronology. Recency is meaningless here -- you read it
                whole or you do not read it.
    observed/   ACCUMULATES. Every shipped file is append-ordered and dated, so it
                HAS a newest end, and the newest end is exactly what the last
                close-day wrote.

So the floor reads the last N entries of every observed file. That is O(1) in the
size of the vault: at ten times the entries this reads the same N per file, while
the map still indexes all of them. A BOUNDED SELECTOR never goes stale; an
unbounded VOLUME does -- which was the original bug ("read everything" was correct
when written and silently stopped being).

Recency is not relevance, and this does not pretend otherwise: older entries stay
indexed by title at the map, and opening one mid-task is expected. What this
guarantees is that no session starts ignorant of what the system learned last.

Every file in both folders is globbed. No filename is ever hardcoded -- operators
rename these files, add their own, and write them in their own language.
"""

import json
import os
import re
import sys

HEADING = re.compile(r"^\#{1,6}\s+\S")
ENTRY = re.compile(r"^\#{3}\s+\S")
DEFAULT_RECENT = 5


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read().split("\n")
    except OSError:
        return None


def split_entries(lines):
    """Return (preamble, [entry_blocks]) in file order. Append-ordered: newest last."""
    pre, out, cur = [], [], None
    for l in lines:
        if ENTRY.match(l):
            if cur is not None:
                out.append(cur)
            cur = [l]
        elif cur is None:
            pre.append(l)
        else:
            cur.append(l)
    if cur is not None:
        out.append(cur)
    return pre, out


def folder(base, name):
    d = os.path.join(base, name)
    if not os.path.isdir(d):
        return None
    out = []
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".md"):
            continue
        lines = read(os.path.join(d, fn))
        if lines is None:
            continue
        out.append((fn, lines))
    return out


def main(argv):
    as_json = "--json" in argv
    recent = DEFAULT_RECENT
    if "--recent" in argv:
        i = argv.index("--recent")
        try:
            recent = max(0, int(argv[i + 1]))
        except (IndexError, ValueError):
            sys.stderr.write("context-floor: --recent needs a number\n")
            return 2
        argv = argv[:i] + argv[i + 2:]
    args = [a for a in argv if not a.startswith("-")]
    root = args[0] if args else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    base = os.path.join(root, "vault", "00 - notes", "context")

    dec, obs = folder(base, "declared"), folder(base, "observed")
    missing = [n for n, v in (("declared", dec), ("observed", obs)) if v is None]
    if missing:
        sys.stderr.write(
            "context-floor: cannot emit a floor -- %s missing under %s\n"
            "  Refusing to print a partial floor: a short one looks like a complete one,\n"
            "  and a session cannot tell the difference from the output alone.\n"
            % (" and ".join(missing), base))
        return 2
    if not dec and not obs:
        sys.stderr.write("context-floor: both folders exist but hold no .md files\n")
        return 2

    payload = {"root": root, "recent_per_file": recent, "declared": [], "observed": []}
    buf = []
    w = buf.append

    w("=" * 72)
    w("CONTEXT FLOOR  --  the map, plus what was learned most recently")
    w("=" * 72)

    # ---- the map -----------------------------------------------------------
    for label, files in (("declared", dec), ("observed", obs)):
        w("")
        w("--- %s/ : %d files ---" % (label, len(files)))
        for fn, lines in files:
            heads = [l.rstrip() for l in lines if HEADING.match(l)]
            payload[label].append({"file": fn, "headings": heads})
            w("")
            w("  %s" % fn)
            for h in heads:
                w("    %s" % h)

    # ---- the recency slice, observed only ----------------------------------
    # declared/ is restated rather than appended, so it has no newest end to read.
    w("")
    w("=" * 72)
    w("MOST RECENT %d ENTRIES PER OBSERVED FILE  --  what the last sessions learned" % recent)
    w("(older entries are indexed by title above; open any of them at any time)")
    w("=" * 72)
    for fn, lines in obs:
        _, es = split_entries(lines)
        tail = es[-recent:] if recent else []
        rec = ["\n".join(e).rstrip() for e in tail]
        for d in payload["observed"]:
            if d["file"] == fn:
                d["recent"] = rec
        w("")
        w("### FILE: %s  (%d entries total, showing last %d)" % (fn, len(es), len(tail)))
        if not es:
            w("  (no ### entries -- this file is mapped by its headings above)")
        for block in rec:
            w("")
            w(block)

    if as_json:
        print(json.dumps(payload, indent=2))
    else:
        print("\n".join(buf))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
