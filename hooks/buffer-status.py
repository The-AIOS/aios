#!/usr/bin/env python3
"""buffer-status.py — read the observation buffer's state as NUMBERS, not prose.

WHY THIS EXISTS
    session-insights.md is the last compounding surface governed entirely by
    prose instruction. Its cap, its clock and its disposition rules all require
    an actor to read the whole file — measured at ~22,000 tokens on one live
    vault, ~14,000 on another — and hold it in context. So all of them are
    executed by judgment, and all of them drift. The documented pattern in this
    framework is that prose enforcement fails silently: a guard that read the
    wrong surface for weeks, a digest pass that stopped firing across six
    consecutive close-days, a 30-day forced disposition believed never to have
    fired once.

    This makes the cheap half mechanical. It READS and REPORTS; it never edits.
    A session can learn the buffer's state for a couple of hundred tokens
    instead of fourteen thousand, and the cap becomes a count instead of an
    impression.

    It is deliberately not the full primitive. `add` / `reinforce` / `route`
    (the write path) belong with the schema work that an outside contributor
    offered to build; this is the parser they can share and the measurement the
    close rituals need today.

THE TWO CLASSES (CLAUDE.md § Observed Context Rules)
    behavioural  about the OPERATOR. Waits for a second independent sighting,
                 which is correct — one sighting might be noise.
    method       about the SYSTEM. Never waits: a second sighting would mean
                 the fix never landed, not that the finding is confirmed. Exits
                 at the same close by route / fold / drop.

    An over-cap Emerging section is almost always undisposed `method` entries.
    Reporting the split is the whole point — a bare "14/10" sends a session
    hunting stale behavioural entries that are not the cause.

FAILURE DISCIPLINE
    A file it cannot parse, or a section heading it cannot find, is reported as
    an ERROR with a non-zero exit — never as a healthy zero. A buffer linter
    that says "0 entries, all good" because its regex missed is the exact class
    of defect this file exists to reduce.

USAGE
    python3 hooks/buffer-status.py [PATH] [--json] [--emerging-cap N] [--reinforced-cap N]
    exit 0 = within contract · 1 = action needed · 2 = could not measure
"""

import argparse
import json
import os
import re
import sys
from datetime import date, datetime

# Windows consoles default to cp1252, which cannot encode the em dashes and
# symbols this script prints — so on Windows the report raised
# UnicodeEncodeError and aborted instead of printing. Already guarded this way
# in pipeline-executor.py, route-insight.py and claude-identity/context-monitor.py;
# these callers were simply missed. Safe on macOS/Linux, where stdout is UTF-8.
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")


DEFAULT_PATH = os.path.expanduser(
    "~/aios/vault/00 - notes/context/observed/session-insights.md"
)
EMERGING_CAP = 10
REINFORCED_CAP = 5
STALE_DAYS = 30

# The contract's machine-readable form:
#   `class: method` · `first-seen: 2026-09-04` · `route: antifragile.md`
FIELD = re.compile(r"`\s*(class|first-seen|route)\s*:\s*([^`]+?)\s*`", re.I)

# ...and the PRE-CONTRACT form, which must also count as a stated route:
#   **Route to:** [[patterns]] (delegation-judgment — …)
# Accepting only the backtick field reported "19 entries state no route target"
# against a live vault where all nineteen named one in this shape. A destination
# written as prose is still a destination; a linter that calls it missing is
# measuring its own format preference, not the property it claims to check —
# and a false finding at this volume is how a linter teaches people to ignore it.
LEGACY_ROUTE = re.compile(r"^\s*\*\*Route to:\*\*\s*(.+)$", re.M | re.I)
VALID_CLASSES = {"behavioural", "method"}


# An entry is a `### ` heading OR a top-level `- ` bullet. This is not a new
# convention: `route-insight.py` — the tool that EXCISES entries from this same
# file — resolves both styles and documents why (indented `  - ` lines are body,
# not entries; unindented continuation prose after a bullet legitimately belongs
# to it, measured at 43 live instances). Counting only `### ` here meant the two
# tools disagreed about what an entry is, and the reader silently lost.
TOP_BULLET = re.compile(r"^- \S")
ANY_HEADING = re.compile(r"^#{1,6} ")


# An entry declares its class on the line under its title (CLAUDE.md § Observed Context Rules),
# so a top-level bullet that carries its OWN `class:` / `first-seen:` / `route:` field is
# the next entry, while an evidence list under a heading entry carries none. Blank lines do
# not decide it: operators write evidence lists after a blank line as often as without one.
# route-insight.py and buffer-status.py share this rule so they can never disagree about
# where an entry ends — when they did, routing a heading entry in a mixed section removed
# every bullet entry after it.
_ENTRY_FIELD = re.compile(r"\b(?:class|first-seen|route)\s*:", re.I)


def bullet_starts_entry(lines, i):
    """True if the top-level bullet at lines[i] (plus its indented continuation) carries an
    entry field, i.e. it is a bullet ENTRY rather than a facet of the entry above it."""
    if _ENTRY_FIELD.search(lines[i]):
        return True
    for ln in lines[i + 1:]:
        if not ln.strip() or not ln[:1].isspace():
            break
        if _ENTRY_FIELD.search(ln):
            return True
    return False


def _entry_chunks(body):
    """Entry text blocks of BOTH styles — `### ` headings and top-level `- ` bullets.

    Both styles are counted, and a MIXED section counts both. The previous
    version picked one style — headings if any existed, bullets otherwise — so
    a single `### ` entry dropped into a section of bullets made every bullet
    entry invisible: the count read 1/10 while the section sat at 10/10. A
    measuring tool that silently undercounts is worse than no tool, because the
    cap it enforces blows past while it reports "within contract".

    Boundaries, consistent with `route-insight.py`:
      * a bullet entry ends at the next top-level bullet, ANY heading level, or
        an HTML comment (the `<!-- ROUTED ... -->` tombstones are file
        furniture, never entries), so its indented facets travel with it;
      * a heading entry ends at the next heading, or at a top-level bullet that
        opens a new paragraph (a blank line above it) — in a mixed section that
        bullet is the next entry. A bullet list ATTACHED to the heading entry's
        text (no blank line above it) is that entry's facets, as it always was,
        so a heading entry with `- evidence` lines under it is still one entry.
    """
    lines = body.split('\n')
    chunks = []
    start = None       # index where the open entry began
    kind = None        # "heading" | "bullet" for the open entry

    for i, ln in enumerate(lines):
        if ln.startswith("### "):
            boundary, nxt = True, (i, "heading")
        elif ANY_HEADING.match(ln):
            boundary, nxt = True, (None, None)
        elif TOP_BULLET.match(ln):
            if kind == "heading" and not bullet_starts_entry(lines, i):
                continue  # a facet of the heading entry above it (no entry field of its own)
            boundary, nxt = True, (i, "bullet")
        elif kind == "bullet" and ln.lstrip().startswith("<!--"):
            boundary, nxt = True, (None, None)
        else:
            boundary = False
        if boundary:
            if start is not None:
                chunks.append('\n'.join(lines[start:i]))
            start, kind = nxt
    if start is not None:
        chunks.append('\n'.join(lines[start:]))
    return chunks


# Three states, not two. A section with no parsed entries is either EMPTY (only
# prose, blank lines and HTML comments — the state the routing flow prescribes:
# a line saying it is empty plus the `<!-- ROUTED ... -->` tombstones) or
# UNPARSEABLE (something shaped like an entry that matches neither style: a
# nested or `*`/`+` bullet, a numbered item, another heading level). The first
# version measured prose LENGTH (>= 80 chars) instead of shape, so a healthy
# empty section whose note ran long refused every morning — measured on a live
# vault as seven straight days of "cannot measure" on a component that worked.
# Entry-shaped: any list item, heading, a bold-led line (an entry written as a titled
# paragraph), or a field line (`class:` / `first-seen:` / `route:`) — so a vault that
# writes entries in a style this parser does not know still REFUSES instead of reading 0.
ENTRY_SHAPED = re.compile(
    r"^\s*(?:[-*+]\s+\S|\d+[.)]\s+\S|#{1,6}\s|\*\*[^*]+\*\*)"
    r"|`?\b(?:class|first-seen|route)\s*:", re.I)


def _entry_shaped_lines(body):
    """Lines outside HTML comments that look like an entry attempt."""
    visible = re.sub(r"<!--.*?-->", "", body, flags=re.S)
    return [l for l in visible.split("\n") if ENTRY_SHAPED.search(l)]


def _first_lines(body, n=3):
    visible = re.sub(r"<!--.*?-->", "", body, flags=re.S)
    return [l.strip() for l in visible.split("\n") if l.strip()][:n]


def parse(text):
    """-> {section: [entry, ...]}. Raises ValueError when it cannot measure."""
    if not text.strip():
        raise ValueError("file is empty")
    sections = {}
    parts = re.split(r"^##\s+", text, flags=re.M)[1:]
    if not parts:
        raise ValueError("no `## ` sections found — the file's shape is not what this parser expects")
    for part in parts:
        head, _, body = part.partition("\n")
        name = head.strip()
        key = None
        if re.search(r"\bemerging\b", name, re.I):
            key = "Emerging"
        elif re.search(r"\breinforced\b", name, re.I):
            key = "Reinforced"
        if key is None:
            continue
        entries = []
        for chunk in _entry_chunks(body):
            first, _, rest = chunk.partition('\n')
            title = re.sub(r"^(?:#{1,6} |- )", "", first)
            fields = {k.lower(): v for k, v in FIELD.findall(rest[:600])}
            if "route" not in fields:
                m = LEGACY_ROUTE.search(rest)
                if m:
                    fields["route"] = m.group(1).strip()
            entries.append(
                {
                    "title": title.strip(),
                    "class": (fields.get("class") or "").lower() or None,
                    "first_seen": fields.get("first-seen"),
                    "route": fields.get("route"),
                    "chars": len(chunk),
                }
            )
        sections[key] = entries
        # Neither style matched a section that plainly holds content: the shape
        # is one this parser does not know. Reporting 0 there is the false-clean
        # zero `main()` promises never to print, so refuse loudly instead.
        if not entries and _entry_shaped_lines(body):
            shown = " | ".join(_first_lines(body)) or "(nothing visible)"
            raise ValueError(
                f"section `## {name}` has entry-shaped lines that match neither "
                "supported style (`### ` heading or top-level `- ` bullet) — "
                "cannot measure; not reporting an empty buffer. First lines: "
                + shown
            )
    if not sections:
        raise ValueError(
            "found `## ` sections but none named Emerging or Reinforced — "
            "cannot measure a buffer whose two stages are missing"
        )
    return sections


def age_days(s):
    if not s:
        return None
    for fmt in ("%Y-%m-%d", "%d %B %Y", "%B %d, %Y"):
        try:
            return (date.today() - datetime.strptime(s.strip(), fmt).date()).days
        except ValueError:
            continue
    return None


def build(sections, ecap, rcap):
    em = sections.get("Emerging", [])
    re_ = sections.get("Reinforced", [])
    by_class = {}
    for e in em:
        by_class[e["class"] or "unclassified"] = by_class.get(e["class"] or "unclassified", 0) + 1
    method_open = [e for e in em if e["class"] == "method"]
    unclassified = [e for e in em + re_ if e["class"] is None]
    bad_class = [e for e in em + re_ if e["class"] and e["class"] not in VALID_CLASSES]
    no_route = [e for e in em + re_ if not e["route"]]
    stale = [e for e in em if (age_days(e["first_seen"]) or 0) > STALE_DAYS]

    actions = []
    if len(em) > ecap:
        over = len(em) - ecap
        if method_open:
            actions.append(
                f"Emerging is {len(em)}/{ecap} (over by {over}) and {len(method_open)} entries are "
                f"class:method — dispose of those first (route / fold / drop). Method entries are "
                f"not waiting for anything; a second sighting would mean the fix never landed."
            )
        elif all(e["class"] is None for e in em):
            actions.append(
                f"Emerging is {len(em)}/{ecap} (over by {over}) and NOTHING is classified yet — "
                f"classify before disposing. Do not assume these are stale behavioural entries; "
                f"on measured vaults ~80% of buffer intake is class:method, which exits by "
                f"route/fold/drop rather than by waiting."
            )
        elif any(e["class"] is None for e in em):
            # MIXED: some classified, some not. The earlier version fell through to
            # the all-classified message here and asserted "every entry is
            # classified" while simultaneously reporting N unclassified entries in
            # the next line — a self-contradicting report, and the same
            # assert-a-cause-you-did-not-measure shape this file was written to
            # avoid. Three states need three messages, not two.
            unc = sum(1 for e in em if e["class"] is None)
            actions.append(
                f"Emerging is {len(em)}/{ecap} (over by {over}), and {unc} of them are still "
                f"unclassified — the cause cannot be attributed yet. Classify those first; on "
                f"measured vaults ~80% of buffer intake is class:method, which exits by "
                f"route/fold/drop rather than by waiting."
            )
        else:
            actions.append(
                f"Emerging is {len(em)}/{ecap} (over by {over}). Every entry is classified and none "
                f"is class:method, so the behavioural ones are genuinely the cause — review those."
            )
    if len(re_) > rcap:
        actions.append(f"Reinforced is {len(re_)}/{rcap} — route the ones carrying a target.")
    if method_open and len(em) <= ecap:
        actions.append(f"{len(method_open)} class:method entries are parked — each should exit this close (route / fold / drop).")
    if unclassified:
        actions.append(f"{len(unclassified)} entries carry no `class:` line (they predate the contract) — classify as you pass.")
    if bad_class:
        actions.append(f"{len(bad_class)} entries have an unrecognised class: {sorted({e['class'] for e in bad_class})} — expected behavioural | method.")
    if no_route:
        actions.append(
            f"{len(no_route)} entries state no route target (neither `route:` nor **Route to:**) — "
            f"an entry with no destination has no exit condition."
        )
    if stale:
        actions.append(f"{len(stale)} Emerging entries are older than {STALE_DAYS} days — forced disposition is due.")

    total_chars = sum(e["chars"] for e in em + re_)
    return {
        "emerging": len(em),
        "emerging_cap": ecap,
        "reinforced": len(re_),
        "reinforced_cap": rcap,
        "by_class": by_class,
        "method_awaiting_disposition": len(method_open),
        "unclassified": len(unclassified),
        "invalid_class": len(bad_class),
        "missing_route": len(no_route),
        "stale_over_30d": len(stale),
        # `entry_chars` counts ONLY the entries. `file_chars` (set in main(), the one
        # caller holding the text) is what a session actually pays to read the file,
        # and the two drift apart: routing tombstones (`<!-- ROUTED ... -->`), front
        # matter and any prose outside an entry are invisible to the entry parser yet
        # billed on every load. A buffer can sit "within contract" on the caps while
        # most of its weight is furniture the caps say nothing about. Report both and
        # name each for what it is: the caps govern the entries; the token bill is the
        # file. The original key keeps its meaning so existing consumers are unaffected.
        "entry_chars": total_chars,
        "approx_tokens_entries": total_chars // 4,
        "approx_tokens_to_read_in_full": total_chars // 4,
        "file_chars": None,             # filled by main()
        "approx_tokens_file": None,     # filled by main()
        "actions": actions,
    }


def main():
    ap = argparse.ArgumentParser(description="Report the observation buffer's state. Reads only; never edits.")
    ap.add_argument("path", nargs="?", default=DEFAULT_PATH)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--emerging-cap", type=int, default=EMERGING_CAP)
    ap.add_argument("--reinforced-cap", type=int, default=REINFORCED_CAP)
    a = ap.parse_args()

    try:
        text = open(a.path, encoding="utf-8").read()
    except OSError as e:
        print(f"buffer-status: cannot read {a.path} — {e}", file=sys.stderr)
        return 2
    try:
        sections = parse(text)
    except ValueError as e:
        # Loud, and exit 2. Never a healthy-looking zero.
        print(f"buffer-status: cannot measure {a.path} — {e}", file=sys.stderr)
        return 2

    r = build(sections, a.emerging_cap, a.reinforced_cap)
    r["file_chars"] = len(text)
    r["approx_tokens_file"] = len(text) // 4
    if a.json:
        print(json.dumps(r, indent=2))
    else:
        print(f"Emerging   {r['emerging']}/{r['emerging_cap']}" + ("  ⚠ OVER" if r["emerging"] > r["emerging_cap"] else ""))
        print(f"Reinforced {r['reinforced']}/{r['reinforced_cap']}" + ("  ⚠ OVER" if r["reinforced"] > r["reinforced_cap"] else ""))
        if r["by_class"]:
            print("  by class : " + " · ".join(f"{k} {v}" for k, v in sorted(r["by_class"].items())))
        _ent, _fil = r["approx_tokens_entries"], r["approx_tokens_file"]
        print(f"  entries      ~{_ent:,} tokens   (what the caps govern)")
        print(f"  WHOLE FILE   ~{_fil:,} tokens   (what every session actually pays)")
        if _fil >= _ent * 1.25:
            _pct = round((1 - _ent / _fil) * 100)
            print(f"  ⚠ {_pct}% of the file is NOT entries — comments, tombstones, front matter.")
            print("    The caps say nothing about that share. Condense or relocate it.")
        if r["actions"]:
            print("\nAction needed:")
            for i, x in enumerate(r["actions"], 1):
                print(f"  {i}. {x}")
        else:
            print("\nWithin contract — nothing to dispose.")
    return 1 if r["actions"] else 0


if __name__ == "__main__":
    sys.exit(main())
