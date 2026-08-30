# Stitch MCP — AI-Native Design → Code Pipeline

Google Stitch 2.0's MCP bridge. Design screens from natural language in Stitch, pull them into Claude Code as production HTML.

## Auth

Stitch MCP is a proxy to `stitch.googleapis.com/mcp`. It authenticates with a
**Google Cloud OAuth login** — an interactive browser sign-in, handled by `gcloud`.
There is **no API key and no `STITCH_API_KEY` env var**; the CLI describes itself as
the "Stitch MCP OAuth setup assistant" and exposes no key flag on any subcommand.

1. Install the Google Cloud CLI if missing: `brew install --cask google-cloud-sdk`
2. Run the interactive setup (opens a browser — must be run by a human, not an agent):
   ```bash
   npx -y @_davideast/stitch-mcp init
   ```
3. `source ~/.zshrc` (or open a new shell)

Verify: `echo $STITCH_API_KEY` shows the key.

## Install

```bash
npx @_davideast/stitch-mcp proxy
```

Register with Claude Code (reads `STITCH_API_KEY` from env at launch):
```bash
claude mcp add stitch -- npx -y @_davideast/stitch-mcp proxy
```

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
