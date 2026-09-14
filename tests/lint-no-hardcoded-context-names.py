#!/usr/bin/env python3
"""Fail if a context hook MATCHES ON a canonical filename in its code.

A filename in a comment or docstring is an example that keeps an exception legible.
A filename in code is a matcher, and matchers go stale: both context folders vary per
vault -- operators rename these files, add their own, and write them in their own
language -- so a hook keyed on `antifragile.md` silently does nothing on a vault that
calls it something else.

Distinguishing the two needs a tokenizer. Two earlier versions of this guard tried and
failed: one grepped the raw file, one stripped with sed and missed docstring bodies, and
both failed a hook that was correct. A guard that cannot be precise about its own claim
is the thing this suite exists to prevent.

    python3 tests/lint-no-hardcoded-context-names.py hooks/context-floor.py ...
"""
import io
import sys
import tokenize

NAMES = ("antifragile", "preferences.md", "patterns.md", "growth.md", "about_me", "personal_voice")
TRIPLES = ('"' * 3, "'" * 3)


def hits(path):
    out = []
    with open(path, encoding="utf-8") as fh:
        src = fh.read()
    for tok in tokenize.generate_tokens(io.StringIO(src).readline):
        if tok.type == tokenize.COMMENT:
            continue
        if tok.type == tokenize.STRING:
            body = tok.string.lstrip("rbfuRBFU")
            if body[:3] in TRIPLES:       # docstring / block prose, not a matcher
                continue
            if any(n in tok.string.lower() for n in NAMES):
                out.append((tok.start[0], tok.string[:70]))
    return out


def main(argv):
    bad = 0
    for path in argv:
        for line, snippet in hits(path):
            print("  %s:%d matches a canonical filename in code: %s" % (path, line, snippet))
            bad += 1
    if bad:
        print("  A per-vault filename is not a matcher. Detect the SHAPE instead "
              "(a heading pattern, a glob), or the hook is silent on a renamed vault.")
        return 1
    print("lint-no-hardcoded-context-names: clean — no context filename is matched on in code")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or ["hooks/context-floor.py", "hooks/context-rungs.py"]))
