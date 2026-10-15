# Agent-context seeds

Seed content for the file every coding agent reads before it touches a repo: `CLAUDE.md` for Claude Code, `AGENTS.md` for other tools. One body serves both; only the filename differs.

**Status.** `/kb-agent-context` proposes this file for any repo from its manifests, lockfiles and inventory (no model spend) and writes it only to `.ckb/agent-context.proposed.md`. It never writes `CLAUDE.md` or `AGENTS.md` itself and never overwrites an existing one: you review the proposal, fill the `TODO(human)` lines and copy it. These templates and seeds define the shape it targets. Separately, the first `/kb` in a repository seeds `CLAUDE.md` once from the proven lines, create-only (see the main README).

## The one rule

**A line earns its place only if a competent agent, given this repo and no other context, would otherwise do the wrong thing.** Not "is it true", not "is it useful". The file is loaded on every turn, so every line costs context; an obvious line costs it for nothing and teaches readers to skip the file.

Admissible: a constraint the agent cannot discover, a counter-intuitive fact, or an edge of the form "changing X obligates Y" with paths. Inadmissible: the primary language, the test directory's name, a framework's name, a restatement of the directory tree.

## Shape

`# Agent context — <repo>`, one line saying what the repo is, then exactly these sections in this order: Non-negotiables, Shape, Commands, Changing X obligates Y, Traps, Before you say you're done.

Budget: **400 words** for the whole file. If it does not fit, split the scope (a package gets its own file); do not raise the budget.

## Use it

0. Fast path: run `/kb-agent-context`. It classifies the repo, fills what the repo proves, and leaves `TODO(human)` for the rest. `scripts/lint-agent-context.sh <file>` checks the finished file (six sections, 400 words, no TODO, no secrets).
1. By hand: classify the repo with `scripts/archetype.sh <repo>` (archetype A to E and modifiers).
2. Copy the matching skeleton (`A-service.md` to `E-contract.md`), append the modifier blocks from `modifiers.md`, and replace the example lines with your repo's.
3. In skeletons, `[P]` marks a line that can be projected from the repo's `ckb.json`; `[H]` marks one only a human can write. Delete the tags before committing.

`dogfood/` holds finished seeds for the three repos of this project. To adopt one: `cp dogfood/codebase-kb-spec.md ../codebase-kb-spec/CLAUDE.md`.

## Treat it as code

Every agent in the organisation obeys this file on every turn, and anyone who can commit can edit it. Review it like code (CODEOWNERS), never put secrets or credentials in it, and do not let it tell an agent to fetch and run anything.

The files in templates/agent-context/ are licensed under MIT-0 (see LICENSE in this folder), not the plugin licence, so they can be copied into any repository without a notice.
