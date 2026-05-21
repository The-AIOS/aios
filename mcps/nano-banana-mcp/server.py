"""Nano Banana MCP — Gemini 2.5 Flash Image generation as an MCP tool."""
import os
import sys
from pathlib import Path
from datetime import datetime

from mcp.server.fastmcp import FastMCP

try:
    from google import genai
    from google.genai import types
except ImportError:
    print("ERROR: google-genai not installed. Run: pip install google-genai mcp", file=sys.stderr)
    sys.exit(1)

API_KEY = os.environ.get("GEMINI_API_KEY")
if not API_KEY:
    print("ERROR: GEMINI_API_KEY env var not set. Get one at https://aistudio.google.com/apikey", file=sys.stderr)
    sys.exit(1)

DEFAULT_OUTPUT_DIR = Path.home() / "obsidian" / "vault" / "03 - assets" / "generated"

mcp = FastMCP("nano-banana")
client = genai.Client(api_key=API_KEY)


@mcp.tool()
def generate_image(
    prompt: str,
    output_path: str | None = None,
    aspect_ratio: str = "1:1",
) -> dict:
    """Generate an image from a text prompt using Gemini 2.5 Flash Image (Nano Banana).

    Args:
        prompt: Natural-language description of the desired image.
        output_path: Where to save the PNG. Defaults to ~/obsidian/vault/03 - assets/generated/{timestamp}.png
        aspect_ratio: One of "1:1", "16:9", "9:16", "4:3", "3:4". Default "1:1".

    Returns:
        Dict with keys: path (str), prompt (str), aspect_ratio (str), size_bytes (int).
    """
    if aspect_ratio not in {"1:1", "16:9", "9:16", "4:3", "3:4"}:
        raise ValueError(f"aspect_ratio must be one of 1:1, 16:9, 9:16, 4:3, 3:4 — got {aspect_ratio}")

    if output_path is None:
        DEFAULT_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        output_path = str(DEFAULT_OUTPUT_DIR / f"{datetime.now().strftime('%Y%m%d-%H%M%S')}.png")

    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents=prompt,
        config=types.GenerateContentConfig(
            response_modalities=["IMAGE"],
            image_config=types.ImageConfig(aspect_ratio=aspect_ratio),
        ),
    )

    for part in response.candidates[0].content.parts:
        if part.inline_data and part.inline_data.data:
            out = Path(output_path)
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(part.inline_data.data)
            return {
                "path": str(out),
                "prompt": prompt,
                "aspect_ratio": aspect_ratio,
                "size_bytes": out.stat().st_size,
            }

    raise RuntimeError("Gemini returned no image data — check prompt or API status.")


if __name__ == "__main__":
    mcp.run()
