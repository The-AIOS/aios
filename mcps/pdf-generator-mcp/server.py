"""PDF Generator MCP — pandoc (md → HTML) → Chrome headless (HTML → PDF)."""
import os
import subprocess
import tempfile
from pathlib import Path
from datetime import datetime

from mcp.server.fastmcp import FastMCP

DEFAULT_OUTPUT_DIR = Path.home() / "obsidian" / "vault" / "04 - export" / "generated"
CHROME_PATH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

mcp = FastMCP("pdf-generator")


def _ensure_tools():
    """Verify pandoc and Chrome are available."""
    if subprocess.run(["which", "pandoc"], capture_output=True).returncode != 0:
        raise RuntimeError("pandoc not found. Install: brew install pandoc")
    if not os.path.exists(CHROME_PATH):
        raise RuntimeError(f"Chrome not found at {CHROME_PATH}. Install Google Chrome.")


def _default_output(ext: str = "pdf") -> str:
    DEFAULT_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    return str(DEFAULT_OUTPUT_DIR / f"{datetime.now().strftime('%Y%m%d-%H%M%S')}.{ext}")


def _html_to_pdf(html_path: str, pdf_path: str) -> None:
    subprocess.run(
        [CHROME_PATH, "--headless", "--no-pdf-header-footer", f"--print-to-pdf={pdf_path}", html_path],
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
        output_path: Where to save the PDF. Defaults to ~/aios/vault/04 - export/generated/{timestamp}.pdf
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
        output_path: Where to save the PDF. Defaults to ~/aios/vault/04 - export/generated/{timestamp}.pdf

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
