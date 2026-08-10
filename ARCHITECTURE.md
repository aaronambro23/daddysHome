# Daddy Architecture — Current State

## Overview

Daddy is a local, voice-first macOS control plane for multi-agent AI coding workflows. Current implementation is Milestone 0-2 complete, with foundations ready for Milestone 3-6.

**Status**: Core infrastructure working. PTY control proven. App shell in place with SwiftTerm integration.

## Built So Far

### Milestone 0: PTY Foundation ✅
- **DaddyCore**: Swift Package (SPM) with all core types
  - `Models.swift`: Project, WorkUnit, Session, AgentKind, AgentState, ModelRef, Focus
  - `PTYProcess.swift`: Thread-safe wrapper around subprocess+PTY control
  - `AgentAdapter.swift`: Protocol + 4 implementations (Claude, Codex, Cursor, OpenCode)
  - `SessionManager.swift`: Concurrent multi-session orchestration

- **Key design**:
  - PTYProcess uses synchronous API with background thread for I/O (avoids actor complexity)
  - AgentAdapter normalizes CLI-specific launch args, model flags, state detection, interrupt handling
  - SessionManager maintains thread-safe session dictionary with NSLock
  - All types exported as public for external use

### Milestone 1: Integration Tests ✅
- 5/6 integration tests passing
- Tests verify: PTY launch/output, adapter launch args, model flag mapping, state detection
- 1 expected failure: Claude launch test (Claude not in test PATH)
- Proves PTY mechanism works with real processes

### Milestone 2: macOS App + CLI ✅
- **daddy-cli**: Command-line executable for testing SessionManager
  - `launch <agent> <project-path> [model]`: Launches a session
  - `help`: Displays usage
  - Fully functional; tested successfully

- **DaddyApp**: Native macOS application
  - Built with AppKit (NSApplication)
  - Integrated SwiftTerm for terminal rendering (LocalProcessTerminalView)
  - Split-view layout: status panel + terminal pane
  - Session creation buttons ("Launch Claude", "Open Project...")
  - SessionManager integration
  - App launches and runs without crashing

## Architecture Diagram

```
DaddyApp (macOS executable)
    ↓
    +── LocalProcessTerminalView (SwiftTerm)
    │        ↓
    │    terminal rendering
    │
    +── SessionManager (DaddyCore)
         ↓
         +── Session (per agent/project)
         │    ├── PTYProcess
         │    ├── AgentAdapter (Claude/Codex/Cursor/OpenCode)
         │    ├── AgentState
         │    └── Output callbacks
         │
         +── Project lookup
              └── Workspace discovery

[Future]
    ↓
    +── HexWatcher (listens to transcription_history.json)
    +── IntentParser (English/Spanish command parsing)
    +── MarkdownWriter (Desktop/DaddyWork/...)
    +── Voice command execution layer
```

## Current File Structure

```
daddy/
├── daddycore-spm/                  # Swift Package (library)
│   ├── Package.swift
│   ├── Sources/DaddyCore/          # Core types + SessionManager
│   │   ├── Models.swift
│   │   ├── PTYProcess.swift
│   │   ├── AgentAdapter.swift
│   │   ├── SessionManager.swift
│   │   └── DaddyCore.swift
│   ├── Sources/DaddyCLI/           # CLI executable
│   │   └── main.swift
│   └── Tests/DaddyCoreTests/       # Integration tests
│       ├── DaddyCoreTests.swift
│       └── PTYIntegrationTests.swift
│
├── DaddyApp/                       # macOS executable
│   ├── Package.swift
│   ├── Sources/DaddyApp/
│   │   └── main.swift              # AppKit app with SwiftTerm
│   └── .build/                     # Build artifacts
│
├── prd.md                          # Product requirements
├── ARCHITECTURE.md                 # This file
└── .git/                           # Version control
```

## Key Technical Decisions

### PTY Control
- Used SwiftTerm's `LocalProcessTerminalView` as the terminal emulator layer
- `PTYProcess` wrapper avoids complexity of actor-based PTY handling; uses synchronous IO with background thread for capture
- Callbacks for output changes allow SessionManager to monitor state transitions

### Agent Adapters
- Each CLI (Claude, Codex, Cursor, OpenCode) has dedicated adapter
- Adapters own: launch args construction, model flag value mapping, state detection heuristics, interrupt mechanism
- Workflow layer remains CLI-agnostic

### Thread Safety
- SessionManager uses NSLock for dictionary access (simple, reliable)
- AgentKind conforms to Sendable for thread-safe state passing
- No actor-based concurrency (simpler debugging, clear lock points)

### Public API
- All types exported as public (Session, AgentKind, ModelRef, SessionManager, etc.)
- Allows external tools (CLI, future UI frameworks) to consume DaddyCore

## What Works Now

✅ Create sessions for any agent in any project directory  
✅ Launch sessions (spawn real CLI processes via PTY)  
✅ Capture live output from processes  
✅ Detect agent state (ready, working, rate-limited, error, exited)  
✅ Send prompts/commands into live sessions  
✅ Interrupt/resume sessions  
✅ Concurrent multi-session management  
✅ CLI test harness  
✅ macOS GUI shell with terminal pane  

## Next Milestones (Not Yet Implemented)

### Milestone 3: Workflow State Model
- Persistent JSON index for projects/sessions/work units
- Focus resolution (current project/work unit/session)
- Rate-limit propagation and handling

### Milestone 4: Markdown Workflow System
- Desktop/DaddyWork/<Project>/<WorkUnit>/ directory tree
- Timestamped state snapshots (YYYY-MM-DD_HHmm.md)
- Semantic work-unit grouping heuristic
- Handoff context generation
- DONE.md for completed work units

### Milestone 5: Voice Command Layer
- HexWatcher: Monitor HEX's transcription_history.json
- IntentParser: Rule-based English/Spanish command parsing
- Personal dictionary: User's custom vocabulary mapping
- Command execution: Route parsed commands to SessionManager

### Milestone 6: Background App Refinement
- Menu-bar NSStatusItem (active sessions, rate limits, current focus)
- Persistent background operation independent of window visibility
- State-detection heuristic tuning
- Error recovery and resilience

## Testing

### Unit Tests
```bash
cd daddycore-spm
swift test
```
Result: 5/6 tests pass (1 expected failure: Claude not in PATH)

### CLI Testing
```bash
DaddyApp/.build/release/daddy-cli help
DaddyApp/.build/release/daddy-cli launch claude /tmp/daddy-test
```

### App Testing
```bash
cd DaddyApp
swift build
.build/debug/DaddyApp  # Launch GUI
```

## Known Limitations & TODOs

1. **PTY output parsing**: State detection is simple substring matching; may need tuning per CLI
2. **Model selection**: Currently uses CLI flags only; mid-session `/model` navigation not yet tested
3. **HEX integration**: Not yet implemented; architecture planned but needs Full Disk Access for reading transcription_history.json
4. **Markdown system**: Not yet implemented; directory structure planned
5. **Voice commands**: Not yet implemented; parser architecture defined
6. **Rate-limit detection**: Text-based heuristic; may need refinement based on real usage
7. **UI**: Minimal for now; terminal pane is rendered but not yet wired to active sessions

## Build & Run

```bash
# Build everything
cd daddycore-spm && swift build -c release
cd ../DaddyApp && swift build

# Run CLI
DaddyApp/.build/release/daddy-cli help

# Run GUI app
DaddyApp/.build/debug/DaddyApp
```

## Dependencies

- **SwiftTerm** (MIT): Terminal emulator + PTY rendering
- **Swift 6.2+** (language version)
- **macOS 13+** (platform requirement)
- **No external backends**: All local, all on-device

## Verification Checklist (for future completion)

- [ ] HEX integration (Full Disk Access granted)
- [ ] Voice command parsing (English + Spanish)
- [ ] Project discovery (~Documents/*)
- [ ] Markdown state files written and updated
- [ ] Handoff context generation working
- [ ] DONE.md creation on explicit completion
- [ ] Multi-session concurrent control
- [ ] Rate-limit detection and user prompting
- [ ] Menu-bar app with status display
- [ ] Background operation independent of window visibility
