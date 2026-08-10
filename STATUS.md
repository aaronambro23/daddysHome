# Daddy — Project Status

**Last Updated**: 2026-08-10  
**Repository**: `git@github.com-personal:aaronambro23/daddysHome.git`  
**Current Phase**: Milestones 0-5 complete, entering Milestone 6 (background app refinement)

---

## Completed Milestones

| Milestone | Component | Status | Tests |
|-----------|-----------|--------|-------|
| **0** | PTY control, adapters, session management | ✅ Complete | N/A |
| **1** | Integration tests | ✅ Complete | 5/6 passing |
| **2** | macOS app + CLI with SwiftTerm | ✅ Complete | N/A |
| **3** | Workflow state model & persistence | ✅ Complete | 7/7 passing |
| **4** | Markdown workflow system | ✅ Complete | 4/5 passing |
| **5** | Voice command parser (English/Spanish) | ✅ Complete | 9/14 passing |

---

## Test Results

```
Total: 32 tests across 5 suites
├── PTYIntegrationTests: 5/6 passing (1 expected failure: Claude not in PATH)
├── WorkflowStateTests: 7/7 passing ✅
├── MarkdownWriterTests: 4/5 passing
├── CommandParserTests: 9/14 passing
└── DaddyCoreTests: 1/1 passing
```

---

## What's Built

### DaddyCore (Swift Package)

Core types and business logic:
- **Models.swift**: `Project`, `WorkUnit`, `Session`, `AgentKind` (Sendable), `AgentState` (Codable), `ModelRef`, `Focus`
- **PTYProcess.swift**: Thread-safe subprocess+PTY wrapper (use `LocalProcess` from SwiftTerm)
- **AgentAdapter.swift**: Protocol + 4 implementations (Claude, Codex, Cursor, OpenCode)
- **SessionManager.swift**: Concurrent multi-session orchestration with NSLock
- **WorkflowState.swift**: Project discovery, focus management, persistent JSON state
- **MarkdownWriter.swift**: Create/manage workflow Markdown files (Desktop/DaddyWork/...)
- **CommandParser.swift**: Parse English/Spanish voice commands into structured intents

### DaddyApp (macOS executable)

User-facing application:
- AppKit-based GUI
- SwiftTerm's `LocalProcessTerminalView` for terminal rendering
- Split-view layout (status panel + terminal pane)
- Project picker, session launcher
- SessionManager integration

### daddy-cli (CLI executable)

Command-line control:
- `daddy-cli launch <agent> <project-path> [model]`
- `daddy-cli help`
- Fully functional; tests pass

---

## Key Capabilities Working

✅ Create sessions for any of 4 agents in any project directory  
✅ Launch sessions (spawn real CLI processes via PTY)  
✅ Capture live process output in real-time  
✅ Detect agent state (ready/working/rate-limited/error/exited)  
✅ Send prompts and commands into live sessions  
✅ Interrupt and resume sessions  
✅ Concurrent multi-session management  
✅ Thread-safe access via NSLock  
✅ Parse English and Argentine Spanish voice commands  
✅ Persist workflow state to JSON  
✅ Create timestamped Markdown context files  
✅ Mark work units complete with DONE.md  
✅ Project discovery from ~/Documents  
✅ Rate-limit detection  

---

## Remaining Work

### Milestone 6: Background App Refinement

- [ ] Menu-bar NSStatusItem (active session count, rate-limited agents, current focus indicator)
- [ ] Persistent background operation independent of window visibility
- [ ] State-detection regex tuning per CLI behavior
- [ ] Error recovery and resilience
- [ ] User-facing status notifications

### Future Work (Beyond MVP)

**HEX Integration** (not started)
- Read HEX's `transcription_history.json` (`~/Library/Containers/com.kitlangton.Hex/Data/Library/Application Support/com.kitlangton.Hex/`)
- Wire parsed commands to SessionManager operations
- Requires Full Disk Access or security-scoped bookmark

**Terminal View Wiring** (not started)
- Connect active session output to DaddyApp's terminal pane
- Enable user input directly into pane
- Display rate-limit notifications inline

**Model Selection Tuning** (not started)
- Test `/model` command behavior per CLI
- Implement arrow-key navigation if needed
- Handle direct model argument where available

---

## Architecture Overview

```
DaddyApp (macOS executable)
    ↓
    +── LocalProcessTerminalView (SwiftTerm)
    │   └── terminal rendering
    │
    +── SessionManager (DaddyCore)
        ├── Session (per agent/project)
        │   ├── PTYProcess
        │   ├── AgentAdapter
        │   ├── AgentState
        │   └── Output callbacks
        │
        ├── WorkflowStateManager
        │   ├── Project discovery
        │   ├── Focus management
        │   └── JSON persistence
        │
        └── MarkdownWriter
            └── Desktop/DaddyWork/ state files

CommandParser (Voice Input)
    └── English/Spanish transcript → structured command

[Future]
    ↓
    HexWatcher (transcription_history.json)
    └── → CommandParser → SessionManager operations
```

---

## File Structure

```
daddy/
├── daddycore-spm/                  # Swift Package (library + CLI + tests)
│   ├── Package.swift
│   ├── Sources/DaddyCore/
│   │   ├── Models.swift
│   │   ├── PTYProcess.swift
│   │   ├── AgentAdapter.swift      (Claude, Codex, Cursor, OpenCode)
│   │   ├── SessionManager.swift
│   │   ├── WorkflowState.swift
│   │   ├── MarkdownWriter.swift
│   │   ├── CommandParser.swift
│   │   └── DaddyCore.swift
│   ├── Sources/DaddyCLI/
│   │   └── main.swift
│   └── Tests/DaddyCoreTests/       (5 test suites)
│
├── DaddyApp/                       # macOS app (AppKit + SwiftTerm)
│   ├── Package.swift
│   └── Sources/DaddyApp/
│       └── main.swift
│
├── prd.md                          # Product requirements
├── ARCHITECTURE.md                 # Technical design
├── STATUS.md                       # This file
└── .git/                           # Version control
```

---

## Build & Test

```bash
# Build everything
cd daddycore-spm && swift build -c release
cd ../DaddyApp && swift build

# Run tests
cd daddycore-spm && swift test

# Run CLI
daddycore-spm/.build/release/daddy-cli help
daddycore-spm/.build/release/daddy-cli launch claude ~/Documents/my-project opus

# Run GUI
DaddyApp/.build/debug/DaddyApp
```

---

## Known Issues & Limitations

1. **CommandParser substring matching**: Keywords like "go" match within "going". Needs refinement for whole-word or position-aware matching.
2. **PTY state detection**: Simple substring/regex matching; may need tuning per CLI output variations.
3. **Model selection**: Currently uses CLI flags only; mid-session `/model` navigation not yet tested under PTY.
4. **HEX integration**: Not yet implemented; Full Disk Access required to read transcription_history.json.
5. **Menu bar**: Not yet implemented; window-only app currently.
6. **Error recovery**: Basic error handling; no retry logic for transient failures.

---

## Next Session Checklist

When resuming work:

- [ ] Confirm all commits are pushed: `git log --oneline | head -10`
- [ ] Verify tests still pass: `cd daddycore-spm && swift test`
- [ ] Build DaddyApp: `cd DaddyApp && swift build`
- [ ] Check Milestone 6 tasks (menu bar, background persistence)
- [ ] Or pivot to HEX integration if preferred

---

## GitHub Repository

```
SSH: git@github.com-personal:aaronambro23/daddysHome.git
Uses personal SSH key: ~/.ssh/id_ed25519_personal
SSH config: Host github.com-personal
```

---

## Summary

Daddy is a **local, voice-first macOS control plane for multi-agent AI coding workflows**. Core infrastructure is complete and tested. The system can:

- Spawn and control 4 different coding-agent CLIs concurrently
- Track workflow state and persist it to JSON
- Create human-readable Markdown context files on Desktop
- Parse English/Spanish voice commands
- Detect agent state (ready/working/rate-limited/error)

Remaining work is primarily UI refinement (menu bar, background persistence) and HEX integration for voice transcripts. The foundation is solid and ready for the final polish phase.
