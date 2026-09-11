# Google Workspace MCP — Setup

> **Purpose.** Wire the `google-workspace-mcp` to a Google account so an agent can read and act on
> Drive, Docs, Sheets, Slides, Calendar, Tasks, Gmail, contacts and Forms for that account —
> including folders **shared with** it.
>
> Uses the **local** MCP (its own OAuth client, `uvx`-launched) per the AIOS MCP policy — not the
> claude.ai-hosted Google connector, which is bound to the active claude.ai OAuth grant and breaks
> on an account switch.

---

## Start here — one command

```bash
bash mcps/google-workspace-mcp/connect.sh
```

It creates a Google Cloud project and enables every API the connector needs, then prints the few
steps that are left as links that land on the exact console page for **your** project.

**Why only "most of it".** Google publishes an API for project creation and API enablement, and
publishes none for the consent screen or for creating an OAuth client — not in any `gcloud` release.
So the honest split is: the script does the two automatable parts, which are also the two tedious
ones, and hands you roughly six clicks it cannot do. It does not pretend otherwise, and it does not
leave you a half-configured project if it stops.

Then, after the clicks:

```bash
# installs the client you downloaded, checks it, prints the registration command
bash mcps/google-workspace-mcp/connect.sh --finish --project-id <your-project> \
     --client ~/Downloads/client_secret_*.json

# re-check the APIs at any time
bash mcps/google-workspace-mcp/connect.sh --verify --project-id <your-project>
```

`--dry-run` shows what would happen and changes nothing. `--print-apis` prints just the API list.

### What the script checks, and what it can only tell you

Four things used to go wrong here, and they were documented as *"traps — read first."* A trap that
has to be read is a trap that gets sprung, so three of the four are now checks:

| What went wrong | Now |
|---|---|
| A scope is granted but its **API was never enabled** → consent succeeds, the tool appears, and the first call returns `403 SERVICE_DISABLED`, which reads like an auth problem and is not | **Cannot happen.** The API list is derived from the same `--permissions` in `connector.json` that registers the server. One list, so there is nothing to mismatch. |
| The OAuth client came from a **different project** → `403 org_internal` | **Checked.** `--finish` reads the client's own `project_id` and refuses if it is not the project whose APIs were enabled. |
| The client was created as **Web application** instead of Desktop → `redirect_uri_mismatch` | **Checked.** `--finish` refuses a Web client and names Desktop as the fix. |
| The account is not on the **test-user list** → `403 access_denied` | **Told, not checked** — no API exposes the consent screen. The script shows the step only when your account type can actually hit it, with a link to the page. |

The API list is not written in this document on purpose. It used to be, and it drifted: this file
listed an API nothing requested, while a third copy elsewhere omitted three services entirely.
Nobody noticed, because a wrong API list fails late and blames the wrong thing. To see the list:

```bash
bash mcps/google-workspace-mcp/connect.sh --print-apis
```

### The one trap no script can remove — a 7-day clock

**On a consumer Google account** (`@gmail.com`), the consent screen has no organization to be
internal to, so the app is External and starts in **Testing**. Google expires the **refresh token**
of a Testing app after **7 days**. Nothing is misconfigured and nobody revoked anything: the grant
reached its built-in expiry, and it presents as `invalid_grant: Token has been expired or revoked`.

This is the most expensive item on the page *because it does not fail during setup.* The other three
fail while you are still holding the context — you are in the console, you read the error, you fix
it. This one fails on a Tuesday three weeks later, on a machine you are not watching. Anything that
depends on the server — a daily ritual, a scheduled routine, an agent that reads your calendar each
morning — goes dark once a week until a human clicks through a consent screen.

- **The lever is the publishing status, not verification.** The 7-day clock is attached to
  **Testing**. Moving the app to **In production** (Audience → *Publish app*) is what stops it.
  Publishing and *being verified* are different things: an app can sit in Production **unverified**,
  still showing the "Google hasn't verified this app" screen.
- **Read what Google asks of you at that screen before assuming it is free.** Gmail and Drive are
  not the basic `email`/`profile`/`openid` trio — they are the scope classes that pull an app into
  Google's verification requirements, and those requirements are Google's to change, not this
  document's to promise. The Audience screen at the moment you click Publish is the only current
  answer. If it does ask for verification and you would rather not, that is a real decision.
- **Either way, write the cost down** next to whatever depends on this server. Staying in Testing
  means a manual re-auth **every 7 days, forever** — fine for a throwaway experiment, wrong for a
  server a daily automation depends on.

**On a Workspace account** (any other domain) none of this applies: the app is Internal to your own
organization, trusted by default, with no test-user list and no 7-day clock. If your Workspace admin
gates internal apps you will find out at the Audience step — that is a one-line ask, not a review.

---

## Doing it by hand

The script is the path; this is the reference for when it stops, or when you would rather not
install `gcloud`. Same outcome, more clicks.

**0. Sign in as the target account.** Open [console.cloud.google.com](https://console.cloud.google.com)
signed in as **the account you are wiring** (a clean browser profile or incognito, so it does not
grab a different one). This is what decides whether the consent screen can be External.

**1. New project** — project dropdown → New Project → name it → for a consumer account set
**Location: No organization** → Create → select it.

**2. Enable the APIs** — APIs & Services → **Library** → search and Enable each one. Get the list
from `connect.sh --print-apis`; **one API per service in `--permissions`**, and the two lists must
match or the server starts fine and the tools 403 at call time.

*A mismatch here fails late and confusingly.* The scope is granted, consent succeeds, the tool is
exposed — then the call returns `403 SERVICE_DISABLED: <API> has not been used in project <N> before
or it is disabled`. The error text carries a direct activation URL; open it, enable, wait a minute,
retry. No re-consent is needed — enabling an API is a project setting, not a scope change.

*(Other AIOS tools use other Google APIs — Gemini for image generation, YouTube Data, Analytics.
Enable those only if you use those tools; none is needed for this MCP.)*

**3. Consent screen** (the console may call it **Google Auth Platform**):
- **Audience: Internal** on a Workspace account · **External** on a consumer account — a consumer
  account can never use an Internal client, which is what `403 org_internal` means.
- App name + user-support email + developer email.
- **External only: Audience → Test users → + Add users →** your account → **Save**.

**4. Create the client** — Clients → **+ Create client → Application type: Desktop app** → Create →
**Download JSON** (it arrives as `client_secret_*.json`, type `installed`). Desktop is required: it
is the only type that allows the `http://localhost` redirect this flow uses.

---

## Wire it

**Nothing to install** — the server is fetched from PyPI on demand by `uvx` (see
[`UPSTREAM.md`](./UPSTREAM.md)). `connect.sh --finish` does the next two steps for you, including
the checks above; by hand it is:

```bash
mkdir -p ~/.google_workspace_mcp
cp ~/Downloads/client_secret_*.json ~/.google_workspace_mcp/client_secret.json
chmod 600 ~/.google_workspace_mcp/client_secret.json
```

Then register at **user scope** (creds land in `~/.claude.json`, machine-local). `--finish` prints
this command with the manifest's own permission list already filled in, which is the version to
prefer — a hand-typed permission list is a fourth copy of the same fact:

```bash
claude mcp add google-workspace --scope user \
  --env GOOGLE_CLIENT_SECRET_PATH="$HOME/.google_workspace_mcp/client_secret.json" \
  --env OAUTHLIB_INSECURE_TRANSPORT=1 \
  --env OAUTHLIB_RELAX_TOKEN_SCOPE=1 \
  -- uvx workspace-mcp --single-user --permissions <from connector.json>
```

- **`--single-user`** = bypass multi-user session mapping; use the one token in the credentials dir.
  Right for an agent that IS one account.
- **`GOOGLE_CLIENT_SECRET_PATH`** > inline `GOOGLE_OAUTH_CLIENT_ID/SECRET` — keeps the secret in a
  `600` file, not in the process args.
- **`OAUTHLIB_RELAX_TOKEN_SCOPE=1`** — Google silently adds `openid`; without this the flow errors
  on "scope changed."

## Authorize the account (one-time consent)

The server does OAuth on first tool call and catches the redirect at **`localhost:8000` on the
machine running the MCP**. The redirect MUST reach that machine:

- **At the machine's screen:** open the consent URL there.
- **Remote / headless:** tunnel first, then open the URL on your laptop —
  `ssh -L 8000:localhost:8000 <the-mcp-host>`.

To drive it without a session restart, run a one-shot consent (`from_client_secrets_file` +
`run_local_server(port=8000)`), which prints the URL and, on success, writes the token to
`~/.google_workspace_mcp/credentials/{email}.json` in the store's exact format (`token,
refresh_token, token_uri, client_id, client_secret, scopes, expiry`). Run it **unbuffered**
(`python -u`) or the URL stays stuck in the stdout buffer while `run_local_server` blocks. If the
long URL gets mangled in a chat → terminal → browser hop, `make_auth_link.py` rebuilds it as a
clickable page.

At the consent screen you will see **"Google hasn't verified this app"** — expected for a Testing
app, not a block: **Advanced → Go to {app} (unsafe) → continue → approve.**

## Verify + use

- **Token:** `~/.google_workspace_mcp/credentials/{email}.json` — confirm `refresh_token: yes`
  (it self-renews; no constant re-auth).
- **APIs:** `connect.sh --verify --project-id <your-project>` names anything missing and prints the
  command that enables it.
- **Smoke test** (Drive `sharedWithMe`) confirms the account and that shared folders are visible
  before reloading anything.
- **Restart your Claude session** to use the tools — MCP tools register at session start, so one
  added mid-session is not callable until the next start. After the restart the
  `mcp__google-workspace__*` tools are live and `--single-user` uses the stored token.

## Gotchas condensed

| Symptom | Cause | Fix |
|---|---|---|
| `403 org_internal` | client from an org/Internal project, used by a consumer account | new project under that account, External consent — `--finish` catches this before it happens |
| `403 access_denied` (testers) | account not a test user | add it under Audience → Test users |
| `403 SERVICE_DISABLED` | the scope's API is not enabled | `connect.sh --verify` names it; the error text also carries a direct activation link |
| `invalid_grant` after ~7 days | publishing status still **Testing** | move it to **In production**; read what Google asks at that screen — these are sensitive scopes |
| `redirect_uri_mismatch` | client is not Desktop type | recreate as Desktop — `--finish` catches this before it happens |
| consent URL never prints | Python stdout buffered while `run_local_server` blocks | run `python -u` / `PYTHONUNBUFFERED=1` |
| "scope has changed" | Google added `openid` | `OAUTHLIB_RELAX_TOKEN_SCOPE=1` |
| tools missing after wiring | MCP added mid-session | restart the Claude session |
| redirect fails when remote | `localhost:8000` hit the wrong machine | `ssh -L 8000:localhost:8000 <host>` |
