# Obsidian vault bridge

Lets the AIOS read and write your notes directly, instead of treating the vault as opaque files.

## Infrastructure, not a connector

This is the one MCP the framework needs to do its own job, so it is **never offered as a choice**.
`connector.json` carries `infrastructure: true`, which tells the AIOS App to keep it out of the
Connectors card entirely — an operator should never be asked whether they want the AIOS to be able to
write the notes they just asked it to write.

It is registered **silently** during `/aios:cold-start-interview`'s opening moments. There is nothing to
decide: the package is published on npm, there is no account, and no token is ever involved.

## Why this folder exists with no server code

The server is the published npm package `@mauricio.wolff/mcp-obsidian`; nothing is vendored here. The
folder exists so the connector has a **manifest**, and the manifest exists so a reader gets an explicit
statement rather than an absence.

That distinction is the whole point. The contract says *"a missing manifest means the connector is not
listed"* — which would produce the right outcome here by accident, while leaving a reader unable to tell
*"deliberately infrastructure"* from *"nobody has written the manifest yet."* Those need different
responses: the first is finished, the second is a gap. An explicit `infrastructure: true` says which.

## Register

Handled for you. Documented here for manual repair only:

```bash
claude mcp add obsidian -- npx -y @mauricio.wolff/mcp-obsidian@latest {framework}/vault
```

`{framework}` is the **resolved** framework root. Never write a literal `~/aios` here — it is a symlink
on some machines, so a hardcoded path documents something different from what works, and the mismatch is
invisible wherever the clone and the symlink happen to agree.

## If it fails

Nothing breaks. Vault writes fall back to ordinary filesystem access; this bridge only makes them
cleaner. Setup deliberately swallows a failure here rather than opening a first run on an error.
