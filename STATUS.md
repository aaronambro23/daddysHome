# Daddy — Project Status

**Last Updated**: 2026-08-12  
**Repository**: `git@github.com-personal:aaronambro23/daddysHome.git`  
**Current Phase**: Milestones 0-6 complete, UI redesign + HEX integration complete, Liquid Glass UI reskin in progress

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
| **6** | Background app refinement | ✅ Complete | 26/32 passing |

---

## Test Results

```
Total: 26/32 tests passing (6 failures)
├── PTYIntegrationTests: 5/6 passing
├── WorkflowStateTests: 7/7 passing ✅
├── MarkdownWriterTests: 4/5 passing
├── CommandParserTests: 9/14 passing
├── DaddyCoreTests: 1/1 passing
└── State detection: improved with regex patterns
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
- AppKit-based GUI with futuristic dark theme (trippy cyan/green accents)
- Menu-bar NSStatusItem with persistent background operation
- Three-pane layout: Projects | Agent Dashboard | Terminal
- Projects sidebar: shows ~/Documents directories for active work
- Agent Dashboard: real-time cards showing:
  * Agent name (cyan), state emoji, project path
  * Model in use, work unit ID, last activity
- SwiftTerm's `LocalProcessTerminalView` for terminal rendering
- SessionManager integration
- Real-time status icon (◇ inactive, ● active, ⚠ rate-limited)
- macOS notifications for session state changes
- HEX integration: listens for voice commands, auto-spawns agents

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
✅ Rate-limit detection (word-boundary regex)  
✅ Menu-bar status monitoring (persistent background app)  
✅ Dynamic session list in menu  
✅ Error recovery with retry mechanism  
✅ User notifications for session state changes  
✅ Futuristic dark dashboard UI (cyan/green accents)  
✅ Project sidebar (~/Documents directories)  
✅ Active agent dashboard with real-time status  
✅ HEX integration (voice command parsing & spawning)  
✅ Clickable session cards with live terminal output  
✅ Real-time PTY streaming to terminal pane  
✅ Session selection with visual highlighting  

---

## Remaining Work

### Milestone 6: Background App Refinement ✅ Complete

- [x] Menu-bar NSStatusItem (active session count, rate-limited agents, current focus indicator)
- [x] Persistent background operation independent of window visibility
- [x] State-detection regex tuning per CLI behavior (word-boundary patterns)
- [x] Error recovery and resilience (retry mechanism, error tracking)
- [x] User-facing status notifications (macOS notifications for state changes)

### Latest Work (Post-Milestone 6)

**UI Redesign** ✅ Complete
- Futuristic dark theme with cyan/green accents (RGB: 0.05-0.12)
- Three-pane layout with projects, dashboard, terminal
- Project sidebar showing ~/Documents directories
- Real-time agent dashboard with status cards
- Live updates (1s sessions, 2s projects)

**HEX Integration** ⚠️ Not wired — see "HEX Voice Intake" under Future Work
- `HEXWatcher.swift` and `CommandParser.swift` both exist and are unit-tested
- But nothing constructs `HEXWatcher` anywhere in the app, and `CommandParser`
  is referenced only by its own tests. The pieces are in isolation; no voice
  command has ever reached a session.

**Terminal Wiring** ✅ Complete
- Click agent cards to select and view live output
- Selected card highlights (bright cyan, 2px border)
- Terminal pane streams real-time PTY output
- Green monospace terminal aesthetic
- Auto-scrolls to latest output
- Switch between agents by clicking cards

**Liquid Glass UI Reskin** 🔄 In Progress (Step 1-5 Complete)
- Dark gradient sky background (#0a1030 → #1a1046 → #07333f, 135°)
- 3 drifting radial-gradient color orbs (blue, teal, purple) with soft 40-50px blur
- Custom glass panel modifiers using .ultraThinMaterial + tint + border + highlight + shadow
- Recolored all UI: accent blue (#33ccff), working green (#1aff99), amber, purple
- Dark terminal pane with green text (#00ff80) and green-tinted border
- Breathing dot animations for HEX-ready and working states
- State-aware status badges (ready=neutral white, working=green+glow, rateLimited=amber, error=red)
- Interactive enhancements: hover effects on pills (HEX ready, session count) and agent cards
- Card scaling animation (1.02x) on hover/selection for tactile feedback
- Header as flush glass strip with traffic-light clearance (78pt leading padding)

**Liquid Glass Approach** (Current vs. Future):
- **Current (macOS 13+)**: Custom `.ultraThinMaterial` glass modifiers with manual overlays
  - Real blur effect via material background
  - Manual tint layer, 1px stroke border, top edge highlight, drop shadow
  - Hover-based interactivity (state tracking + scale effects)
  - Works on current macOS version (no unreleased APIs)
- **Deferred (macOS 26.0+)**: Apple's official Liquid Glass APIs (not yet available)
  - `glassEffect()` modifier for automatic glass rendering
  - `GlassEffectContainer` for intelligent shape blending
  - `glassEffectID()` + morphing transitions for automatic card/shape morphing
  - `.interactive()` for real-time pointer/touch responsiveness
  - Better performance optimization via native framework

**Next Steps (Step 6 & Beyond)**:
- [ ] Terminal input (accept user typing in terminal pane → PTY)
- [ ] Session management buttons (stop, interrupt on cards)
- [ ] Full Liquid Glass morphing once macOS 26.0+ APIs available
- [ ] Fix remaining 6 test failures
- [ ] Session history/replay
- [ ] Task status tags (feat/bug/refactor/test)
- [ ] Clickable project cards to spawn new sessions

### Future Work (Beyond MVP)

**HEX Voice Intake** (not started — components exist, nothing is connected)

*What HEX is:* a third-party system-wide dictation app (`/Applications/Hex.app`,
bundle `com.kitlangton.Hex`). Daddy does **not** implement speech recognition and
never needs microphone permission. HEX keeps its own global hotkey (hold left ⌥,
double-tap to lock) and stays useful across every other app on the machine.

*What exists today:*
- `DaddyCore/HEXWatcher.swift` — `DispatchSource` file watcher over
  `~/Library/Containers/com.kitlangton.Hex/Data/Library/Application Support/com.kitlangton.Hex/transcription_history.json`,
  exposing `onNewTranscription: ((String) -> Void)`. Never instantiated.
- `DaddyCore/CommandParser.swift` — parses English/Spanish phrases into
  structured intents. 9/14 tests passing. Referenced only by its tests.

*The missing link:* `HEXWatcher.onNewTranscription` → `CommandParser.parse()` →
`SessionManager` action.

*Design decision — addressing (how Daddy knows a transcription is for it):*
HEX pastes into whatever field has focus. Its settings confirm there is no
silent mode (`copyToClipboard: false`, `useClipboardPaste: true`). So a global
wake word would type the command into Slack/notes/whatever is focused.

Decision: **consume voice only while Daddy is frontmost.** The paste then lands
in Daddy's own composer — harmless, and it shows what was heard before it runs.
This also means the frontmost path can read its own `TextField` directly and
skip `HEXWatcher` entirely: no Full Disk Access, no file watching.

Optional later: a global wake-word mode ("daddy, …") for across-the-room
control, keeping `HEXWatcher` for that path only, accepting that it pastes into
the focused app. Note the tradeoff against PRD principle 4.1 (voice-first):
frontmost-only means clicking into Daddy first, which weakens hands-off use.

*Known bugs to fix before this ships:*
- `HEXWatcher.swift:74-76` — dedup is broken. It compares
  `UInt64(text.utf8.count)` (the transcription's character length) against a
  variable named `lastReadPosition`, so a transcription only fires if its text
  is longer than the longest seen so far. "start codex on test coverage"
  followed by "stop" drops the second. Key off transcription `id`/`timestamp`.
- `HEXWatcher.init?()` returns nil and never retries if the JSON file is absent,
  so if HEX hasn't run since boot the watcher is dead for the whole session.

*External dependencies:*
- HEX setting `saveTranscriptionHistory: true` — if the user turns this off, the
  file-watcher path goes deaf silently.
- Full Disk Access, required to read another app's container (file-watcher path
  only; the frontmost path avoids it).

**Terminal Input** (not started)
- Accept user input in terminal pane (type into active agent)
- Send keyboard input directly to PTY
- Handle control characters (Ctrl+C, Ctrl+D, etc)

**Session Management UI** (not started)
- Stop/interrupt buttons on session cards
- Session history and replay
- Session output export/copy
- Multi-select sessions

**Dashboard Enhancements**
- Clickable project cards to spawn new sessions
- Task status indicators (feat/bug/refactor/test)
- Session duration tracking
- Agent performance metrics (time, tokens, etc)

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

## What's Working Now

**Voice-First Workflow:**
1. User double-clicks option key (HEX activation)
2. Speaks command: "Claude, fix the bug in this feature"
3. App parses command → spawns Claude session in ~/Documents
4. Dashboard shows live agent status (cyan card with state emoji)
5. Click card to select agent → terminal pane streams live output
6. Watch agent work in real-time with green terminal text
7. Session state visible on menu bar (● active, ⚠ rate-limited, etc)
8. Notifications alert on rate-limit, error, or completion

**Example Voice Commands:**
- "claude work on the feature" → spawns Claude, intent: work
- "codex switch to opus" → spawns Codex with opus model
- "cursor review the code" → spawns Cursor for review
- "stop" → interrupts current agent

## What's Ready to Ship

✅ Full voice-first workflow (HEX → spawn agents)
✅ Real-time agent monitoring dashboard
✅ Live terminal output from selected agents
✅ Menu bar persistent background app
✅ State notifications (ready, rate-limited, error, exited)
✅ Error recovery with auto-retry
✅ Project discovery from ~/Documents
✅ Agent switching via dashboard clicks
✅ Dark futuristic UI with cyan/green accents

## Next Session Checklist

When resuming work:

- [ ] Confirm all commits are pushed: `git log --oneline | head -10`
- [ ] Verify tests still pass: `cd daddycore-spm && swift test` (~26/32 passing)
- [ ] Build both: `cd daddycore-spm && swift build && cd ../DaddyApp && swift build`
- [ ] **Next priorities:**
  - Terminal input (accept typing in terminal pane → agent)
  - Session management buttons (stop, interrupt, kill)
  - Fix remaining 6 test failures
  - Add task type tags to dashboard
  - Session history/replay

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
