# GitHub MCP

Bundled via [`@modelcontextprotocol/server-github`](https://github.com/modelcontextprotocol/servers/tree/main/src/github) — Anthropic's official GitHub MCP server.

## What it does

- Repositories: search, browse, create, fork
- Issues: search, read, create, comment, close
- Pull requests: list, read, create, review, merge
- Files: read, create, update, delete, push
- Branches: create, delete, switch
- Workflows: list runs, get logs, trigger

Works with any GitHub account (personal, org, enterprise).

## Example usage

Ask Claude naturally — it picks the right tool:

```
"Show me open PRs I'm assigned to review"
"Create an issue in the current repo with the title and body from this note"
"Get the diff of the PR I just opened and summarize the risky changes"
"Merge this PR if CI is green"
"Search the org for any repo still importing a deprecated package"
"Push this CHANGELOG update on a new branch and open a PR"
"What's my commit volume this week across all my orgs?"
"List the last 10 releases in this repo with their dates"
```

## Setup

Runs via `npx` — no install step beyond npm presence.

```bash
npx -y @modelcontextprotocol/server-github --version
```

## Auth

1. Create a Personal Access Token: https://github.com/settings/tokens/new
2. Scopes (minimum): `repo`, `read:org`, `read:user`, `workflow`
3. Add to `~/.zshrc` or `~/.claude/mcp-env.sh`:
   ```
   export GITHUB_TOKEN="ghp_..."
   ```

## Register with Claude Code

```bash
claude mcp add github -- npx -y @modelcontextprotocol/server-github
```

The server reads `GITHUB_TOKEN` from your environment at spawn time. Restart Claude after registering. Tools appear as `mcp__github__*`.

## Disable the claude.ai-hosted GitHub connector (if enabled)

If you have GitHub enabled via claude.ai → Settings → Connectors, disable it. This bundled version works independently of Anthropic auth (see CLAUDE.md → MCP Policy).
