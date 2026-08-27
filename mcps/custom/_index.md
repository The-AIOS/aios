---
tags: [mcps, custom, index]
created: '2026-05-21'
---
# Custom MCPs

> Your custom MCP servers. These survive `/aios:update` — bundled MCPs in the parent `mcps/` folder get replaced, but `custom/` is yours.

Add a folder per MCP server with its own README and `claude mcp add` instructions. Document each in the registry below.

## Add a `connector.json` too — or the AIOS App will not know your MCP exists

The App builds its Connectors card by reading `connector.json` from every folder under `mcps/`, **including this one**, and it ships no fallback list. So a custom MCP without a manifest is not shown as broken or unconfigured — it is **not shown at all**, and nothing says why.

This is not hypothetical. `mint-mcp` was found **registered and working, with no manifest** — invisible to the card while functioning perfectly in every session. It surfaced only once the App started reporting folders that have no manifest; before that the absence looked exactly like a deliberate omission.

Copy the shape from any bundled folder (`../google-workspace-mcp/connector.json` is a good reference) and keep these true:

- **`id` must equal the name you registered with `claude mcp add`.** A reader pairs manifest to live registration by this field; get it wrong and a connected service reports as unconnected.
- **`service`** is the service as *you* would say it out loud — never containing the string "MCP".
- **every path uses `{framework}`**, never a literal `~/aios`. That path is a symlink on some machines, so a hardcoded copy documents something different from what actually works — and it is invisible on every machine where the clone and the symlink agree.
- **`connect`** is `one-click` · `needs-key` · `guided`.
- **`requires`** lists anything that must exist on disk first (a `.venv`, an OAuth file), so a connector pointing at something not yet built is detectable *before* a registration is written rather than at first use.
- **not actually an MCP server?** Set `registers: false` and say how the capability is delivered instead. A reader must not read the absent registration as drift.

> **Nothing in canonical validates this file for you.** `mcps/custom/` is yours — `/aios:update` never touches it, and the canonical test suite never reaches your machine (`tests/` is repo infrastructure and is deliberately not synced to vaults). The AIOS App's unmanifested-folder report is the surface that catches a missing manifest here. That asymmetry is worth knowing rather than discovering: the bundled folders are guarded by CI, and yours are guarded by the card telling you a folder is unlisted.

## Registry

| MCP | Folder | Auth | Use case |
|-----|--------|------|----------|
