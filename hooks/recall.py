#!/usr/bin/env python3
"""Find what was learned when the TITLE does not say it: a bounded, on-demand index of observed/.

    uv run hooks/recall.py "build cache stale credentials"
    uv run hooks/recall.py "autoriza" --limit 3 --excerpt 200
    uv run hooks/recall.py --vault /path/to/framework-root "query"
    uv run hooks/recall.py --exact "whole words only"
    uv run hooks/recall.py --all "every term must appear"

    exit 0  at least one section matched
    exit 1  the index was built and queried and nothing matched (says how much it searched)
    exit 2  it could not run: no observed/ folder, no FTS5, no searchable word in the query,
            bad flags

WHY IT EXISTS
-------------
The context floor names EVERY title of observed/ and prints the newest few bodies of each file.
That is a bounded selector, and it stays bounded on purpose (hooks/context-floor.py explains why).
Its price is one blind spot: an old lesson whose title does not name the concept is invisible
to a session that is looking for the concept. The title says "baked values"; the body says that a
build cache served stale credentials; the session thinks "cache", scans the titles, finds nothing,
and re-learns it. Nothing in that sequence announces a miss. recall is the other half of
index-then-open: the floor stays as it is, and a session that suspects a title points somewhere
asks by CONCEPT and gets back `path:line :: title` plus a short excerpt, then opens the entry.

HOW IT SEES THE SAME ENTRIES AS THE FLOOR
-----------------------------------------
One row per `###` section, title and body as separate columns. The split is not reimplemented:
this imports `split_entries` from context-floor.py (the way context-rungs.py imports its slice), so
the floor and recall cannot drift into counting different entries. observed/ is globbed, never
listed by name -- both folders vary per vault -- and ONLY observed/ is read: declared/ is
restated identity and is read whole or not at all, and nothing here is a reason to skim it.

WHY THE OUTPUT IS CAPPED, AND BY WHAT
-------------------------------------
A retrieval tool that can answer with 200 KB is a second floor. The cap is MAX_TOTAL_CHARS,
measured on the whole rendered text -- header, warnings, long paths and titles, the "trimmed"
notice -- not on the excerpts alone, because a budget that counts only the part it controls is
exceeded by the part it does not. No flag can raise it: --limit, --excerpt and --max-chars are
each clamped to their own ceiling, and --max-chars can only go DOWN from the total. The output
says when it trimmed, because a short answer that does not say it was cut looks like a complete one.

WHY IT REFUSES, AND WHY IT HAS THREE EXIT CODES
-----------------------------------------------
"Nothing relevant" and "could not look" print the same empty screen, and a session acts on them
oppositely (stop searching / go and fix something). So a missing observed/ folder, a Python built
without FTS5, and a query with no searchable word are exit 2 with a message on stderr, while a
query that ran against a real index and found nothing is exit 1 and says how many sections it
searched. A file it cannot read or decode is never dropped in silence: it is named in the output.
That is a deliberate softening of the floor's rule (the floor refuses on an unreadable file),
because a lookup that is blocked by one locked file is worse than a lookup that says so.

WHY THE QUERY IS TOKENIZED HERE
-------------------------------
FTS5 has a query language: quotes, NEAR, AND/OR/NOT, `*`, `-`, parentheses, column filters. Text
typed by a person or a session (an error message, a title, a half-remembered phrase) trips it with
a raw SQL syntax error. So the query is split into word tokens the way the index splits text (runs
of letters and digits; `_` and punctuation separate), and each token is quoted as an FTS5 string.
Operators in the query are therefore ordinary words, and no query can reach the FTS5 parser as syntax.

WHY PREFIX MATCHING, AND WHY ANY-WORD
-------------------------------------
SQLite's FTS5 ships no Spanish stemmer: `autoriza` does not match `autorizacion`. Two defaults were
decided by measurement, not taste. The measurement: on a live vault of a couple of hundred sections,
for 150 sections it built a query from the three rarest words that appear in the body and NOT in the
title (the exact case recall exists for) and asked whether that section came back in the top 5 and
as the first result. Then the same with every word cut by three letters, with an inflected ending
added, and with three very common words added, the way a session half-remembers a phrase.

    query shape            exact/any   exact/all   prefix/any   prefix/all
    words as written       100 / 100   100 / 100   100 / 100    100 / 100     (top 5 / top 1, %)
    each word cut short       5 / 3       0 / 0      99 / 97      100 / 100
    + 3 common words        100 / 100    36 / 36    100 / 100     38 / 38

Exact spelling lost nearly every section the moment a word was cut. All-words matching was perfect
until the query held one word the section does not contain, and then it lost two sections in three.
Prefix + any-word lost nothing in any row, at the price of more low-ranked matches: BM25 puts the
section that holds more of the words, and rarer ones, first, which is what makes any-word usable. A
title-only match is weighted above a body-only one. So the default is prefix + any-word; `--exact` and
`--all` are there for the day the noise matters more than the recall. A token shorter than MIN_PREFIX
characters always matches whole (`a*` would match everything).

Known limit, measured rather than hidden: prefix matching finds a LONGER form from a shorter query
(`autoriza` finds `autorizacion`) and not the reverse -- a query word with an ending the section does
not have found 0% of sections in the same run. Truncating every query word to about 70% of its length
repaired that (100%), but it also raised the number of matches several-fold and cost four points of
first-place accuracy on the cut-word shape, so it is not the default. Query with the stem.

NOTHING IS WRITTEN
------------------
The index lives in memory for one run and is rebuilt every time -- a vault of hundreds of sections
indexes in well under a second, and an on-disk index is a second copy of private context that goes
stale the moment a close-session appends. No file is created, touched or left behind, in the vault
or outside it. It is opt-in: no hook or settings entry calls it.
"""

import argparse
import importlib.util
import os
import re
import sys
import unicodedata
from pathlib import Path

# ---- the budget. Every one of these is a CEILING a flag can only lower. -------------------------
MAX_TOTAL_CHARS = 6000      # the whole rendered output, header and notices included
MIN_TOTAL_CHARS = 300       # below this not even one result and the notice fit
DEFAULT_LIMIT, MAX_LIMIT = 5, 20
DEFAULT_EXCERPT, MAX_EXCERPT = 240, 600
MAX_TITLE_CHARS = 160
MAX_PATH_CHARS = 200
MAX_QUERY_ECHO = 80
MAX_QUERY_TOKENS = 24
MIN_PREFIX = 3              # shorter tokens match whole
MAX_FILE_BYTES = 32 * 1024 * 1024
EXCERPT_SCAN_CHARS = 100000
TITLE_WEIGHT, BODY_WEIGHT = 3.0, 1.0

TOKEN = re.compile(r"[^\W_]+")
HEADING_PREFIX = re.compile(r"^\#+\s*")


def load_floor():
    """The floor's own entry splitter, so recall and the floor see the same sections."""
    # Importing a file by path would otherwise drop a compiled copy beside it in hooks/.
    sys.dont_write_bytecode = True
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "context-floor.py")
    spec = importlib.util.spec_from_file_location("aios_context_floor", path)
    if spec is None or spec.loader is None or not os.path.isfile(path):
        raise RuntimeError("cannot load %s" % path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def tokenize(text):
    """Word tokens the way the index will split them: letters and digits, nothing else."""
    seen, out = set(), []
    for t in TOKEN.findall(unicodedata.normalize("NFC", text)):
        key = t.lower()
        if key not in seen:
            seen.add(key)
            out.append(t)
    return out


def build_match(tokens, prefix=True, require_all=False):
    """An FTS5 MATCH expression made only of quoted strings, `*` and the joiner we choose."""
    parts = []
    for t in tokens:
        q = '"%s"' % t.replace('"', '""')
        parts.append(q + " *" if prefix and len(t) >= MIN_PREFIX else q)
    return (" " if require_all else " OR ").join(parts)


def read_section_file(path):
    """(text, undecodable) or (None, reason). Never raises for a bad file."""
    try:
        if path.stat().st_size > MAX_FILE_BYTES:
            return None, "over %d MiB" % (MAX_FILE_BYTES // (1024 * 1024))
        try:
            return path.read_text(encoding="utf-8-sig"), False
        except UnicodeDecodeError:
            return path.read_text(encoding="utf-8-sig", errors="replace"), True
    except OSError as e:
        return None, "unreadable (%s)" % (e.strerror or type(e).__name__)


def collect(root, floor):
    """Sections of every observed/*.md: (sections, files_seen, unindexed, lossy).

    A section is {"path", "line", "title", "body"}. `path` is relative to `root` with forward
    slashes, so the same entry prints the same text on every platform.
    """
    obs = Path(root) / "vault" / "00 - notes" / "context" / "observed"
    sections, unindexed, lossy, files = [], [], [], 0
    for p in sorted(q for q in obs.iterdir() if q.name.endswith(".md") and not q.is_dir()):
        files += 1
        text, flag = read_section_file(p)
        if text is None:
            unindexed.append("%s: %s" % (p.name, flag))
            continue
        if flag:
            lossy.append(p.name)
        lines = text.split("\n")
        pre, blocks = floor.split_entries(lines)
        rel = p.relative_to(root).as_posix()
        line_no = len(pre) + 1
        for block in blocks:
            title = HEADING_PREFIX.sub("", block[0]).strip()
            sections.append({"path": rel, "line": line_no, "title": title,
                             "body": "\n".join(block[1:]).strip()})
            line_no += len(block)
    return sections, files, unindexed, lossy


class NoFTS5(Exception):
    pass


def build_index(sections):
    """An in-memory FTS5 table, one row per section. Raises NoFTS5 with the reason."""
    import sqlite3
    try:
        conn = sqlite3.connect(":memory:")
        conn.execute("CREATE VIRTUAL TABLE s USING fts5(title, body, "
                     "tokenize='unicode61 remove_diacritics 2')")
    except Exception as e:  # sqlite3.Error, or a build without the module
        raise NoFTS5(str(e))
    conn.executemany("INSERT INTO s(rowid, title, body) VALUES (?, ?, ?)",
                     [(i, s["title"], s["body"]) for i, s in enumerate(sections)])
    return conn


def search(conn, match, limit):
    """(total matches, [section index ...]) best first. BM25, title weighted over body."""
    total = conn.execute("SELECT count(*) FROM s WHERE s MATCH ?", (match,)).fetchone()[0]
    rows = conn.execute("SELECT rowid FROM s WHERE s MATCH ? "
                        "ORDER BY bm25(s, ?, ?), rowid LIMIT ?",
                        (match, TITLE_WEIGHT, BODY_WEIGHT, limit)).fetchall()
    return total, [r[0] for r in rows]


def fold(s):
    """Lowercase and strip accents without changing the length, so offsets stay valid."""
    out = []
    for ch in s:
        base = unicodedata.normalize("NFD", ch)[:1].lower()
        out.append(base[:1] or ch)
    return "".join(out)


def excerpt(body, tokens, width):
    """A window of the body around the densest cluster of query words, whitespace collapsed."""
    # A section can be megabytes; the excerpt only needs to look near the front of it.
    text = " ".join(body[:EXCERPT_SCAN_CHARS].split())
    if width <= 0 or not text:
        return ""
    if len(text) <= width:
        return text
    folded = fold(text)
    keys = [fold(t) for t in tokens]
    hits = sorted({m.start() for k in keys if k for m in re.finditer(re.escape(k), folded)})[:300]
    best = 0
    if hits:
        best, best_n = hits[0], -1
        for h in hits:
            lo = max(0, h - width // 4)
            window = folded[lo:lo + width]
            n = sum(1 for k in keys if k and k in window)
            if n > best_n:
                best, best_n = h, n
    start = max(0, best - width // 4)
    start = min(start, max(0, len(text) - width))
    if start > 0:
        space = text.find(" ", start, start + 20)
        start = space + 1 if space != -1 else start
    chunk = text[start:start + width].rstrip()
    return ("..." if start > 0 else "") + chunk + ("..." if start + width < len(text) else "")


def clip(s, n, keep_end=False):
    if len(s) <= n:
        return s, False
    if n <= 3:
        return s[:n], True
    if keep_end:   # a path: keep both ends, the folder it lives in and the file it names
        head = (n - 3) // 3
        return s[:head] + "..." + s[-(n - 3 - head):], True
    return s[:n - 3] + "...", True


def one_line(s):
    return " ".join(s.split())


def render(query, mode, searched, files, total, shown_sections, tokens, limit, excerpt_w,
           cap, notices):
    """The whole output as one string no longer than `cap` characters, and whether it trimmed."""
    q, _ = clip(one_line(query), MAX_QUERY_ECHO)
    head = 'recall "%s" (%s): %d match%s; searched %d sections in %d files' % (
        q, mode, total, "" if total == 1 else "es", searched, files)
    trimmed = False
    blocks = []
    for n, s in enumerate(shown_sections, 1):
        path, p_cut = clip(s["path"], MAX_PATH_CHARS, keep_end=True)
        title, t_cut = clip(one_line(s["title"]), MAX_TITLE_CHARS)
        trimmed = trimmed or p_cut or t_cut
        line = "%d. %s:%d :: %s" % (n, path, s["line"], title)
        body = excerpt(s["body"], tokens, excerpt_w)
        blocks.append((line, body))

    def footer(shown):
        bits = []
        if shown < len(blocks):
            bits.append("trimmed: the %d-char cap allows %d of the %d best" % (cap, shown, len(blocks)))
        elif trimmed:
            bits.append("trimmed: a long path, title or excerpt was shortened")
        if total > shown:
            n = total - shown
            bits.append("%d more match%s not shown" % (n, "" if n == 1 else "es"))
        return ("[" + "; ".join(bits) + "]") if bits else ""

    def assemble(shown, last_excerpt=None):
        out = [head] + notices
        for k in range(shown):
            line, body = blocks[k]
            if k == shown - 1 and last_excerpt is not None:
                body = last_excerpt
            out.append(line)
            if body:
                out.append("   " + body)
        f = footer(shown)
        if f:
            out.append(f)
        return "\n".join(out)

    shown, last = len(blocks), None
    text = assemble(shown)
    while len(text) + 1 > cap and shown > 0:
        trimmed = True            # the notice itself costs characters: count it before measuring
        text = assemble(shown, last)
        over = len(text) + 1 - cap
        if over <= 0:
            break
        body = blocks[shown - 1][1]
        if last is None and len(body) - over - 3 >= 40:
            # Keep the result and shorten its excerpt; only a result that cannot shrink is dropped.
            last = body[:len(body) - over - 3].rstrip() + "..."
            text = assemble(shown, last)
            continue
        shown -= 1
        last = None
        text = assemble(shown)
    if len(text) + 1 > cap:   # not even the header fits: the cap still wins
        text = text[:cap - 4].rstrip() + "..."
    return text, trimmed


def notices_for(unindexed, lossy):
    out = []
    if unindexed:
        shown = "; ".join(unindexed[:3]) + ("; +%d more" % (len(unindexed) - 3) if len(unindexed) > 3 else "")
        out.append("WARNING: %d file(s) NOT indexed, results are partial: %s" % (len(unindexed), shown))
    if lossy:
        shown = ", ".join(lossy[:3]) + (", +%d more" % (len(lossy) - 3) if len(lossy) > 3 else "")
        out.append("WARNING: %d file(s) had undecodable bytes (indexed with replacement characters): %s"
                   % (len(lossy), shown))
    return [clip(n, 400)[0] for n in out]


def positive_int(name, ceiling):
    def conv(v):
        try:
            n = int(v)
        except ValueError:
            raise argparse.ArgumentTypeError("%s needs a whole number" % name)
        if n < 1:
            raise argparse.ArgumentTypeError("%s must be at least 1" % name)
        return min(n, ceiling)
    return conv


def parse(argv):
    ap = argparse.ArgumentParser(
        prog="recall.py",
        description="Search the entries of observed/ by concept (title AND body). Read-only, "
                    "in memory, hard output cap of %d characters." % MAX_TOTAL_CHARS)
    ap.add_argument("query", nargs="+", help="words to look for (quotes and operators are plain words)")
    ap.add_argument("--vault", metavar="PATH", help="framework root that contains vault/ "
                    "(default: $AIOS_ROOT, else the root this hook lives in)")
    ap.add_argument("--limit", type=positive_int("--limit", MAX_LIMIT), default=DEFAULT_LIMIT,
                    help="results to show (default %d, ceiling %d)" % (DEFAULT_LIMIT, MAX_LIMIT))
    ap.add_argument("--excerpt", type=positive_int("--excerpt", MAX_EXCERPT), default=DEFAULT_EXCERPT,
                    help="characters of excerpt per result (default %d, ceiling %d)"
                         % (DEFAULT_EXCERPT, MAX_EXCERPT))
    ap.add_argument("--max-chars", type=positive_int("--max-chars", MAX_TOTAL_CHARS), default=MAX_TOTAL_CHARS,
                    help="total characters of output; can only lower the %d ceiling" % MAX_TOTAL_CHARS)
    ap.add_argument("--exact", action="store_true", help="match whole words only (default: prefix)")
    ap.add_argument("--all", action="store_true", help="every word must appear (default: any word, ranked)")
    a = ap.parse_args(argv)
    if a.max_chars < MIN_TOTAL_CHARS:
        ap.error("--max-chars must be at least %d" % MIN_TOTAL_CHARS)
    return a


def main(argv):
    a = parse(argv)
    query = " ".join(a.query)
    tokens = tokenize(query)
    if not tokens:
        sys.stderr.write("recall: the query has no searchable word (letters or digits) -- "
                         "nothing was searched\n")
        return 2
    ignored = max(0, len(tokens) - MAX_QUERY_TOKENS)
    tokens = tokens[:MAX_QUERY_TOKENS]

    root = a.vault or os.environ.get("AIOS_ROOT") or os.path.dirname(
        os.path.dirname(os.path.abspath(__file__)))
    obs = Path(root) / "vault" / "00 - notes" / "context" / "observed"
    if not obs.is_dir():
        sys.stderr.write(
            "recall: cannot search -- observed/ not found at %s\n"
            "  This is NOT 'no results': nothing was looked at. Pass --vault with the folder that "
            "contains vault/.\n" % obs.as_posix())
        return 2

    try:
        floor = load_floor()
    except Exception as e:
        sys.stderr.write("recall: cannot search -- the context floor's entry splitter did not load "
                         "(%s)\n" % e)
        return 2

    try:
        sections, files, unindexed, lossy = collect(Path(root), floor)
    except OSError as e:
        sys.stderr.write("recall: cannot search -- observed/ could not be listed (%s)\n" % e)
        return 2

    try:
        conn = build_index(sections)
    except NoFTS5 as e:
        sys.stderr.write(
            "recall: cannot search -- this Python's SQLite has no usable FTS5 (%s)\n"
            "  This is NOT 'no results': nothing was searched. Use a Python whose sqlite3 includes "
            "FTS5 (python.org builds, Homebrew, uv-managed Pythons do).\n" % e)
        return 2

    mode = "%s, %s" % ("exact" if a.exact else "prefix", "all words" if a.all else "any word")
    match = build_match(tokens, prefix=not a.exact, require_all=a.all)
    try:
        total, ids = search(conn, match, a.limit)
    except Exception as e:  # the expression is built only from quoted strings; belt and braces
        sys.stderr.write("recall: cannot search -- the index rejected the query (%s)\n" % e)
        return 2

    notices = notices_for(unindexed, lossy)
    if ignored:  # a word that was never looked for must not read as a word that was not found
        notices.append("WARNING: only the first %d words were searched, %d ignored: results are "
                       "partial" % (MAX_QUERY_TOKENS, ignored))
    if total == 0:
        msg = ('recall "%s" (%s): NO MATCH. The index was built and queried: %d sections in %d files '
               'searched. This is an answer, not a failure. Try fewer or shorter words%s.'
               % (clip(one_line(query), MAX_QUERY_ECHO)[0], mode, len(sections), files,
                  "" if not a.all else ", or drop --all"))
        out = "\n".join([msg] + notices)
        sys.stdout.write(clip(out, min(a.max_chars, MAX_TOTAL_CHARS) - 1)[0] + "\n")
        return 1

    text, _ = render(query, mode, len(sections), files, total, [sections[i] for i in ids],
                     tokens, a.limit, a.excerpt, min(a.max_chars, MAX_TOTAL_CHARS), notices)
    sys.stdout.write(text + "\n")
    return 0


if __name__ == "__main__":
    # Windows consoles default stdout to cp1252, and vault titles carry accents and arrows:
    # a print would raise UnicodeEncodeError and the answer would be nothing at all, which is
    # indistinguishable from "nothing relevant". Force UTF-8 on both streams.
    for _stream in (sys.stdout, sys.stderr):
        if hasattr(_stream, "reconfigure"):
            _stream.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main(sys.argv[1:]))
