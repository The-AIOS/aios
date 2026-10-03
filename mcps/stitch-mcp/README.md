# Stitch MCP — AI-Native Design → Code Pipeline

Google Stitch 2.0's MCP bridge. Design screens from natural language in Stitch, pull them into Claude Code as production HTML.

## Auth

**Needs an API key.** The `proxy` command — the only part Claude Code runs — reads
`STITCH_API_KEY` and nothing else. Without it the process exits immediately with
*"StitchProxy requires an API key (STITCH_API_KEY) or access token"*, which `claude mcp list`
shows as `✘ Failed to connect`. (Checked against the package source for v0.5.5 through v0.9.0.)

The CLI's Google Cloud login (`init`) does **not** feed the proxy. It serves the CLI's other
commands (`doctor`, `serve`, `site`, `screens`). **`doctor` does more than check:** on a machine that
has never run it, it installs a bundled `gcloud` into `~/.stitch-mcp/` and opens a Google sign-in
in the browser.

1. Open https://stitch.withgoogle.com/settings (profile picture → **Stitch Settings**) → **API Key**
   → **Create Key**. If it offers two kinds of key, choose the **MCP** key; that is the one verified here.
   No Google Cloud project or billing is needed.
2. Copy it. Don't paste it into a chat: read it from the clipboard in step 3 so it never lands in
   the conversation.

## Install

Register with Claude Code. `-s user` makes it available from every folder, not only the one you ran it in:
```bash
claude mcp add -s user stitch -e STITCH_API_KEY="$(pbpaste | tr -d '[:space:]')" -- npx -y @_davideast/stitch-mcp proxy
```
(`pbpaste` is macOS. On Linux use `xclip -o -selection clipboard`; on Windows paste the key in place of the `$(…)`.)

**Verify with a real call, not only the status line.** `✔ Connected` means the process started. It
does not prove the key is accepted. Ask Claude to *"list my Stitch projects"*: an empty result `{}`
is success, and an auth error means the key is wrong.

No vendored code — runs directly via npx.

## Example usage

Ask Claude naturally — it picks the right tool:

```
"Design a mobile login screen — logo, email/password, primary button, social auth options"
"Generate a desktop landing page with a hero, three feature cards, and a pricing table — Linear-like feel"
"Make three onboarding screens: welcome, create account, import existing"
"Turn the screens from my current Stitch project into real HTML I can drop into my repo"
"Pull the screenshot for a given screen ID and save it to 02 - assets/"
"Seed a new project with the Stripe DESIGN.md, then generate a pricing page in that style"
"Generate a dashboard layout with sidebar nav, top bar, and a grid of stat cards"
```

## Tools

| Tool | What it does |
|------|-------------|
| `create_project` | Creates a new Stitch project (container for screens + design system) |
| `generate_screen_from_text` | Generates a new screen from a natural-language prompt |
| `create_design_system` / `apply_design_system` | Seed a project with a known design system (Stripe, Linear, etc.) |
| `build_site` | Maps Stitch screens to routes, returns design HTML per page |
| `get_screen_code` | Retrieves a screen's HTML code |
| `get_screen_image` | Retrieves a screen's screenshot as base64 |
| `list_projects` / `list_screens` | Browse what's in your Stitch workspace |

## Workflow

1. **Design in Stitch** — describe panels, get production-quality screens
2. **Export DESIGN.md** — portable design system (colors, fonts, spacing, components)
3. **Stitch MCP → Claude Code** — pull screen HTML via `build_site` / `get_screen_code`
4. **Claude Code builds** — wire up real functionality behind the Stitch screens

## Seeding with an existing design system

Stitch auto-invents a design system per project unless you seed one. To force a known aesthetic (Stripe-like, Linear-like, Apple-like, etc.), pass a `DESIGN.md` into `create_design_system` before generating screens.

Pre-built library: [VoltAgent/awesome-design-md](https://github.com/VoltAgent/awesome-design-md) — 69 curated DESIGN.md files extracted from public sites. Pick one, paste its contents into `create_design_system` → `apply_design_system`, then `generate_screen_from_text`. Screens come out in the reference brand's dialect instead of a Stitch-invented one.

The same files also drop into any code project root — Claude Code and Cursor read them natively, no Stitch dependency needed.

## Links

- [Stitch 2.0](https://stitch.withgoogle.com/)
- [MCP setup docs](https://stitch.withgoogle.com/docs/mcp/setup/)
- [DESIGN.md format](https://stitch.withgoogle.com/docs/design-md/format/)
- [Stitch SDK](https://github.com/google-labs-code/stitch-sdk)
- [Stitch Skills](https://github.com/google-labs-code/stitch-skills)
- [awesome-design-md](https://github.com/VoltAgent/awesome-design-md) — 69 ready-made DESIGN.md files for seeding Stitch projects or code repos
