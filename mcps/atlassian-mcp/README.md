# Atlassian MCP (Jira + Confluence)

Bundled via [`mcp-atlassian`](https://github.com/sooperset/mcp-atlassian) — self-hosted, no claude.ai connector required.

## What it does

- Jira: search issues, read/comment/create/transition, get worklog
- Confluence: search pages, read/create/update pages, manage comments
- Works with Atlassian Cloud (your-domain.atlassian.net)

## Example usage

Ask Claude naturally — it picks the right tool:

```
"Show me my open Jira tickets, grouped by status"
"Create a Jira bug with the repro steps from today's notes"
"Transition the ticket I just mentioned to In Progress and add a comment linking the PR"
"Summarize all issues closed this week — who closed what"
"Create a Confluence page under the Engineering space with the content from this markdown file"
"Find every Confluence page mentioning a given topic and list them with last-updated dates"
"Pull the acceptance criteria from every open ticket in the current sprint"
```

## Setup

```bash
# Installed via mcps/setup.sh — or manually:
pipx install mcp-atlassian
# or: uvx mcp-atlassian --help
```

## Auth

1. Get an API token: https://id.atlassian.com/manage-profile/security/api-tokens → "Create API token"
2. Add to `~/.zshrc` or `~/.claude/mcp-env.sh`:
   ```
   export ATLASSIAN_URL="https://your-domain.atlassian.net"
   export ATLASSIAN_USERNAME="you@example.com"
   export ATLASSIAN_API_TOKEN="ATATT3x..."
   ```

## Register with Claude Code

**Use the wrapper script** — it reads env vars at launch so secrets never land in `~/.claude.json`:

```bash
claude mcp add atlassian -- ~/aios/mcps/atlassian-mcp/run.sh
```

(The wrapper is `mcps/atlassian-mcp/run.sh` — it checks for the three env vars and calls `uvx mcp-atlassian` with them. DO NOT pass the token directly as an arg to `claude mcp add` — it gets stored in plaintext in your config.)

Restart your Claude session. Tools appear as `mcp__atlassian__*`.

## Disable the claude.ai-hosted Atlassian

claude.ai → Settings → Connectors → disable "Atlassian" (per Anthropic account). Prevents account-switch breakage (see CLAUDE.md → MCP Policy).
