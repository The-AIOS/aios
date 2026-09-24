#!/usr/bin/env python3
"""observed-staleness.py — the observed-context staleness alarm, as CODE.

WHY THIS EXISTS
    The alarm itself was already the reliable-over-clever design: read each
    `observed/*.md` file's `updated:` stamp, compare against a threshold, flag
    what crossed. What stayed in prose was the EXEMPTION — which files have no
    clock at all — and that is the half that failed.

    Measured on a live vault: an observed file carried `status:
    historical-snapshot` and a body paragraph saying in plain words that it is
    a frozen record which is not updated incrementally. The commands only ever
    knew `restated: true`. So every morning a session recomputed the exemption
    by hand from the file body: nine mornings in a row each re-derived it, four
    of them wrote some version of *"excluded from here on — I will not flag it
    again"*, and the next session flagged it again anyway. One session finally
    believed the alarm and proposed backfilling a file that is frozen by design.

    That is the documented failure shape: a rule that lives only in prose fires
    only on the runs where someone reads and remembers it. A permanent false
    positive is worse than no alarm, because it is how an operator learns to
    ignore the real one.

    So the exemption becomes code. It READS and REPORTS; it never edits.

THE TWO SHAPES THAT HAVE NO CLOCK (CLAUDE.md § III)
    restated   a specification rewritten in place (`restated: true`). Unchanged
               means the spec is stable, which is the system working.
    frozen     a historical record, closed and superseded (`status:
               historical-snapshot`). It has no write trigger at all; nothing
               will ever update it, and that is correct.

    Both are REPORTED, never silently dropped — an invisible exemption is just
    a muted alarm, and nobody can audit it.

FAILURE DISCIPLINE
    A file with no parseable `updated:` stamp is an ERROR with a non-zero exit,
    never a healthy zero. A staleness checker that reports "all fresh" because
    its regex missed is the defect this file exists to reduce.

USAGE
    uv run ~/aios/hooks/observed-staleness.py [DIR] [--json] [--today YYYY-MM-DD]
    exit 0 = nothing stale · 1 = something crossed its threshold · 2 = could not measure
"""
import argparse
import datetime as dt
import json
import os
import re
import sys

# The alarm prints ⚠️ / ✅ / ❌, and on Windows the default console encoding is
# cp1252, which cannot encode any of them: the checker died with
# UnicodeEncodeError on its own SUCCESS path. That is the same failure this hook
# exists to end, one layer down — `/today` and `/close-day` call it, a crash
# emits no verdict, and no output reads exactly like a clean run. Reported as an
# exit-1 traceback rather than silently, which is the only reason it was caught.
# UTF-8 on both streams, on every platform, before anything is printed.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError, OSError):
        pass  # a redirected or wrapped stream that cannot be reconfigured

# Self-locate from this file (hooks/ -> framework root) rather than assuming the ~/aios symlink.
DEFAULT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "vault", "00 - notes", "context", "observed")

# Aggregate/derived files decay faster: a relationship map or an identity
# synthesis looks fine right up until you rely on it.
# See CLAUDE.md § Observed Context Rules ("Aggregate vs atomic").
# Everything else gets the ordinary accumulation threshold.
AGGREGATE_DAYS = 21
DEFAULT_DAYS = 30
AGGREGATES = {"ecosystem.md", "profile.md"}

# Files that are indexes of the folder, not observations in it.
SKIP_NAMES = {"_index.md"}

FM = re.compile(r"\A---\r?\n(.*?)\r?\n---", re.S)


def frontmatter(text):
    m = FM.match(text)
    if not m:
        return {}
    out = {}
    for line in m.group(1).splitlines():
        if ":" not in line or line.lstrip().startswith("#"):
            continue
        k, _, v = line.partition(":")
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def exemption(fm):
    """Return the name of the no-clock shape, or None."""
    if str(fm.get("restated", "")).lower() == "true":
        return "restated"
    if fm.get("status", "") == "historical-snapshot":
        return "frozen"
    return None


def measure(directory, today):
    rows, errors = [], []
    names = sorted(n for n in os.listdir(directory) if n.endswith(".md"))
    if not names:
        raise ValueError(f"no .md files in {directory}")

    for name in names:
        if name in SKIP_NAMES:
            continue
        path = os.path.join(directory, name)
        try:
            text = open(path, encoding="utf-8").read()
        except OSError as e:
            errors.append(f"{name}: cannot read — {e}")
            continue

        fm = frontmatter(text)
        shape = exemption(fm)
        if shape:
            rows.append({"file": name, "exempt": shape, "updated": fm.get("updated"),
                         "age_days": None, "threshold": None, "stale": False})
            continue

        raw = fm.get("updated")
        # An EXPLICITLY empty stamp (`updated: ""`) is a file nobody has written yet — the
        # framework ships its observed files as seeds that way. It has no clock until its
        # first write, so it is reported as not started, never as an error: otherwise every
        # fresh install's first /today opens on a wall of "cannot measure". A MISSING key is
        # still an error — that is a file whose shape the alarm cannot trust.
        if "updated" in fm and raw == "":
            rows.append({"file": name, "exempt": "not-started", "updated": None,
                         "age_days": None, "threshold": None, "stale": False})
            continue
        if not raw:
            errors.append(f"{name}: no `updated:` in frontmatter — cannot measure")
            continue
        try:
            when = dt.date.fromisoformat(raw[:10])
        except ValueError:
            errors.append(f"{name}: `updated: {raw}` is not an ISO date — cannot measure")
            continue

        age = (today - when).days
        threshold = AGGREGATE_DAYS if name in AGGREGATES else DEFAULT_DAYS
        rows.append({"file": name, "exempt": None, "updated": when.isoformat(),
                     "age_days": age, "threshold": threshold, "stale": age > threshold})

    return rows, errors


def main():
    ap = argparse.ArgumentParser(
        description="Report which observed-context files crossed their staleness threshold. Reads only; never edits.")
    ap.add_argument("directory", nargs="?", default=DEFAULT_DIR)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--today", help="override today's date (YYYY-MM-DD), for tests")
    a = ap.parse_args()

    today = dt.date.fromisoformat(a.today) if a.today else dt.date.today()

    try:
        rows, errors = measure(a.directory, today)
    except (OSError, ValueError) as e:
        print(f"observed-staleness: cannot measure {a.directory} — {e}", file=sys.stderr)
        return 2

    stale = [r for r in rows if r["stale"]]
    exempt = [r for r in rows if r["exempt"]]
    clocked = [r for r in rows if r["exempt"] is None]

    if a.json:
        print(json.dumps({"today": today.isoformat(), "rows": rows,
                          "stale": [r["file"] for r in stale], "errors": errors}, indent=2))
    else:
        if stale:
            print(f"⚠️  {len(stale)} observed file(s) past threshold:")
            for r in sorted(stale, key=lambda r: -r["age_days"]):
                print(f"   {r['file']:<28} {r['age_days']:>4}d  (threshold {r['threshold']}d, updated {r['updated']})")
        elif errors:
            # NOT a ✅. Some file could not be measured, so "nothing stale" is a
            # claim this run has not earned — and a green line on stdout is
            # exactly how an unmeasurable file becomes an invisible one.
            print(f"⚠️  nothing stale among the {len(clocked)} file(s) that could be measured — "
                  f"but {len(errors)} could NOT be measured (see below). Incomplete, not clean.")
        else:
            print(f"✅ nothing stale — {len(clocked)} file(s) on a clock, all within threshold")
        # Exemptions are printed, never silent: an invisible exemption is a muted alarm.
        for r in exempt:
            print(f"   — {r['file']:<26} no clock ({r['exempt']}; updated {r['updated']})")
        for e in errors:
            print(f"   ❌ {e}", file=sys.stderr)

    if errors:
        return 2
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())
