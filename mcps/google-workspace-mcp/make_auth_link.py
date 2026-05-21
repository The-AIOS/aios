#!/usr/bin/env python3
"""Generate a clickable auth_link.html from a Google OAuth URL.

Why this exists: long OAuth URLs occasionally get mangled when copy-pasted
through chat -> terminal -> browser (line wrapping, encoding quirks, HSTS
upgrades on localhost). This helper writes a static HTML file with a proper
<a href> button so the browser handles the URL natively. Open the file,
click the button.

Usage:
  python make_auth_link.py "<full-oauth-url>"   # explicit URL
  python make_auth_link.py                       # auto-detect from MCP log
"""

import re
import sys
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parent
HTML_PATH = ROOT / "auth_link.html"
LOG_PATH = ROOT / "mcp_server_debug.log"

URL_PATTERN = re.compile(
    r"Advise user to visit:\s*(https://accounts\.google\.com/\S+)"
)


def find_latest_url_from_log() -> str | None:
    if not LOG_PATH.exists():
        return None
    last = None
    for line in LOG_PATH.read_text(encoding="utf-8", errors="ignore").splitlines():
        m = URL_PATTERN.search(line)
        if m:
            last = m.group(1)
    return last


def write_html(url: str) -> Path:
    content = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Authorize Google Workspace</title>
<style>
  body {{ font-family: system-ui, sans-serif; padding: 40px; max-width: 800px; margin: auto; }}
  a.btn {{ display: inline-block; padding: 16px 32px; background: #1a73e8; color: white;
          text-decoration: none; border-radius: 8px; font-size: 18px; margin: 20px 0; }}
  a.btn:hover {{ background: #1558b8; }}
  small {{ color: #5f6368; }}
</style>
</head>
<body>
  <h1>Authorize Google Workspace</h1>
  <p>Click the button, sign in to Google, and approve the requested scopes.
     Your browser will redirect to <code>localhost:8000</code> when the MCP catches the callback.</p>
  <a class="btn" href="{escape(url, quote=True)}">Authorize Google Workspace</a>
  <p><small>This link is single-use and expires after auth. Re-run the auth command for a fresh one.</small></p>
</body>
</html>
"""
    HTML_PATH.write_text(content, encoding="utf-8")
    return HTML_PATH


def main() -> int:
    url = sys.argv[1] if len(sys.argv) > 1 else find_latest_url_from_log()
    if not url:
        print(
            "ERROR: no URL given and none found in mcp_server_debug.log.\n"
            'Usage: python make_auth_link.py "<full-oauth-url>"',
            file=sys.stderr,
        )
        return 1
    path = write_html(url)
    print(f"Wrote {path}")
    print("Open it in your browser to complete authentication.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
