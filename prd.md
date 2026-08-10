# PRD — Daddy

**Status:** Draft v0.1
**Platform:** macOS
**Primary interaction:** Voice via HEX
**Primary user:** Single developer / personal use
**UI priority:** Low for v1
**Core objective:** Ship code faster by eliminating manual coordination across coding-agent CLIs.

---

# 1. Product Summary

Daddy is a personal macOS control plane for a developer who works simultaneously across many repositories, projects, technologies, and coding-agent sessions.

The user primarily interacts with Daddy through voice transcription from [HEX](https://github.com/kitlangton/Hex).

Daddy does not replace coding agents.

It remotely controls and coordinates existing agent CLIs:

* Claude Code
* Codex
* Cursor Agent CLI
* OpenCode

The user remains responsible for deciding **what work should happen and which agent should perform it**.

Daddy removes the mechanical coordination required to make that happen:

* selecting the appropriate agent
* selecting the requested model
* locating the appropriate project/session
* sending prompts
* controlling agent sessions
* switching between active agents
* running commands
* observing agent state
* preserving meaningful work context
* creating and maintaining human-readable Markdown handoffs
* identifying completed vs unfinished work

The central product concept is **workflow state**.

---

# 2. Problem

The user works in a highly non-linear environment.

They have:

* many personal and client projects
* repositories stored under `Documents`
* different technology stacks including Flutter, Next.js, TypeScript, Python, etc.
* multiple coding agents active simultaneously
* multiple agents working against the same project
* frequent switching between projects
* frequent switching between agents

Agent switching is generally not because different agents have different workflow responsibilities.

Instead, the user may switch agents because:

* an agent is rate-limited
* an agent is unavailable
* the user simply wants to use another agent
* another model is preferable for the current task

Today, coordination is manual.

The user has a `daddyshome` script which opens:

1. Cursor Agent CLI
2. Claude Code CLI
3. Codex CLI
4. OpenCode

Each runs in its own terminal tab and starts in the repository/directory where `daddyshome` was executed.

When moving work between agents, the user manually asks the current agent to summarize:

* what was done
* what changed
* what remains
* relevant context

The resulting Markdown file is then manually supplied to another agent through the CLI's `@` context mechanism.

This works, but creates significant coordination overhead.

---

# 3. Product Vision

The desired experience is:

> **Say what you want to happen. Daddy operates the appropriate coding-agent session and keeps the workflow state organized.**

The user should be able to say things like:

> “Claude, continue.”

> “Claude, stop.”

> “Codex, review this.”

> “Cursor, take over.”

> “OpenCode, run the tests.”

> “Claude, switch to Opus.”

> “What's Claude doing?”

> “What's left?”

> “Hand this to Codex.”

The interaction should be terse.

The user should not need to describe the entire project, repository, task, or agent session every time.

Daddy uses current context and workflow state to resolve references.

---

# 4. Product Principles

## 4.1 Voice-first

Voice is the primary control mechanism.

The product should not require a complex GUI to be useful.

HEX remains the speech-to-text interface.

Daddy consumes the resulting transcript.

---

## 4.2 User remains in control

Daddy is a remote control, not an autonomous project manager.

The user chooses:

* what work to do
* which agent to use
* which model to use
* when to switch agents
* when to stop
* when to continue

Daddy should remove mechanical work, not make strategic decisions on the user's behalf.

---

## 4.3 Terse interaction

Commands should be short and contextual.

The user should not have to say:

> “Please switch to the Claude Code session currently working on the authentication feature in my Acme repository.”

Instead:

> “Claude, continue.”

Daddy resolves the intended session from context.

If ambiguity exists, Daddy asks a short clarification.

---

## 4.4 Personal vocabulary

Daddy should support a personal dictionary of words and phrases specific to the user's workflow.

The user frequently switches between English and Argentine Spanish.

The command interpreter should therefore support both languages and personal expressions.

Examples:

```text
continue
seguí
dale

stop
frená
pará

review
revisá

handoff
pasalo
pasáselo

status
qué onda
estado

tests
corré los tests
```

The dictionary should eventually be configurable and learnable.

---

## 4.5 Agents are interchangeable workers

The work itself is the primary entity.

An agent is metadata about who is currently performing the work.

Daddy must not impose an artificial workflow such as:

```text
Claude → Codex → Cursor
```

The same agent can implement, review, test, debug, and finish a task.

Agents may change primarily because of availability or rate limits.

---

## 4.6 Filesystem-readable state

The user wants workflow state represented through Markdown files on the Desktop.

The filesystem should remain human-readable without Daddy.

A user should be able to open the workflow directory and immediately understand:

* what projects exist
* what work exists
* what is active
* what is completed

The system should not make an opaque database the only representation of workflow state.

---

# 5. Core Concepts

## 5.1 Project

A repository/project located on the user's Mac.

Example:

```text
~/Documents/acme-mobile
```

Projects may use different technologies.

---

## 5.2 Work Unit

A meaningful coherent piece of work.

Examples:

* authentication refactor
* Stripe subscription implementation
* dashboard redesign
* flaky test investigation

A work unit is **not** an individual command, prompt, or tiny code change.

Daddy should intelligently group related changes into one work unit.

For example:

```text
fix typo
rename variable
update test
fix related API call
run tests
```

may all belong to one work unit.

Daddy should avoid generating a Markdown file for every trivial action.

---

## 5.3 Session

An active interaction with an agent CLI.

A project may have many concurrent sessions:

```text
Acme
├── Claude
├── Codex
├── Cursor
└── OpenCode
```

Multiple sessions may operate on the same project simultaneously.

---

## 5.4 Agent

One of the supported coding-agent CLIs:

* Claude Code
* Codex
* Cursor Agent CLI
* OpenCode

---

## 5.5 Model

The model selected within an agent CLI.

The user may explicitly specify a model:

> “Claude Opus.”

or omit it.

If omitted and a model must be selected, Daddy asks the user.

Daddy must be capable of interacting with agent-specific model selectors such as `/model` and keyboard navigation.

---

## 5.6 Focus

Daddy maintains a currently focused project/session/work unit.

This allows extremely terse commands.

Example:

> “Continue.”

can mean:

```text
continue(focused_session)
```

while:

> “Codex, continue.”

resolves a Codex session.

If multiple sessions are ambiguous, Daddy asks for clarification.

---

# 6. Existing Environment

The user currently has:

```text
daddyshome
```

which launches four agent CLIs in separate terminal tabs, all from the directory where the command is executed.

This existing workflow should be preserved conceptually.

Daddy should eventually become the orchestration layer around these processes rather than requiring the user to abandon them.

---

# 7. Core User Flow

## 7.1 Start work

User says:

> “Claude, fix the login bug.”

Daddy determines:

```text
agent = Claude
action = start/work
project = relevant project
prompt = "fix the login bug"
```

If the model was specified:

> “Claude Opus, fix the login bug.”

Daddy selects the requested model.

If the model was not specified and selection is required, Daddy asks:

> “Which model?”

The user responds via HEX.

---

# 8. Agent Selection

Agent selection is explicitly user-controlled.

Daddy may identify the agent from the transcript:

```text
Claude
Codex
Cursor
OpenCode
```

or ask:

> “Which agent?”

The system must resolve natural references to agents.

Examples:

```text
Claude
Claude Code
the Claude one

Codex
the Codex tab

Cursor

OpenCode
Open Code
```

Aliases should eventually be configurable.

---

# 9. Model Selection

The user may specify the model in the voice command.

Example:

> “Claude Opus, fix the bug.”

Daddy parses:

```text
agent = claude
model = opus
```

Daddy then interacts with the agent CLI to select that model.

For CLIs requiring interactive selection:

```text
/model
↓
keyboard navigation
↓
requested model
↓
confirm
```

If the user does not specify a model and Daddy needs one, it asks.

Example:

> “Which model?”

The answer is then incorporated into the current operation.

Model selection must be implemented inside the agent adapter rather than the core workflow engine.

---

# 10. Agent Remote Control

Daddy should support remote-control primitives including:

* start
* continue
* stop
* interrupt
* resume
* send prompt
* send follow-up
* inspect output
* inspect status
* change model
* run commands
* run tests
* handoff
* switch focus

Examples:

```text
“Claude, stop.”

“Claude, keep going.”

“Codex, review.”

“Run the tests.”

“Claude, switch to Opus.”

“OpenCode, take over.”

“Tell Codex what Claude found.”
```

---

# 11. Concurrent Sessions

Daddy must support many simultaneously active sessions.

Example:

```text
Acme
├── Claude / Opus
│   └── authentication
├── Codex / GPT-x
│   └── API review
└── Cursor
    └── dashboard UI

Personal
└── OpenCode
    └── CLI refactor

Client B
├── Claude
│   └── Flutter bug
└── Codex
    └── test fixes
```

Sessions must remain distinguishable even when the same agent is used across multiple projects.

---

# 12. Rate Limits

Rate limits are a first-class state.

Example:

```text
Claude
status: RATE_LIMITED

Codex
status: AVAILABLE
```

If the user says:

> “Claude, continue.”

and Claude cannot continue because of a rate limit, Daddy should report that fact and offer the user control over the next agent.

Example:

> “Claude is rate-limited. Which agent?”

The user can respond:

> “Codex.”

The work unit remains the same.

Only the active agent changes.

---

# 13. Workflow State

Workflow state is the central product capability.

Daddy should maintain enough state to understand:

* projects
* work units
* active sessions
* agents
* models
* current focus
* work status
* recent actions
* meaningful changes
* handoffs
* completion state
* rate limits
* relevant context

The system should not initially attempt to build a generalized long-term personal memory system.

That can be added later.

---

# 14. Markdown Workflow System

Markdown files are the user's persistent workflow record.

They should be stored in a dedicated folder on the Desktop.

Proposed structure:

```text
Desktop/
└── DaddyWork/
    ├── AcmeApp/
    │   ├── authentication/
    │   │   ├── 2026-08-10_1420.md
    │   │   ├── 2026-08-10_1640.md
    │   │   └── DONE.md
    │   │
    │   └── payments/
    │       └── 2026-08-10_1100.md
    │
    ├── ClientB/
    │   └── dashboard/
    │       └── 2026-08-10_0915.md
    │
    └── Personal/
        └── MyProject/
            └── cli/
                └── 2026-08-10_1530.md
```

Exact folder naming conventions may evolve during implementation.

---

# 15. Markdown Granularity

Daddy must **not** create a Markdown file for every small action.

Markdown files represent meaningful accumulated work/context.

The system should semantically group related changes.

Example:

A single work unit may include:

```text
Claude investigates bug
Claude implements fix
Claude changes three files
Claude runs tests
Claude discovers another related issue
Claude fixes issue
Codex continues because Claude is rate-limited
Codex runs tests
```

This may remain one coherent work unit.

A new Markdown snapshot is created when there is a meaningful state/context boundary.

Possible triggers:

* significant work accumulation
* meaningful change in direction
* handoff
* user-requested summary
* work becoming inactive
* milestone
* completion

These rules should be tuned through actual usage.

---

# 16. Markdown Contents

A normal work-state Markdown file should summarize meaningful accumulated context.

Example:

```md
# Authentication Refactor

## Goal

...

## Current State

...

## What Was Done

- ...
- ...

## Changes

- ...
- ...

## Remaining

- ...
- ...

## Decisions

- ...
- ...

## Agents Used

- Claude / Opus
- Codex / GPT-x

## Agent Changes

Claude:
- ...

Codex:
- ...

## Notes

...

## Updated

2026-08-10 16:40
```

The exact schema should remain flexible in v1.

The objective is usefulness to both the user and another coding agent.

---

# 17. Agent Handoff

When the user changes agents for the same work unit, Daddy should be able to create/update the appropriate Markdown context automatically.

Example:

> “Claude, hand this to Codex.”

Daddy should:

1. determine the current work unit
2. capture relevant current state
3. create/update the appropriate Markdown state
4. switch/focus the Codex session
5. provide the relevant Markdown context to Codex using the CLI's context mechanism
6. preserve the work unit identity

The user should not manually ask for a summary or manually locate the Markdown file.

---

# 18. Completion

When a work unit is complete, Daddy creates:

```text
DONE.md
```

inside that work unit's directory.

Example:

```text
authentication/
├── 2026-08-10_1420.md
├── 2026-08-10_1640.md
└── DONE.md
```

`DONE.md` is the canonical final summary.

It should contain:

* goal
* what was implemented
* significant changes
* agents/models used
* important decisions
* tests/results
* remaining caveats, if any
* completion timestamp

The existence of `DONE.md` means the work unit is complete.

---

# 19. Completion Detection

Daddy should not assume that an agent saying:

> “I think we're done.”

means the work is complete.

Initially, completion should be explicitly user-controlled.

Examples:

> “We're done.”

> “Mark this done.”

> “Finish this.”

Daddy then creates `DONE.md`.

Automatic completion detection may be explored later.

---

# 20. Future Reminder System

Not part of the initial implementation.

Eventually Daddy can scan the workflow directory.

For each work-unit directory:

```text
DONE.md exists
    → completed

DONE.md missing
    → unfinished
```

This enables future functionality such as:

> “You have three unfinished things from yesterday.”

or:

> “Remind me about the payment refactor tomorrow.”

Reminder functionality should not block the initial product.

---

# 21. Multilingual Voice Input

The system must support mixed English and Argentine Spanish.

The parser should not require the user to speak exclusively in one language.

Example:

> “Claude, fijate qué onda con este error y arreglalo.”

should resolve to an actionable internal command.

Likewise:

> “Codex, review this and después corré los tests.”

The internal representation should be language-independent.

Example:

```json
{
  "intent": "work",
  "agent": "codex",
  "actions": [
    "review",
    "run_tests"
  ],
  "target": "focused_work_unit"
}
```

---

# 22. Intent / Command Architecture

Voice transcripts should be transformed into structured commands.

Conceptually:

```text
HEX transcript
      ↓
Intent parser
      ↓
Structured command
      ↓
Context resolver
      ↓
Workflow engine
      ↓
Agent/session operation
```

Example:

```text
“Claude, keep going.”
```

becomes approximately:

```json
{
  "intent": "continue",
  "agent": "claude",
  "target": "focused"
}
```

Another:

```text
“Codex, take over.”
```

becomes:

```json
{
  "intent": "handoff",
  "target_agent": "codex",
  "work_unit": "focused"
}
```

The exact protocol is implementation detail.

---

# 23. Ambiguity Handling

Daddy should prefer acting when context is sufficiently clear.

If there is ambiguity, it should ask a short question.

Example:

> “Codex, continue.”

If two Codex sessions are active:

> “Which one: Acme or Personal?”

The user answers:

> “Acme.”

The operation continues.

The system should avoid requiring unnecessarily verbose commands.

---

# 24. Focus Management

Daddy should maintain:

* focused project
* focused work unit
* focused session
* focused agent

Examples:

> “Switch to the Flutter project.”

> “What is it doing?”

> “Continue.”

These should operate against the current focus.

Explicit agent references override focus where appropriate.

---

# 25. Project Discovery

The user's repositories currently live under `Documents`.

Daddy should discover projects from the filesystem rather than requiring the user to manually register every repository.

Initial assumptions:

```text
~/Documents/
```

contains project/repository directories.

Project discovery should be extensible later.

---

# 26. Technical Architecture

Recommended technology:

### Platform

macOS

### Language

Swift

### UI

SwiftUI

UI is intentionally low priority.

### Runtime

Native macOS background/menu-bar application.

### Concurrency

Swift Concurrency:

* `async/await`
* actors
* structured concurrency

### Process Control

Use:

* Swift `Process` where appropriate
* POSIX PTYs for interactive CLI sessions

Interactive agent CLIs must be controlled through PTYs because Daddy needs to emulate terminal interaction.

This includes:

* keyboard input
* arrow keys
* model selection
* prompts
* terminal output
* interruption
* long-running sessions

---

# 27. Agent Adapter Architecture

Each CLI should have an independent adapter.

```text
AgentAdapter
├── ClaudeAdapter
├── CodexAdapter
├── CursorAdapter
└── OpenCodeAdapter
```

Adapters encapsulate CLI-specific behavior:

```text
launch()
sendPrompt()
sendKeys()
selectModel()
stop()
resume()
readOutput()
detectState()
```

The workflow engine should not contain agent-specific terminal logic.

---

# 28. Normalized Agent State

Adapters should normalize CLI-specific states into a common model.

Example:

```text
AgentReady
AgentWorking
AgentWaiting
AgentRateLimited
AgentError
AgentExited
AgentOutput
```

This allows the workflow layer to remain independent of individual CLI implementations.

---

# 29. PTY Prototype

Before building the full application, a technical spike should prove that Daddy can reliably:

1. spawn an agent CLI
2. create/control a PTY
3. capture terminal output
4. detect readiness
5. send `/model`
6. send arrow-key navigation
7. select a requested model
8. send a prompt
9. capture long-running output
10. detect completion/waiting
11. interrupt the process
12. resume/control it
13. detect rate-limit/error states

This should first be proven with one agent, then generalized into the adapter architecture.

This is the highest-risk technical component of v1.

---

# 30. Existing `daddyshome`

The existing `daddyshome` script should be preserved during development.

Eventually, Daddy may replace or extend it.

Potential future behavior:

```text
daddyshome
    ↓
Daddy Controller
    ↓
agent sessions
```

The existing behavior of starting four CLIs in separate terminal tabs should remain available until the new controller is proven reliable.

---

# 31. Filesystem Watcher

Daddy should monitor its workflow directory for changes.

This allows:

* external edits to Markdown
* manually created notes
* completion state changes
* future integrations

The filesystem should remain usable independently of the application.

---

# 32. Local-First Architecture

v1 should not require:

* cloud backend
* remote database
* account system
* external API server

Everything can run locally on the Mac.

The primary state representation is local Markdown.

A lightweight local index/database may be added later for performance, search, and richer querying, but it must not replace the human-readable Markdown state.

---

# 33. UI

UI is explicitly low priority.

A minimal menu-bar application is sufficient initially.

Possible information:

```text
Daddy

7 active sessions
3 projects
1 rate-limited agent

Current:
Acme / authentication / Claude

Open dashboard
Open workflow folder
Settings
Quit
```

A richer dashboard may eventually visualize:

* projects
* active agents
* work units
* status
* rate limits
* recent activity

But voice interaction remains the primary interface.

---

# 34. Non-Goals for v1

Daddy should NOT initially attempt to:

* autonomously decide which agent to use
* autonomously decide what work should be done
* replace coding agents
* become a general AI coding assistant
* create a complex project-management UI
* provide cloud synchronization
* provide team collaboration
* implement reminders
* automatically determine completion
* maintain generalized personal memory
* orchestrate agents according to fixed pipelines

---

# 35. MVP

The minimum viable product should support:

### Voice

* receive HEX transcript
* parse basic commands
* English + Spanish support
* personal dictionary

### Projects

* discover repositories under `Documents`
* identify project context

### Agents

* Claude
* Codex
* Cursor
* OpenCode

### Sessions

* launch/control agent processes
* maintain concurrent sessions
* identify active sessions
* maintain focus

### Models

* parse model from transcript
* ask for model when missing
* select model through agent CLI interaction

### Remote control

* start
* continue
* stop
* interrupt
* send prompt
* inspect status
* run commands/tests
* switch agent

### Workflow state

* work units
* session state
* agent state
* current focus
* rate-limit state

### Markdown

* semantic work grouping
* timestamped context files
* project/feature organization
* handoff context
* `DONE.md`

---

# 36. Example End-to-End Experience

User starts in:

```text
~/Documents/acme-app
```

and says:

> “Claude, Opus, fix the authentication bug.”

Daddy:

```text
Project: acme-app
Work unit: authentication
Agent: Claude
Model: Opus
Action: work
```

Claude works.

Later the user says:

> “Claude, what's left?”

Daddy reads current session/workflow state and responds.

Later:

> “Claude is rate limited. Give it to Codex.”

Daddy:

1. preserves the same work unit
2. captures meaningful state
3. updates the Markdown context
4. switches to Codex
5. supplies the handoff context
6. continues the work

Later:

> “Codex, run the tests.”

Codex runs them.

Later:

> “We're done.”

Daddy generates:

```text
Desktop/
└── DaddyWork/
    └── AcmeApp/
        └── authentication/
            ├── 2026-08-10_1420.md
            ├── 2026-08-10_1730.md
            └── DONE.md
```

The user can open the directory and immediately see that authentication is complete.

---

# 37. Success Criteria

Daddy is successful when the user can spend an entire coding session without manually:

* switching terminal tabs
* typing prompts into agent CLIs
* selecting models through CLI menus
* manually creating handoff summaries
* finding the correct Markdown context
* manually attaching handoff context
* tracking which agent is working on which project
* remembering which work is complete

The ideal outcome is:

> **The user thinks about the work. Daddy handles the coordination.**

---

# 38. Development Plan

## Phase 0 — PTY Proof of Concept

Build a tiny Swift prototype for one CLI.

Prove:

```text
spawn
→ observe
→ interact
→ select model
→ prompt
→ monitor
→ interrupt
→ resume
```

---

## Phase 1 — Agent Runtime

Implement the common `AgentAdapter` protocol.

Add:

* Claude
* Codex
* Cursor
* OpenCode

Normalize their states.

---

## Phase 2 — Workflow State

Implement:

* projects
* work units
* sessions
* agents
* models
* focus
* state transitions

---

## Phase 3 — Markdown State

Implement:

* semantic grouping
* Markdown snapshots
* timestamping
* project/feature directories
* handoff generation
* `DONE.md`

---

## Phase 4 — Voice Command Layer

Integrate HEX transcript input.

Implement:

* agent identification
* action identification
* project/session resolution
* model identification
* personal dictionary
* ambiguity questions
* English/Argentine Spanish handling

---

## Phase 5 — Background Runtime

Convert the prototype into a persistent macOS menu-bar/background application.

Ensure sessions remain active independently of the minimal UI.

---

## Phase 6 — Refinement

Tune:

* semantic work grouping
* context generation
* state detection
* voice command vocabulary
* session resolution
* rate-limit handling
* Markdown quality

Only after real-world usage should additional automation and reminders be introduced.

---

# 39. Future Features

Potential future capabilities:

* unfinished-work reminders
* automatic daily/weekly summaries
* intelligent project discovery
* richer workflow search
* “what was I doing here?” queries
* historical work summaries
* automatic completion suggestions
* agent availability/rate-limit prediction
* configurable aliases
* learned personal vocabulary
* richer dashboard
* keyboard shortcuts
* notifications
* task history
* Git integration
* branch awareness
* automatic context extraction from diffs
* intelligent Markdown compression/archiving

These are explicitly secondary to the core remote-control + workflow-state system.

---

# 40. Final Product Definition

Daddy is a **local, voice-first macOS control plane for a developer's multi-project, multi-agent coding environment**.

It sits above existing coding-agent CLIs and below the user's intent.

```text
                    USER
                     |
                    VOICE
                     |
                    HEX
                     |
               COMMAND LAYER
                     |
              WORKFLOW STATE
               /           \
        PROJECTS          WORK UNITS
             \              /
              \            /
                SESSIONS
                   |
              AGENT ADAPTERS
             /   /    \    \
        Claude Codex Cursor OpenCode
             \   |     |   /
                    PTYs
                     |
                AGENT CLIs
```

The filesystem provides the durable, human-readable representation of work:

```text
Desktop/DaddyWork/
    Project/
        Feature/
            timestamp.md
            timestamp.md
            DONE.md
```

The user's job is to decide **what to do**.

The agents' job is to **do the work**.

Daddy's job is to make everything between those two points nearly frictionless.

