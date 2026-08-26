# Orchestrator Context

This file carries the Orchestrator context into future sessions. It is a
project note, not a handoff document.

## What Is Implemented

- Native Swift `URLSession` Ollama client for `/api/chat`, with streaming,
  `gemma4:e4b` as the default model, `think: false`, and a warm model lifetime.
- First-class Orchestrator workspace beside Fleet, with direct Enter-to-send,
  Ctrl+O workspace toggle, Escape cancellation, trash clearing, and a typing
  indicator.
- Separate in-memory conversations for `ALL`, `BUGS`, `UI/UX`, `FUTURE FEATURES`,
  `CONCEPTS`, and `OTHER`. Switching categories preserves each category's chat.
- Cancellation preserves the partial assistant output and marks it `STOPPED`.
- Local attachment picker and drag/drop support for text, Markdown, PDFs, and
  images. Image data is sent through Ollama vision input; attachments stay local.
- Typed Ollama tools for projects, agents, work items, and dispatch preparation.
  Dispatch still requires explicit UI approval.
- Markdown work items in `Desktop/DaddyWork/Orchestrator`, with front matter for
  category, status, project, priority, source context, attachments, and sessions.
- Work-item inspection/editing and dispatch selection for Claude, Codex, Cursor,
  and OpenCode through the existing SessionManager path.
- Concise internal-assistant system prompt with no onboarding, greetings,
  capability explanations, repeated context, or motivational filler.
- Provider dropdown follow-up behavior from `main` was selectively applied to
  `GlassDropdown.swift` and `ProviderLaunchMenu.swift` without merging unrelated
  changes or touching the Orchestrator work.

## Still To Do

- Decide whether category conversations should persist across app restarts. The
  old global `conversation.md` restoration was removed because it caused stale
  chats to reappear; current category chats are intentionally in-memory only.
- Add a clearer Ollama/model availability state in the UI beyond request errors.
- Revisit streaming cadence after testing on the target local model. The current
  client paces displayed characters at 12ms to reduce visual clumping.
- Verify the full app build and run behavior when explicitly authorized. No broad
  tests, debug runs, release runs, or generated testing scripts are part of this
  pass.
- Continue tightening tool argument validation and edge cases around dispatch,
  attachments, and switching categories during active work.

## Original V1 Sketch

1. Ollama integration
   - Add a native Swift URLSession client for Ollama's `/api/chat`.
   - Support streamed responses.
   - Use `gemma4:e4b` as the configured default.
   - Handle unavailable Ollama/model states visibly in the UI.
2. Orchestrator conversation
   - Add a first-class Orchestrator workspace beside Fleet.
   - Provide chat for brainstorming and commands.
   - Store conversation history as Markdown.
   - Keep it independent from the coding-agent PTY system.
3. Attachments
   - Support drag/drop and a file picker.
   - Extract text and Markdown.
   - Extract PDF text through PDFKit.
   - Send images through Ollama vision input.
   - Keep attachments local.
4. Tool calling
   - Inspect projects and active agents.
   - Read, create, and edit work items.
   - Prepare agent dispatch.
   - Validate tool arguments.
   - Do not expose an arbitrary shell tool.
   - Require explicit UI confirmation before launching or messaging an agent.
5. Markdown work items
   - Store items in Daddy's existing DaddyWork area.
   - Keep category separate from workflow status.
   - Store category, status, project, priority, source context, attachments,
     and linked sessions in Markdown front matter.
6. Dispatch
   - Select a work item.
   - Choose Claude, Codex, Cursor, or OpenCode.
   - Choose an existing live session or launch a new one.
   - Generate the agent prompt from the work item and attached context.
   - Let SessionManager perform the actual launch/send operation.

## Constraints

- Do not create or update handoff documentation.
- Do not build, debug-run, release-run, or broadly test unless explicitly
  authorized.
- Do not replace the user's Orchestrator changes with branch or main history.
