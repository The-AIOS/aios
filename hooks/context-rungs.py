#!/usr/bin/env python3
"""Measure what each rung of the context ladder costs IN THIS VAULT.

Why this ships as code rather than as numbers written into CLAUDE.md:

    "Read everything" was CORRECT when it was written. A small vault's entire
    context is a few thousand words -- cheaper than the paragraph telling you
    to skip it. (SIZE decides, not age: a long-standing vault whose owner
    writes little stays small, and a three-month-old heavy one does not.) It silently stopped being correct as the vault grew past a
    hundred thousand words, because nothing ever measured. A constant baked
    into a rule about a quantity that GROWS works, then doesn't, and nobody
    is told.

So no session, command or skill states a volume. They ask this, and it answers
for the vault in front of it. A newcomer is told to read all of it; a mature
vault is told where to stop. Same rule, opposite advice, both right.

    python3 hooks/context-rungs.py            # human-readable ladder
    python3 hooks/context-rungs.py --json     # machine-readable

Exit 0 with a ladder, or exit 2 having said what it could not measure and why.
It never reports a rung it did not actually count -- an absent folder is named
as absent, not folded into a total that then reads as small.
"""

import importlib.util
import json
import os
import re
import sys

# Rung 1 is defined as "exactly what hooks/context-floor.py emits", so the recent slice is
# priced with the floor's OWN selection function rather than a second copy of the rule.
# The copy drifted once: the floor emitted a rule library's index and entries sorted by
# date, while this file priced the last five bodies of every file -- rung 1 overstated
# by a rule library's bodies, and the "cheap vault" ratio moved with it.
def _load_floor():
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location(
        "aios_context_floor", os.path.join(here, "context-floor.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)   # no fallback: a rung 1 priced without the floor is a guess
    return mod


FLOOR = _load_floor()

# Text read from files (vault headings, request payloads, names) carries "→", "—" and
# accents. On a Windows console stdout/stderr default to cp1252, so print() raises
# UnicodeEncodeError on the first one and the tool emits nothing. Force UTF-8 on both.
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        try:
            _stream.reconfigure(encoding="utf-8", errors="replace")
        except (ValueError, OSError):
            pass  # a wrapped or redirected stream that cannot be reconfigured

# ~1.3 tokens per English word. An ESTIMATE, stated as one everywhere it surfaces:
# the point is the ratio between rungs, which is robust to the constant being off.
TOK_PER_WORD = 1.3

HEADING = re.compile(r"^\#{2,6}\s+\S")
ENTRY = re.compile(r"^\#{3}\s+\S")

# The floor's default recency depth, read from the floor itself rather than restated.
RECENT_PER_FILE = FLOOR.DEFAULT_RECENT

# When is "just read everything" the right answer? NOT at some absolute token count --
# that is a constant about a growing quantity, which is the exact bug this tool exists to
# end, and it was the last one left in the design. Derive it from the vault's own SHAPE:
# the floor is what every session already pays, so if EVERYTHING costs barely more than
# the floor, the deliberation about what to skip is the expensive part. Below this ratio,
# do not deliberate.
#
# Measured against both known shapes: a fresh clone is 2.3x (read all) and a heavily
# written vault is 7.7x (narrow) -- the same verdicts the absolute threshold gave, now
# with nothing hand-picked in them.
CHEAP_IF_UNDER = 3.0

def measure(folder):
    """Word/heading counts per file. Returns (per_file, total) or None if absent."""
    if not os.path.isdir(folder):
        return None
    out = {}
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".md"):
            continue
        path = os.path.join(folder, name)
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                lines = fh.read().split("\n")
        except OSError:
            continue  # unreadable file: counted as absent, never as empty
        words = sum(len(l.split()) for l in lines)
        heads = [l for l in lines if HEADING.match(l)]
        # Price the recency slice as the floor emits it: a rule library's index, or the
        # newest entries by the date they carry (never simply the file's tail).
        entries, is_lib, recent = FLOOR.recent_slice(lines, RECENT_PER_FILE)
        out[name] = {
            "words": words,
            "headings": len(heads),
            "entries": len(entries),
            "rule_library": is_lib,
            "heading_words": sum(len(l.split()) for l in heads),
            "recent_words": sum(len(t.split()) for t in recent),
        }
    return out


def rungs(dec, obs, root_for_intent, ventures):
    """The four rungs, in the order a session climbs them."""
    def s(d, key, only=None):
        if not d:
            return 0
        return sum(v[key] for k, v in d.items() if only is None or k in only)

    idx = s(dec, "words", {"_index.md"}) + s(obs, "words", {"_index.md"})
    heads = s(dec, "heading_words") + s(obs, "heading_words")
    # The recency slice is OBSERVED-ONLY: declared/ is restated in place and has no
    # newest end, while every observed file is append-ordered and dated.
    recent = s(obs, "recent_words")
    dec_body = s(dec, "words") - s(dec, "words", {"_index.md"})
    # INTENT.md is at the FLOOR, not with the identity layer: it governs what a session
    # may DO, which is a separate question from whether its output speaks as the operator.
    intent_p = os.path.join(root_for_intent, "INTENT.md")
    intent = 0
    if os.path.isfile(intent_p):
        try:
            with open(intent_p, encoding="utf-8", errors="replace") as fh:
                intent = len(fh.read().split())
        except OSError:
            intent = 0
    obs_body = s(obs, "words") - s(obs, "words", {"_index.md"})
    return [
        ("0", "both _index.md only", idx,
         "orientation only -- you know the filenames, nothing else"),
        ("1", "+ all headings + newest %d entries/observed file + INTENT.md"
         % RECENT_PER_FILE,
         idx + heads + recent + intent,
         "THE FLOOR. Always. Exactly what hooks/context-floor.py emits."),
        ("2", "+ declared/ read whole", idx + heads + recent + intent + dec_body,
         "when your output will be read as the words of the operator"),
        ("3", "+ all of observed/ + every venture (EVERYTHING)",
         idx + heads + intent + dec_body + obs_body + sum(v[1] for v in ventures),
         "right when the context is small, or when the TASK is the context itself"),
    ]


def main(argv):
    as_json = "--json" in argv
    args = [a for a in argv if not a.startswith("-")]
    root = args[0] if args else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    base = os.path.join(root, "vault", "00 - notes", "context")
    dec, obs = measure(os.path.join(base, "declared")), measure(os.path.join(base, "observed"))
    # ventures/ is PARTITIONED, not global: mapped at the floor, one venture opened on
    # demand. Priced separately because folding it into rung 3 silently understated the
    # true "everything" figure by a third of the vault on a live install.
    vdir = os.path.join(base, "ventures")
    ventures = []
    if os.path.isdir(vdir):
        for v in sorted(d for d in os.listdir(vdir) if os.path.isdir(os.path.join(vdir, d))):
            vm = measure(os.path.join(vdir, v)) or {}
            ventures.append((v, sum(x["words"] for x in vm.values()),
                             sum(x["heading_words"] for x in vm.values())))

    # REFUSE rather than report a total built from one folder. A missing folder does not
    # make the vault small -- it makes the measurement wrong, and a wrong SMALL number is
    # the one that talks a session out of reading anything.
    missing = [n for n, d in (("declared", dec), ("observed", obs)) if d is None]
    if missing:
        sys.stderr.write(
            "context-rungs: cannot measure -- %s missing under %s\n"
            "  Not reporting a partial ladder: a total missing a folder reads as SMALL,\n"
            "  which is exactly the answer that talks a session out of loading context.\n"
            % (" and ".join(missing) + ("/" if len(missing) == 1 else " folders"), base))
        return 2
    if not dec and not obs:
        sys.stderr.write("context-rungs: both folders exist but hold no .md files -- nothing to measure\n")
        return 2

    ladder = rungs(dec, obs, root, ventures)
    dw = sum(v["words"] for v in dec.values())
    ow = sum(v["words"] for v in obs.values())
    full = ladder[-1][2]

    if as_json:
        print(json.dumps({
            "ventures": [{"venture": v, "words": w_, "heading_words": h}
                         for v, w_, h in ventures],
            "root": root,
            "tokens_per_word": TOK_PER_WORD,
            "declared": {"files": len(dec), "words": dw, "detail": dec},
            "observed": {"files": len(obs), "words": ow, "detail": obs},
            "ratio_observed_to_declared": round(ow / dw, 2) if dw else None,
            "rungs": [{"rung": r, "what": w, "words": n,
                       "tokens_est": int(n * TOK_PER_WORD), "when": note}
                      for r, w, n, note in ladder],
            "floor_to_everything_ratio": round(full / max(ladder[1][2], 1), 2),
            "cheap_if_under_ratio": CHEAP_IF_UNDER,
            "read_everything_is_cheap": full <= ladder[1][2] * CHEAP_IF_UNDER,
        }, indent=2))
        return 0

    print("Context ladder for %s" % base)
    print("  EACH RUNG INCLUDES EVERY RUNG BELOW IT -- rung 2 is the whole floor plus")
    print("  declared/, never declared/ instead of it. The figures are cumulative totals.")
    print("  declared/  %6d words in %2d files" % (dw, len(dec)))
    print("  observed/  %6d words in %2d files%s" % (
        ow, len(obs), "   (%.1fx declared/)" % (ow / dw) if dw else ""))
    if ventures:
        vw = sum(v[1] for v in ventures)
        print("  ventures/  %6d words in %2d ventures  (mapped at the floor, ONE opened on demand)"
              % (vw, len(ventures)))
        for v, w_, h in ventures:
            print("      %-18s %6d words   ~%5d tok to read this one venture"
                  % (v, w_, int(w_ * TOK_PER_WORD)))
    print()
    for r, what, n, note in ladder:
        print("  rung %s  %-36s %7d words  ~%6d tok   %s"
              % (r, what, n, int(n * TOK_PER_WORD), note))
    print()
    ratio = full / max(ladder[1][2], 1)
    if ratio <= CHEAP_IF_UNDER:
        print("  VERDICT: everything is only %.1fx the floor (~%d tok). Read ALL of it."
              % (ratio, int(full * TOK_PER_WORD)))
        print("           Below %.1fx, deciding what to skip costs more than reading it."
              % CHEAP_IF_UNDER)
    else:
        print("  VERDICT: everything is %.1fx the floor (~%d tok) -- too much to spend BEFORE"
              % (ratio, int(full * TOK_PER_WORD)))
        print("           the first question.")
        print("           Floor at rung 1. Climb to rung 2 when your output speaks as the operator.")
        print("           Open individual observed/ entries by title, on demand, at any time.")
        print("           Rung 3 is still RIGHT here when the TASK IS THE CONTEXT ITSELF --")
        print("           synthesising across their history, auditing or compacting the observed")
        print("           files, deriving a pattern that only shows up across many of them, or")
        print("           answering AS them. An index cannot serve those; the corpus is the input.")
    print("  (token figures are an estimate at %.1f tok/word; the RATIO between rungs is the signal)"
          % TOK_PER_WORD)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
