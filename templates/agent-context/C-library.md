<!-- Archetype C: library or CLI. [P] = project from ckb.json or the inventory; [H] = a human writes it. Delete this comment and the tags. -->
# Agent context — textkit

A Python 3.11+ library with one console script. [P]

## Non-negotiables
- [P] The public surface is `src/textkit/__init__.py` and the `textkit` console script. Renaming or re-typing anything exported is a breaking change; say so in `CHANGELOG.md`.
- [P] Adding a dependency means editing `pyproject.toml` and regenerating `uv.lock` in the same change.
- [H] No new dependency to save fewer than fifty lines of code. The current set is deliberately two packages.

## Shape
- [P] `src/textkit/`: the package. `tests/`: pytest. `vendor/`: copied code, not yours to edit.

## Commands
- [P] `uv sync --extra dev`, then `uv run pytest`. Minimum Python is 3.11.

## Changing X obligates Y
- [P] A public function signature: `CHANGELOG.md` and the version in `pyproject.toml`.
- [P] A version bump: the tag, `CHANGELOG.md` and `pyproject.toml` together.

## Traps
- [H] Tests that import `textkit.internal` pin private behaviour. Do not use them as proof the public API is safe to change.

## Before you say you're done
- [P] `uv run pytest` passes. If the public surface moved, `CHANGELOG.md` says so.
