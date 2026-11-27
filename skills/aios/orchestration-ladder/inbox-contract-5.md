# Spawn-inbox contract 5: the `open` verb

> **Status: specified, not in force.** This spec and its conformance fixture
> (`inbox-contract-5.conformance.json`, checked by `tests/inbox-contract-5.test.sh`) ship first. Contract 4
> stays in force until both surfaces implement the verb and stamp `aios-spawn-inbox: contract 5` in
> `~/.aios/spawn-inbox/README.md`. Until then a session must not send `open`: a fulfiller on contract 4
> dead-letters it as an unknown action.

## What changes

One new verb. Nothing that worked stops working; the other four verbs and the contract 4 fields are unchanged.

`open` asks a surface to show a file in its own viewer, beside the sessions: the AIOS App opens it in a
viewer pane, AIOS Glass in an editor tab. It exists because a session had no way to show the operator a
file except the system opener (`open`, `xdg-open`, `start`), which hands it to whatever application the
operating system has for that type.

```json
{"action": "open", "name": "<the session asking>", "path": "/absolute/path/to/file.md", "line": 12}
```

| Field | Required | Meaning |
|---|---|---|
| `action` | yes | `"open"`. |
| `name` | yes | The registry name of the session asking. Not a target: it is who is asking, used for the rate limit and named in what the operator sees. Required also because a fulfiller on contract 4 refuses a request with no `name` without naming the verb; with one, it dead-letters `unknown action 'open'`, which is what an agent is told to expect. |
| `path` | yes | An absolute path. No `~`, no relative path. |
| `line` | no | A line to put the cursor on, an integer from 1. |
| `surface` | no | As in contract 2: which surface should do it. Absent, whichever claims it first. |
| `from` | no | As in contract 4. |

Opening only SHOWS. The surface never runs the file, never hands it to another application, and never
reveals it in the system file manager. The file's content never goes back to the session that asked.

## The decision, in order

A surface decides every `open` request with the checks below, in this order, and stops at the first that
fails. A failure is a dead letter (`.undelivered`) whose reason names the check; nothing is opened. The
`why` code in brackets is what the conformance fixture compares; the wording of the reason is the
surface's own.

1. **`name`** is missing or sanitizes to nothing [`missing-name`].
2. **`path`** is missing, not a string, empty after trimming, or contains a NUL, a carriage return or a
   line feed [`bad-path`]. It is not absolute, or it starts with `~` [`not-absolute`].
3. **Age.** The request file is older than **60 seconds** [`too-old`]. The other verbs wait; this one
   does not, because a file that opens ten minutes after it was asked for (a surface that was closed, an
   App still starting) takes the operator's attention for something nobody is asking for any more.
4. **`line`**, when present, is not an integer from 1 to 10,000,000 [`bad-line`].
5. **A secret, by the path as written** [`secret`]. See *Secrets* below.
6. **Resolve.** The path is resolved through every symbolic link, in every segment. It does not exist
   [`not-found`].
7. **Roots.** The RESOLVED path is not inside one of the surface's roots [`outside-roots`]. The roots are
   the framework root (the vault included) and the operator's workspace folders: the folders the surface
   already lets its explorer and quick-open read. Not the files the operator dropped onto a surface (that
   grant is for the operator's own work, not for an agent), and not anything else in the home folder. The
   roots are compared resolved too. A path written through a link inside a root that points outside is
   therefore refused: deciding on the path as written would let a link in the vault open a key in
   `~/.ssh`.
8. **A regular file.** The resolved path is a directory, a device, a socket or anything but a regular
   file [`not-a-file`].
9. **A secret, by the resolved path** [`secret`].
10. **Kind.** The file is binary, or too large for the viewer to show [`unreadable`]. A surface does not
    fall back to revealing it in the file manager. Images and PDF documents are shown: the surface
    renders them itself.
11. **Executable.** The file has an execute permission bit, or its extension is one of `.exe`, `.com`,
    `.bat`, `.cmd`, `.ps1`, `.msi`, `.scr`, `.app`, `.command` [`executable`]. Showing a script is
    harmless; the rule is there so that no request ever puts an executable in front of the operator one
    click away from running it.
12. **Rate.** The same `name` has had **5** files opened by this surface in the last **60 seconds**
    [`rate-limited`]. A file already open in this surface does not count again: asking twice for the same
    file brings its tab forward. Each surface counts its own opens.

When every check passes, the surface opens the RESOLVED path, with:

- **`mode: "source"`** for `.html` and `.htm`. A surface's viewer may render HTML with its scripts
  running, on the assumption that the file is the operator's own export; a file an agent asked for is not
  known to be. Every other file opens in the viewer's usual mode.
- the cursor on `line` when it was given.

## Secrets

Decided by NAME only. No surface reads a file's content to decide whether it is a secret.

A path is a secret when, compared without case:

- any segment is `.ssh`, `.gnupg`, `.aws` or `agent-secrets`; or
- its last segment is `.env`, starts with `.env.`, ends with `.env`, or is `.envrc`, `.netrc` or `.pgpass`; or
- its last segment ends with `.pem`, `.key`, `.p12` or `.pfx`; or
- its last segment is `id_rsa`, `id_dsa`, `id_ecdsa` or `id_ed25519`, optionally followed by `_sk`
  (the private halves of SSH keys; the `.pub` files are not secrets).

The first two lines are the ones the framework's agent-secrets convention already blocks for reads. The
list is applied to the path as written and to the resolved path, so neither a secret reached through a
link nor a link named like a secret gets through. `.env.example` is refused too: a name-only rule cannot
tell a template from the real file.

## What the operator sees

- The file opens in the surface's own viewer: a viewer pane in the App, an editor tab in Glass.
- **In front, unless the operator is typing.** If the operator has typed into a session in the last few
  seconds (the App's existing guard against typing over a prompt that is being written), the file opens in
  a background tab and a short notice names the session that asked and the file. Otherwise its tab comes
  to the front. Glass always keeps the keyboard where it is (`preserveFocus`): the tab shows, the cursor
  stays in the terminal.
- A request that is refused is a dead letter, which `/today` and `/close-day` already show.

## How a session uses it

Inside a surface (the terminal carries `AIOS_GLASS_TERM`) and only when the inbox README is stamped
contract 5 or later, a session shows a file with `open` instead of the system opener. Outside a surface,
or on an older stamp, nothing changes.

## Conformance

`inbox-contract-5.conformance.json` is one fixture for every implementation. It describes a small
file system (paths, links, kinds), the roots and the home folder, and for each case a request, its age, the
opens already counted, and the expected decision: `{"do": "open", "path", "line", "mode"}` or
`{"do": "refuse", "why"}`. The paths are POSIX; a surface on Windows runs the same decision with its own
path rules. `tests/inbox-contract-5.test.sh` runs every case against a reference implementation, so the
fixture is known to be self-consistent before a surface runs it.
