#!/usr/bin/env python3
"""Import session cookies from Chrome for each supported site.

Reads your Chrome cookie store via browser-cookie3, extracts the cookies
for each configured site, and writes a Playwright storage_state JSON to
`auth/<site>.json`. That file can then be loaded by any Playwright script:

    context = browser.new_context(storage_state='auth/substack.json')

No login flow inside Playwright, no profile copy, no magic links, no bot
detection. Same technique slack-mcp uses for Slack. One pattern for all sites.

Usage:
    # Import all configured sites
    python cookie_import.py

    # Import a subset
    python cookie_import.py substack
    python cookie_import.py substack linkedin x

macOS notes:
    - browser-cookie3 reads Chrome's encrypted cookie store via Keychain.
    - macOS may prompt for your login password the first time. Click
      "Always Allow" to skip future prompts.
    - You don't need to close Chrome. Read-only access to the cookie file.

Adding a new site:
    1. Add an entry to SITES below: name → list of domain patterns
    2. Optionally add a "critical" cookie name to validate post-import
    3. Tell teammates via CHANGELOG
"""
import os
import sys
import json

try:
    import browser_cookie3
except ImportError:
    print("ERROR: browser-cookie3 not installed.", file=sys.stderr)
    print("       source .venv/bin/activate && pip install browser-cookie3", file=sys.stderr)
    sys.exit(1)


# site name → (cookie domain patterns, critical cookie to validate or None to skip validation)
SITES = {
    "substack":  (["substack.com", "substackcdn.com"], "substack.sid"),
    "linkedin":  (["linkedin.com"], "li_at"),
    "x":         (["x.com", "twitter.com"], "auth_token"),
    "paragraph": (["paragraph.com", "paragraph.xyz"], "privy-token"),  # Privy-based auth
}


AUTH_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "auth")
os.makedirs(AUTH_DIR, exist_ok=True)


def import_site(site: str) -> bool:
    """Extract cookies for one site, save to auth/{site}.json. Returns True on success."""
    if site not in SITES:
        print(f"  ✗ unknown site: {site} (known: {', '.join(SITES)})", file=sys.stderr)
        return False

    domains, critical = SITES[site]
    cookies = []
    seen = set()

    for domain in domains:
        try:
            cj = browser_cookie3.chrome(domain_name=domain)
            for c in cj:
                key = (c.name, c.domain)
                if key in seen:
                    continue
                seen.add(key)

                # Use cookielib's standard API — works across browser_cookie3 versions
                http_only = c.has_nonstandard_attr("HttpOnly") or c.has_nonstandard_attr("httponly")
                same_site = None
                for attr in ("SameSite", "samesite"):
                    if c.has_nonstandard_attr(attr):
                        same_site = c.get_nonstandard_attr(attr)
                        break

                cookies.append({
                    "name": c.name,
                    "value": c.value,
                    "domain": c.domain,
                    "path": c.path or "/",
                    "expires": int(c.expires) if c.expires else -1,
                    "httpOnly": bool(http_only),
                    "secure": bool(c.secure),
                    "sameSite": same_site or "Lax",
                })
        except Exception as e:
            print(f"  warning: couldn't read {domain}: {e}", file=sys.stderr)

    if not cookies:
        print(f"  ✗ {site}: no cookies found — are you logged in to {domains[0]} in Chrome?", file=sys.stderr)
        return False

    if critical is None:
        has_critical = True  # no validation configured yet
        status = "✓"
        hint = " (no critical cookie configured — add one to SITES after inspecting cookies)"
    else:
        has_critical = any(c["name"] == critical for c in cookies)
        status = "✓" if has_critical else "⚠"
        hint = "" if has_critical else f" (missing {critical} — may not be fully logged in)"

    storage_state = {"cookies": cookies, "origins": []}
    output = os.path.join(AUTH_DIR, f"{site}.json")
    with open(output, "w") as f:
        json.dump(storage_state, f, indent=2)

    print(f"  {status} {site}: {len(cookies)} cookies → auth/{site}.json{hint}")
    return has_critical


def main():
    requested = sys.argv[1:] or list(SITES.keys())
    print(f"Importing cookies for: {', '.join(requested)}")
    print()

    # Process every site (not short-circuited — we want per-site reporting)
    results = [import_site(site) for site in requested]
    print()
    if all(results):
        print("All sites imported. Auth files ready for Playwright scripts.")
    else:
        failed = [s for s, ok in zip(requested, results) if not ok]
        print(f"Partial success. Sites with issues: {', '.join(failed)}")
        sys.exit(1)


if __name__ == "__main__":
    main()
