# Upstream: `workspace-mcp`

- **Package:** [`workspace-mcp`](https://pypi.org/project/workspace-mcp/) (PyPI) · [taylorwilsdon/google_workspace_mcp](https://github.com/taylorwilsdon/google_workspace_mcp)
- **License:** MIT · **Author:** taylorwilsdon
- **How we consume it:** `uvx workspace-mcp` — resolved from PyPI at launch. **We vendor none of it.**

## Why we stopped vendoring (2026-07-28)

This folder used to hold a full copy of the upstream server, and `SETUP.md` registered it via
`uv run --directory …`. That was a deliberate choice with three stated reasons: pin a known-good
audited version, let teammates install from the repo instead of PyPI, and track any local
modifications in git. Reasonable goals. Here is what actually happened:

- **The copy froze at 1.15.0** while upstream reached 1.22.2 — seven minor versions, including
  several OAuth fixes (v1.22.2 specifically ends an hourly re-auth loop). We never modified the
  vendored code, so reason 3 bought nothing.
- **It was quietly broken.** `main.py` imported `gappsscript.apps_script_tools`, a module that was
  never copied in. Enabling that service would have raised ImportError. Nobody noticed, because
  nobody ran the vendored copy on the machine where it was maintained.
- **Three surfaces gave three different answers** about what the runtime even was: `SETUP.md` said
  the vendored tree, `mcps/setup.sh`'s own summary said `uvx`, `mcps/_index.md` said "vendored."
- **It cost every operator ~196 MB** — `setup.sh` built a venv for a runtime their registration
  didn't point at. The source was only 1.6 MB; the venv was the rest.

The decisive lesson is about reason 1, not reason 2 or 3: **a pin with no bump discipline is not a
pin, it's a freeze.** Pinning is only safer than floating if something reliably raises the version.
Nothing did, so "pinned to a known-good version" silently became "stuck on a stale, broken one" —
strictly worse than floating, because it also felt deliberate.

So the default is now **unpinned `uvx`**: upstream ships frequently and maintains OAuth actively,
and staying current has empirically been the lower risk (this vault ran unpinned across ~25
releases without incident).

## If you want determinism anyway

Pinning is legitimate — for a fortress machine, a shared team install, or after a bad release. Pin
in the registration itself, not by copying code:

```bash
claude mcp add google-workspace … -- uvx workspace-mcp@1.22.2 --single-user --permissions …
```

**If you pin, own the bump.** Put a recurring check somewhere you actually read, and compare against
`pip index versions workspace-mcp` (or the PyPI JSON API). An unbumped pin is the failure documented
above. Prefer pinning a *whole team* over pinning one machine — a lone pinned operator diverges from
everyone else's behavior, which is harder to debug than either extreme.

## What lives in this folder

| File | Ours? | Purpose |
|---|---|---|
| `oauth.json.template` | AIOS | Shape of the gitignored `oauth.json` you create. Credentials are per-person secrets; the repo ships only the template. |
| `personal-account-setup.md` | AIOS | Google Cloud Console walkthrough — create a Desktop OAuth client, wire a personal/agent account. |
| `TROUBLESHOOTING.md` | AIOS | Local-first recovery: stale token, scope mismatch, port held by a dead process. |
| `make_auth_link.py` | AIOS | Rebuilds a clickable consent link when the URL is mangled in a chat → terminal → browser hop. |
| `README.md` | AIOS | Usage + setup + permissions reference. |

No upstream `LICENSE` or `.upstream-sync` lives here anymore, because no upstream code does. See
`LICENSE-AUDIT.md` § MCPs — this row moved out of "vendored upstream."
