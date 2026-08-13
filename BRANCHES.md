# Branches — what each one is for

**Last updated**: 2026-08-12

This file is identical on all three branches. It explains what each branch is
building, so that opening any of them tells you where you are.

---

## Why there are three

The PRD asks for two different things, and they pull in opposite directions.

**One:** Daddy should be able to reach into a running agent — stop it, interrupt
it, tell it to keep going, send it a follow-up, switch its model. Section 10 of
the PRD lists these plainly, with examples like *"Claude, stop."* and *"Codex,
review."*

**Two:** Daddy should not take your terminal away from you. The PRD is explicit:
the agents run in their own terminal tabs, and *"Daddy should eventually become
the orchestration layer around these processes rather than requiring the user to
abandon them."*

Those two are hard to have at once. If your terminal owns the agent, Daddy can't
reach in and stop it. If Daddy owns the agent so that it *can* stop it, then the
agent isn't in your terminal anymore.

Rather than guess, the work was split so both can be built and compared.

---

## `main` — the original PRD line

The trunk. This is the project as it was built against the original PRD, and it
is where the other two branches grew from.

What lives here that matters: the real machinery for driving an agent — the
plumbing that lets software send keystrokes, interrupts and prompts into a
running CLI as though a person were typing them, and shut it down cleanly along
with everything it spawned. That is the foundation for the "Claude, stop" half of
the PRD, and it works.

Also here: the Liquid Glass interface, and project discovery.

Left alone deliberately. It is the reference point.

---

## `simple` — the memory half

**The question it answers: "Where did we leave off, and what do I hand the next
agent?"**

Daddy does not run agents here. It launches them into your own Terminal window —
which is what the PRD asks for — and then owns the written record of the work.

How it goes:

1. Daddy installs one working agreement into a project, in a file every agent CLI
   already reads, so Claude, Codex, Cursor and opencode all behave the same way.
2. You decide how the work should be divided into batches.
3. At the *start* of each batch the agent writes a numbered document: the plan, as
   a checklist.
4. It ticks items off as it works, and records what it changed or deleted.
5. When it finishes, it writes a summary and — most valuable — its opinion on
   what should happen next.
6. Daddy reads all of these and tells you where a new agent should pick up. One
   click opens a Terminal with that agent already told which document to read and
   what is still unfinished.

Because the document is written at the beginning rather than the end, a
half-finished checklist *is* the record of where things stopped. Nothing has to be
reconstructed afterwards, and an interrupted session still leaves something
useful behind.

The point of all this: when you start a new session — a fresh chat, or a switch to
a different CLI — you should not have to explain the project again.

**What it gives up:** once an agent is running in your Terminal, Daddy cannot
reach it. It can start work and remember work, but it cannot stop or steer
anything mid-flight.

**Status:** the working branch. Actively developed and usable.

---

## `complex` — the control half

**The question it answers: "What is this agent doing right now, and how do I
steer it without touching the keyboard?"**

This is where the remote-control half of the PRD gets built: stop, interrupt,
continue, send a follow-up, change the model, run the tests — spoken or clicked,
reaching into an agent that is already running. Plus the live visibility that
makes those commands worth having: seeing what an agent is doing at the moment
you decide to intervene.

That requires Daddy to hold the agent itself, rather than handing it to Terminal,
which is the opposite trade from `simple`. The likely way to have both is a
session multiplexer — Daddy holds the process, your Terminal attaches to the same
session, and you both have hands on it. That is the piece to design first.

**Status:** not started. It currently sits at the same commit as `main` because
that is where it branched from and no work has gone into it yet. The foundation it
needs — the agent-driving machinery described under `main` — is already there and
tested.

---

## How they relate

These are not two competing products. They are two halves of one PRD that were
split apart so each could be built properly.

`simple` is the memory. `complex` is the control. The end state is probably both:
a Daddy that remembers everything across sessions *and* can reach into a running
one.

Worth knowing: `simple` still carries the agent-driving machinery inside it,
unused. Bringing control back to that branch would be a matter of reconnecting it,
not rebuilding it — once the question of how you reach into a running session is
settled.
