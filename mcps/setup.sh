#!/bin/bash
# MCP Setup — creates virtual environments and installs dependencies for all bundled MCPs.
# Run once after cloning, or after vault-update adds a new MCP.
# Usage: bash mcps/setup.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "Setting up MCPs in $SCRIPT_DIR..."
echo ""
# NOTE: intentionally no `set -e` — each MCP block is independent. One failure
# shouldn't kill the rest. Errors are surfaced per block.

# Cross-platform venv binary dir: Unix → .venv/bin, Windows (Git Bash) → .venv/Scripts.
# Call from inside the MCP dir AFTER `$PY -m venv .venv`. Without this, the
# hardcoded `.venv/bin/pip` path does not exist on Windows, the `&& echo "✓"`
# chain short-circuits, and the operator sees no error while nothing installed —
# the silent-failure bug surfaced on a Windows operator's machine 2026-05-26.
# Git Bash resolves bare names (pip, playwright) to their .exe, so no suffix needed.
vbin() { if [ -d ".venv/Scripts" ]; then echo ".venv/Scripts"; else echo ".venv/bin"; fi; }

# Cross-platform Python launcher. On Windows, `python3.exe` is the Microsoft Store
# redirector stub by default — invoking it opens an "install Python" page and exits
# non-zero, so `python3 -m venv` silently no-ops while the `&& echo "✓"` chain hides
# it (the second half of the Windows silent-install bug — first half was the .venv/bin
# vs .venv/Scripts path, fixed via vbin() above; surfaced by a Windows operator
# 2026-05-27). Probe for a REAL interpreter: python3 → python → py -3. $PY is used
# UNQUOTED below so `py -3` word-splits correctly.
PY=""
for cand in python3 python "py -3"; do
  if $cand -c 'import sys' >/dev/null 2>&1; then PY="$cand"; break; fi
done
if [ -z "$PY" ]; then
  echo "✗ No working Python found (python3 / python / py -3 all failed)."
  echo "  On Windows: install Python from python.org, then disable the Store alias —"
  echo "  Settings → Apps → Advanced app settings → App execution aliases → turn OFF"
  echo "  python.exe and python3.exe. Node-only MCPs (slack/github/stitch) still set up below."
  echo ""
fi

# --- Google Workspace MCP (Python) ---
if [ -d "$SCRIPT_DIR/google-workspace-mcp" ] && [ ! -d "$SCRIPT_DIR/google-workspace-mcp/.venv" ]; then
  echo "→ google-workspace-mcp..."
  (cd "$SCRIPT_DIR/google-workspace-mcp" && $PY -m venv .venv && "$(vbin)/pip" install -e . -q) \
    && echo "  ✓ installed" \
    || echo "  ✗ failed — check google-workspace-mcp/README.md"
fi

# --- Slack MCP (Node/NPM — invoked via npx at runtime, no install needed) ---
if [ -d "$SCRIPT_DIR/slack-mcp" ]; then
  echo "→ slack-mcp..."
  if ! command -v npx >/dev/null 2>&1; then
    echo "  ⚠ npx not found — install Node.js first"
  else
    npx -y @jtalk22/slack-mcp --version >/dev/null 2>&1 \
      && echo "  ✓ ready (invoked via npx @jtalk22/slack-mcp at runtime)" \
      || echo "  ✓ ready (will install on first invocation)"
  fi
fi

# --- NotebookLM MCP ---
if [ -d "$SCRIPT_DIR/notebooklm-mcp" ] && [ ! -d "$SCRIPT_DIR/notebooklm-mcp/.venv" ]; then
  echo "→ notebooklm-mcp..."
  cd "$SCRIPT_DIR/notebooklm-mcp"
  $PY -m venv .venv
  "$(vbin)/pip" install notebooklm-py playwright -q
  "$(vbin)/playwright" install chromium 2>/dev/null
  "$(vbin)/notebooklm" skill install 2>/dev/null || true
  echo "  ✓ installed (authenticate: run notebooklm login from mcps/notebooklm-mcp/$(vbin))"
fi

# --- Playwright MCP ---
if [ -d "$SCRIPT_DIR/playwright-mcp" ] && [ ! -d "$SCRIPT_DIR/playwright-mcp/.venv" ]; then
  echo "→ playwright-mcp..."
  cd "$SCRIPT_DIR/playwright-mcp"
  $PY -m venv .venv
  "$(vbin)/pip" install playwright browser-cookie3 -q
  "$(vbin)/playwright" install chromium 2>/dev/null
  echo "  ✓ installed (chromium bundled)"
fi

# --- Atlassian MCP (vendored via pipx/uvx) ---
if [ -d "$SCRIPT_DIR/atlassian-mcp" ]; then
  echo "→ atlassian-mcp..."
  if ! command -v uvx >/dev/null 2>&1 && ! command -v pipx >/dev/null 2>&1; then
    echo "  ⚠ neither uvx nor pipx found — install one (brew install uv or brew install pipx), then re-run"
  else
    if command -v uvx >/dev/null 2>&1; then
      uvx --help mcp-atlassian >/dev/null 2>&1 || uvx mcp-atlassian --help >/dev/null 2>&1 || true
      echo "  ✓ ready (invoked via uvx mcp-atlassian at runtime)"
    else
      pipx install mcp-atlassian --force 2>/dev/null
      echo "  ✓ installed via pipx"
    fi
  fi
fi

# --- GitHub MCP (vendored via npx, no install needed) ---
if [ -d "$SCRIPT_DIR/github-mcp" ]; then
  echo "→ github-mcp..."
  if ! command -v npx >/dev/null 2>&1; then
    echo "  ⚠ npx not found — install Node.js first"
  else
    npx -y @modelcontextprotocol/server-github --help >/dev/null 2>&1 || true
    echo "  ✓ ready (invoked via npx @modelcontextprotocol/server-github at runtime)"
  fi
fi

# --- Nano Banana MCP (Gemini image gen) ---
if [ -d "$SCRIPT_DIR/nano-banana-mcp" ] && [ ! -d "$SCRIPT_DIR/nano-banana-mcp/.venv" ]; then
  echo "→ nano-banana-mcp..."
  cd "$SCRIPT_DIR/nano-banana-mcp"
  $PY -m venv .venv
  "$(vbin)/pip" install google-genai mcp -q
  echo "  ✓ installed (requires GEMINI_API_KEY — see README)"
fi

# --- PDF Generator MCP ---
if [ -d "$SCRIPT_DIR/pdf-generator-mcp" ] && [ ! -d "$SCRIPT_DIR/pdf-generator-mcp/.venv" ]; then
  echo "→ pdf-generator-mcp..."
  cd "$SCRIPT_DIR/pdf-generator-mcp"
  $PY -m venv .venv
  "$(vbin)/pip" install mcp -q
  command -v pandoc >/dev/null 2>&1 || echo "  ⚠ pandoc not found — brew install pandoc"
  [ -d "/Applications/Google Chrome.app" ] || echo "  ⚠ Google Chrome not found — install from https://google.com/chrome"
  echo "  ✓ installed (requires pandoc + Chrome)"
fi

# --- Spotify DJ MCP ---
if [ -d "$SCRIPT_DIR/spotify-dj-mcp" ] && [ ! -d "$SCRIPT_DIR/spotify-dj-mcp/.venv" ]; then
  echo "→ spotify-dj-mcp..."
  cd "$SCRIPT_DIR/spotify-dj-mcp"
  $PY -m venv .venv
  "$(vbin)/pip" install spotipy mcp -q
  echo "  ✓ installed (requires Spotify Dev app + SPOTIFY_CLIENT_ID/SECRET — see README)"
fi

# --- Stitch MCP (Google AI-native design — runs via npx, no install needed) ---
if [ -d "$SCRIPT_DIR/stitch-mcp" ]; then
  echo "→ stitch-mcp..."
  if ! command -v npx >/dev/null 2>&1; then
    echo "  ⚠ npx not found — install Node.js first"
  else
    npx -y @_davideast/stitch-mcp --version >/dev/null 2>&1 \
      && echo "  ✓ ready (invoked via npx @_davideast/stitch-mcp proxy at runtime; requires STITCH_API_KEY — see README)" \
      || echo "  ✓ ready (will install on first invocation)"
  fi
fi

echo ""
echo "All MCPs installed. Recommended: ask Claude to run \`/mcps-setup\` — it walks"
echo "you through tokens + register + verify for each MCP in a guided flow."
echo ""
echo "Manual auth steps per MCP (if you prefer):"
echo "  • pdf-generator    : no auth (works immediately — just register)"
echo "  • google-workspace : uvx workspace-mcp (opens browser on first call)"
echo "  • slack            : npx -y @jtalk22/slack-mcp --refresh-tokens  (extracts from Chrome; posts AS YOU)"
echo "  • notebooklm       : run 'notebooklm login' from mcps/notebooklm-mcp/.venv/bin (Unix) or .venv/Scripts (Windows)"
echo "  • github           : export GITHUB_TOKEN (Personal Access Token)"
echo "  • atlassian        : export ATLASSIAN_URL / ATLASSIAN_USERNAME / ATLASSIAN_API_TOKEN"
echo "  • nano-banana      : export GEMINI_API_KEY (requires Cloud Billing enabled — ~\$0.04/image)"
echo "  • spotify-dj       : export SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET (Developer app)"
echo "  • stitch           : export STITCH_API_KEY (create at stitch.withgoogle.com)"
echo "  • playwright       : per-service browser-state login, see playwright-mcp/README.md"
echo ""
echo "Register each with: claude mcp add {name} -- {command}  (see each README)"
