# /aios:fortress — find your containment rung, then climb one

Inspects this machine, reports which rung of the containment ladder the operator is actually on, and offers to execute the next one. The Fortress equivalent of *"set up my AI-OS from this repo"* — the operator should never have to read 600 lines to find out that the first useful thing costs nothing.

Read [`FORTRESS.md`](../../../FORTRESS.md) § The containment ladder for the rungs themselves, and `USER.md` → `### /aios:fortress` for personalizations.

> **Detect, never interrogate.** Every rung below is *measurable from the machine*. Asking the operator "have you scoped your permissions?" gets you their impression, which is the thing that was wrong. Run the probes, report findings, and ask only for the decision to proceed.

---

## Step 1 — Probe (silent, read-only, no writes)

Run these and hold the results. **Every probe must distinguish "absent" from "could not check."** A probe that errors and is read as a clean pass is how this command would tell someone they are contained when they are not — the failure mode that matters most here, because the output is a safety claim.

```bash
# ── Rung 1 · what leaves ────────────────────────────────────────────────────
git -C ~/aios remote -v 2>/dev/null | awk '{print $2}' | sort -u   # any PUBLIC remote?
# Guard the file test: on a vault that has not pulled the hook yet, an unguarded
# call prints a Python traceback, which reads like a broken machine rather than a
# missing update. "Not installed" is a legitimate answer, not an error.
test -f ~/aios/hooks/openrouter.py \
  && python3 ~/aios/hooks/openrouter.py --check 2>&1 | tail -2 \
  || echo "rail:not-installed (run /aios:update)"
grep -c 'AIOS-OPERATOR-IGNORES' ~/aios/.gitignore 2>/dev/null       # operator marker present?
ls ~/.claude/plugins 2>/dev/null >/dev/null; echo "claude-config:$?"

# ── Rung 2 · what an agent can touch ────────────────────────────────────────
test -f ~/aios/.claude/settings.json && echo "settings:present" || echo "settings:absent"
# NOT `ls ~/.config/aios-secrets/*.env`: zsh aborts the whole command on an
# unmatched glob ("no matches found") BEFORE ls runs, so redirecting ls's stderr
# does nothing and the probe dies on exactly the machine it is meant to describe
# — the one with no secrets dir yet. find takes the pattern as an argument.
find ~/.config/aios-secrets -name '*.env' -maxdepth 1 2>/dev/null | wc -l | tr -d ' '
test -x ~/aios/.git/hooks/pre-commit && echo "githook:installed" || echo "githook:absent"
# keys exported in a shell rc = present in the environment of EVERY process launched
grep -lE '^[[:space:]]*export[[:space:]]+[A-Z0-9_]*(API_KEY|TOKEN|SECRET)' \
  ~/.zshrc ~/.zshenv ~/.bashrc ~/.bash_profile 2>/dev/null

# ── Rung 3/4 · separation ───────────────────────────────────────────────────
# `worktree list` always prints the main tree, so 1 means ZERO additional ones.
# Reporting the raw count as "1 worktree" would read as rung 3 satisfied.
echo $(( $(git -C ~/aios worktree list 2>/dev/null | wc -l) - 1 ))
command -v tailscale >/dev/null 2>&1 && echo "tailscale:present" || echo "tailscale:absent"
sudo pfctl -s rules 2>/dev/null | head -3 || echo "pf:not-readable"
```

**Reading the probes.** Four of these lie if read naively, and each one was caught by running this list against a live machine rather than reasoning about it:

- **`pfctl` without sudo** prints nothing and exits non-zero — that is *not-readable*, never *no firewall*. - **The rc-grep** prints filenames only when it matches, so **empty output is the good case** and an error is neither.
- **`git worktree list`** counts the main tree, so the useful number is one less than the line count.
- **An absent `~/aios/hooks/openrouter.py`** means the vault has not pulled the update yet — report *not-installed*, not *inert*, because those imply different next steps.

When a probe cannot run, say so in the report and **exclude it from the rung verdict** rather than counting it either way. A rung claimed on the strength of a probe that never executed is worse than no verdict at all: the whole output of this command is a safety claim.

---

## Step 2 — Verdict

State the rung in one line, then the evidence, then the single next action. **Name the rung by what is true, not by what is aspired to** — an operator with a Mac mini and keys in `~/.zshrc` is on rung 1, not rung 4. Containment is the weakest link, not the most expensive component.

```
You are on rung 2 of 4.

  ✓ rung 0  vault local + private remote, tokens on disk, no telemetry
  ✓ rung 1  4 MCPs connected · no public remote · rail inert (no key) · ignores marker present
  ✓ rung 2  settings.json scoped · 3 keys in ~/.config/aios-secrets · pre-commit hook installed
  ✗ rung 3  no worktrees in use; experimental work runs in your main tree
  ✗ rung 4  single machine (this is fine — see below)

Next: rung 3, and it is free. ~10 min.
```

**Two calls this command must make honestly:**

- **Rung 4 is not a goal.** If the operator has one machine and no unattended agents, say plainly that rung 4 would buy them little and rung 3 is the end of the useful ladder for their setup. A command that pushes everyone toward $600 of hardware is a brochure.
- **A failing rung 2 outranks a passing rung 4.** If keys are in a shell rc, lead with that regardless of what else is installed.

---

## Step 3 — Execute the next rung (ask once, then do it)

Offer the next rung as a concrete action list with its real time cost — **AI execution time, not human-equivalent** — and run what is runnable. Never run more than one rung per invocation; climbing is meant to be deliberate.

- **Rung 1** — produce the inventory as a note at `vault/00 - notes/reflections/audits/{date}-containment-inventory.md`, wiki-linked, listing each outbound path and what it carries. This rung's whole deliverable is the written list.
- **Rung 2** — the executable one. Move keys from the shell rc into `~/.config/aios-secrets/*.env` (**show the diff and ask before touching any rc file** — a broken rc costs the operator their next shell), install git hooks, add private-data ignores below the marker, and walk the `settings.json` permissions together rather than guessing at them.
- **Rung 3** — set up a worktree for experimental work; explain the second-account option without setting it up (it needs the operator at a GUI).
- **Rung 4** — hand over to `FORTRESS.md` and execute its six layers in order. Hard prerequisites first: two Macs, the second on AC power and stable network. **If either is missing, say so and stop** rather than starting a setup that cannot finish.

**After any rung lands:** update the project note or daily note per the ship-time truth-flip contract, and re-run Step 1 so the new rung is *verified* rather than assumed. A rung that was executed but not re-probed is a claim, and this command deals in evidence.

---

## What this command must never do

- **Never claim a rung it could not measure.** An unreadable probe is reported as unreadable.
- **Never write to a shell rc without showing the diff and getting a yes.**
- **Never touch `~/.ssh/`, the keychain, or system security settings.** Those are the operator's own hands, always — offer the exact commands and let them run them.
- **Never present rung 4 as the finish line.** For most operators the ladder ends at 3.
