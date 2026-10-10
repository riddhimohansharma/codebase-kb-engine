<!-- Archetype E: contract and content. [P] = project from ckb.json or the inventory; [H] = a human writes it. Delete this comment and the tags. -->
# Agent context — api-contracts

The committed artifacts are the product: JSON Schemas, example payloads and the scripts that validate them. [P]

## Non-negotiables
- [P] There is no compiler. The validator is the only definition of correct: run it after every edit.
- [P] Files under `tests/invalid/` are negative cases that are meant to fail. Do not tidy them.
- [H] Never rename a schema field without a version bump; consumers pin the version.

## Shape
- [P] `schema/`: the contracts. `examples/`: valid payloads. `tests/`: positive and negative fixtures. `scripts/`: the validators.

## Commands
- [P] `scripts/validate.sh` runs the whole suite. It needs `jq` and `uvx`.

## Changing X obligates Y
- [P] A constraint in `schema/orders.schema.json`: a rejecting fixture in `tests/invalid/`.
- [P] Anything under `schema/`: re-vendor it into `../orders-service/spec/`; the consumer carries a copy.
- [P] A new example: it must validate, and `README.md` links to it.

## Traps
- [H] A fixture that trips two rules fails the suite even though it is rejected. Keep each negative case minimal.

## Before you say you're done
- [P] `scripts/validate.sh` passes and every schema change has a rejecting fixture.
