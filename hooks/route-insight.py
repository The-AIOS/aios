#!/usr/bin/env python3
"""route-insight.py — surgical excision of a session-insights entry.

Used by /close-day's Tier-A routing + Emerging-cap gardening to remove a single
buffer entry AFTER its content has been written to a target observed file (Tier A)
or judged expired (Emerging cap). This is the SURGICAL mechanism: snapshot-first,
validate-after, abort+restore on ANY mismatch. It never blunt-rewrites; it removes
exactly one entry block and leaves a trail marker in its place.

TWO ENTRY STYLES are supported, because a buffer that follows the documented lifecycle
naturally becomes bullets rather than headings:
  heading — a `### ` line; body runs to the next `## `/`### `. Bullets do NOT terminate
            it, since a heading entry's body may legitimately contain them.
  bullet  — a top-level `- ` line; ends at the next top-level bullet, any section
            heading, or an HTML comment. Indented `  - ` facets travel with it.
Heading style is tried FIRST, so every pre-existing caller keeps identical behaviour.

It does the MECHANICAL part only. The JUDGMENT (which entry to route/expire, what the
marker says) is the caller's (Claude in /close-day). This tool guarantees that once a
decision is made, the buffer edit is reliable and can't silently corrupt the file.

Usage:
  route-insight.py <file> --match "<unique substring of the entry line>" --marker "<HTML comment line>"
  route-insight.py <file> --match "..." --marker "..." --dry-run

Exit codes: 0 = excised + validated; 2 = no/ambiguous match (no change);
            3 = validation failed (restored from snapshot, no change).
"""
import re
import argparse, datetime, os, re, shutil, sys

# Windows: stdout defaults to the locale codepage (cp1252 on a Western-European
# install), so echoing an excised entry that contains an arrow, emoji or accented
# character raises UnicodeEncodeError and aborts the excision. The file IO below is
# already explicit UTF-8; only the report was not.
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

def is_top_bullet(ln):
    """A top-level list item: `- ` at column 0. Indented facets (`  - `) are body, not entries."""
    return bool(re.match(r"^- \S", ln))

def entry_lines(text, style):
    """The entry lines of ONE style. Validation must count the style the match resolved to —
    counting `### ` while excising a bullet asserts nothing at all."""
    src = text.split("\n") if isinstance(text, str) else text
    return [l for l in src if (l.startswith("### ") if style == "heading" else is_top_bullet(l))]

def find_entry(lines, match):
    """Return ((start, end), n, style) for the single entry whose first line contains `match`.

    Boundaries are STYLE-DEPENDENT and that is load-bearing: a bullet must not terminate a
    heading entry (it would orphan the back half of every one), and a bullet entry must end
    at the next top-level bullet / heading / HTML comment so its indented facets travel with
    it and neighbouring file-level comments are not swallowed.

    THE LAST ENTRY IN A LIST HAS NO NEXT, and that is where the enumeration above ran out.
    Reported 2026-08-28 by an operator with an executed repro: excising the last bullet of a
    section carried the whole file tail with it — the caps line, the `---`, and the
    `**See also:**` footer — while exiting 0 and printing `✓ excised`. The design was written
    against neighbours and had no case for the edge, so the very goal this docstring states
    ("neighbouring file-level comments are not swallowed") was the one it broke.

    The fix is NOT a fourth terminator. Enumerating stoppers is incomplete by construction
    and this function is the proof: three were enumerated with care, `#### ` was already
    missing (h4 exists in the live corpus), and the edge case was not in the list either.
    So when the forward scan reaches EOF without finding any terminator — the ambiguous case,
    and the ONLY case that produced the bug — we do not guess. `entry_span_is_clean` decides,
    and an unclean span REFUSES rather than deletes.

    Why not "an entry is its line plus its indented continuations, cut at the first
    unindented line" (the reporter's preferred form, and the more elegant one): measured
    against the seven live files that carry both bullets and a footer, **43 bullets are
    followed by unindented continuation prose that genuinely belongs to them** — `**Note the
    asymmetry:** …`, `**Category:** [PROCESS / …]`. That rule would cut those entries in half.
    The reporter flagged this exact risk as a contract decision rather than a detail, and the
    corpus decided it against the elegant form."""
    m = match.lower()
    style = "heading"
    hits = [i for i, ln in enumerate(lines) if ln.startswith("### ") and m in ln.lower()]
    if not hits:                                    # fall through to bullet style
        style = "bullet"
        hits = [i for i, ln in enumerate(lines) if is_top_bullet(ln) and m in ln.lower()]
    if len(hits) != 1:
        return None, len(hits), style, False
    start = hits[0]
    end = len(lines)
    hit_terminator = False
    for j in range(start + 1, len(lines)):
        ln = lines[j]
        # ANY heading level, not just h2/h3. `#### ` was absent from the original list and
        # h4 exists in the live corpus (business.md carries 10), so a bullet sitting before
        # one already over-extended — the same gap as the edge case, found while fixing it.
        if re.match(r'^#{1,6} ', ln):
            end = j; hit_terminator = True; break
        if style == "bullet" and (is_top_bullet(ln) or ln.lstrip().startswith("<!--")):
            end = j; hit_terminator = True; break
    return (start, end), 1, style, hit_terminator


def entry_span_is_clean(lines, start, end):
    """Lines that would be removed but are NOT part of the entry — empty tuple means clean.

    Only consulted when the forward scan found no terminator (see `find_entry`). A default is
    a silent assertion about the case you did not enumerate, so this is the noisy alternative:
    the span may contain the entry's own line, blanks, and indented continuations. Unindented
    prose is ALLOWED (the corpus has 43 legitimate instances) — but file-level furniture is
    not, and neither is anything that looks like a section footer.

    Deliberately NOT a complete list of furniture: whatever this fails to recognise stays in
    the span and the caller keeps its own positive check. The list only makes the message
    specific; the refusal does not depend on it being complete."""
    FURNITURE = (
        lambda l: l.strip() == "---",
        lambda l: l.startswith("_Caps:"),
        lambda l: l.startswith("**See also:"),
        # NOT `<!--`: the caller's `kept` filter already carries file-level HTML comments
        # through the excision, so they survive. Listing them here would report a loss that
        # does not happen — and the HTML-comment count check downstream already covers them.
    )
    offenders = []
    for j in range(start + 1, end):
        ln = lines[j]
        if not ln.strip():
            continue
        if any(f(ln) for f in FURNITURE):
            offenders.append((j + 1, ln))
    return tuple(offenders)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--match", required=True,
                    help="unique substring of the entry line (`### ` heading or top-level `- ` bullet)")
    ap.add_argument("--marker", default="", help="HTML-comment trail line to leave in place (optional)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    if not os.path.isfile(a.file):
        print(f"[route-insight] file not found: {a.file}", file=sys.stderr); sys.exit(3)
    orig = open(a.file, encoding="utf-8").read()
    lines = orig.split("\n")

    span, n, style, hit_terminator = find_entry(lines, a.match)
    if span is None:
        print(f"[route-insight] {'no' if n==0 else n} matches for '{a.match}' — refusing (need exactly 1).", file=sys.stderr)
        sys.exit(2)
    start, end = span

    # The scan found no terminator, so `end` is EOF by default rather than by evidence. This
    # is the one case that produced the reported data loss, and it is the case where the
    # honest answer is "I do not know where this entry ends". Refuse loudly instead of
    # deleting to the end of the file: a refusal costs one manual excision, the alternative
    # cost a caps line, a rule and a footer while printing ✓.
    if not hit_terminator:
        offenders = entry_span_is_clean(lines, start, end)
        if offenders:
            print(f"[route-insight] refusing: '{a.match}' is the last entry in its section and the span "
                  f"to end-of-file contains {len(offenders)} line(s) that are not part of it:", file=sys.stderr)
            for ln_no, text in offenders:
                print(f"    line {ln_no}: {text[:90]}", file=sys.stderr)
            print("  Excising would delete them. Fix the file (move the entry above the footer, or add a "
                  "terminating comment) or excise by hand. File untouched.", file=sys.stderr)
            sys.exit(3)

    heading = lines[start]

    # File-level `<!-- ... -->` trail lines can sit INSIDE a span; they belong to the file,
    # not to the entry, so they survive the excision.
    kept = [l for l in lines[start:end] if l.lstrip().startswith("<!--")]
    new_lines = lines[:start] + ([a.marker] if a.marker else []) + kept + lines[end:]
    new = "\n".join(new_lines)

    # --- validation (before trusting the edit) ---
    errs = []
    if a.match.lower() in "\n".join(entry_lines(new, style)).lower():
        errs.append(f"target still present as a {style} entry after removal")
    if len(entry_lines(new, style)) != len(entry_lines(orig, style)) - 1:
        errs.append(f"{style} entry count off (was {len(entry_lines(orig, style))}, "
                    f"now {len(entry_lines(new, style))}; expected -1)")
    # The marker is itself an HTML comment, so the expected count RISES by however many
    # it contributes. Asserting equality here would fail on every successful marked run.
    want_comments = orig.count("<!--") + (a.marker.count("<!--") if a.marker else 0)
    if new.count("<!--") != want_comments:
        errs.append(f"HTML-comment count off (expected {want_comments}, got {new.count('<!--')})"
                    " — a file-level trail line was swallowed")
    if a.marker and a.marker not in new:
        errs.append("marker did not land")
    # truncation guard: we only removed [start,end); everything else must be byte-identical.
    #
    # ⚠️ This guard CANNOT catch a wrong `end`, and that is structural rather than an
    # oversight: it compares `lines[end:]` against `new_lines[head:]` — using the same `end`
    # on both sides. When `end` was wrongly EOF, both slices were empty and it passed while a
    # footer was being deleted. A check scoped by the value under suspicion cannot test that
    # value. So the SPAN itself is asserted separately below, in absolute terms.
    head = start + (1 if a.marker else 0) + len(kept)
    if new_lines[:start] != lines[:start] or new_lines[head:] != lines[end:]:
        errs.append("collateral change detected outside the excised span")
    # Scope assertion — independent of `end`. Whatever was removed must be the entry's own
    # line, blanks, or continuations; never file-level furniture.
    span_offenders = entry_span_is_clean(lines, start, end)
    if span_offenders:
        errs.append("excised span contains file-level furniture: "
                    + "; ".join(f"line {n} {t[:50]!r}" for n, t in span_offenders))
    if errs:
        print("[route-insight] VALIDATION FAILED — no change written:\n  - " + "\n  - ".join(errs), file=sys.stderr)
        sys.exit(3)

    if a.dry_run:
        print(f"[route-insight] DRY-RUN ok — would excise [{style}]:\n  {heading}\n  (lines {start+1}-{end})"
              f" -> {'marker' if a.marker else 'removed'}"
              f"{f', preserving {len(kept)} comment line(s)' if kept else ''}")
        sys.exit(0)

    # snapshot, then write
    ts = datetime.datetime.fromtimestamp(os.path.getmtime(a.file)).strftime("%Y%m%d-%H%M%S")
    bak = f"{a.file}.routebak-{ts}"
    shutil.copy2(a.file, bak)
    open(a.file, "w", encoding="utf-8").write(new)
    # post-write re-read guard
    if open(a.file, encoding="utf-8").read() != new:
        shutil.copy2(bak, a.file)
        print("[route-insight] post-write mismatch — restored from snapshot.", file=sys.stderr)
        sys.exit(3)
    print(f"[route-insight] ✓ excised [{style}]: {heading.strip()}\n  backup: {bak}")
    sys.exit(0)

if __name__ == "__main__":
    main()
