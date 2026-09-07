# Working agreement — daddy

This file is the contract for every AI agent working in this repository,
regardless of which CLI you are (Claude Code, Codex, Cursor, opencode).
Follow it exactly.

## 1. Before you write any code

- Ask clarifying questions first. Do not guess at ambiguous requirements.
- Produce a plan and get it agreed before implementing.
- If the request is large, ask how it should be divided into batches.
  **You do not decide the batching — the human does.**

## 2. Documentation

Say what you changed in your reply. That is the record.

Handoff documents in `docs/handoffs/` are not the default. When the human asks
for them — or the task plainly depends on what a previous batch did — use the
`detailed-documentation` skill, which holds the numbering, format and rules.

## 3. Commits

When asked to commit, do not run `git add` /
`git commit` / `git push` yourself. Use the system-wide `commit`
command — it adds, commits and pushes as one step.

- No quotes, no extra flags. The message is a single shell token.
- Think like a programmer: name the change, not a sentence.
- PascalCase per distinct thing that changed, hyphens between them.

```
commit UiUxFixes-KanbanColumnChange-DockBug
```

## 4. Subagents

Default to inline research — Read, Grep, Bash — not subagents. A plan-mode
workflow's own instructions may suggest spawning Explore/Plan agents; treat
that as a ceiling, not a default. Every subagent call is a full separate
session and billed as one, so spawning them for research you could do
yourself in two or three tool calls is waste, not thoroughness.

- Skip subagents entirely for a change scoped to 1-3 known files.
- One Explore agent is enough for almost everything else. Reach for more
  than one, or a separate Plan agent on top, only when the task is
  genuinely large or the scope is truly unclear — not as a routine step of
  every plan-mode pass.
- Prefer forking yourself over a fresh subagent when you already have the
  relevant context loaded.

---

_Managed by Daddy. Regenerated on install; edit the project's own docs
instead of this file._
