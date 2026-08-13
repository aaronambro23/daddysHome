# Daddy — Project Status (`simple` branch)

**Last Updated**: 2026-08-12
**Repository**: `git@github.com-personal:aaronambro23/daddysHome.git`
**Branch**: `simple`

---

## What Daddy is

A **command centre and PM centre** for AI coding agents.

Daddy does not run agents inside itself. It launches them into Terminal.app,
where the work actually happens, and it owns the paper trail: what each batch of
work was meant to do, what got done, what is left, and what the previous agent
thought should happen next.

The problem it exists to solve: when you open a new agent session — a fresh
Claude chat, or a switch to Codex or Cursor — you should not have to re-explain
the project. Daddy hands the new session a written record of exactly where the
last one stopped.

---

## The two branches

| | `simple` (this branch) | `complex` |
|---|---|---|
| **Where work happens** | Your own Terminal.app window | Embedded terminal inside Daddy |
| **Who owns the process** | Terminal.app | `SessionManager` owns a real pty |
| **What Daddy shows** | Batch documents, progress, history | Live agent output, states, uptime |
| **Terminal rendering** | None | SwiftTerm `TerminalView` |
| **Core question** | "Where did we leave off?" | "What is the agent doing right now?" |
| **Head** | `802c040` | `b78c745` |

Both share the same base commit (`b78c745`): the real pty work, the
process-group shutdown fix, `ExecutableResolver`, and the Liquid Glass UI.
`simple` then removed the embedded terminal and everything mock; `complex`
keeps them.

`simple` is the active line of development.

---

## The workflow

1. **Install the working agreement** on a project. Daddy writes `AGENTS.md` —
   the convention Codex, Cursor and opencode already read — plus a one-line
   `CLAUDE.md` containing `@AGENTS.md`, so Claude Code picks up the same file.
   One contract, every CLI.

2. **You decide the batching.** In your prompt, you say how the work should be
   divided. One area of work may become one document or five; the agent does not
   decide this.

3. **The agent creates the document at the start of a batch**, at
   `docs/handoffs/NNN-slug.md` in the project it is working in — numbered for
   order, with the plan as unticked checkboxes.

4. **It ticks boxes as it works**, and records changes (especially deletions) as
   it goes.

5. **It closes the document** with a summary and, most importantly, its opinion
   on the next possible steps — the part a git diff can never produce.

6. **Daddy reads all of it** and tells you where a new agent should resume. One
   click launches that agent in Terminal.app, already told which document to read
   and which tasks are still open.

Because the document is created at the *start*, a half-ticked file is itself the
"where we left off" signal. Nothing has to be reconstructed after the fact, and
an interrupted session still leaves a usable record.

---

## Development status

| Step | | Status |
|---|---|---|
| — | Handoff contract, parser, derived overview | ✅ `85a5a0e` |
| 1 | Cross-project Overview; mock surfaces removed | ✅ `549aef9` |
| 2 | Launch into Terminal.app, pre-briefed | ✅ `c7721c4` |
| 4 | Voice intake, foreground-only | ✅ `802c040` |
| 3 | Live refresh via file watching | ⬜ Not started |
| 5 | Diagnostics (`daddy doctor`) | ⬜ Not started |

### Tests

```
82 tests · 5 failures · 1 skipped · ~1s
```

All failures are pre-existing and confined to `CommandParserTests` and
`MarkdownWriterTests`. `CommandParserTests` is mildly flaky — the count varies
between 4 and 5 across runs.

Live agent tests are opt-in: `DADDY_LIVE_AGENT_TESTS=1 swift test`. They are
skipped by default because launching an interactive agent TUI inside XCTest is
unreliable — the agent never exits and the runner can block at exit on the file
descriptors it inherited.

---

## What's built

### DaddyCore

- **`WorkflowContract.swift`** — the cross-CLI working agreement written into a
  project. A Claude *skill* cannot serve this role: skills live in
  `.claude/skills/` and no other CLI can read them.
- **`HandoffDoc.swift`** — parses `NNN-slug.md`: status, agent, checkbox
  progress, goal / summary / changes / next-steps. Distinguishes "all ticked but
  never marked done" (`stalled`) from `done`, and ignores the template's italic
  placeholders so a fresh document does not look pre-filled.
- **`HandoffStore.swift`** — reads a project's documents and derives the
  overview, including which document to resume at. Can render it as `DONE.md`.
- **`ContractInstaller.swift`** — writes `AGENTS.md` + `CLAUDE.md`, copying any
  existing file to `.bak` first.
- **`TerminalLauncher.swift`** — opens an agent in Terminal.app via AppleScript
  `do script`, with an initial prompt naming the document to continue.
- **`ExecutableResolver.swift`** — resolves bare CLI names against the login
  shell's PATH. A GUI app launched from Finder inherits a minimal PATH that does
  not include `~/.local/bin`, where these CLIs live.
- **`PTYProcess.swift`** — a real pty (`forkpty` via SwiftTerm's `LocalProcess`)
  with process-group shutdown. Unused by the UI on this branch; kept for future
  unattended runs.
- **`TerminalInput.swift`** — typed control bytes and named keys.

### DaddyApp

- **Overview** — every project that has batch documents, its progress, and a
  Needs Attention panel flagging stalled batches and projects with unfinished
  work untouched for a week.
- **Batches** — the selected project's documents in order, expandable to goal,
  outstanding tasks, summary and next steps. "Copy brief" assembles what a fresh
  agent needs. "Continue with…" launches an agent on that batch.
- **Voice** — foreground-only intake (see below).
- **Settings** — which agent CLIs actually resolve, and what Daddy is tracking.

Projects are real directories under `~/Documents`, via DaddyCore's
`discoverProjects()`, filtered to those that still exist.

---

## How voice works

HEX (`/Applications/Hex.app`, third-party) keeps its global hotkey and stays
useful in every other app. Daddy takes **no microphone permission**, watches no
files, and needs no Full Disk Access.

When Daddy becomes frontmost it focuses its voice field. HEX pastes the
transcription into that field, Daddy shows its interpretation, and **Return**
runs it.

Foreground rather than a wake word because HEX always pastes into the focused
field — `copyToClipboard: false`, `useClipboardPaste: true`, and there is no
silent mode. A global "daddy, …" would type the command into whatever app you
were in. Frontmost makes the paste land somewhere harmless, and visible.

`VoiceRouter` reuses `CommandParser` for intent and its Spanish keywords, but
does its own verb, agent and target matching: `CommandParser`'s dictionary has
`continue`, `go` and `dale` but no `start`, `launch` or `run`, and it has no
concept of projects or batches.

---

## Known gaps

- **The HEX paste path has never been tested with real dictation.** The field
  focuses, the parse is correct, and the launch works — but pasting from HEX into
  the focused field is the one step that has not been exercised.
- **No file watching yet.** A five-second rescan stands in, so an agent ticking a
  box takes up to five seconds to appear. Step 3 replaces this.
- **No diagnostics.** Failures are silent: a CLI missing from PATH, `Hex.app` not
  installed, `saveTranscriptionHistory` switched off. Step 5 addresses this.
- **`HEXWatcher` is unused and buggy.** Its dedup compares `UInt64(text.utf8.count)`
  against a variable named `lastReadPosition`, so a short transcription following
  a long one is dropped. Only relevant if a global wake-word mode is ever added.
- **`CommandParser` has 4-5 failing tests**, covering intents this branch routes
  around rather than uses.

---

## Build & test

```bash
# Tests
cd daddycore-spm && swift test

# Run the app
cd DaddyApp && swift build && ./.build/debug/DaddyApp
```

Requires **macOS 26** (`DaddyApp` targets `.macOS(.v26)` for the Liquid Glass
APIs). `daddycore-spm` stays on `.macOS(.v13)`.

The app must **not** be sandboxed, or a launched child shell loses filesystem
access. Relevant when bundling and notarizing.

---

## Next steps

1. **Step 3 — file watching.** `DispatchSource.makeFileSystemObjectSource` over
   each project's `docs/handoffs/`, debounced. The pattern already exists in
   `HEXWatcher.swift:44`; fix its two bugs rather than inheriting them.
2. **Step 5 — diagnostics.** Which CLIs resolve, is Hex installed and configured,
   is Full Disk Access granted, which projects have the contract.
3. **Try it on a real project.** Install the working agreement on one of the
   client repos and run a real batch through it end to end.
