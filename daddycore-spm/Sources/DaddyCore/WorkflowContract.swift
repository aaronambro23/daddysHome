import Foundation

/// The workflow contract Daddy installs into a project.
///
/// This is the mechanism that makes every CLI behave the same way. `AGENTS.md`
/// is the cross-CLI convention — Codex, Cursor and opencode all read it — and
/// Claude Code picks it up through a one-line `CLAUDE.md` containing
/// `@AGENTS.md`. A Claude *skill* cannot serve this purpose: skills live in
/// `.claude/skills/` and no other CLI can see them.
///
/// The contract is deliberately opinionated about one thing only: how work is
/// recorded, so that any agent can pick up where any other left off.
public enum WorkflowContract {

    /// Directory, relative to the target project, where batch documents live.
    public static let handoffDirectory = "docs/handoffs"

    /// Written to `CLAUDE.md`. Claude Code expands the import, so the contract
    /// lives in exactly one file.
    public static let claudeImport = "@AGENTS.md\n"

    /// The contract itself, written to `AGENTS.md`.
    public static func agentsMarkdown(projectName: String) -> String {
        """
        # Working agreement — \(projectName)

        This file is the contract for every AI agent working in this repository,
        regardless of which CLI you are (Claude Code, Codex, Cursor, opencode).
        Follow it exactly.

        ## 0. Modes

        Daddy starts each session in a **mode**, and the mode decides how much
        of this file applies. You will be told which one you are in — in your
        system prompt at launch, or by a message during the session. A later
        instruction wins over an earlier one.

        **QUICK mode** — sections 1 to 5 are suspended. Instead:

        - Do the thing that was asked. Ask a clarifying question only if the
          request is genuinely ambiguous, not as a matter of routine.
        - Do **not** read `\(handoffDirectory)/` unless the prompt asks you to
          or the task plainly depends on what a previous batch did. Reading
          three documents to fix an alignment bug costs more than the fix.
        - Do **not** create or update a batch document unless asked. If you are
          asked at the end, write one document covering what you did.
        - Say what you changed in your reply instead. That is the record.

        **DETAILED mode** — the default, and everything below applies as
        written.

        Neither mode changes what good work is. Quick means less ceremony, not
        less care: you still read the code you are changing, and you still say
        so plainly when something is broken or you did not finish.

        ## 1. Before you write any code

        - Ask clarifying questions first. Do not guess at ambiguous requirements.
        - Produce a plan and get it agreed before implementing.
        - If the request is large, ask how it should be divided into batches.
          **You do not decide the batching — the human does.**

        ## 2. Every batch of work gets one document

        A "batch" is a unit of work the human has named. It is not one task, and
        it is not one bug fix. A single large area of work may be split into
        several batches; that is the human's call, not yours.

        At the **start** of a batch, create:

        ```
        \(handoffDirectory)/NNN-short-slug.md
        ```

        - `NNN` is the next unused three-digit number, zero-padded (`001`, `002`,
          `014`). Numbers give the reading order — never reuse or renumber.
        - `short-slug` is two to four lowercase words joined by hyphens.
        - Look at the existing files in `\(handoffDirectory)/` to find the next
          number before creating yours.

        ## 3. Document format

        Create it with the plan filled in and every task unchecked:

        ```md
        # NNN — Human readable title

        - **Status:** in-progress
        - **Agent:** claude | codex | cursor | opencode
        - **Started:** YYYY-MM-DD

        ## Goal

        What this batch is meant to achieve, in a few sentences.

        ## Tasks

        - [ ] First task
        - [ ] Second task
        - [ ] Third task

        ## Summary

        _Filled in when the batch is complete._

        ## Changes

        _Files added, changed or deleted, and why. Filled in as you go._

        ## Next possible steps

        _Filled in when the batch is complete._
        ```

        ## 4. While you work

        - Tick a box (`- [x]`) the moment that task is genuinely done. Do not
          batch up the ticking at the end.
        - Add to `## Changes` as you go, especially **deletions** — anything
          removed must be recorded, or the next agent will not know it is gone.
        - If you discover a task the plan missed, add it to `## Tasks` unchecked.

        This matters because an unfinished document with unticked boxes is how
        the next agent knows exactly where you stopped. A half-finished file is
        useful. A missing file is not.

        ## 5. When the batch is complete

        - Set `**Status:** done`.
        - Write `## Summary` — what was actually built, in plain language.
        - Write `## Next possible steps` — what you would do next and why. This
          is your judgement, and it is the most valuable part of the document
          for whoever picks this up next. Be specific and opinionated.

        ## 6. Rules

        - **Do not** create a `DONE.md`, an index, or any file that aggregates
          across batches. Daddy owns the overview and derives it from these
          documents. Maintaining a shared index across several agents only
          produces stale and conflicting files.
        - **Do not** create a document per small task. One document per batch.
        - **Do not** renumber or delete existing documents. They are the history.
        - **Do** read the most recent documents in `\(handoffDirectory)/` before
          starting, so you know what came before and what was left undone.

        ---

        _Managed by Daddy. Regenerated on install; edit the project's own docs
        instead of this file._
        """
    }
}
