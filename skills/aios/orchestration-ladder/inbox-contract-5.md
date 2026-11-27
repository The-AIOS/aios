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
| `path` | yes | An absolute path inside the framework root. No `~`, no relative path, no `.` or `..`. |
| `line` | no | A line to put the cursor on. |
| `surface` | no | As in contract 2: which surface should do it. Absent, whichever claims it first. |
| `from` | no | As in contract 4. |

Opening only SHOWS. The surface never runs the file, never hands it to another application, and never
reveals it in the system file manager. The file's content never goes back to the session that asked.

**What this protects against, in proportion.** A session able to rewrite a surface's configuration or a
link in the home folder can already read those files with its own tools. What `open` must not become is a
more comfortable way to put them on the operator's screen, nor something a session confused by someone
else's text can trigger with a single JSON file. The checks below are written for that, not as a boundary
against a session that is determined to get around them.

## The root

**The only root is the framework root (the vault included).** The operator's workspace folders do not
count for a request from a session: their list lives in files inside the framework root that any session
can write (`.glass/shell.json`, `.glass/state.json`), so a session could add `~/.config` to it and then ask
for a file there. A file in a repository outside the framework root therefore cannot be opened through this
verb; the way to change that later is a list of folders the operator confirms in the surface itself, not
implemented here.

The surface resolves the root **once, when it starts**, not on every request: re-pointing the link the root
is reached through (`~/aios`) or the setting that names it then needs the surface to restart. A root is never
the file-system root, the home folder, a folder that contains the home folder, or a folder inside a hidden
folder of the home (any segment below home that starts with a dot: `~/.config`, `~/.local`). And it must look
like a framework root (it holds `vault/` and `plugins/aios/`). When no root is left, the surface turns `open`
off: it logs why once, and refuses every `open` that reaches check 8 with an [`unavailable`] dead letter that
says `open` is off and why, rather than open files from somewhere else.

The fixture's `roots` list several candidates on purpose, so these rules are tested; prepared, they leave
exactly one. Its `framework_roots` cases give other lists and what is left of each.

## The decision, in order

A surface decides every `open` request with the checks below, in this order, and stops at the first that
fails. A failure is a dead letter (`.undelivered`) whose reason names the check; nothing is opened. The `why`
code in brackets is what the conformance fixture compares; the wording of the reason is the surface's own,
and it quotes only the path as written, never a resolved one. Checks 1 to 8 make no file-system call.

1. **Age.** The surface first saw the request file more than **60 seconds** ago, or the file was already in
   the inbox when the surface started [`too-old`]. "First saw" is the surface's own clock: the time of the
   file event, or of the first pass that listed it. Never the file's timestamps, which whoever writes the
   request sets. A request refused here is not counted in check 2. The other verbs wait; this one does not,
   because a file that opens minutes after it was asked for takes the operator's attention for something
   nobody is asking for any more.
2. **Flood.** Every `open` request a surface decides is counted (except those refused by check 1), refused
   ones included, and asking again for a file already open counts too. If this surface has counted
   **20** or more in the last **60 seconds**, from any sessions [`flood`]. This check needs no field, so a stream of
   malformed requests is a flood too. A surface may drop `flood` requests without a dead letter for each,
   writing instead one dead letter a minute that says how many were dropped, so a flood cannot bury the dead
   letters that matter.
3. **`name`** is missing, is not a string, or once sanitized is empty or longer than 64 characters
   [`bad-name`]. Sanitized as the surfaces sanitize every session name: trimmed, lower case, white space to
   dashes, every character other than `a`–`z`, `0`–`9` and `-` dropped, and leading and trailing dashes
   removed.
4. **Rate.** The surface has counted **5** or more requests for this same `name` in the last 60 seconds
   [`rate-limited`].
5. **`path`**, in this order: it is missing or not a string, or, once ASCII spaces and tabs are trimmed from
   both ends, is empty or contains a control character (U+0000–U+001F, U+007F–U+009F), a line or paragraph
   separator (U+2028, U+2029) or a direction mark or override (U+061C, U+200E, U+200F, U+202A–U+202E,
   U+2066–U+2069) [`bad-path`]: dead letters and notices quote the path, and these would make it read as
   something else. It is not absolute, or it starts with `~` [`not-absolute`]. It is longer than 4,096
   characters, ends in a separator, or has a `.` or `..` segment [`bad-path`]: resolving `..` would make the
   system walk folders outside the root, and whether that succeeds would tell the session that they exist.
   The trimmed path is the one used from here on. On Windows these apply with both separators, and also:
   - a path starting with two separators of either kind (`\\host\share`, `\\?\…`, `\\.\…`, `\/host`)
     [`bad-path`]: touching it could send the operator's network credentials to that host;
   - a path that is not a drive letter, a colon and a separator (`C:x.md`, `\Users\x.md`) [`not-absolute`];
   - a colon anywhere after the drive (an alternate data stream), a segment ending in a dot or a space, a
     segment with a `~` followed by an ASCII digit (a short 8.3 name such as `OBSIDI~1`, which says nothing about the
     long name it stands for), or a segment whose name before its first dot, without trailing spaces, is a
     reserved device (`CON`, `PRN`,
     `AUX`, `NUL`, `COM0`–`COM9`, `LPT0`–`LPT9`, `COM¹`–`COM³`, `LPT¹`–`LPT³`, `CONIN$`, `CONOUT$`)
     [`bad-path`]: Windows would open something other than what the name says.
6. **`line`**, when the field is present, is not a number equal to a whole number from 1 to 10,000,000
   [`bad-line`]. `true`, `null`, `"12"`, `1.5` and numbers too large for a float are refused; `12.0` and
   `1e3` are lines 12 and 1000.
7. **A secret, by the path as written** [`secret`]. See *Secrets* below.
8. **Root, as text.** With separators collapsed, the path is not inside the root, as the root was configured
   or as it resolved at start [`unavailable`]. No file-system call is made for a path that fails here.
9. **Resolve, inside the root.** Starting at the resolved root and walking the rest of the path one segment
   at a time: a segment that does not exist, more than **40** links followed in one walk, or a link whose
   target (read, not followed; a relative target taken from the link's folder; separators collapsed and `.`
   and `..` applied as text) is outside the resolved root [`unavailable`]. The target of such a link is never touched. A link to somewhere inside the root is
   followed and the walk continues from there. Missing and outside share one code on purpose: the dead letter
   is readable by the session, and two codes would let it probe what exists outside the root.
10. **A regular file, with one link.** What the walk ends on is a directory, a pipe, a socket, a device or
    anything but a regular file [`not-a-file`]. It has more than one hard link [`hard-link`]: a hard link to a
    key made inside the vault resolves to itself and has an innocent name, so neither the root nor the secret
    check would see it. (Measured on the framework root of a working vault: 0 of 103,145 files have a second
    link.)
11. **A secret, by the resolved path, and by the name the file system stores** [`secret`]. The walk keeps
    the spelling of the request, and a case-insensitive file system matches more spellings than a lower-case
    comparison does (on macOS `.obſidian` reaches `.obsidian`). So the surface also asks the file system for
    the stored name of the file it is about to open (`realpath(3)`; in Node `fs.realpathSync.native`, which
    on Windows also turns a short name into the long one) and applies the secret rules to that too. If that
    call fails [`unavailable`]. If the stored name is not a secret but differs from the resolved path by more
    than the case of its letters or a short name, the file changed under the checks [`unavailable`].
12. **Kind.** The file is binary, or too large for the viewer to show [`unreadable`]. A surface does not fall
    back to revealing it in the file manager. Images and PDF documents are shown: the surface renders them
    itself.
13. **Executable.** The resolved name ends in `.exe`, `.com`, `.bat`, `.cmd`, `.ps1`, `.msi`, `.scr`, `.app`,
    `.command`, `.lnk`, `.url`, `.webloc`, `.desktop`, `.terminal`, `.jar`, `.vbs`, `.hta`, `.reg`, `.scpt`,
    `.workflow`, `.pkg`, `.dmg`, `.appimage`, `.jse`, `.vbe`, `.wsf`, `.wsh`, `.cpl`, `.msc`, `.pif`, `.scf`,
    `.appref-ms`, `.application`, `.appinstaller`, `.msix`, `.appx`, `.msp`, `.settingcontent-ms`,
    `.library-ms`, `.searchconnector-ms`, `.fileloc`, `.inetloc`, `.afploc`, `.mobileconfig` or `.jnlp` (files
    the system acts on when opened, with nothing to read), or the file has an execute permission bit and its name does
    not end in a document extension (`.md`, `.markdown`, `.txt`, `.json`, `.yaml`, `.yml`, `.toml`, `.csv`,
    `.log`, `.html`, `.htm`, `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.svg`, `.pdf`) [`executable`]. Some
    drives mark every file executable, which is why documents are exempt from the bit. Source code (`.py`,
    `.js`, `.sh` without the bit) is shown: it is text to read, and the surfaces never run what they show.

On Windows, checks 8 and 9 compare paths with one separator (`\`) and without regard to case.

When every check passes, the surface opens the RESOLVED path, with:

- **`mode: "source"`** when the resolved name ends in `.html`, `.htm`, `.xhtml`, `.xht`, `.shtml`, `.mht` or
  `.mhtml`. A viewer may render HTML with its scripts running, on the assumption that the file is the
  operator's own export; a file an agent asked for is not known to be. An `.svg` is shown only as an image
  (an `<img>`, never inline and never in a frame), where it cannot run code. Every other file opens in the
  viewer's usual mode.
- the cursor on `line` when it was given.

## Secrets

Decided by NAME only. No surface reads a file's content to decide whether it is a secret.

Names are compared folded: lower case, then upper case, then lower case again (`s.lower().upper().lower()` in
Python, `s.toLowerCase().toUpperCase().toLowerCase()` in JavaScript, which agree), so `ſ` is `s`, `ß` and `ẞ`
are `ss`, and `ı` is `i`: spellings a case-insensitive file system may take to the ASCII names below. One backup
suffix (`.bak`, `.old`, `.orig`, `.backup` or `~`) is taken off the last segment first, so `token.json.bak` is
judged as `token.json`. A path is a secret when:

- any segment is `.ssh`, `.gnupg`, `.aws`, `.docker`, `.kube`, `.git`, `.obsidian`, `.claude` or
  `agent-secrets`; or
- its last segment is `.env` or `.envrc`, starts with `.env_` or `.env-`, contains `.env.`, or ends with
  `.env` (but `.envelope.md` is a note); or it is `.netrc`, `.pgpass`, `.npmrc`, `.pypirc`,
  `.git-credentials`, `.dockercfg`, `.mcp.json`, `.dev.vars`, `credentials`, `kubeconfig`, `auth.json`,
  `.htpasswd`, `.vault-token`, `.yarnrc.yml`, `.s3cfg`, `.my.cnf`, `storage_state.json` or
  `spotify-cache.json`; or
- its last segment ends with `.asc`, `.pem`, `.key`, `.p12`, `.pfx`, `.p8`, `.kdbx`, `.ovpn`, `.ppk`, `.jks`,
  `.keystore`, `.tfstate` or `.tfvars`; or
- its last segment ends with `.json` and starts with `service-account` or contains `firebase-adminsdk`; or
- it is a `.json` file directly inside a folder named `auth` (where browser automation keeps saved logins);
  or
- its last segment is not prose (it does not end in `.md`, `.markdown`, `.html`, `.htm`, `.pdf`, `.png`,
  `.jpg`, `.jpeg`, `.gif`, `.webp` or `.svg`), and its name without the extension, split into words (at every
  change from an ASCII lower-case letter to an ASCII upper-case one, then, folded, into runs of `a`–`z` and of
  `0`–`9`), has one of the words `token`, `tokens`, `credential`, `credentials`, `oauth`, `secret`, `secrets`,
  `cookie`, `cookies`, `password`, `passwords`, `apikey` or `apikeys`, or the word `api` followed by `key` or
  `keys` (where the framework's own `.gitignore` says OAuth tokens, saved browser
  sessions and cookies live); or
- its last segment starts with `id_rsa`, `id_dsa`, `id_ecdsa` or `id_ed25519` and does not end in `.pub` (the
  private halves of SSH keys, whatever suffix they were given).

The list is applied to the path as written and to the resolved path, so neither a secret reached through a
link nor a link named like a secret gets through. It refuses some ordinary files too (`.env.example`,
anything under `.git` or `.obsidian`, a data file such as `token-usage.json`, `design-tokens.json` or
`cookie-consent.yml`): a name-only rule cannot tell a template from the real file, and none of those is
something an agent needs to show. It does not refuse a note whose name merely mentions a token or a secret
(`tokenomics.md`, `secrets-of-sales.md`), nor a data file whose words only resemble one (`tokenizer.json`).
Binary secret stores (a browser's `Cookies` or `Login Data`, a password manager's database) are refused by
check 12 whatever their name.

## Showing it

These hold however a surface's viewer works:

- **The content shown is the content checked.** A surface reads what it shows from the file it decided on:
  it opens the resolved path without following a final link and without blocking (a pipe swapped in must not
  hang it), checks on the open descriptor that it is still a regular file with one link and the same file
  (device and inode, or the Windows file id) as when the checks ran, walks the path once more to the same
  end, and reads at most what the viewer shows from that descriptor. Images and PDF documents are shown from
  those bytes too, never by their path. A viewer that would read the file again later repeats checks 9 to 13 first and shows nothing
  new if they fail. Otherwise a session could swap the file for a link to a key after the open, and the viewer
  would display the key. (The surfaces show such a file as a read-only snapshot and never reload it, and never
  save or restore it as an open file across a restart. "Open to edit" reopens it in the surface's own editor as
  the operator's own file; it never hands it to the system opener.)
- **Nothing the file points at is loaded on its behalf unless it would pass these checks.** A local image in
  a rendered note is joined to the opened file's resolved folder, `..` applied as text, and shown only if a
  request for it would pass checks 5 to 13, from the bytes of the file that passed. Remote images wait for the
  operator, as the viewers already do for notes. Raw HTML inside a note never runs scripts, and frames,
  objects and embeds are never loaded. A PDF is shown with its scripts and launch actions inert. A link the
  operator clicks inside the file is the operator's own action, through the surface's usual path; nothing in
  an opened file is handed to the system opener by itself.
- **No raised window.** An `open` never brings the surface's window to the front of the operating system, and
  never moves the keyboard focus out of what the operator is typing into.

## What the operator sees

- The file opens in the surface's own viewer: a viewer pane in the App, an editor tab in Glass.
- **In front inside the surface, unless the operator is typing.** If the operator has typed into a session in
  the last few seconds (the App's existing guard against typing over a prompt that is being written), the file
  opens in a background tab and a short notice names the session that asked and the file. Otherwise its tab
  comes to the front of the surface. Glass always keeps the keyboard where it is (`preserveFocus`).
- A request that is refused is a dead letter, which `/today` and `/close-day` already show.

## How a session uses it

Inside a surface (the terminal carries `AIOS_GLASS_TERM`) and only when the inbox README is stamped contract 5
or later, a session shows a file with `open` instead of the system opener. Outside a surface, or on an older
stamp, nothing changes.

## What this does not cover

- A session that re-points the framework root to a visible folder (through the link or the setting) and has
  the surface restarted widens what `open` reaches. The real anchor is a root the operator confirms in the
  surface, with `open` turned off until they confirm again if it changes; not implemented here.
- A file mounted into the root under an innocent name (a bind or network mount of a secret folder) is not
  seen by a name-only rule.
- "Open to edit" opens the real file in an ordinary editor tab, which reloads from disk as such tabs do and
  does not repeat these checks: a session that later swaps the file for a link to a key, after the operator
  chose to edit it, is outside what `open` decides.
- A name-only rule refuses some ordinary files (an extensionless `TODO-passwords-rotation`) and lets through
  secrets with unremarkable names; it is a guard against the comfortable case, not an inventory.
- Two surfaces running at once may have resolved different roots; with `surface` absent, the one that claims
  the request decides.

## Conformance

`inbox-contract-5.conformance.json` is one fixture for every implementation. It describes a small file system
(paths, links, kinds, link counts, and for some files a `stored` name: what `realpath` native returns for
it, empty when that call fails), the configured roots and the home folder, and for each case a request, how
long ago the surface first saw it, the requests already counted, and the expected decision:
`{"do": "open", "path", "line", "mode"}` or `{"do": "refuse", "why"}`. Its `windows_paths` give the code the
path-shape and secret checks assign to Windows paths, and `windows_roots` whether a Windows path is inside a
root. `tests/inbox-contract-5.test.sh` runs every case against a reference implementation
(`tests/fixtures/inbox-contract-5-ref.py`), so the fixture is known to be self-consistent before a surface runs
it.
