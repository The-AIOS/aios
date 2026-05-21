# The AIOS

> **Everyone is building an AIOS. We built The AIOS.**

The context-engineering primitive that turns transactional AI into compounding leverage. Not another agent. Not another tool. The **prompt, context, intent, and collaboration layers** you and your agents run on.

Used daily by senior executives, founders, builders, and operators — on personal vaults, ventures, and the work that compounds.

---

## What this repo contains

The AIOS framework — generic infrastructure that runs on top of [Claude Code](https://claude.com/claude-code) and produces a personalized agent operating system on your machine.

- **`commands/`** — vault-command files (`/today`, `/close-day`, `/7plan`, etc.) — the daily ritual surface
- **`hooks/`** — Claude Code event hooks (UserPromptSubmit, etc.) + harness wrappers (`spawn`, `spawn-kill`)
- **`mcps/`** — bundled MCP servers (Google Workspace, Slack, NotebookLM, Playwright, etc.)
- **`plugins/`** — Claude Code plugins that ship with the framework
- **`skills/`** — reusable capabilities (frontend-design, brainstorming, writing-plans, etc.)
- **`templates/`** — vault templates (project notes, daily notes, weekly plans, etc.)
- **`agents/`** — task agents (sales, legal, code-review, content-writer, etc.)

---

## Quick start

```bash
# clone the framework
git clone https://github.com/The-AIOS/aios.git ~/aios

# bootstrap your personal vault
cd ~/aios && bash SETUP.md
```

See [`SETUP.md`](SETUP.md) for the full first-run flow.

---

## Three principles, all load-bearing

- **Amplify intelligence, not artificial.** Human + AI beats human alone or AI alone.
- **Context, not prompts.** Prompts are the artifact most people optimize. Context is the substrate that determines what those prompts can do.
- **Trust earned over time.** Autonomy compounds with judgment — like a good A-Player on a real team.
- **Portable, not proprietary.** The AIOS is the layer; the LLM is interchangeable. Plug Claude (recommended), Gemini, or your best model.

---

## Who this is for

For anyone navigating AI-overwhelming days — builders, founders, executives. AI alone multiplies confusion. The AIOS gives you the structure (prompt, context, intent, collaboration) where clarity emerges, then gets amplified.

The AIOS is completely portable — plug Claude, Gemini, or your best LLM. If you want to make the most of AI without losing what makes you irreplaceable — and without IP/PII risk — this is for you.

---

## License

[MIT](LICENSE) — use it, fork it, build on it. We compound when you compound.

---

*Amplify yourself and your team — with AI co-workers.*

*Not zero people. Compounded people.*
