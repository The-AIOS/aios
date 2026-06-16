#!/usr/bin/env python3
"""route-insight.py — surgical excision of a session-insights entry.

Used by /close-day's Tier-A routing + Emerging-cap gardening to remove a single
buffer entry AFTER its content has been written to a target observed file (Tier A)
or judged expired (Emerging cap). This is the SURGICAL mechanism: snapshot-first,
validate-after, abort+restore on ANY mismatch. It never blunt-rewrites; it removes
exactly one `### ` entry block (heading + body, up to the next heading) and leaves
a trail marker in its place.

It does the MECHANICAL part only. The JUDGMENT (which entry to route/expire, what the
marker says) is the caller's (Claude in /close-day). This tool guarantees that once a
decision is made, the buffer edit is reliable and can't silently corrupt the file.

Usage:
  route-insight.py <file> --match "<unique heading substring>" --marker "<HTML comment line>"
  route-insight.py <file> --match "..." --marker "..." --dry-run

Exit codes: 0 = excised + validated; 2 = no/ambiguous match (no change);
            3 = validation failed (restored from snapshot, no change).
"""
import argparse, datetime, os, re, shutil, sys

def find_entry(lines, match):
    """Return (start, end) line indices [start, end) of the single `### ` entry whose
    heading contains `match`. End = next line that starts a `## ` or `### ` heading, or EOF."""
    hits = [i for i, ln in enumerate(lines)
            if ln.startswith("### ") and match.lower() in ln.lower()]
    if len(hits) != 1:
        return None, len(hits)
    start = hits[0]
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j].startswith("## ") or lines[j].startswith("### "):
            end = j
            break
    return (start, end), 1

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--match", required=True, help="unique substring of the ### heading to excise")
    ap.add_argument("--marker", default="", help="HTML-comment trail line to leave in place (optional)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    if not os.path.isfile(a.file):
        print(f"[route-insight] file not found: {a.file}", file=sys.stderr); sys.exit(3)
    orig = open(a.file, encoding="utf-8").read()
    lines = orig.split("\n")

    span, n = find_entry(lines, a.match)
    if span is None:
        print(f"[route-insight] {'no' if n==0 else n} matches for '{a.match}' — refusing (need exactly 1).", file=sys.stderr)
        sys.exit(2)
    start, end = span
    heading = lines[start]

    new_lines = lines[:start] + ([a.marker] if a.marker else []) + lines[end:]
    new = "\n".join(new_lines)

    # --- validation (before trusting the edit) ---
    def headings(text): return [l for l in text.split("\n") if l.startswith("### ")]
    errs = []
    if a.match.lower() in "\n".join(headings(new)).lower():
        errs.append("target heading still present as a ### entry after removal")
    if len(headings(new)) != len(headings(orig)) - 1:
        errs.append(f"### heading count off (was {len(headings(orig))}, now {len(headings(new))}; expected -1)")
    if a.marker and a.marker not in new:
        errs.append("marker did not land")
    # truncation guard: we only removed [start,end); everything else must be byte-identical
    if new_lines[:start] != lines[:start] or new_lines[start + (1 if a.marker else 0):] != lines[end:]:
        errs.append("collateral change detected outside the excised span")
    if errs:
        print("[route-insight] VALIDATION FAILED — no change written:\n  - " + "\n  - ".join(errs), file=sys.stderr)
        sys.exit(3)

    if a.dry_run:
        print(f"[route-insight] DRY-RUN ok — would excise:\n  {heading}\n  (lines {start+1}-{end}) → {'marker' if a.marker else 'removed'}")
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
    print(f"[route-insight] ✓ excised: {heading.strip()}\n  backup: {bak}")
    sys.exit(0)

if __name__ == "__main__":
    main()
