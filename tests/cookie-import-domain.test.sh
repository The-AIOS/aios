#!/usr/bin/env bash
# tests/cookie-import-domain.test.sh
#
# mcps/playwright-mcp/cookie_import.py asks browser_cookie3 for each configured domain, and
# browser_cookie3 matches the cookie store with host LIKE '%<domain>%' (case-insensitive). So the
# "x" site ("x.com") also received box.com, dropbox.com, wix.com and any other host that merely
# contains those letters, such as x.com.example.net. Checks, against a stub that behaves the same way:
#   1. the "x" import keeps x.com, its subdomains and twitter.com, and nothing that only shares
#      the suffix (box.com, xbox.com, dropbox.com, wix.com);
#   2. every SITES entry is filtered the same way (a look-alike of substack.com is dropped);
#   3. the output file is owner-only (0600), including when it already existed with a wider mode;
#   4. CONTROL: the same importer with its filter turned off keeps box.com on this stub, so
#      check 1 is known to be able to fail (no git history needed; CI clones shallow).
# Usage: bash tests/cookie-import-domain.test.sh [repo-root]. Written for bash 3.2.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1
T="$(mktemp -d)" || exit 1; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stub"
cat > "$T/stub/browser_cookie3.py" <<'PY'
# Behaves like browser_cookie3.chrome(domain_name=d): host LIKE '%d%', case-insensitive.
from http.cookiejar import Cookie, CookieJar
STORE = ["x.com", ".x.com", "mobile.x.com", ".twitter.com", "box.com", ".xbox.com",
         ".dropbox.com", "wix.com", "substack.com", ".notsubstack.com", ".linkedin.com",
         ".x.com.example.net", "x.community", "WWW.X.COM"]
def _c(domain, name):
    return Cookie(0, name, "v-" + domain, None, False, domain, True, domain.startswith("."),
                  "/", True, True, None, False, None, None, {})
def chrome(domain_name=""):
    jar = CookieJar()
    for d in STORE:
        if domain_name.lower() in d.lower():
            jar.set_cookie(_c(d, "auth_token" if "x.com" in d else "sid"))
    return jar
PY
run(){ # $1 = path to the importer under test, $2 = site, $3 = output dir
  PYTHONPATH="$T/stub" python3 - "$1" "$2" "$3" <<'PY'
import contextlib, importlib.util, io, json, os, sys
src, site, out = sys.argv[1:]
spec = importlib.util.spec_from_file_location("ci", src); m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.AUTH_DIR = out
with contextlib.redirect_stdout(io.StringIO()):
    m.import_site(site)
d = json.load(open(os.path.join(out, site + ".json")))
print(" ".join(sorted({c["domain"] for c in d["cookies"]})))
PY
}
PASS=0; FAIL=0
ok(){ echo "  ok   $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL $1"; [ -n "${2:-}" ] && echo "       $2"; FAIL=$((FAIL+1)); }
echo "cookie import keeps only the site's own domains"
H="$ROOT/mcps/playwright-mcp/cookie_import.py"
mkdir -p "$T/out"
x=$(run "$H" x "$T/out" 2>/dev/null)
[ "$x" = ".twitter.com .x.com mobile.x.com www.x.com x.com" ] && ok "x keeps x.com, its subdomains and twitter.com" || no "x kept the wrong set" "$x"
case " $x " in "  ") no "x imported nothing; the drop check proves nothing" ;; *box.com*|*dropbox*|*wix.com*|*example.net*|*community*) no "x kept another site's cookies" "$x" ;; *) ok "box.com, xbox.com, dropbox.com, wix.com, x.com.example.net and x.community are dropped" ;; esac
s=$(run "$H" substack "$T/out" 2>/dev/null)
[ "$s" = "substack.com" ] && ok "every site is filtered: a look-alike of substack.com is dropped" || no "substack kept a look-alike" "$s"
mode=$(stat -c '%a' "$T/out/x.json" 2>/dev/null || stat -f '%Lp' "$T/out/x.json")
[ "$mode" = "600" ] && ok "the cookie file is owner-only (0600)" || no "cookie file mode is $mode"
chmod 644 "$T/out/x.json"; run "$H" x "$T/out" >/dev/null 2>&1
mode=$(stat -c '%a' "$T/out/x.json" 2>/dev/null || stat -f '%Lp' "$T/out/x.json")
[ "$mode" = "600" ] && ok "an existing wider-mode file is narrowed to 0600" || no "existing file kept mode $mode"
# Control, independent of git history (CI clones shallow): the same importer with its filter
# turned off must keep box.com on this stub, or check 1 proves nothing.
mkdir -p "$T/ctl"
o=$(PYTHONPATH="$T/stub" python3 - "$H" "$T/ctl" <<'PY'
import contextlib, importlib.util, io, json, os, sys
src, out = sys.argv[1:]
spec = importlib.util.spec_from_file_location("ci", src); m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.AUTH_DIR = out; m.domain_matches = lambda *a: True
with contextlib.redirect_stdout(io.StringIO()):
    m.import_site("x")
print(" ".join(sorted({c["domain"] for c in json.load(open(os.path.join(out, "x.json")))["cookies"]})))
PY
)
case " $o " in *" box.com "*) ok "control: without the filter, box.com comes back, so check 1 can fail" ;; *) no "control: the stub did not reproduce the bug; check 1 proves nothing" "$o" ;; esac
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
