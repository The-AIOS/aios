"""Manual NotebookLM login — workaround for `notebooklm login`'s broken flow.

`notebooklm-py`'s built-in `notebooklm login` command navigates to
accounts.google.com after sign-in to refresh regional cookies, but Google
auto-redirects newly-signed-in users back to notebooklm.google.com,
producing "Navigation to X is interrupted by another navigation to Y" and
aborting before storage_state.json saves.

This script mirrors the upstream flow but wraps the post-login navigation
in try/except so the storage state still saves cleanly. Numbered logs make
it easy to debug headless / silent-failure cases (e.g. Windows on ARM).

Run from any terminal that supports interactive input:
  python mcps/notebooklm-mcp/manual_login.py
"""
import json
from pathlib import Path

from playwright.sync_api import sync_playwright, Error as PlaywrightError


def _notebooklm_dirs():
    """Where notebooklm-py keeps the session. 0.8 moved it under profiles/<name>/ and migrates
    the old location on its first run, so prefer the profile when it exists and fall back to the
    old root otherwise (0.8 then migrates what this script wrote)."""
    root = Path.home() / ".notebooklm"
    try:
        name = json.loads((root / "config.json").read_text(encoding="utf-8")).get("default_profile")
    except (OSError, ValueError):
        name = None
    base = root / "profiles" / name if name and (root / "profiles" / name).is_dir() else root
    return base / "browser_profile", base / "storage_state.json"


PROFILE, STORAGE = _notebooklm_dirs()

URL = "https://notebooklm.google.com/"

print(f"[1/5] Profile dir: {PROFILE}", flush=True)
PROFILE.mkdir(parents=True, exist_ok=True)
print("[2/5] Starting Playwright...", flush=True)

with sync_playwright() as p:
    print("[3/5] Launching Chromium with persistent context (visible window)...", flush=True)
    ctx = p.chromium.launch_persistent_context(
        user_data_dir=str(PROFILE),
        headless=False,
        args=["--disable-blink-features=AutomationControlled"],
        ignore_default_args=["--enable-automation"],
    )
    print(f"[4/5] Chromium launched. Pages: {len(ctx.pages)}", flush=True)
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    page.goto(URL)
    print(f"      Current URL: {page.url}", flush=True)
    print()
    print("=== ACTION ===")
    print("1. Sign in to Google in the Chromium window that just opened.")
    print("2. Wait until you see the NotebookLM homepage.")
    print("3. Come back here and press ENTER.")
    print()
    input("Press ENTER when logged in: ")

    # Refresh .google.com cookies for regional users (e.g. UK lands on .google.co.uk).
    # Google auto-redirects signed-in users away from accounts.google.com to NotebookLM,
    # which surfaces as "Navigation to X is interrupted by another navigation to Y".
    # That's fine — the cookie scope is what we need, not the destination.
    for target in ("https://accounts.google.com/", URL):
        try:
            page.goto(target, wait_until="load")
        except PlaywrightError as e:
            if "interrupted" in str(e).lower():
                continue
            raise

    print(f"[5/5] Saving storage state to {STORAGE}...", flush=True)
    ctx.storage_state(path=str(STORAGE))
    ctx.close()

print(f"\n[OK] Done. Storage saved to: {STORAGE}")
print(f"  Size: {STORAGE.stat().st_size} bytes")
