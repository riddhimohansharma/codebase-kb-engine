---
description: Tri-lens reconnaissance of the current repo (10k strategy / 2k architecture / 500 execution).
argument-hint: "[optional focus area]"
---
First-principles reconnaissance of THIS repository. Auto-read git state, tree, build/test config, and dependency manifests before responding. Never ask for baseline context. Load the `codebase-kb-engine:doctrine` skill first.

Deliver exactly three lenses, terse, no preamble:

## 10k ft — Strategy / MOAT
- What this repo produces, and where the defensible leverage is vs. commodity work.
- The 1-2 structural risks that would break it.

## 2k ft — Architecture
- Core data models and control flow (the 4% that governs the rest).
- Seams: where change is cheap vs. where it is load-bearing.

## 500 ft — Execution
- Current state: build, tests, CI, obvious tech debt (cite files/paths).
- The nearest 3 concrete, shippable changes.

Use the `scout` subagent for wide reads so this context stays clean. Scope to $ARGUMENTS if provided.
