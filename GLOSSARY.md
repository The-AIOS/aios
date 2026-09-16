# Glossary — the words you need to decide

> **Who this is for.** Anyone deciding whether to grant AIOS access to their machine, calendar, email or Slack — without a technical background. **You cannot consent to something described in a vocabulary you do not have**, and not having it is the normal starting position, not a disqualification.
>
> One plain sentence per term. *"In AIOS"* appears only where the local meaning differs from the general one. Read [`SECURITY.md`](./SECURITY.md) next; this file exists so that one is readable.

---

## Start here: three words that mean two things each

**These collisions cause more confusion than every other entry combined.** If you remember nothing else, remember these.

**Token** — two unrelated meanings.
1. **A unit of text** an AI reads or writes. Roughly ¾ of a word. *"This file costs 25,000 tokens"* means "it is long."
2. **A credential** — a long secret string that grants access to an account, like a password a program uses instead of you typing one. *"Your Slack token"* means **something that can act as you.**

**These are not related, and merging them is the dangerous mistake.** "Reducing tokens" is about cost. "Leaking a token" is about someone getting into your Slack. Sense 2 is the one that matters for security.

**Agent** — two meanings.
1. **In the industry:** any AI that takes actions rather than only answering.
2. **In AIOS:** a *named role* you can start, like `accountant` or `lawyer` — a file describing how that role should behave. Starting one is called a **spawn**.

**Context** — two meanings.
1. **What the AI can currently see** — the conversation plus the files it has read. Finite; the limit is the **context window**.
2. **In AIOS:** the *stored knowledge about you* in your vault — `declared` (what you wrote) and `observed` (what Claude noticed). This persists between sessions.

---

## 1 · The AI itself

**AI / model** — the program that reads text and produces text. Claude is a model; so is GPT; so is Gemini.

⚠️ **Which model runs is not fixed, and it is part of your security posture.** AIOS is built around Claude Code, and a **spawned worker** is always a Claude model — `spawn` passes its model argument straight to the `claude` binary, which runs Claude models only. But the repo also ships [`AGENTS.md`](./AGENTS.md), a portable contract for other tools that read that convention (Codex, Cursor, Aider), and the desktop app **opens terminals** — whatever CLI you run inside one is what is actually running, whoever made it.

Why that matters here rather than in a footnote: **a model's own refusal behaviour is one of the controls.** A model that declines to exfiltrate a credential when a malicious document asks it to is doing real security work that no permission setting replaces. That behaviour differs between models and is not something AIOS can supply on their behalf — so *choosing* the model is a decision, not a default.

**LLM (large language model)** — the technical name for that kind of model. It predicts likely continuations of text. It does not "look things up" unless given a tool that does.

**Prompt** — what you send the model. Your message, plus instruction files it was given, plus anything it has read.

**Context window** — the maximum the model can hold at once. Past it, older material is summarised or dropped.

**Inference** — one round of the model producing an answer. Each costs money and time.

**Hallucination** — the model stating something false with the same confidence as something true. It is not lying; it has no separate sense of "I know this" versus "this seems likely." **This is why AIOS insists on evidence over assertion** — a claim checked against a file is worth more than a claim delivered confidently.

**Prompt injection** — ⚠️ **the most important security term here.** Text hidden inside content the AI *reads* — an email, a web page, a PDF, a shared document — written to look like instructions *to the AI*. A model cannot reliably tell "content I was asked to read" from "instructions I was given."

*Why it matters in AIOS:* if a session reads a malicious email **and** holds your Google credentials, the question is not whether the email can read your Drive. It is whether the session that read it can then be talked into reading your Drive. See [`SECURITY.md`](./SECURITY.md) § *The one thing to understand first*.

---

## 2 · The runtime — what is actually running

**Terminal** — the text window where you type commands.

**CLI (command-line interface)** — a program you drive by typing rather than clicking. Claude Code is one.

**Session** — one running conversation with Claude, with its own context. Closing it ends that memory; your vault persists. You can have several at once, which is why AIOS cares about two sessions writing the same file.

**Tool call** — the model using a capability instead of just answering: reading a file, running a command, sending an email. **Actions happen only through tool calls**, which is why *which tools a session has* is the real security question.

**Agent / subagent / worker** — a session started for a specific job. A **subagent** reports back into the session that started it; a **spawned worker** is independent and cannot be harvested inline.

**Spawn** — starting a named worker.

**Permission mode** — how Claude Code decides whether a tool call needs your approval. The setting that actually enforces limits. *In AIOS:* `INTENT.md` records your *preferences*; permission mode is what **enforces** them. Preference is not enforcement.

**Sandbox** — a restriction on what a program may touch. **Not sandboxed** means normal access to your files, as any app you run has. The AIOS desktop app is deliberately not sandboxed, because it must launch other programs.

**Routine / scheduled run** — a session that starts on a timer with **nobody watching**. Matters because a prompt nobody sees cannot be answered, and silence must never count as yes.

---

## 3 · AIOS's own vocabulary

**Vault** — your folder of notes. The whole system is files on your disk; there is no AIOS cloud holding your data.

**Declared context** — what *you* wrote about yourself. You control it.

**Observed context** — what *Claude* wrote about you over time: patterns, preferences, growth notes. **Private by design**, never shared or pushed to a shared repository.

**Skill** — a reusable capability loaded when relevant, like a manual the session can open.

**Plugin** — a bundle of commands added to Claude Code.

**Slash command** — a shortcut you type, like `/aios:today`. It runs a written procedure, not hidden code.

**Hook** — a small script that runs automatically at a defined moment. ⚠️ **Worth understanding before you consent:** some hooks write outside your vault — to your shell configuration or login items. [`SECURITY.md`](./SECURITY.md) § *The update model* names which, and a session will show you the actual file before running it.

**MCP (Model Context Protocol)** — the standard way a model connects to an outside service. **An MCP server is a small program that lets Claude use one service** — Gmail, Slack, Drive. Connecting one grants access with whatever permissions you approve. *Most MCP code AIOS uses is written by other people*, which is why [`SECURITY.md`](./SECURITY.md) lists each one's source and whether we have read it.

**Surface** — an app you run AIOS through: the terminal, the desktop app, or the editor extension.

**Roadmap key** — a short label like `AB-12` that tracks one piece of work.

**Truth surface** — the single file that answers *"is this done?"* for an item, so two places can never disagree.

**Snapshot** — an automatic archived copy of a file before it changes, so history survives an edit.

---

## 4 · The plumbing a consent decision needs

**Repo (repository)** — a folder of code with its full history. AIOS is a public one on GitHub.

**Git** — the tool tracking every change. **Commit** — one saved change with a description. **Push** — sending commits to GitHub. **Clone** — your own copy. **Fork** — your own copy you can change independently.

**SHA / commit hash** — a fingerprint identifying one exact version, like `8beacf8`. ⚠️ **Why it matters:** *"pinned to a SHA"* means **exactly this version, nothing else**. Without it you get "whatever is current," which can change between yesterday and today.

**Package** — someone else's code your software uses. **Dependency** — a package yours needs to work.

**Pinning** — writing down the **exact version** of a package instead of "the newest." ⚠️ **The single most important term in this section.** Unpinned, the code audited yesterday is not the code that runs tomorrow. **Pinning gives reproducibility, never safety** — a pinned bad version stays bad; it removes *silent substitution*, which is how most real supply-chain attacks work.

**npm / npx** — the registry for JavaScript packages, and the command that downloads and runs one. `npx thing@latest` means **"fetch whatever is newest right now and run it."**

**PyPI / uvx** — the same for Python.

**Supply chain** — everyone whose code ends up running on your machine. A **supply-chain attack** compromises one of *them* rather than you: they publish a malicious update, and everyone who auto-updates receives it. ⚠️ This is why [`SECURITY.md`](./SECURITY.md) is blunt about unsigned, unpinned updates.

**Credential** — anything proving you are you: password, API key, token, cookie.

**Cookie** — a small file your browser holds that keeps you logged in. ⚠️ **Copying a cookie copies the login.** AIOS's browser automation can read your Chrome cookies, which is why a **separate Chrome profile** for agent use is the recommendation that costs nothing.

**Scope** — the specific permissions a credential carries. *"Read-only calendar"* is a narrow scope; *"full Gmail"* is broad. **Narrow scopes are the cheapest real protection available to you.**

**OAuth** — the "Sign in with Google" flow. You approve a list of permissions and the program receives a **token** (sense 2) instead of your password. ⚠️ Read that approval screen — it is the moment you decide.

**Service account / bot** — a separate identity for a program, rather than lending it yours. ⚠️ **The distinction that matters most in [`SECURITY.md`](./SECURITY.md):** a bot misbehaving is a contained incident; *your* identity misbehaving is a message your colleagues believe came from you.

**PAT (personal access token)** — a scoped credential for GitHub instead of your password.

**Notarization / code signing** — Apple's check that an app came from the developer it claims and was not altered. ⚠️ **It does not mean the app is limited in what it can do** — only that it is authentic.

**CI (continuous integration)** — automated checks on every change. AIOS runs ~64 test suites; several exist specifically to stop a security rule from silently going missing.

---

*If a term you need is missing, that is a gap worth reporting — the absence of a word is the same failure this file exists to fix.*
