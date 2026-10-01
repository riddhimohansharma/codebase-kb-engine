---
name: kb-docs
description: Human-docs contract for the codebase-kb-engine /kb command ONLY (not for general documentation, READMEs, or ADR work outside /kb). Defines the 8 model-written docs in <repo>/ckb/, their exact required headings, diagrams, anchors, confidence tags, determinism, and secrets rules, all enforced by scripts/lint-docs.sh.
---
# KB docs contract (/kb only)

Goal: a complete, verifiable KB for one repository, understood as a standalone system (micro) and as a piece of a larger system (macro). The machine artifact is governed by the `ckb-contract` skill. The docs and `ckb.json` describe the same facts and never contradict.

## Principles
- First principles: reduce to the ~4% of data models, interfaces, and rules that govern the rest. State assumptions.
- Provenance: every non-obvious claim cites `path:line` (or `path:line-end`), repo-relative. Never cite `ckb/`. Never mention `ckb.draft*` files.
- Confidence: `[C]` confirmed in code, `[I]` inferred, `[?]` unknown or needs verification. They equal `confirmed` / `inferred` / `unknown` in `ckb.json`. Never present inference as fact; never invent facts. Write `[?]` instead.
- Read-only toward code. Write only inside the KB dir. Never commit.
- Terse, dense, decision-oriented. Link paths; do not paste code.

## Discover first (prefer the scout subagent for wide reads)
Languages, entrypoints, components, routes, events, RPC, manifests, datastores and migrations, config/env/secrets names, CI, IaC, deploy targets, observability, auth, existing `docs/adr`, business logic.

## Files
Write exactly these 8 into `<KB_DIR>` with absolute paths. Do not write anything else there except `ckb.draft.json`.

| File | Purpose | Diátaxis | Words |
|---|---|---|---|
| `00-overview.md` | What it is, for whom, glossary, macro context | explanation | 300–1000 |
| `01-technical-architecture.md` | C4 L2/L3, data model, interfaces, deps, config, deploy, NFRs (arc42 5–8, 10) | explanation | 400–1800 |
| `02-functional-workflows.md` | Actors, capabilities, end-to-end workflows (arc42 6) | explanation | 300–1800 |
| `03-business-rules.md` | Rule catalog with enforcement sites and traceability | reference | 300–1800 |
| `04-system-context-and-gaps.md` | C4 L1, contracts exposed/consumed, risks, open questions (arc42 3, 11) | explanation | 300–1500 |
| `05-operations.md` | Build, run, test, deploy, observe, roll back | how-to | 300–1200 |
| `06-security-and-data.md` | Trust boundaries, auth, data classes, secrets inventory, findings | reference | 300–1500 |
| `07-decisions.md` | ADR-lite log of observed/inferred decisions (arc42 9) | explanation | 300–1500 |

Generated, never hand-written: YAML front-matter on each doc (`scripts/docmeta.sh`), `90-reference.md` (`scripts/reference.sh`, tables from `ckb.json`), `README.md`, `ckb.json`, `manifest.json`. Do not write front-matter yourself; if present it is replaced.

## Global rules (lint-enforced)
1. **Structure.** Line 1 is `# <Doc title>`. Then the required `##` headings below, verbatim, unnumbered, in the listed order. Extra `##` sections are allowed after the required ones. Every required section has content.
2. **Not applicable.** A required section that genuinely does not apply keeps its heading and contains one line: `Not applicable — <reason> [?]`. Any line containing `Not applicable` must carry `[?]`.
3. **Confidence tags.** Every line containing a citation (`file.ext:N`, pattern `[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+`) must also contain `[C]`, `[I]`, or `[?]`. Applies to bullets, table rows, captions, and prose. Code fences are exempt. Host:port strings with a dot (`db.local:5432`) match too; tag those lines.
4. **Anchors.** Every `###` heading for a component or interface (01 `## Components (C4 L3)`, `## Interfaces`), workflow (02 `## Workflows`), or rule (03 `## Rule catalog`) is wrapped exactly so:
   ```
   <a id="business-rule-order-total-positive"></a>
   ### Order total must be positive
   `ckb:business_rule:order-total-positive`
   ```
   The marker holds the entity's `id`. Write the **local id you gave the entity in the draft**; finalize rewrites markers to final IDs and regenerates the anchor. Anchor id = marker id lowercased, every char outside `[a-z0-9]` replaced by `-`.
5. **Diagrams (mermaid).** 01: one `C4Container`, one component `flowchart`, one `erDiagram` (or Not applicable). 02: one `sequenceDiagram` inside every workflow `###`. 04: one `C4Context`. Node ids = entity slugs (e.g. `src_api`, `orders_table`), never `A`/`B`/`n1`. ≤15 nodes per diagram, ≤40 lines per block. Inferred edges are dashed (`-.->`, `-->>` in sequences, `Rel` with `[I]` label in C4). Directly below each block a caption line: `Source: path:line[, path:line] [C|I|?]`.
6. **Code blocks.** Non-mermaid fences ≤15 lines. Prefer a citation over a snippet.
7. **Determinism.** Order every list, table, and `###` sequence by first provenance path, then line. IDs are slugs from the name (`BR-order-total-positive`, `Q-who-owns-refunds`, `ADR-postgres-as-system-of-record`), never sequential (`BR-1`, `Q-01`). No dates, timestamps, run notes, or "as of" prose: front-matter carries commit and freshness.
8. **Secrets.** Never write a secret value, token, key, connection string, or password, even partially or masked. Name it and cite `path:line`. Hardcoded secrets go in 06 `## Security findings` and 04 `## Risks and tech debt`.
9. **Parity with `ckb.json`.** Each `business_rules[].name` is exactly one `###` under 03 `## Rule catalog`; each `workflows[].name` is exactly one `###` under 02 `## Workflows`; and vice versa. Same names (case-insensitive), same facts.
10. **Budgets.** Words (whitespace tokens outside code fences and front-matter) within the per-doc range above.

## Per-doc required headings
### 00-overview.md
`## Elevator pitch` · `## Executive summary` · `## Stakeholders and users` · `## Quality goals` · `## Glossary` · `## Macro context` · `## How to read this KB`
- Glossary: table `| Term | Meaning | Source |`, ubiquitous language only.
- Macro context: which larger system this belongs to and what it needs to be complete.
- How to read this KB: the confidence legend and a one-line pointer to each doc, including `90-reference.md`.

### 01-technical-architecture.md
`## First-principles core` · `## Containers (C4 L2)` · `## Components (C4 L3)` · `## Data model` · `## Interfaces` · `## Dependencies` · `## Configuration reference` · `## Deployment` · `## Non-functional posture`
- Containers: `C4Container` diagram + caption. Components: `flowchart` + one anchored `###` per significant component (responsibility, collaborators, citations). Data model: `erDiagram` + entity lifecycles.
- Interfaces: one anchored `###` per significant interface or a table; full listing lives in `90-reference.md`.
- Dependencies: direction (upstream/downstream), why each critical one matters. Configuration reference: key names, purpose, secret yes/no. Never values.
- Non-functional posture: security, compliance/PHI, performance, reliability, observability, each tagged.

### 02-functional-workflows.md
`## Actors` · `## Capabilities` · `## Workflows` · `## State machines` · `## Error and edge handling`
- Under `## Workflows`: one anchored `### <workflow name>` per workflow, each with trigger, inputs/outputs, a `sequenceDiagram`, caption, and numbered steps citing code.

### 03-business-rules.md
`## Rule catalog` · `## Traceability`
- Under `## Rule catalog`: one anchored `### <rule name>` per rule, then exactly these bullets:
  ```
  - **ID:** BR-order-total-positive
  - **Statement:** An order is rejected unless its total is > 0.
  - **Rationale:** Prevents zero-value charges. [I]
  - **Trigger:** POST /orders
  - **Outcome:** HTTP 422; no row written.
  - **Exceptions:** None observed. [?]
  - **Enforced at:** src/orders/validate.ts:42 [C]
  - **Confidence:** [C]
  ```
- `## Traceability`: table `| Rule | Enforced at | Tests | Confidence |`, one row per rule, ordered like the catalog.

### 04-system-context-and-gaps.md
`## System context (C4 L1)` · `## Contracts exposed` · `## Contracts consumed` · `## Assumptions` · `## Risks and tech debt` · `## Open questions`
- System context: `C4Context` with this repo and connected systems; owns vs delegates.
- `## Open questions`: table `| ID | Question | Why it matters | Where to look |` with ids `Q-<slug>`.

### 05-operations.md
`## Build` · `## Run locally` · `## Test` · `## Deploy and environments` · `## Observability` · `## Alerts and failure modes` · `## Rollback`
- Commands only as observed in manifests, Makefiles, CI, or docs; cite them. Unobserved steps are `[?]`.

### 06-security-and-data.md
`## Trust boundaries` · `## AuthN/AuthZ model` · `## Data classification` · `## Secrets inventory` · `## Security findings` · `## Compliance notes`
- Secrets inventory: table `| Name | Kind | Source | Referenced at |`: names and `path:line` only, NEVER values.
- Security findings: concrete, cited, each with severity `high|medium|low` and confidence tag.

### 07-decisions.md
`## Decision log` · `## Existing ADRs`
- Under `## Decision log`: one `### ADR-<slug>: <title>` per decision, with bullets `**Status:**` (`observed` = documented in repo, `inferred` = deduced from code), `**Context:**`, `**Decision:**`, `**Consequences:**`, `**Evidence:**` (citations), `**Confidence:**` (`[C]`/`[I]`/`[?]`). Never invent decisions or rationale.
- `## Existing ADRs`: link every existing ADR/RFC in the repo (e.g. `docs/adr/`), or Not applicable.

## Self-check
Before finalize, run `"${CLAUDE_PLUGIN_ROOT}/scripts/lint-docs.sh" "<KB_DIR>"` and fix every violation it prints (JSON, keyed by file). After finalize, `--parity "<KB_DIR>/ckb.json"` also checks name and marker parity with the artifact.
