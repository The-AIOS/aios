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
        for chunk in re.split(r"^###\s+", body, flags=re.M)[1:]:
            title, _, rest = chunk.partition("\n")
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
        "approx_tokens_to_read_in_full": total_chars // 4,
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
    if a.json:
        print(json.dumps(r, indent=2))
    else:
        print(f"Emerging   {r['emerging']}/{r['emerging_cap']}" + ("  ⚠ OVER" if r["emerging"] > r["emerging_cap"] else ""))
        print(f"Reinforced {r['reinforced']}/{r['reinforced_cap']}" + ("  ⚠ OVER" if r["reinforced"] > r["reinforced_cap"] else ""))
        if r["by_class"]:
            print("  by class : " + " · ".join(f"{k} {v}" for k, v in sorted(r["by_class"].items())))
        print(f"  reading the buffer in full costs ~{r['approx_tokens_to_read_in_full']:,} tokens")
        if r["actions"]:
            print("\nAction needed:")
            for i, x in enumerate(r["actions"], 1):
                print(f"  {i}. {x}")
        else:
            print("\nWithin contract — nothing to dispose.")
    return 1 if r["actions"] else 0


if __name__ == "__main__":
    sys.exit(main())
