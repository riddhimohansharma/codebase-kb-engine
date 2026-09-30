---
description: Generate a complete read-only knowledge base for THIS repo into $KB_DIR (five high-level .md files). Writes only the KB; never modifies the repo.
argument-hint: "[optional subsystem focus]"
---
Produce the repository knowledge base per the `kb` skill contract.

1. Resolve the output dir: run `printenv KB_DIR`. If empty, tell the user to relaunch via `repokb kb <repo>` or `repokb run <repo>` (both set KB_DIR and grant it with --add-dir) and STOP.
2. Determine appname from package metadata (package.json / pyproject / go.mod) or the repo directory name.
3. Recon the repo first — use the `scout` subagent for wide reads: languages, entrypoints, services, data models, interfaces/contracts, dependencies, config/env, CI/IaC, and business logic. Cite `path:line`.
4. Write all five files as ABSOLUTE paths under $KB_DIR with the Write tool (it creates parent dirs):
   `00-overview.md`, `01-technical-architecture.md`, `02-functional-workflows.md`, `03-business-rules.md`, `04-system-context-and-gaps.md`.
5. Enforce provenance and the `[C]`/`[I]`/`[?]` confidence legend in every file. Extract business rules explicitly with enforcement sites. Include mermaid diagrams. Cover micro (standalone) and macro (puzzle-piece) views.
6. Never edit or delete anything in the repo (the gate enforces this). If $ARGUMENTS is given, still produce all five files but weight them toward that subsystem.

Finish with a one-line index of the files written and the top 3 `[?]` items to verify.
