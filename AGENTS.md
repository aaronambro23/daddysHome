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

---

_Managed by Daddy. Regenerated on install; edit the project's own docs
instead of this file._
