# Agent-context seeds

Seed content for the file every coding agent reads before it touches a repo: `CLAUDE.md` for Claude Code, `AGENTS.md` for other tools. One body serves both; only the filename differs.

**Status.** The engine does not generate or write this file yet. These are hand-copied seeds that define the shape, so a later generator has something to target and a team can start today.

## The one rule

**A line earns its place only if a competent agent, given this repo and no other context, would otherwise do the wrong thing.** Not "is it true", not "is it useful". The file is loaded on every turn, so every line costs context; an obvious line costs it for nothing and teaches readers to skip the file.

Admissible: a constraint the agent cannot discover, a counter-intuitive fact, or an edge of the form "changing X obligates Y" with paths. Inadmissible: the primary language, the test directory's name, a framework's name, a restatement of the directory tree.

## Shape

`# Agent context — <repo>`, one line saying what the repo is, then exactly these sections in this order: Non-negotiables, Shape, Commands, Changing X obligates Y, Traps, Before you say you're done.

Budget: **400 words** for the whole file. If it does not fit, split the scope (a package gets its own file); do not raise the budget.

## Use it

1. Classify the repo: `scripts/archetype.sh <repo>` prints the archetype (A to E) and modifiers.
2. Copy the matching skeleton (`A-service.md` to `E-contract.md`), append the modifier blocks from `modifiers.md`, and replace the example lines with your repo's.
3. In skeletons, `[P]` marks a line that can be projected from the repo's `ckb.json`; `[H]` marks one only a human can write. Delete the tags before committing.

`dogfood/` holds finished seeds for the three repos of this project. To adopt one: `cp dogfood/codebase-kb-spec.md ../codebase-kb-spec/CLAUDE.md`.

## Treat it as code

Every agent in the organisation obeys this file on every turn, and anyone who can commit can edit it. Review it like code (CODEOWNERS), never put secrets or credentials in it, and do not let it tell an agent to fetch and run anything.

The files in templates/agent-context/ are licensed under MIT-0 (see LICENSE in this folder), not the plugin licence, so they can be copied into any repository without a notice.
