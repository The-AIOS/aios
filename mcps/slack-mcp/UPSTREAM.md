# Upstream Reference

- **Package:** `@jtalk22/slack-mcp`
- **Version:** 3.2.5 (vendored 2026-03-26)
- **Repository:** https://github.com/jtalk22/slack-mcp-server
- **License:** MIT
- **Author:** jtalk22

## Why vendored

The vault uses this MCP for Slack integration (unreads triage, message history, send messages). Vendoring ensures:
1. Team doesn't depend on npm availability for a critical integration
2. We can pin a known-good version
3. Future modifications (if needed) are tracked in git

## How to update

```bash
# Check latest version
npm view @jtalk22/slack-mcp version

# If update needed, replace contents:
npx -y @jtalk22/slack-mcp --help  # forces download
cp -R ~/.npm/_npx/*/node_modules/@jtalk22/slack-mcp/{src,lib,package.json,README.md,LICENSE,server.json} mcps/slack-mcp/
# Update version in this file
```

## How teammates install

```bash
# Option 1: Use vendored copy (recommended)
cd ~/Dev/internal-vault/mcps/slack-mcp && npm install

# Option 2: Use upstream directly
npx -y @jtalk22/slack-mcp --setup
```

Both options store tokens at `~/.slack-mcp-tokens.json`.
