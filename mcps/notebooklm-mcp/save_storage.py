"""Re-open the existing persistent profile and save storage_state.json.

Recovery tool. Use this if `notebooklm login` (or `manual_login.py` from
an older revision) crashed mid-flow but the persistent profile already
holds a signed-in session. The session lives in browser_profile/ even if
the storage_state.json export step failed.

Headless — no window. Just dumps the cookies the profile already has.

Run from any terminal:
  python mcps/notebooklm-mcp/save_storage.py
"""
import json
from pathlib import Path

from playwright.sync_api import sync_playwright


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


print(f"[1/3] Opening existing profile: {PROFILE}", flush=True)
with sync_playwright() as p:
    ctx = p.chromium.launch_persistent_context(
        user_data_dir=str(PROFILE),
        headless=True,  # No window needed — just dump cookies
    )
    print(f"[2/3] Profile opened. Saving storage state...", flush=True)
    ctx.storage_state(path=str(STORAGE))
    ctx.close()

print(f"[3/3] Saved to {STORAGE}")
print(f"  Size: {STORAGE.stat().st_size} bytes")
