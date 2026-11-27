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
| `name` | yes | The registry name of the session asking. Not a target: it is who is asking, used for the rate limit and named in what the operator sees. It is a claim, never an identity. Required also because a fulfiller on contract 4 refuses a request with no `name` without naming the verb; with one, it dead-letters `unknown action 'open'`, which is what an agent is told to expect. |
| `path` | yes | An absolute path. No `~`, no relative path. |
| `line` | no | A line to put the cursor on. |
| `surface` | no | As in contract 2: which surface should do it. Absent, whichever claims it first. |
| `from` | no | As in contract 4. |

Opening only SHOWS. The surface never runs the file, never hands it to another application, and never
reveals it in the system file manager. The file's content never goes back to the session that asked.

## The decision, in order

A surface decides every `open` request with the checks below, in this order, and stops at the first that
fails. A failure is a dead letter (`.undelivered`) whose reason names the check; nothing is opened. The
`why` code in brackets is what the conformance fixture compares; the wording of the reason is the
surface's own, and it quotes only the path as written, never the resolved one. Checks 1 to 7 read no file
system at all.

1. **`name`** is missing, is not a string, sanitizes to nothing, or is longer than 64 characters once
   sanitized [`bad-name`]. (Sanitized as the surfaces sanitize every session name: trimmed, lower case,
   whitespace to dashes, anything but letters, digits and dashes dropped.)
2. **Rate.** Every `open` request a surface decides is counted, refused ones included, and so is asking
   again for a file already open. If this surface has decided **20** or more in the last **60 seconds**,
   from any sessions [`flood`]. If it has decided **5** or more for this same `name` in that time
   [`rate-limited`]. A surface may drop `flood` requests without writing a dead letter for each, writing
   instead one dead letter a minute that says how many were dropped, so a flood cannot bury the dead
   letters that matter.
3. **`path`** is missing, not a string, contains a NUL, a carriage return or a line feed, or is empty after
   trimming surrounding white space [`bad-path`]. It is not absolute, or it starts with `~`
   [`not-absolute`]. The trimmed path is the one used from here on. On Windows, also:
   - a path starting with two separators (`\\host\share`, `\\?\…`, `\\.\…`) [`bad-path`]: touching it could
     send the operator's network credentials to that host;
   - a path that is not a drive letter, a colon and a separator (`C:x.md`, `\Users\x.md`) [`not-absolute`];
   - a colon anywhere after the drive (an alternate data stream), a segment ending in a dot or a space, or a
     segment whose name before its first dot is a reserved device (`CON`, `PRN`, `AUX`, `NUL`, `COM1`–`COM9`,
     `LPT1`–`LPT9`) [`bad-path`]: Windows would open a different file than the name says.
4. **Age.** The surface first saw the request file more than **60 seconds** ago, or the file was already in
   the inbox when the surface started [`too-old`]. "First saw" is the surface's own clock: the time of the
   file event, or of the first pass that listed it. Never the file's timestamps, which whoever writes the
   request sets. The other verbs wait; this one does not, because a file that opens ten minutes after it
   was asked for takes the operator's attention for something nobody is asking for any more.
5. **`line`**, when the field is present, is not a number equal to a whole number from 1 to 10,000,000
   [`bad-line`]. `true`, `null`, `"12"` and `1.5` are refused; `12.0` is line 12.
6. **A secret, by the path as written** [`secret`]. See *Secrets* below.
7. **Roots, as text.** With `.` and `..` applied as text, the path is not inside one of the surface's roots,
   as written or resolved [`unavailable`]. No file system call is made for a path that fails here.
8. **Resolve.** The path is resolved through every symbolic link, in every segment, to the name the file
   system stores (`realpath(3)`; in Node, `fs.realpathSync.native`), and compared byte for byte. It does not
   exist, or the resolution loops [`unavailable`].
9. **Roots, resolved.** The resolved path is not inside one of the resolved roots [`unavailable`]. A path
   written through a link inside a root that points outside is therefore refused: deciding on the path as
   written would let a link in the vault open a key in `~/.ssh`. Missing and outside share one code on
   purpose: the dead letter is readable by the session, and two codes would let it probe which files exist
   outside the roots.
10. **A regular file, with one link.** The resolved path is a directory, a pipe, a socket, a device or
    anything but a regular file [`not-a-file`]. It has more than one hard link [`hard-link`]: a hard link
    to a key made inside the vault resolves to itself and has an innocent name, so neither the roots nor
    the secret check would see it.
11. **A secret, by the resolved path** [`secret`].
12. **Kind.** The file is binary, or too large for the viewer to show [`unreadable`]. A surface does not
    fall back to revealing it in the file manager. Images and PDF documents are shown: the surface renders
    them itself.
13. **Executable.** The file has an execute permission bit, or its extension is one of `.exe`, `.com`,
    `.bat`, `.cmd`, `.ps1`, `.msi`, `.scr`, `.app`, `.command`, `.lnk`, `.url`, `.webloc`, `.desktop`,
    `.terminal`, `.jar`, `.vbs`, `.hta`, `.reg`, `.scpt`, `.workflow`, `.pkg`, `.dmg`, `.appimage`
    [`executable`]. Showing a script is harmless; the rule is there so that no request ever puts something
    runnable one click away.

**The roots** are the framework root (the vault included) and the operator's workspace folders: the folders
the surface already lets its explorer and quick-open read. Not the files the operator dropped onto a surface
(that grant is for the operator's own work, not for an agent), and never the file-system root, the home
folder, or a folder that contains the home folder, even if a configuration lists one: the workspace list is
a file inside the framework root, which a session can write.

When every check passes, the surface opens the RESOLVED path, with:

- **`mode: "source"`** when the resolved name ends in `.html`, `.htm`, `.xhtml`, `.xht`, `.shtml`, `.mht` or
  `.mhtml`. A viewer may render HTML with its scripts running, on the assumption that the file is the
  operator's own export; a file an agent asked for is not known to be. Every other file opens in the
  viewer's usual mode.
- the cursor on `line` when it was given.

## Secrets

Decided by NAME only. No surface reads a file's content to decide whether it is a secret.

A path is a secret when, compared without case:

- any segment is `.ssh`, `.gnupg`, `.aws`, `.docker`, `.kube`, `.git`, `.obsidian` or `agent-secrets`; or
- its last segment is `.env`, starts with `.env.`, ends with `.env`, or is `.envrc`, `.netrc`, `.pgpass`,
  `.npmrc`, `.pypirc`, `.git-credentials`, `.dockercfg`, `.mcp.json` or `storage_state.json`; or
- its last segment ends with `.pem`, `.key`, `.p12`, `.pfx`, `.kdbx`, `.ovpn`, `.ppk`, `.jks` or
  `.keystore`; or
- its last segment starts with `service-account` and ends with `.json`; or
- its last segment ends with `.json`, `.yaml`, `.yml` or `.toml` and contains `token`, `credential`,
  `oauth`, `secret` or `cookie` (where the framework's own `.gitignore` says OAuth tokens, saved browser
  sessions and cookies live); or
- its last segment is `id_rsa`, `id_dsa`, `id_ecdsa` or `id_ed25519`, optionally followed by `_sk` (the
  private halves of SSH keys; the `.pub` files are not secrets).

The list is applied to the path as written and to the resolved path, so neither a secret reached through a
link nor a link named like a secret gets through. It refuses a few ordinary files too (`.env.example`,
anything under `.git`, Obsidian's own settings): a name-only rule cannot tell a template from the real file,
and none of those is something an agent needs to show. It does not refuse a note whose name merely mentions a
token or a secret (`tokenomics.md`): only data files are matched by those words.

## Showing it

These hold however a surface's viewer works:

- **The content shown is the content checked.** A surface reads what it shows from the file it decided on:
  still a regular file, still one link, still the same file (device and inode, or the Windows file id) as
  when the checks ran. A viewer that would read the file again later (a reload when the file changes on
  disk) repeats checks 8 to 13 first, and shows nothing new if they fail. Otherwise a session could swap the
  file for a link to a key after the open, and the viewer would display the key.
- **Nothing the file points at is fetched on its behalf from outside the roots.** A rendered note's images
  that are local files outside the roots are not loaded; remote images wait for the operator, as the
  viewers already do for notes; nothing in an opened file is handed to the system opener.
- **No raised window.** An `open` never brings the surface's window to the front of the operating system,
  and never moves the keyboard focus out of what the operator is typing into.

## What the operator sees

- The file opens in the surface's own viewer: a viewer pane in the App, an editor tab in Glass.
- **In front inside the surface, unless the operator is typing.** If the operator has typed into a session
  in the last few seconds (the App's existing guard against typing over a prompt that is being written), the
  file opens in a background tab and a short notice names the session that asked and the file. Otherwise
  its tab comes to the front of the surface. Glass always keeps the keyboard where it is (`preserveFocus`).
- A request that is refused is a dead letter, which `/today` and `/close-day` already show.

## How a session uses it

Inside a surface (the terminal carries `AIOS_GLASS_TERM`) and only when the inbox README is stamped
contract 5 or later, a session shows a file with `open` instead of the system opener. Outside a surface, or
on an older stamp, nothing changes.

## What this does not cover

- A file mounted into a root under an innocent name (a bind or network mount of a secret folder) is not
  seen by a name-only rule.
- Two surfaces running at once may have different roots; with `surface` absent, the one that claims the
  request decides.

## Conformance

`inbox-contract-5.conformance.json` is one fixture for every implementation. It describes a small file
system (paths, links, kinds, link counts), the roots and the home folder, and for each case a request, how
long ago the surface first saw it, the requests already counted, and the expected decision:
`{"do": "open", "path", "line", "mode"}` or `{"do": "refuse", "why"}`. Its `windows_paths` give the code the
path-shape and secret checks assign to Windows paths. `tests/inbox-contract-5.test.sh` runs every case
against a reference implementation, so the fixture is known to be self-consistent before a surface runs it.
