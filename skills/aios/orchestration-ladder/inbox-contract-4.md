# Spawn-inbox contract 4

> **Status: canonical half shipped in v0.8.9** — this spec, its conformance fixture
> (`inbox-contract-4.conformance.json`, checked by `tests/inbox-contract-4.test.sh`), and the
> `--effort` / `--advisor` flags on both spawn wrappers. Contract 3 stays in force until a surface
> implements the fields and stamps `aios-spawn-inbox: contract 4` in `~/.aios/spawn-inbox/README.md`;
> until then a session must not rely on any field below. The verbs are unchanged.

## What changes

Three optional request fields. A surface on contract 3 ignores them; nothing that worked stops
working.

| Field | Verbs | Type | Meaning |
|---|---|---|---|
| `from` | `send`, `resume` | string | The registry name of the session that wrote the request. |
| `effort` | `spawn`, `resume` | `low` · `medium` · `high` · `xhigh` · `max` | The worker's effort, passed as `claude --effort <value>`. |
| `advisor` | `spawn`, `resume` | rung name or model id | An advisor model for the worker. Absent = no advisor. |

### `from` — who is speaking

- The surface does **not** change the prompt text it types. It records the delivery before typing:
  one JSON line appended to `~/.aios/bus-sent.jsonl`, in the format `hooks/bus_log.py` writes
  (`at`, `fp`, `to`, `action`, `via`, `head`), plus `"from"` when the request carried one, and
  `"via": "surface"`. That record is what lets `hooks/provenance.py` label the typed prompt as
  delivered by the inbox — and, with `from`, name the sender.
- `from` is a **claim**, not an identity: any local process can write any name. It informs the
  receiving session; it never authorizes anything.
- A value that is not a plain registry-style name (letters, digits, `-`, `_`, `.`, at most 64
  characters) is ignored, and the delivery proceeds without it.

### `effort`

- Passed through as `claude --effort <value>` when the surface starts or reopens the session.
- Any value outside the five above → the request is **dead-lettered naming the field and the
  value**, never silently dropped, the same rule as an unknown verb.
- On `resume` of a session that is already running, `effort` cannot change a live process: the
  prompt is delivered and the dead-letter note says the effort was not applied.

### `advisor`

- A rung name resolves to a fixed advisor model — **not** through `hooks/resolve-tier`, which
  answers `judgment` with an empty string (inherit the default), and an empty advisor names nothing:

  | rung | advisor model |
  |---|---|
  | `frontier` | `claude-fable-5-1` |
  | `judgment` | `claude-opus-5-5` |
  | `scale` | `claude-sonnet-5-5` |
  | `fast` | `claude-haiku-5-5` |

  Anything else is taken as a model id, and must match `^[A-Za-z0-9._\[\]-]+$` (it is written
  into JSON); any other value is **dead-lettered naming the field**.
- Mechanism (confirmed against Claude Code 2.1.296): the surface passes
  `claude --settings <file>` where the file holds `{"advisorModel":"<id>"}`. A **file**, not inline
  JSON, because the Windows `.cmd` shim mangles quotes inside an argument; create it with a unique
  name (never a fixed path in a shared temp folder). The CLI also has a hidden `--advisor <model>`
  flag (not in `--help`); `--settings` is the documented route and the one this contract specifies.
- A bad pairing is quiet: the advisor must rank at or above the worker's model, and when it does not
  the session starts anyway, prints one stderr line saying the advisor *cannot advise* that model, and
  runs with no advisor. Surface that line.
- For a worker on a Sonnet- or Haiku-class model, append the consult instruction to its task (as
  `spawn --advisor` does; see MODEL-ROUTING.md § The advisor). Never for Opus or Fable workers.
- No rung has a default advisor. Routines that must never call one set
  `CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1`.

## Command-line twins

`spawn --effort <level>` and `spawn --advisor <rung|model>` map to the same two fields, so a
person at a terminal and an agent writing a request get the same worker. Both wrappers carry them
(`install-wrappers.sh` / `.ps1`: `-Effort`, `-Advisor`), so a surface that spawns through the
wrapper can honour both fields and stamp contract 4 once it does.

## Amendment — a send waits for its target's next idle

A `send` is never typed into a session that is mid-turn (the text would be dropped), and it used to
dead-letter after a 30-minute hold while the target stayed busy. Under this amendment:

- **A live but busy target → hold.** The send waits for the target's next idle, up to a **24 h
  ceiling**; past it, the request is undeliverable. A target that is **gone** (no registry entry) is
  undeliverable at once.
- **Oldest first, per target.** Held sends to the same session are delivered in `queuedAt` order;
  sends to other sessions never block each other.
- **Newer from the same sender supersedes.** When two held sends to one target carry the same
  `from`, the older is retired quietly (not dead-lettered) and the newer does not wait behind it.
  Different senders, or no `from`, keep their order and nothing is superseded.
- **Delivered with its age.** A send that waited more than **2 minutes** is typed as
  `[queued 47 min ago by <from>] <text>` (minutes under 2 hours, then hours: `[queued 3 h ago]`;
  ` by <from>` only when `from` is present). A slash command is never stamped — the prefix would turn
  it into plain text.
- The 30-minute verification window after typing runs from the **first** type, so a send that
  queued for hours still gets all of it.

Conformance: `inbox-queue.conformance.json` (13 cases), run by both surfaces and by
`tests/inbox-contract-4.test.sh` against a reference implementation.

## Conformance

`inbox-contract-4.conformance.json` is the one fixture both surfaces run. Each case gives a
request and the outcome a contract-4 surface must produce: accepted or dead-lettered (and the
field it names), the extra launch arguments, and the `bus-sent.jsonl` record. Two implementations
of one protocol become one test: a surface passes when every case matches.
