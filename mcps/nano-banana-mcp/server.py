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

# SELF-LOCATE the vault — this file lives at {root}/mcps/nano-banana-mcp/server.py, so the
# framework root is three parents up. Correct wherever the operator cloned, and through the
# ~/aios symlink. It used to join the home directory to a literal "aios" segment: with no
# symlink in place the mkdir(parents=True) at the write site did not fail, it CREATED a phantom
# ~/aios/vault tree and wrote generated images there instead of into the real vault — silently,
# while reporting success. Self-location removes the symlink dependency.
AIOS_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_DIR = AIOS_ROOT / "vault" / "02 - assets" / "generated"

mcp = FastMCP("nano-banana")
client = genai.Client(api_key=API_KEY)


@mcp.tool()
def generate_image(
    prompt: str,
    output_path: str | None = None,
    aspect_ratio: str = "1:1",
    reference_images: list[str] | None = None,
) -> dict:
    """Generate an image from a text prompt using Gemini 2.5 Flash Image (Nano Banana).

    Args:
        prompt: Natural-language description of the desired image.
        output_path: Where to save the PNG. Defaults to your vault's 02 - assets/generated/{timestamp}.png
        aspect_ratio: One of "1:1", "16:9", "9:16", "4:3", "3:4". Default "1:1".
        reference_images: Optional local image paths (PNG/JPEG/WebP, up to 3) the model
            should look at, e.g. an approved character portrait, so a new pose keeps the same
            face, colours and proportions. The prompt then describes the change ("the same
            character, now working at a laptop"). Without it the model only has the words,
            and a character drifts between images.

    Returns:
        Dict with keys: path (str), prompt (str), aspect_ratio (str), size_bytes (int).
    """
    if aspect_ratio not in {"1:1", "16:9", "9:16", "4:3", "3:4"}:
        raise ValueError(f"aspect_ratio must be one of 1:1, 16:9, 9:16, 4:3, 3:4 — got {aspect_ratio}")

    if output_path is None:
        DEFAULT_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        output_path = str(DEFAULT_OUTPUT_DIR / f"{datetime.now().strftime('%Y%m%d-%H%M%S')}.png")

    contents: list = []
    for ref in (reference_images or [])[:3]:
        rp = Path(ref).expanduser()
        if not rp.is_file():
            raise ValueError(f"reference image not found: {ref}")
        mime = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
                ".webp": "image/webp"}.get(rp.suffix.lower())
        if not mime:
            raise ValueError(f"reference image must be PNG, JPEG or WebP: {ref}")
        contents.append(types.Part.from_bytes(data=rp.read_bytes(), mime_type=mime))
    contents.append(prompt)

    response = client.models.generate_content(
        model="gemini-2.5-flash-image",
        contents=contents,
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
                "reference_images": list(reference_images or [])[:3],
                "size_bytes": out.stat().st_size,
            }

    raise RuntimeError("Gemini returned no image data — check prompt or API status.")


if __name__ == "__main__":
    mcp.run()
