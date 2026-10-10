# Agent context — codebase-kb-spec

The normative CKB specification: JSON Schema, executable ID derivation, semantic rules and conformance fixtures. Text and schemas only; there is nothing to build.

## Non-negotiables
- 0.x breaks freely (`VERSIONING.md`). Do not add compatibility shims or deprecation windows; make the change and record it in `CHANGELOG.md`.
- A schema change is never a one-file change. It needs a rejecting fixture here, then fresh vendored copies in `codebase-kb-engine/spec/` (via `tools/sync-spec.sh`) and `consumer-repo/src/codebase_kb_graph/spec/`.
- `schema/v0.1/` serves old artifacts. Touch it only for a deliberate repo-wide break.
- Contributions are not accepted (`CONTRIBUTING.md`) and the licence is CC BY-ND 4.0. Do not publish modified copies of the spec text.
- Vendor data belongs in `x-` fields. Reach for `x-` before a new required field.

## Shape
- `schema/v0.2/ckb.schema.json` holds structure, `semantic.jq` the rules R1 to R12, `derive.jq` the normative ID derivation (R8), and `ckb-lock.schema.json` the consumer lock.
- `schema/v0.2/examples/` must stay valid; `full.json` exercises every collection.
- `tests/v0.2/invalid*/` hold the negative fixtures.

## Commands
- `tests/validate.sh` runs the whole suite and needs `jq` and `uvx`. `tests/validate.sh <artifact.json>` checks one artifact.

## Changing X obligates Y
- A constraint in `ckb.schema.json`: add a rejecting fixture under `tests/v0.2/invalid/`.
- A rule `RN` in `semantic.jq`: add `tests/v0.2/invalid-semantic/rN-<slug>.json`. The suite requires it to be rejected by `RN` and by no other rule.
- `derive.jq`: update `derive.py` in `consumer-repo`; its `tests/test_derive.py` asserts byte parity.
- The canonical KB directory (`.ckb/`) appears in lock `artifact_path`, in R7 and in the freshness rule. Change all three together.

## Traps
- Every file under `tests/*/invalid*/` is meant to fail. Do not fix one.
- A fixture that trips a second rule fails the suite even though it is rejected. Keep fixtures minimal.
- `tests/semantic.jq` is the v0.1 rule file; v0.2's lives under `schema/v0.2/`. Editing the wrong one changes nothing.

## Before you say you're done
- `tests/validate.sh` passes for v0.1 and v0.2.
- Every schema change has a rejecting fixture, and `README.md` and `VERSIONING.md` still describe what you did.
