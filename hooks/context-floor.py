#!/usr/bin/env python3
"""Emit the context FLOOR in one call: the map, plus what was learned most recently.

    python3 hooks/context-floor.py            # write the floor to a file, print its map
    python3 hooks/context-floor.py --recent 8 # widen the recency slice
    python3 hooks/context-floor.py --out F    # write the floor to F instead of the temp dir
    python3 hooks/context-floor.py --print    # the whole floor on stdout (pipes, tests)
    python3 hooks/context-floor.py --json

WHY IT WRITES A FILE AND PRINTS A MAP
-------------------------------------
The floor outgrows what a session can see in one tool result. Measured on a live
vault it is 203 KB, while a Bash result shows about 30,000 characters, so a session
reading stdout saw roughly the first 15% -- and the part it lost was the END, where
the newest observed entries sit, i.e. exactly what the last close-day wrote. Nothing
in a cut read says it was cut. So by default the whole floor goes to a file and
stdout carries only a map: every section, its size and its line range in that file.
A session then reads the file with a paged reader, which says when there is more.
The selection is unchanged; only the delivery is. If the file cannot be written the
floor is printed in full instead, because emitting nothing is the one failure this
hook exists to end.

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
import tempfile

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


RESTATED = re.compile(r"^restated:\s*true\s*$", re.I)


def is_restated(lines):
    """A file that declares `restated: true` in its front matter is a specification rewritten in
    place, not a chronology -- the same shape as declared/, so it has no newest end to read. Read
    from the front matter only, never sniffed from headings (CLAUDE.md § A third shape)."""
    if not lines or lines[0].strip() != "---":
        return False
    for l in lines[1:40]:
        if l.strip() == "---":
            return False
        if RESTATED.match(l.strip()):
            return True
    return False


def recent_slice(lines, n):
    """What the floor emits for ONE observed file: (entries, is_rule_library, texts).

    The single definition of "the recent slice". hooks/context-rungs.py imports it to price
    rung 1, so the price and the emission cannot drift apart: a second copy of this rule is
    how rung 1 once priced five antifragile bodies while the floor emitted its index.
    """
    _, es = split_entries(lines)
    # A restated file has no newest end: it is mapped by its headings, like declared/, and read
    # when a task needs it. Measured on a heavy vault: one such file was 13 KB of every floor.
    if is_restated(lines):
        return es, False, []
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
        return es, True, ["\n".join(lines[i:j]).rstrip()]
    return es, False, ["\n".join(e).rstrip() for e in newest(es, n)]


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
    to_stdout = "--print" in argv
    out_path = None
    if "--out" in argv:
        i = argv.index("--out")
        if i + 1 >= len(argv) or argv[i + 1].startswith("-"):
            sys.stderr.write("context-floor: --out needs a file path\n")
            return 2
        out_path = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
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
    marks = []   # (buf index where a section starts, label) -- turned into line ranges for the map

    def mark(label):
        marks.append((len(buf), label))

    w("=" * 72)
    w("CONTEXT FLOOR  --  the map, what was learned most recently, and your limits")
    w("=" * 72)

    # ---- INTENT.md: what you are allowed to DO, whatever you produce ---------
    intent_path = os.path.join(root, "INTENT.md")
    intent = read(intent_path)
    w("")
    mark("INTENT.md -- the trust contract: what you may do without asking")
    w("--- INTENT.md : the trust contract (what you may do without asking) ---")
    if intent is None:
        w("  (absent -- no trust contract in this vault; assume nothing is pre-authorised)")
    else:
        payload["intent"] = "\n".join(intent)
        w("")
        w("\n".join(intent).rstrip())

    # ---- payload entries for the map (emitted after the recency slice) -------
    for label, files in (("declared", dec), ("observed", obs)):
        for fn, lines in files:
            payload[label].append({"file": fn, "headings": [l.rstrip() for l in lines if HEADING.match(l)]})

    # ORDER IS DELIBERATE: INTENT, then what was learned most recently, then the maps.
    # The floor is larger than one read of the file, so a session reads it in parts, and
    # one that stops early should lose the INDEX (consultable any time), never the newest
    # learnings -- they are what makes the session smarter from its first minute.
    # ---- the recency slice, observed only ----------------------------------
    # declared/ is restated rather than appended, so it has no newest end to read.
    w("")
    w("=" * 72)
    w("MOST RECENT %d ENTRIES PER OBSERVED FILE  --  what the last sessions learned" % recent)
    w("(older entries are indexed by title in the map below; open any of them at any time)")
    w("=" * 72)
    for fn, lines in obs:
        es, is_lib, rec = recent_slice(lines, recent)
        if is_restated(lines):
            w("")
            mark("newest: %s -- restated spec, mapped not read" % fn)
            w("### FILE: %s  (restated spec -- every heading is in the map below; open the file when the task needs it)" % fn)
            for d in payload["observed"]:
                if d["file"] == fn:
                    d["recent"] = []
                    d["restated"] = True
            continue
        if is_lib:
            w("")
            mark("newest: %s -- rule library, its index" % fn)
            w("### FILE: %s  (%d entries -- RULE LIBRARY, index shown instead of newest)" % (fn, len(es)))
            w("")
            w(rec[0])
            for d in payload["observed"]:
                if d["file"] == fn:
                    d["recent"] = rec
                    d["rule_library"] = True
            continue
        for d in payload["observed"]:
            if d["file"] == fn:
                d["recent"] = rec
        w("")
        mark("newest: %s -- %d newest of %d entries" % (fn, len(rec), len(es)))
        w("### FILE: %s  (%d entries total, showing the %d newest by date)"
          % (fn, len(es), len(rec)))
        if not es:
            w("  (no ### entries -- this file is mapped by its headings above)")
        for block in rec:
            w("")
            w(block)

    # ---- the map -----------------------------------------------------------
    for label, files in (("declared", dec), ("observed", obs)):
        w("")
        mark("%s/ -- every heading of %d files (the map)" % (label, len(files)))
        w("--- %s/ : %d files ---" % (label, len(files)))
        for fn, lines in files:
            heads = [l.rstrip() for l in lines if HEADING.match(l)]
            w("")
            w("  %s" % fn)
            for h in heads:
                w("    %s" % h)

    # ---- ventures: listed and indexed, never read whole at the floor -------
    vdir = os.path.join(base, "ventures")
    w("")
    mark("ventures/ -- listed, not read; open the one your task touches")
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

    if as_json:
        print(json.dumps(payload, indent=2))
        return 0

    body = "\n".join(buf)
    end = ("=== END OF FLOOR -- %d bytes above this line. If your read of the floor does "
           "not end on this line, it was cut: read the rest before acting. ==="
           % len((body + "\n").encode("utf-8")))
    floor = body + "\n" + end + "\n"
    if to_stdout:
        sys.stdout.write(floor)
        return 0

    # Default: the whole floor to a file, the map on stdout. Per session, so two sessions
    # never read each other's floor; outside the vault, so it never lands in its git.
    #
    # The floor is PRIVATE (INTENT.md, observed context) and the temp dir may be shared by
    # every user on the machine (Linux /tmp). So it lives in a per-user folder created 0700,
    # refused if it is a symlink or not ours, and the file is created by mkstemp (O_EXCL,
    # 0600, random name) and renamed into place -- a predictable name opened for writing is
    # one another user can pre-plant as a symlink to a file of yours.
    try:
        if out_path is None:
            sid = re.sub(r"[^A-Za-z0-9_.-]", "", os.environ.get("CLAUDE_CODE_SESSION_ID", "")) or str(os.getpid())
            who = str(os.getuid()) if hasattr(os, "getuid") else re.sub(r"[^A-Za-z0-9_.-]", "", os.environ.get("USERNAME", "")) or "user"
            d = os.path.join(tempfile.gettempdir(), "aios-floor-" + who)
            try:
                os.mkdir(d, 0o700)
            except FileExistsError:
                pass
            st = os.lstat(d)
            import stat
            if not stat.S_ISDIR(st.st_mode) or (hasattr(os, "getuid") and st.st_uid != os.getuid()):
                raise OSError("%s is not a directory owned by you" % d)
            if hasattr(os, "getuid") and stat.S_IMODE(st.st_mode) & 0o077:
                os.chmod(d, 0o700)
            out_path = os.path.join(d, "context-floor-%s.md" % sid)
        fd, tmp = tempfile.mkstemp(prefix=".floor-", dir=os.path.dirname(os.path.abspath(out_path)))
        try:
            with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(floor)
            os.replace(tmp, out_path)
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise
    except OSError as e:
        sys.stderr.write("context-floor: could not write %s (%s) -- printing the whole floor "
                         "instead\n" % (out_path, e))
        sys.stdout.write(floor)
        return 0

    # Line numbers of each section start, 1-based, in the file as written.
    starts = []
    for idx, label in marks:
        starts.append((body[:len("\n".join(buf[:idx]))].count("\n") + 2 if idx else 1, label))
    total = floor.count("\n")
    out = []
    o = out.append
    o("CONTEXT FLOOR -- written in full to:")
    o("  %s" % out_path)
    o("  %d bytes, %d lines. READ THAT FILE TO THE END BEFORE ACTING: this map is not the floor." % (len(floor.encode("utf-8")), total))
    o("  It is larger than one read returns: read it in parts (about 600 lines at a time) until")
    o("  you reach its last line. INTENT and the newest learnings come first, the maps after.")
    o("")
    o("Sections (lines in that file, size):")
    for k, (ln, label) in enumerate(starts):
        nxt = starts[k + 1][0] - 1 if k + 1 < len(starts) else total
        size = len("\n".join(floor.split("\n")[ln - 1:nxt]).encode("utf-8"))
        o("  %5d-%-5d %6.1f KB  %s" % (ln, nxt, size / 1024.0, label))
    o("")
    o("The file's last line is '=== END OF FLOOR'. If your read did not reach it, read on.")
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    # Windows consoles default stdout to cp1252, and vault headings carry "→", "—", accents:
    # print() then raises UnicodeEncodeError and the floor emits NOTHING -- the one failure
    # this hook exists to end. Force UTF-8 here instead of relying on PYTHONIOENCODING.
    # stderr too: the floor's own refusal names files it could not read, and a file
    # name can carry the same characters as a heading.
    for _stream in (sys.stdout, sys.stderr):
        if hasattr(_stream, "reconfigure"):
            _stream.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main(sys.argv[1:]))
