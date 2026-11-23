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
os.makedirs(AUTH_DIR, mode=0o700, exist_ok=True)
try:
    os.chmod(AUTH_DIR, 0o700)  # an existing folder keeps its old mode through makedirs
except OSError:
    pass


def domain_matches(cookie_domain: str, domain: str) -> bool:
    """True only when a cookie belongs to `domain` itself or one of its subdomains.

    browser_cookie3.chrome(domain_name=d) matches the cookie store with LIKE '%d%', so asking for
    "x.com" also returns box.com, dropbox.com, x.com.example.net and any other host that merely
    contains those letters. Every cookie is therefore checked here, on a label boundary:
    "x.com" and "mobile.x.com" pass, "box.com" and "x.com.example.net" do not."""
    d = (cookie_domain or "").strip().lower().lstrip(".")
    want = domain.strip().lower().lstrip(".")
    return bool(d) and (d == want or d.endswith("." + want))


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
                if not domain_matches(c.domain, domain):
                    continue  # another site's cookie that only shares the suffix
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
    # Owner-only: the file holds live session cookies. Written to a temp file that mkstemp creates
    # 0600 in the same folder, then moved over the old one: the cookies are never in a file another
    # local user can read (not even an old 0644 one being rewritten), a symlink at the destination is
    # replaced rather than followed, and a failed write leaves the previous file whole. On Windows the
    # mode bits only control read-only, so there the folder's own permissions are what protect it.
    import tempfile
    fd, tmp = tempfile.mkstemp(prefix=f".{site}.", suffix=".json", dir=AUTH_DIR)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(storage_state, f, indent=2)
        os.replace(tmp, output)
    except BaseException:
        os.unlink(tmp)
        raise

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
