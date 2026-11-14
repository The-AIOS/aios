#!/usr/bin/env bash
# hooks/openrouter.py tries the next configured provider when one is out of credits, over a
# spend cap or rate-limited (HTTP 402/429), and says so when every one is exhausted. Any other
# failure (a bad key, a bad request) is reported as is, never retried elsewhere, and a forced
# --provider never falls back. Offline: both providers are faked.
# Usage: bash tests/openrouter-fallback.test.sh [repo-root]. Written for bash 3.2.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1
python3 - <<'PY'
import contextlib, importlib.util, io, os, sys
ok = fail = 0
def check(name, cond):
    global ok, fail
    if cond: ok += 1; print("  ok   " + name)
    else: fail += 1; print("  FAIL " + name)
print("openrouter-fallback")
os.environ["OPENROUTER_API_KEY"] = "sk-or-test"; os.environ["GEMINI_API_KEY"] = "g-test"
spec = importlib.util.spec_from_file_location("orb", "hooks/openrouter.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.load_env = lambda name: {}
calls = []
def fake(name, behaviour):
    def f(key, model, prompt, system):
        calls.append((name, model))
        if isinstance(behaviour, Exception): raise behaviour
        return behaviour, name + "-model", {}
    return f
def run(argv, orb, gem):
    calls.clear()
    m.call_openrouter, m.call_gemini = fake("openrouter", orb), fake("gemini", gem)
    out, err = io.StringIO(), io.StringIO()
    sys.argv = ["openrouter.py"] + argv
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        rc = m.main()
    return rc, out.getvalue(), err.getvalue()
no_credits = RuntimeError("HTTP 402 from https://openrouter.ai/api/v1/chat/completions\n{\"error\":{\"message\":\"This request requires more credits\"}}")
capped = RuntimeError("HTTP 429 from https://generativelanguage.googleapis.com\n{\"error\":{\"status\":\"RESOURCE_EXHAUSTED\"}}")
bad_key = RuntimeError("HTTP 401 from https://openrouter.ai/api/v1/chat/completions\n{\"error\":\"invalid key\"}")

rc, out, err = run(["--prompt", "hi", "--model", "x/y"], no_credits, "from gemini")
check("OpenRouter out of credits: Gemini answers", rc == 0 and "from gemini" in out)
check("the hand-over is said, not silent", "trying the next provider" in err)
check("a provider-specific model id is not sent to the next provider", calls == [("openrouter", "x/y"), ("gemini", None)])

rc, out, err = run(["--prompt", "hi"], no_credits, capped)
check("every provider exhausted: fails, naming each", rc == 1 and "every configured provider" in err and "openrouter (HTTP 402" in err and "gemini (HTTP 429" in err)

blip = RuntimeError("HTTP 429 from https://openrouter.ai/api/v1/chat/completions\n{\"error\":{\"message\":\"Rate limit exceeded, retry in 2s\"}}")
rc, out, err = run(["--prompt", "hi"], blip, "from gemini")
check("a momentary rate limit does not send the prompt to another provider", rc == 1 and calls == [("openrouter", None)])

rc, out, err = run(["--prompt", "hi"], bad_key, "from gemini")
check("a bad key is reported, never retried elsewhere", rc == 1 and calls == [("openrouter", None)] and "HTTP 401" in err)

rc, out, err = run(["--prompt", "hi", "--provider", "openrouter"], no_credits, "from gemini")
check("a forced provider never falls back", rc == 1 and calls == [("openrouter", None)])

rc, out, err = run(["--prompt", "hi"], "from openrouter", "from gemini")
check("a working OpenRouter is used alone", rc == 0 and "from openrouter" in out and calls == [("openrouter", None)])
print("%d passed, %d failed" % (ok, fail))
sys.exit(1 if fail else 0)
PY
