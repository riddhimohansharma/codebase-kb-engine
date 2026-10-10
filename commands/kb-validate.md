---
description: Validate a ckb.json against the CKB spec (JSON Schema + semantic rules R1–R7) and report freshness and report pass/fail per rule. Read-only.
argument-hint: "[path/to/ckb.json]"
---
Validate a CKB artifact. Read-only: do not modify the artifact or anything else.

1. Artifact path: `$ARGUMENTS` if given, otherwise `<git toplevel>/.ckb/ckb.json` for the current repo. If the file does not exist, say so, suggest `/kb`, and stop.
2. Run `"${CLAUDE_PLUGIN_ROOT}/scripts/validate.sh" "<path>"`. For the in-repo KB, also run `"${CLAUDE_PLUGIN_ROOT}/scripts/freshness.sh" "<git toplevel>"` and report its `FRESHNESS=` line.
3. Report a table with one row per check — Schema (structural), R1 unique IDs, R2 ID prefix matches collection, R3 references resolve, R4 confidence_summary counts, R5 workflow step order, R6 end_line ≥ line, R7 no citations of `.ckb/` — marking each PASS / FAIL / SKIPPED from the script output (a rule with no `semantic: R<n>` line passed). Quote each violation verbatim.
4. End with the script's `RESULT=` line. If structural was skipped, say plainly that conformance is unproven until `uv` is installed. Never report SKIPPED as PASS.
