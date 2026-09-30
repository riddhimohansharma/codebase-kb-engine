---
description: Repository knowledge-base contract. Load when generating or updating a repo KB (the /kb command). Defines required files, first-principles framing, business-rule extraction, provenance, and confidence.
---
# Knowledge-base contract

Goal: a complete, verifiable KB for a repository — understood both as an independent system (micro) and as a component of a larger system (macro / puzzle piece).

## Principles
- First principles: reduce to core axioms and the ~4% of data models/interfaces that govern the rest. State assumptions; erase inherited ones.
- Micro AND macro: describe the repo standalone, then as a puzzle piece — the contracts it exposes and consumes, and what connected components complete the whole.
- Provenance: every non-obvious claim cites evidence as `path:line`. Distinguish observed-in-code from inferred.
- Confidence legend on every doc: `[C]` confirmed in code · `[I]` inferred · `[?]` unknown / needs verification. Never present inference as fact.
- Read-only toward code: gather via Read/Grep/Glob and read-only bash; WRITE ONLY the KB files under $KB_DIR. Never modify the repo.
- Diagrams as text: mermaid for architecture and workflows.

## Discover first (prefer the scout subagent for wide reads)
appname (package.json name / pyproject / go module / dir), languages, entrypoints, services, data stores, external deps, interfaces/contracts, config/env/secrets, CI, IaC, and business logic.

## Required files — write ALL under $KB_DIR using absolute paths
1. `00-overview.md` — appname; KB metadata (repo path, git commit, date, generator, confidence legend); one-paragraph elevator; executive summary; ubiquitous-language glossary; macro context (which larger system this belongs to; what it needs to be complete).
2. `01-technical-architecture.md` — components & responsibilities; core domain/data model & entity lifecycles; interfaces & contracts (APIs, events, schemas, CLIs); dependencies (internal modules; external services/libs/infra) with direction (upstream/downstream); runtime & deployment topology; config/environments/secrets; non-functional posture (security, compliance/PHI, performance, reliability, observability). Mermaid component diagram. Name the first-principles core (the 4%).
3. `02-functional-workflows.md` — capabilities/features; actors; end-to-end workflows, each with a mermaid sequence/flow; inputs/outputs; state machines; error/edge handling; integration workflows with connected systems.
4. `03-business-rules.md` — rule catalog: each rule = ID, statement, rationale, trigger/inputs, outcome, exceptions, enforcement site `path:line`, confidence. Invariants; validation, authorization, and compliance rules; domain constraints; SLAs/policies. Traceability matrix rule -> code. Open questions.
5. `04-system-context-and-gaps.md` — system-of-systems map (mermaid): this piece + connected components; contracts exposed vs consumed; boundaries/ownership (owns vs delegates); how the pieces complete the whole; risks & tech debt; assumptions; unknowns / to-verify list; suggested next reads.

## Style
Terse, dense, decision-oriented, high-level. Link to files/paths instead of pasting large code. No invented facts — mark `[?]` instead.
