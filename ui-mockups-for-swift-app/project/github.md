repo: aaronambro23/daddysHome
branch: main

## Last sync

date: 2026-08-11T00:17:00Z

### Updated in this project
- Read STATUS.md, ARCHITECTURE.md and the AppKit app source to ground the mockups.
- Built "Daddy Glass" — liquid-glass reskin of the three-pane macOS window (3 layout options).
- Added work-unit history, settings, and notification/HEX-listening panels.

## Screen map

| Project screen | Repo files |
| --- | --- |
| 1a / 1b / 1c three-pane window | DaddyApp/Sources/DaddyApp/main.swift (AppDelegate, ProjectsViewController, DashboardViewController, TerminalViewController) |
| Session cards / agent state | daddycore-spm/Sources/DaddyCore/Models.swift, AgentAdapter.swift |
| Voice log / HEX listening (1f) | daddycore-spm/Sources/DaddyCore/CommandParser.swift, HEXWatcher.swift |
| Work units (1d) | daddycore-spm/Sources/DaddyCore/MarkdownWriter.swift, WorkflowState.swift, STATUS.md |
| Settings (1e) | daddycore-spm/Sources/DaddyCore/AgentAdapter.swift (ApprovalPolicy, executablePath, model aliases) |
