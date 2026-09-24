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

VENTURES ARE MAPPED, NOT READ
-----------------------------
context/ventures/ is a THIRD access pattern and it needs its own, because it is
PARTITIONED where the other two are global. Any observed entry might apply to any
task, so observed/ is indexed entry-by-entry. But venture context is scoped to one
venture, and which venture a task touches is usually obvious from the task -- so
the floor lists the ventures and reads their _index, and the worker opens the one
that applies. Measured on a live vault that folder is 108,646 words, LARGER than
observed/ and six times declared/; reading its headings alone costs ~7.8k tokens
and reading it whole costs ~141k, so neither belongs at a floor every session pays.

about_business.md does NOT substitute for it. On that same vault it is 1,086 words
summarising 108,646 -- a 1:100 pointer, and CLAUDE.md says so itself: "the detailed
context lives in each venture's about_venture.md". A worker that reads the summary
and believes it has venture context has the index mistaken for the territory.

INTENT.md IS PART OF THE FLOOR
-----------------------------
It is a PERMISSION document, not an identity one: autonomy levels, decision
boundaries, communication rules, what is parked. "Will my output be read as their
words" is a question about VOICE and it correctly gates the identity layer. "Am I
allowed to do this" is a different question, and it applies to every session
whatever it produces -- most sharply to the mechanical worker that is least likely
to have read anything and most likely to commit, push, send or delete. A floor that
omits it hands the largest blast radius to the least-contextualised session.

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


ENTRY_DATE = re.compile(r"20\d{2}-\d{2}-\d{2}")
# A file the operator's ritual treats as a RULE LIBRARY rather than a chronology gets its
# index read instead of its tail. Matched on the heading text, not a filename, so a vault
# that renamed the file still gets it right.
#
# Two constraints, each earned (#150):
#   · `meta-patterns?` -- the canonical seed heads the section `## Meta-patterns`, and with
#     `\bmeta-pattern\b` the trailing `s` defeated the word boundary, so a vault running the
#     seed as shipped was never treated as a rule library at all.
#   · `#{1,2}` -- a SECTION heading marks a rule library; an ENTRY (`###`) never does. With
#     `#{1,3}` any numbered entry whose title contained "index" qualified and the first hit
#     won -- a live vault carries `### 12. Index updated without updating project note`, and
#     was classified correctly only because its `##` heading happened to come first. Not a
#     position rule ("the file opens with it"): the seed puts its meta-pattern section AFTER
#     an example entry, so "before the first `###`" would reject the seed itself.
INDEX_HEADING = re.compile(r"^\#{1,2}\s+.*\b(meta-patterns?|read these first|index)\b", re.I)


def entry_date(block):
    """The date an entry carries, if any -- from its heading or opening lines."""
    m = ENTRY_DATE.search("\n".join(block[:4]))
    return m.group(0) if m else None


def newest(blocks, n):
    """The n newest entries.

    File order is NOT reliably newest-last. Measured across one vault's nine observed
    files, the tail was the newest entry in only 5 of 8 -- patterns.md's last entry was
    three weeks older than its newest, and session-insights.md's was three weeks older
    still. Taking the tail there hands a session stale entries while calling them recent,
    which is worse than handing it none: it is wrong AND it looks right.

    So sort by the date each entry carries, and fall back to file order only for entries
    that carry none (undated entries keep their relative position and sort oldest).
    """
    dated = [(entry_date(b) or "", i, b) for i, b in enumerate(blocks)]
    dated.sort(key=lambda x: (x[0], x[1]))
    return [b for _, _, b in dated[-n:]] if n else []


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


UNREADABLE = []   # files a listing returned but open() could not read -- see main()


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
            UNREADABLE.append(os.path.join(name, fn))
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
    # A file the listing returned but that could not be READ used to drop out of the map in
    # silence (#150d), while a missing FOLDER refuses above. Same class, same answer: with one
    # file gone the floor prints as complete, and a session cannot tell from the output.
    if UNREADABLE:
        sys.stderr.write(
            "context-floor: cannot emit a floor -- could not read: %s\n"
            "  Refusing to print a partial floor: a short one looks like a complete one.\n"
            "  Check the file's permissions, or re-run if it was being moved.\n"
            % ", ".join(UNREADABLE))
        return 2

    payload = {"root": root, "recent_per_file": recent, "declared": [], "observed": [],
               "intent": None, "ventures": []}
    buf = []
    w = buf.append

    w("=" * 72)
    w("CONTEXT FLOOR  --  the map, what was learned most recently, and your limits")
    w("=" * 72)

    # ---- INTENT.md: what you are allowed to DO, whatever you produce ---------
    intent_path = os.path.join(root, "INTENT.md")
    intent = read(intent_path)
    w("")
    w("--- INTENT.md : the trust contract (what you may do without asking) ---")
    if intent is None:
        w("  (absent -- no trust contract in this vault; assume nothing is pre-authorised)")
    else:
        payload["intent"] = "\n".join(intent)
        w("")
        w("\n".join(intent).rstrip())

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

    # ---- ventures: listed and indexed, never read whole at the floor -------
    vdir = os.path.join(base, "ventures")
    w("")
    w("--- ventures/ : scoped context, OPEN THE ONE YOUR TASK TOUCHES ---")
    if not os.path.isdir(vdir):
        w("  (no ventures/ folder in this vault)")
    else:
        vents = sorted(d for d in os.listdir(vdir)
                       if os.path.isdir(os.path.join(vdir, d)))
        vidx = read(os.path.join(vdir, "_index.md"))
        if vidx:
            w("")
            w("\n".join(vidx).rstrip())
        for v in vents:
            files = sorted(f for f in os.listdir(os.path.join(vdir, v))
                           if f.endswith(".md"))
            words = 0
            for f in files:
                ls = read(os.path.join(vdir, v, f))
                if ls:
                    words += sum(len(l.split()) for l in ls)
            payload["ventures"].append({"venture": v, "files": files, "words": words})
            w("")
            w("  %s/  (%d files, ~%d words -- read this folder when the task is about it)"
              % (v, len(files), words))
            for f in files:
                w("    %s" % f)
        if not vents:
            w("  (ventures/ exists but holds no venture folders)")

    # ---- the recency slice, observed only ----------------------------------
    # declared/ is restated rather than appended, so it has no newest end to read.
    w("")
    w("=" * 72)
    w("MOST RECENT %d ENTRIES PER OBSERVED FILE  --  what the last sessions learned" % recent)
    w("(older entries are indexed by title above; open any of them at any time)")
    w("=" * 72)
    for fn, lines in obs:
        _, es = split_entries(lines)
        # A rule library announces itself: it opens with a meta-pattern / index heading
        # saying to read that first. Recency is the wrong selector there -- an entry from
        # four months ago binds as hard as one from this week, and the file's job is to
        # fire BEFORE the mistake. So emit its index instead of its newest bodies; every
        # title is already in the map above, which is what makes scanning it possible.
        idx = [l for l in lines if INDEX_HEADING.match(l)]
        if idx:
            i = lines.index(idx[0])
            # The index is the SECTION the heading opens: everything up to the next heading at
            # the same or a higher level. It used to stop at the next `###`, which for a
            # `## Meta-patterns` section whose patterns are `###` children meant emitting the
            # heading and one sentence and NONE of the patterns -- measured on a live vault,
            # 234 bytes emitted of a 13.4 KB index, 0 of 23 meta-patterns (#150c).
            lvl = len(lines[i]) - len(lines[i].lstrip("#"))
            j = next((k for k in range(i + 1, len(lines))
                      if HEADING.match(lines[k]) and len(lines[k]) - len(lines[k].lstrip("#")) <= lvl),
                     len(lines))
            w("")
            w("### FILE: %s  (%d entries -- RULE LIBRARY, index shown instead of newest)" % (fn, len(es)))
            w("")
            w("\n".join(lines[i:j]).rstrip())
            for d in payload["observed"]:
                if d["file"] == fn:
                    d["recent"] = ["\n".join(lines[i:j]).rstrip()]
                    d["rule_library"] = True
            continue
        tail = newest(es, recent)
        rec = ["\n".join(e).rstrip() for e in tail]
        for d in payload["observed"]:
            if d["file"] == fn:
                d["recent"] = rec
        w("")
        w("### FILE: %s  (%d entries total, showing the %d newest by date)"
          % (fn, len(es), len(tail)))
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
    # Windows consoles default stdout to cp1252, and vault headings carry "→", "—", accents:
    # print() then raises UnicodeEncodeError and the floor emits NOTHING -- the one failure
    # this hook exists to end. Force UTF-8 here instead of relying on PYTHONIOENCODING.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main(sys.argv[1:]))
