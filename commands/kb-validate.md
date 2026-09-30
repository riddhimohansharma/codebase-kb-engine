---
description: Validate a ckb.json against the CKB spec (JSON Schema + semantic rules R1–R6) and report pass/fail per rule. Read-only.
argument-hint: "[path/to/ckb.json]"
---
Validate a CKB artifact. Read-only: do not modify the artifact or anything else.

1. Artifact path: `$ARGUMENTS` if given. Otherwise `$KB_DIR/ckb.json` if `printenv KB_DIR` is set, else `<parent of git toplevel>/<repo name>-kb/ckb.json` for the current repo. If the file does not exist, say so, suggest `/kb`, and stop.
2. Run `"${CLAUDE_PLUGIN_ROOT}/scripts/validate.sh" "<path>"`.
3. Report a table with one row per check — Schema (structural), R1 unique IDs, R2 ID prefix matches collection, R3 references resolve, R4 confidence_summary counts, R5 workflow step order, R6 end_line ≥ line — marking each PASS / FAIL / SKIPPED from the script output (a rule with no `semantic: R<n>` line passed). Quote each violation verbatim.
4. End with the script's `RESULT=` line. If structural was skipped, say plainly that conformance is unproven until `uv` is installed. Never report SKIPPED as PASS.
