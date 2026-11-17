#!/usr/bin/env bash
# Security fixes carried in v0.8.19 for code that predates it:
#  - bus_log fingerprints inbox writes on Windows paths too (mixed separators matched nothing);
#  - issue-scrub loads **bold** and linked names, and redacts private folders in home paths;
#  - video-watch's headless reader may read only its frames, and a "URL" can never be an option.
# Usage: bash tests/security-fixes-0819.test.sh [repo-root]. Written for bash 3.2.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
no(){ fail=$((fail+1)); echo "  FAIL $1"; }
echo "security-fixes-0819"

python3 - <<'PY' && ok "bus_log recognises a Windows inbox path with mixed separators" || no "bus_log misses Windows inbox paths"
import sys, ntpath; sys.path.insert(0, "hooks/context"); import bus_log
box = "C:\\Users\\x/.aios/spawn-inbox"
assert bus_log.in_inbox("C:\\Users\\x\\.aios\\spawn-inbox\\worker.json", box, ntpath)
assert bus_log.in_inbox("c:/users/X/.aios/spawn-inbox/worker.json", box, ntpath)
assert not bus_log.in_inbox("C:\\Users\\x\\.aios\\other\\worker.json", box, ntpath)
PY

python3 - <<'PY' && ok "issue-scrub loads **bold** and linked names; skips *italic* examples" || no "issue-scrub name loading wrong"
import importlib.util as u
s = u.spec_from_file_location("s", "hooks/security/issue-scrub.py"); m = u.module_from_spec(s); s.loader.exec_module(m)
got = m.table_first_column("| Name | x |\n|---|---|\n| **Acme Corp** | a |\n| [Northwind](https://n.example) | b |\n| [[Globex]] | c |\n| *Example Co* | d |\n")
assert got == ["Acme Corp", "Northwind", "Globex"], got
PY

python3 - <<'PY' && ok "issue-scrub redacts private folders in home paths, keeps framework paths" || no "home path redaction wrong"
import importlib.util as u
s = u.spec_from_file_location("s", "hooks/security/issue-scrub.py"); m = u.module_from_spec(s); s.loader.exec_module(m)
rx = m.HOME_PATHS[0]
f = lambda t: rx.sub(lambda x: "~" + m.home_rest(x.group(1)), t)
assert f("see /Users/jo/Clients/Northwind-litigation/brief.pdf now") == "see ~/<path redacted> now", f("see /Users/jo/Clients/Northwind-litigation/brief.pdf now")
assert f("run /Users/jo/aios/hooks/vault/aios-commit") == "run ~/aios/hooks/vault/aios-commit"
assert f("home is /Users/jo") == "home is ~"
p = lambda t: m.HOME_PRIVATE[0].sub("~/<path redacted>", t)
assert "Acme" not in p("see /Users/jo/Google Drive/Clients/Acme Litigation/brief.pdf"), "a path with spaces leaked"
assert "Clients" not in p("x /Users/jo/aios/../Clients/Acme"), "aios/.. escaped the redaction"
assert p("run /Users/jo/aios/hooks/x.py") == "run /Users/jo/aios/hooks/x.py"
w = m.HOME_PRIVATE[1].sub("~/<path redacted>", r"C:\Users\jo\My Documents\Acme Corp\file.docx")
assert "Acme" not in w, w
assert "Acme Corp" in m.table_first_column("| Name |\n|---|\n| [[acme-corp\\|Acme Corp]] |\n")
PY

V=hooks/media/video-watch.py
grep -qE '"--allowedTools", "Read\(/%s/\*\*\)" % fdir, "--setting-sources", "project"' "$V" && grep -q 'cwd=fdir' "$V" \
  && ok "video-watch's headless reader may read only its frames folder, with no user allow rules" || no "video-watch's reader is not scoped to its frames"
grep -q '"--quiet", "--", url' "$V" && grep -q 're.match(r"https?://", src, re.I)' "$V" && grep -q 'src = os.path.abspath(src)' "$V" && grep -q 'workdir = os.path.abspath(a.workdir)' "$V" \
  && ok "a video URL must be http(s) and follows --; a local path is made absolute" || no "video-watch input can still be read as an option"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
