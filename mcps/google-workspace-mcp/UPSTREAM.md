# Upstream Reference

- **Package:** `workspace-mcp`
- **Version:** 1.15.0 (vendored 2026-03-26)
- **Repository:** https://github.com/taylorwilsdon/google_workspace_mcp
- **License:** MIT
- **Author:** taylorwilsdon

## Why vendored

The vault uses this MCP for all Google Workspace operations: Calendar, Tasks, Gmail, Docs, Sheets, Slides, Drive. Vendoring ensures:
1. Pin a known-good, audited version — `uvx workspace-mcp` always pulls latest, which could include unreviewed changes
2. Team installs from the repo, not from PyPI
3. Future modifications (if needed) are tracked in git

## Capabilities

| Module | Read | Write |
|--------|------|-------|
| Calendar | list, get_events, freebusy | create/modify/delete events |
| Tasks | list, get_task | create/update/delete/move tasks |
| Gmail | search, read, list_labels | send, reply, create_draft |
| Docs | search, get_content, inspect | create, modify_text, batch_update |
| Drive | search, list, get_content | create_folder, create_file |
| Sheets | list, read_values | modify_values, format, create |
| Slides | get_presentation | batch_update |
| Chat | read | send |
| Forms | read | - |
| Search | google search | - |
| Contacts | read | - |

## Security notes

- OAuth 2.0 — tokens stored locally at `~/.google_workspace_mcp/credentials/`
- stdio mode — runs locally, no data sent to third parties
- Write operations are real — no sandbox. Claude can create/modify/delete calendar events, send emails, edit docs.
- `allowed-tools: mcp__google-workspace__*` in command frontmatter controls which commands can use it

## How to update

```bash
# Check latest version
pip3 index versions workspace-mcp

# If update needed, clone and replace:
git clone --depth=1 https://github.com/taylorwilsdon/google_workspace_mcp.git /tmp/gwm
cp -R /tmp/gwm/{auth,core,gcalendar,gdocs,gdrive,gforms,gmail,gsearch,gsheets,gslides,gtasks,gchat,gcontacts,main.py,fastmcp_server.py,pyproject.toml,README.md,LICENSE,server.json,uv.lock} mcps/google-workspace-mcp/
rm -rf /tmp/gwm
# Update version in this file
```

## How teammates install

```bash
# Option 1: Use vendored copy (recommended)
cd ~/Dev/internal-vault/mcps/google-workspace-mcp && uv pip install -e .

# Option 2: Use upstream directly (not recommended — unpinned)
uvx workspace-mcp --single-user
```
