#!/usr/bin/env bash
# voice-gate's candidate finder is one versioned script, so runs compare (#271). Checks the exact
# count on a sample with known tells, zero on clean text, that quotes/code/blockquotes are never
# counted, that two runs print the same output, and that the skill points at the script.
# Usage: bash tests/voice-gate-finder.test.sh [repo-root]. Written for bash 3.2.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1
F="skills/aios/voice-gate/finder.py"
S="skills/aios/voice-gate/SKILL.md"
T=$(mktemp -d "${TMPDIR:-/tmp}/vgf.XXXXXX")
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
no(){ fail=$((fail+1)); echo "  FAIL $1"; }
echo "voice-gate-finder"
[ -f "$F" ] && ok "the finder ships at $F" || { no "the finder ships at $F"; echo "$pass passed, $fail failed"; exit 1; }

cat > "$T/tells.md" <<'EOF'
---
title: sample
---
This launch is not about speed, it's about trust. At its core, the plan is simple.

Honestly? We built a robust pipeline. It serves as the backbone of the release.

I hope this helps the team decide.
EOF
cat > "$T/clean.md" <<'EOF'
We shipped the update on Tuesday. The build took four minutes and the tests passed.

The next step is the Windows check, which runs on the CI lane tomorrow.
EOF
cat > "$T/quoted.md" <<'EOF'
She said "it's not a bug, it's a feature" and laughed. Run `delve --robust` to test.

> At its core, a quoted line never counts.

```
let's dive in, a testament to code that is never counted
```

The word “pivotal” in curly quotes is being discussed, not used.
EOF

printf 'It\342\200\231s not a tool, it\342\200\231s a partner.\n\nHere\342\200\231s the thing about it.\n' > "$T/curly.md"
count(){ python3 "$F" "$1" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["results"][0]["candidates"])'; }
[ "$(count "$T/tells.md")" = 6 ] && ok "sample with six known tells counts exactly 6" || no "sample count: got $(count "$T/tells.md"), want 6"
[ "$(count "$T/clean.md")" = 0 ] && ok "clean text counts 0" || no "clean text: got $(count "$T/clean.md")"
[ "$(count "$T/quoted.md")" = 0 ] && ok "quotes, code spans, fences and blockquotes count 0" || no "quoted/code text: got $(count "$T/quoted.md")"
[ "$(count "$T/curly.md")" = 2 ] && ok "curly apostrophes (it’s, here’s) match like straight ones" || no "curly apostrophes: got $(count "$T/curly.md"), want 2"
python3 "$F" "$T/curly.md" --json | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["results"][0]["words"]==12 else 1)' \
  && ok "a word with a curly apostrophe counts once" || no "curly-apostrophe words split in two"
python3 "$F" "$T/tells.md" > "$T/a"; python3 "$F" "$T/tells.md" > "$T/b"
cmp -s "$T/a" "$T/b" && ok "two runs print the same output" || no "two runs differ"
head -1 "$T/a" | grep -qE '^voice-gate finder v[0-9]+ \(patterns [0-9a-f]{8}\)$' && ok "the first line names the version and the pattern hash" || no "version line: $(head -1 "$T/a")"
python3 "$F" "$T/tells.md" --json | python3 -c 'import json,sys; r=json.load(sys.stdin)["results"][0]; sys.exit(0 if r["burst_paragraphs"] and r["words"]>0 else 1)' \
  && ok "the summary reports words and paragraphs with two or more" || no "summary fields missing"
grep -qF "skills/aios/voice-gate/finder.py" "$S" && ok "the skill tells every run to use the bundled finder" || no "the skill does not name the finder"
grep -qF "finder version" "$S" && ok "the report names the finder version beside the density" || no "the skill does not ask for the finder version"
grep -q 'sys.platform == "win32"' "$F" && ok "the finder guards Windows output" || no "no Windows output guard"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
