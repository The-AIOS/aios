#!/usr/bin/env python3
"""openrouter.py — call a non-Claude model as a tool. Text in, text out.

WHY THIS EXISTS
    Two needs turn out to be the same piece of code:
      1. A cheap lane for text work where Claude is the wrong instrument.
      2. An INDEPENDENT judge. A model cannot dock points for a systematic
         tendency it shares, so scoring Claude-authored prose with a Claude
         model is a family grading itself. See MODEL-ROUTING.md § Judge
         independence.

WHAT IT DELIBERATELY CANNOT DO
    No MCP tools. No vault writes. No credentials but its own key. A
    non-Claude model is called BY an AIOS session and never IS one — that
    boundary is the point, not a limitation (MODEL-ROUTING.md § The
    containment boundary).

    In particular: never route Claude Code itself through a third-party
    proxy to change models. Every session holds live Gmail/Drive/Slack
    credentials and a private vault; a proxy sits in the request path of
    all of them.

THE PRIVACY TRADE, STATED PLAINLY
    This is the one AIOS component that sends your content off-machine to a
    third party. That is the mechanism, not a caveat. So it is OPT-IN and
    SILENT UNTIL CONFIGURED: with no key on disk it makes no call, exits
    non-zero, and names the exact file to create. It never guesses, never
    prompts, and never falls back to something that would send your data
    somewhere you did not choose.

    Pass it prose drafts. Do not pass it client material, NDA'd content,
    financial records, or personal context.

PROVIDER RESOLUTION — OpenRouter first, Gemini second, then stop
    1. OPENROUTER_API_KEY  -> OpenRouter (one key, one account, hundreds of
       models; switching model is a string change).
    2. GEMINI_API_KEY      -> Gemini direct. The fallback because a Gemini
       key is already present in many AIOS installs (it is what the
       nano-banana MCP uses), so the rail works before anyone funds a new
       account.
    3. Neither             -> fail, naming BOTH paths and both file
       locations. Never a silent no-op: a scorer that quietly returns
       nothing reads exactly like a scorer that found nothing wrong.

    Keys are read from ~/.config/aios-secrets/{openrouter,gemini}.env
    (KEY=value, one per line), then from the environment. The file is
    preferred so a key never has to live in a shell rc.

USAGE
    python3 hooks/openrouter.py --prompt "..." [--model ID] [--system ...]
    python3 hooks/openrouter.py --prompt-file brief.md --json
    python3 hooks/openrouter.py --check          # what is configured, no call

    --model accepts an OpenRouter id (e.g. google/gemini-3-pro,
    deepseek/deepseek-v4) or, on the Gemini path, a bare Gemini id. Omit it
    for the provider's default.

STDLIB ONLY. The OpenRouter endpoint is OpenAI-compatible, so urllib is
enough; nothing to pip install, which is what keeps this runnable from a
routine on a fresh machine.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

SECRETS_DIR = Path.home() / ".config" / "aios-secrets"

OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
# Defaults are VERIFIED ids, not plausible ones. The first draft of this file
# guessed an OpenRouter id and a bare Gemini id that both LOOKED right and
# neither existed: the public OpenRouter catalog (no auth needed:
# GET https://openrouter.ai/api/v1/models) did not carry the first, and the
# second 404'd on generateContent. Both were replaced with ids checked against
# the live catalogs. Re-check the same way before changing either — a
# plausible-looking model id is the easiest wrong specific to ship, because it
# fails only at call time and then looks like an outage rather than a typo.
OPENROUTER_DEFAULT = "google/gemini-2.5-pro"

GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
# A FLOATING alias, deliberately: it tracks the current Gemini Pro rather than
# pinning a version this file would then have to chase. Verified serving
# generateContent (HTTP 200).
GEMINI_DEFAULT = "gemini-pro-latest"

TIMEOUT = 180


def load_env(name):
    """Read KEY=value pairs from ~/.config/aios-secrets/{name}.env into a dict.

    Returns {} when the file is absent — an absent secrets file is the normal
    unconfigured state, not an error. Malformed lines are skipped rather than
    raising, so one bad line cannot take out a key that parsed fine.
    """
    path = SECRETS_DIR / f"{name}.env"
    out = {}
    if not path.exists():
        return out
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        out[k.strip()] = v.strip().strip("'\"")
    return out


def find_key(var, secrets_name):
    """Secrets file first, environment second. Empty/whitespace is NOT a key.

    The empty-string check is load-bearing: `export OPENROUTER_API_KEY=` is a
    very easy thing to have in a shell rc, and treating "" as present sends a
    request with an empty Authorization header that fails as a 401 — an auth
    error for a key that was never set, which is a wrong cause and directs the
    work at the wrong place.
    """
    v = load_env(secrets_name).get(var) or os.environ.get(var) or ""
    v = v.strip()
    return v or None


def resolve_provider(force=None):
    """-> (provider, key) or (None, None). OpenRouter first, Gemini second."""
    if force in (None, "openrouter"):
        k = find_key("OPENROUTER_API_KEY", "openrouter")
        if k:
            return "openrouter", k
        if force == "openrouter":
            return None, None
    if force in (None, "gemini"):
        k = find_key("GEMINI_API_KEY", "gemini")
        if k:
            return "gemini", k
        if force == "gemini":
            return None, None
    return None, None


def unconfigured_message(force=None):
    """The error text for 'no key anywhere'. Names every path and every file.

    Deliberately verbose. This is the message an operator meets the first time
    they touch the rail, and the failure mode it replaces — a rail that reports
    'unavailable' without saying what to do — costs more than the words do.
    """
    lines = ["openrouter.py: no provider key found — this rail is opt-in and makes no call until one exists.", ""]
    if force in (None, "openrouter"):
        lines += [
            "  OpenRouter (preferred — one key reaches hundreds of models):",
            f"    mkdir -p {SECRETS_DIR}",
            f"    echo 'OPENROUTER_API_KEY=sk-or-...' >> {SECRETS_DIR / 'openrouter.env'}",
            "    Key: https://openrouter.ai/keys",
            "",
        ]
    if force in (None, "gemini"):
        lines += [
            "  Gemini direct (fallback — a key may already be present for the nano-banana MCP):",
            f"    echo 'GEMINI_API_KEY=...' >> {SECRETS_DIR / 'gemini.env'}",
            "    Key: https://aistudio.google.com/apikey",
            "",
        ]
    lines += [
        "  Either file is read before the environment, so the key never has to live in a shell rc.",
        "  What this rail sends off-machine, and what not to pass it: MODEL-ROUTING.md",
    ]
    return "\n".join(lines)


def _post(url, payload, headers):
    """POST JSON, return parsed JSON. Raises RuntimeError with the response body.

    The body matters: provider errors carry the actionable half (an invalid
    model id, a spent balance) and urllib's exception string alone is just the
    status code.
    """
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode("utf-8"), headers=headers, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", errors="replace")[:1200]
        except Exception:
            pass
        raise RuntimeError(f"HTTP {e.code} from {url}\n{body}") from None
    except urllib.error.URLError as e:
        raise RuntimeError(f"could not reach {url}: {e.reason}") from None


def call_openrouter(key, model, prompt, system):
    msgs = ([{"role": "system", "content": system}] if system else []) + [
        {"role": "user", "content": prompt}
    ]
    d = _post(
        OPENROUTER_URL,
        {"model": model or OPENROUTER_DEFAULT, "messages": msgs},
        {
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            # OpenRouter attributes traffic by these; harmless and honest.
            "HTTP-Referer": "https://github.com/The-AIOS/aios",
            "X-Title": "AIOS",
        },
    )
    try:
        text = d["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        raise RuntimeError(f"unexpected OpenRouter response shape: {json.dumps(d)[:600]}") from None
    return text, (d.get("model") or model or OPENROUTER_DEFAULT), d.get("usage") or {}


def call_gemini(key, model, prompt, system):
    m = model or GEMINI_DEFAULT
    payload = {"contents": [{"parts": [{"text": prompt}]}]}
    if system:
        payload["systemInstruction"] = {"parts": [{"text": system}]}
    d = _post(
        GEMINI_URL.format(model=m),
        payload,
        {"x-goog-api-key": key, "Content-Type": "application/json"},
    )
    try:
        text = "".join(
            p.get("text", "") for p in d["candidates"][0]["content"]["parts"]
        )
    except (KeyError, IndexError, TypeError):
        raise RuntimeError(f"unexpected Gemini response shape: {json.dumps(d)[:600]}") from None
    return text, m, d.get("usageMetadata") or {}


def main():
    ap = argparse.ArgumentParser(
        description="Call a non-Claude model as a tool (text in, text out).",
        epilog="Boundaries and the privacy trade: MODEL-ROUTING.md",
    )
    src = ap.add_mutually_exclusive_group()
    src.add_argument("--prompt", help="prompt text")
    src.add_argument("--prompt-file", help="read the prompt from a file ('-' for stdin)")
    ap.add_argument("--system", help="system instruction")
    ap.add_argument("--system-file", help="read the system instruction from a file")
    ap.add_argument("--model", help="provider model id (omit for the provider default)")
    ap.add_argument(
        "--provider",
        choices=["openrouter", "gemini"],
        help="force one provider instead of resolving OpenRouter-then-Gemini",
    )
    ap.add_argument("--json", action="store_true", help="emit JSON (text + model + usage)")
    ap.add_argument(
        "--check",
        action="store_true",
        help="report what is configured and exit; makes no call",
    )
    a = ap.parse_args()

    provider, key = resolve_provider(a.provider)

    if a.check:
        # Report the resolution WITHOUT the key. A --check that prints a secret
        # is a --check nobody can safely paste into an issue.
        print(f"secrets dir : {SECRETS_DIR}")
        for var, nm, label in (
            ("OPENROUTER_API_KEY", "openrouter", "openrouter"),
            ("GEMINI_API_KEY", "gemini", "gemini"),
        ):
            k = find_key(var, nm)
            where = "not found"
            if k:
                where = "secrets file" if load_env(nm).get(var, "").strip() else "environment"
            print(f"  {label:<11}: {'configured' if k else 'not configured'} ({where})")
        print(f"resolved    : {provider or 'NONE — the rail will refuse rather than guess'}")
        return 0

    if not provider:
        print(unconfigured_message(a.provider), file=sys.stderr)
        return 3

    if a.prompt_file:
        prompt = sys.stdin.read() if a.prompt_file == "-" else Path(a.prompt_file).read_text(
            encoding="utf-8"
        )
    elif a.prompt:
        prompt = a.prompt
    else:
        ap.error("one of --prompt or --prompt-file is required (or use --check)")

    if not prompt.strip():
        print("openrouter.py: refusing to send an empty prompt", file=sys.stderr)
        return 2

    system = a.system
    if a.system_file:
        system = Path(a.system_file).read_text(encoding="utf-8")

    try:
        fn = call_openrouter if provider == "openrouter" else call_gemini
        text, model_used, usage = fn(key, a.model, prompt, system)
    except RuntimeError as e:
        print(f"openrouter.py: {provider} call failed — {e}", file=sys.stderr)
        return 1

    if not text.strip():
        # An empty completion is a FAILURE, not an answer. A judge that returns
        # nothing reads identically to a judge that found nothing wrong.
        print(
            f"openrouter.py: {provider} ({model_used}) returned an empty completion — "
            "treating as failure, not as an empty result",
            file=sys.stderr,
        )
        return 1

    if a.json:
        print(json.dumps({"provider": provider, "model": model_used, "usage": usage, "text": text}, indent=2))
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
