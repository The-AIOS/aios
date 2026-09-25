# Upstream Reference

- **Package:** `@jtalk22/slack-mcp@5.0.0` — the version every AIOS registration runs
- **Vendored:** 2026-09-25, the complete npm package, byte for byte (`.upstream-manifest`)
- **Repository:** https://github.com/jtalk22/slack-mcp-server
- **License:** MIT
- **Author:** jtalk22

## Why the copy is here

It posts to Slack *as you*, so the code that runs should be readable in this repo. Registrations pin the same
version (`npx -y @jtalk22/slack-mcp@5.0.0`), which makes the vendored files what executes. Its two dependencies are declared with
`^` ranges and resolve at launch: the pin narrows the unpinned surface to them, it does not remove it.

`connector.json` and this file are AIOS's own (`local=` in `.upstream-sync`); everything else is upstream's.

## How to update

Bump deliberately, and vet the release first: it acts as you.

```bash
npm view @jtalk22/slack-mcp version                      # what is current
cd "$(mktemp -d)" && npm pack @jtalk22/slack-mcp@<ver> && tar xzf *.tgz   # the exact published files
# replace everything in mcps/slack-mcp except connector.json and UPSTREAM.md with package/*
# set package=@jtalk22/slack-mcp@<ver> in .upstream-sync, then pin the same version everywhere it is invoked:
#   connector.json · mcps/setup.sh · SETUP.md · plugins/aios/commands/mcps-setup.md · hooks/pipeline-executor.py
bash tests/vendored-pins.test.sh --record mcps/slack-mcp
bash tests/vendored-pins.test.sh --upstream mcps/slack-mcp  # must print N/N files match
```
