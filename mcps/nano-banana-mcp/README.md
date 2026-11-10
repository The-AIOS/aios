# Nano Banana MCP — Gemini Image Generation

Bundled MCP for generating images with Google's Gemini 2.5 Flash Image (a.k.a. "Nano Banana"). Used for cover images, content visuals, mockups.

## What it does

Single tool: `generate_image(prompt, output_path?, aspect_ratio?, reference_images?)` — generates an image from a text prompt, optionally looking at up to three reference images, saves to disk, returns the path.

- **Model:** `gemini-2.5-flash-image` (Nano Banana, released Aug 2025)
- **Aspect ratios:** `1:1`, `16:9`, `9:16`, `4:3`, `3:4`
- **Output:** PNG, saved to `output_path` (default: `~/aios/vault/02 - assets/generated/{timestamp}.png`)

## Keeping a character the same: `reference_images`

A text prompt is a fresh interpretation every time, so a character you generate twice drifts: the head shape, the eyes, small marks. When you need the same character in several pictures (a portrait in different moods, a mascot in several scenes), pass the approved picture as a reference and describe only what changes:

```
generate_image(
  prompt="The same character as in the reference image: keep the face, eyes, colours and outfit "
         "exactly the same. Change only the pose: now working at a laptop. "
         "Same framing and background. No text.",
  reference_images=["~/path/to/approved-portrait.png"],
)
```

- Up to three local PNG, JPEG or WebP files, sent to the model before the prompt. Nothing is fetched from a URL.
- Name what must stay ("keep the face, eyes and colours exactly the same") and what changes; name small details that tend to multiply ("ONE antenna rod"), and the angle ("the same three-quarter view").
- Still compare each result with the reference: it holds the character far better than words alone, not perfectly.
- Without `reference_images` the call is exactly what it was before.

## Setup

```bash
# Installed via mcps/setup.sh — or manually:
cd mcps/nano-banana-mcp
python3 -m venv .venv
.venv/bin/pip install google-genai mcp
```

## Auth

1. Get a Gemini API key: https://aistudio.google.com/apikey
2. **Enable billing on your API project** — image generation requires paid tier. Free tier limit is 0 images. At https://aistudio.google.com click your project → enable billing. Cost: ~$0.04/image, pay-as-you-go.
3. Add to `~/.zshrc`:
   ```
   export GEMINI_API_KEY="AIza..."
   ```

## Register with Claude Code

```bash
claude mcp add nano-banana -- ~/aios/mcps/nano-banana-mcp/.venv/bin/python ~/aios/mcps/nano-banana-mcp/server.py
```

Tools appear as `mcp__nano-banana__generate_image`.

## Example usage

Ask Claude naturally — it calls `generate_image` and returns the saved path:

```
"Generate a minimalist book cover: dark background, single golden tree, serif title, 16:9"
"Create a hero image for a blog post about caches pretending to be databases — soft blue glow, editorial illustration style"
"Make three variants of a mobile app splash screen, 9:16, with a fingerprint motif"
"Draw a podcast cover — warm cream background, abstract architecture motif, 1:1"
"Generate an image for a newsletter header: a workshop bench with tools neatly arranged, warm light, 16:9"
"Produce an op-ed illustration: a figure standing at a fork in the road, editorial line-art, 4:3"
```

Images land at the default output path — ready to embed or publish.
