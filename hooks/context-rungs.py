#!/usr/bin/env python3
"""Measure what each rung of the context ladder costs IN THIS VAULT.

Why this ships as code rather than as numbers written into CLAUDE.md:

    "Read everything" was CORRECT when it was written. A fresh clone's entire
    context is a few thousand words -- cheaper than the paragraph telling you
    to skip it. It silently stopped being correct as the vault grew past a
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

import json
import os
import re
import sys

# ~1.3 tokens per English word. An ESTIMATE, stated as one everywhere it surfaces:
# the point is the ratio between rungs, which is robust to the constant being off.
TOK_PER_WORD = 1.3

HEADING = re.compile(r"^\#{2,6}\s+\S")
ENTRY = re.compile(r"^\#{3}\s+\S")

# The four observed/ files whose ENTRY TITLES are the floor (CLAUDE.md step 4a).
FLOOR = ("antifragile.md", "preferences.md", "patterns.md", "growth.md")


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
        out[name] = {
            "words": words,
            "headings": len(heads),
            "entries": sum(1 for l in lines if ENTRY.match(l)),
            "heading_words": sum(len(l.split()) for l in heads),
        }
    return out


def rungs(dec, obs):
    """The four rungs, in the order a session climbs them."""
    def s(d, key, only=None):
        if not d:
            return 0
        return sum(v[key] for k, v in d.items() if only is None or k in only)

    idx = s(dec, "words", {"_index.md"}) + s(obs, "words", {"_index.md"})
    # Rung 1 adds every heading in both folders -- that IS the index.
    heads = s(dec, "heading_words") + s(obs, "heading_words")
    dec_body = s(dec, "words") - s(dec, "words", {"_index.md"})
    obs_body = s(obs, "words") - s(obs, "words", {"_index.md"})
    return [
        ("0", "both _index.md only", idx,
         "orientation only -- you know the filenames, nothing else"),
        ("1", "+ every heading in both folders", idx + heads,
         "THE FLOOR. Always, whatever the task."),
        ("2", "+ declared/ read whole", idx + heads + dec_body,
         "when your output will be read as the words of the operator"),
        ("3", "+ observed/ read whole (everything)", idx + heads + dec_body + obs_body,
         "rarely correct on a mature vault; correct on a small one"),
    ]


def main(argv):
    as_json = "--json" in argv
    args = [a for a in argv if not a.startswith("-")]
    root = args[0] if args else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    base = os.path.join(root, "vault", "00 - notes", "context")
    dec, obs = measure(os.path.join(base, "declared")), measure(os.path.join(base, "observed"))

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

    ladder = rungs(dec, obs)
    dw = sum(v["words"] for v in dec.values())
    ow = sum(v["words"] for v in obs.values())
    full = ladder[-1][2]

    if as_json:
        print(json.dumps({
            "root": root,
            "tokens_per_word": TOK_PER_WORD,
            "declared": {"files": len(dec), "words": dw, "detail": dec},
            "observed": {"files": len(obs), "words": ow, "detail": obs},
            "ratio_observed_to_declared": round(ow / dw, 2) if dw else None,
            "rungs": [{"rung": r, "what": w, "words": n,
                       "tokens_est": int(n * TOK_PER_WORD), "when": note}
                      for r, w, n, note in ladder],
            "read_everything_is_cheap": full * TOK_PER_WORD < 25000,
        }, indent=2))
        return 0

    print("Context ladder for %s" % base)
    print("  declared/  %6d words in %2d files" % (dw, len(dec)))
    print("  observed/  %6d words in %2d files%s" % (
        ow, len(obs), "   (%.1fx declared/)" % (ow / dw) if dw else ""))
    print()
    for r, what, n, note in ladder:
        print("  rung %s  %-36s %7d words  ~%6d tok   %s"
              % (r, what, n, int(n * TOK_PER_WORD), note))
    print()
    if full * TOK_PER_WORD < 25000:
        print("  VERDICT: this whole context is ~%d tokens. Read ALL of it (rung 3)."
              % int(full * TOK_PER_WORD))
        print("           The ladder exists for vaults that have grown past this. Yours has not.")
    else:
        print("  VERDICT: rung 3 is ~%d tokens -- too much to spend before the first question."
              % int(full * TOK_PER_WORD))
        print("           Floor at rung 1. Climb to rung 2 when your output speaks as the operator.")
        print("           Open individual observed/ entries by title, on demand, at any time.")
    print("  (token figures are an estimate at %.1f tok/word; the RATIO between rungs is the signal)"
          % TOK_PER_WORD)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
