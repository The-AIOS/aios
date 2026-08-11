"""PDF Generator MCP — pandoc (md → HTML) → Chrome headless (HTML → PDF).

Cross-platform (macOS / Windows / Linux). Chrome is resolved per-OS at call time;
override with the CHROME_PATH env var if your browser lives somewhere unusual.
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from datetime import datetime

from mcp.server.fastmcp import FastMCP

# SELF-LOCATE the vault. This file lives at {root}/mcps/pdf-generator-mcp/server.py, so the
# framework root is three parents up — correct wherever the operator cloned, and through the
# ~/aios symlink (.resolve() lands on the real directory).
#
# It previously joined the home directory to a literal "aios" segment. That is the documented
# install path, so it worked for anyone whose symlink was in place — but when it was not, the
# `mkdir(parents=True)` below did not fail, it CREATED ~/aios/vault/03 - export/generated and
# wrote the operator's PDFs into a directory tree that is not their vault. A silent wrong
# destination is worse than a missing one, because the tool still reports success. Deriving the
# root from this file's location removes the dependency on the symlink entirely.
AIOS_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_DIR = AIOS_ROOT / "vault" / "03 - export" / "generated"

mcp = FastMCP("pdf-generator")


def _find_chrome() -> str | None:
    """Locate a Chrome/Chromium/Edge binary across macOS, Windows and Linux."""
    # 1) explicit override
    env = os.environ.get("CHROME_PATH")
    if env and os.path.exists(env):
        return env

    # 2) per-OS well-known locations
    if sys.platform == "darwin":
        candidates = [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Chromium.app/Contents/MacOS/Chromium",
            "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
        ]
    elif sys.platform == "win32":
        candidates = [
            os.path.expandvars(r"%ProgramFiles%\Google\Chrome\Application\chrome.exe"),
            os.path.expandvars(r"%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"),
            os.path.expandvars(r"%LocalAppData%\Google\Chrome\Application\chrome.exe"),
            os.path.expandvars(r"%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"),
            os.path.expandvars(r"%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"),
        ]
    else:  # linux / other unix
        candidates = [
            "/usr/bin/google-chrome",
            "/usr/bin/google-chrome-stable",
            "/usr/bin/chromium",
            "/usr/bin/chromium-browser",
            "/snap/bin/chromium",
        ]
    for c in candidates:
        if c and os.path.exists(c):
            return c

    # 3) anything on PATH
    for name in ("google-chrome", "google-chrome-stable", "chromium",
                 "chromium-browser", "chrome", "msedge"):
        found = shutil.which(name)
        if found:
            return found
    return None


def _ensure_tools() -> str:
    """Verify pandoc and a Chrome-family browser are available. Returns the browser path."""
    if shutil.which("pandoc") is None:
        raise RuntimeError("pandoc not found. Install pandoc and make sure it's on PATH.")
    chrome = _find_chrome()
    if not chrome:
        raise RuntimeError(
            "Chrome/Chromium/Edge not found. Install Google Chrome, "
            "or set the CHROME_PATH env var to your browser binary."
        )
    return chrome


def _default_output(ext: str = "pdf") -> str:
    DEFAULT_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    return str(DEFAULT_OUTPUT_DIR / f"{datetime.now().strftime('%Y%m%d-%H%M%S')}.{ext}")


def _html_to_pdf(html_path: str, pdf_path: str) -> None:
    chrome = _ensure_tools()
    subprocess.run(
        [chrome, "--headless", "--no-pdf-header-footer", f"--print-to-pdf={pdf_path}", html_path],
        check=True,
        capture_output=True,
    )


@mcp.tool()
def markdown_to_pdf(
    markdown: str,
    output_path: str | None = None,
    title: str = "",
) -> dict:
    """Convert markdown to PDF via pandoc → Chrome headless pipeline.

    Args:
        markdown: The markdown content to convert.
        output_path: Where to save the PDF. Defaults to your vault's 03 - export/generated/{timestamp}.pdf
        title: Optional title used in pandoc's HTML <title> tag.

    Returns:
        Dict with keys: path (str), size_bytes (int).
    """
    _ensure_tools()
    if output_path is None:
        output_path = _default_output("pdf")

    with tempfile.TemporaryDirectory() as tmp:
        md_path = os.path.join(tmp, "input.md")
        html_path = os.path.join(tmp, "input.html")
        Path(md_path).write_text(markdown, encoding="utf-8")

        pandoc_cmd = ["pandoc", md_path, "-o", html_path, "--standalone"]
        if title:
            pandoc_cmd += ["--metadata", f"title={title}"]
        subprocess.run(pandoc_cmd, check=True, capture_output=True)

        _html_to_pdf(html_path, output_path)

    out = Path(output_path)
    return {"path": str(out), "size_bytes": out.stat().st_size}


@mcp.tool()
def html_to_pdf(html: str, output_path: str | None = None) -> dict:
    """Convert HTML directly to PDF via Chrome headless (for pre-styled templates).

    Args:
        html: The full HTML document (with inline CSS, fonts, etc.) to render.
        output_path: Where to save the PDF. Defaults to your vault's 03 - export/generated/{timestamp}.pdf

    Returns:
        Dict with keys: path (str), size_bytes (int).
    """
    _ensure_tools()
    if output_path is None:
        output_path = _default_output("pdf")

    with tempfile.TemporaryDirectory() as tmp:
        html_path = os.path.join(tmp, "input.html")
        Path(html_path).write_text(html, encoding="utf-8")
        _html_to_pdf(html_path, output_path)

    out = Path(output_path)
    return {"path": str(out), "size_bytes": out.stat().st_size}


if __name__ == "__main__":
    mcp.run()
