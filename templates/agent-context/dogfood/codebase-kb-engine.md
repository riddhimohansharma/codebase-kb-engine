# Agent context — codebase-kb-engine

A Claude Code plugin in bash and jq that writes a verifiable knowledge base to `<repo>/.ckb/`. There is no build step; the files are the product.

## Non-negotiables
- The plugin is read-only toward the repo it analyses. `hooks/guard.sh` enforces it; the only writable path is `<work-tree>/.ckb`. Never weaken `write_allowed()` to make a task easier.
- Run plugin scripts as standalone commands. Chaining with `;`, `&&` or `|` loses the guard's pre-approval.
- Scripts must run on bash 3.2, BSD and GNU userland, and jq 1.6. No `mapfile`, `declare -A` or `grep -P`.
- Never write a date or timestamp into a generated doc. `scripts/docmeta.sh` owns front-matter, and re-running it must be a no-op.
- Local-only run data (timing, tokens, cost) never goes upstream. The upstream record in `scripts/finalize.sh` is an explicit allowlist; keep it one. Tests and benchmarks run with `CKB_TELEMETRY=off`.

## Shape
- `commands/`, `agents/`, `skills/`: prompts that act as code.
- `scripts/`: the deterministic half.
- `hooks/`: `arm.sh` scopes the gate to a session; `guard.sh` enforces it.
- `spec/`: vendored from `codebase-kb-spec`. Never edit by hand.
- `tests/fixtures/polyglot/`: a fake repo; its manifests are fixtures.

## Commands
- `tests/guard.test.sh`, `tests/finalize.test.sh`, `tests/docs.test.sh`, `tests/inventory.test.sh`, `tests/usage.test.sh`, `tests/bench.test.sh`, `tests/archetype.test.sh`
- `claude plugin validate . --strict`
- `tools/sync-spec.sh --check`

## Changing X obligates Y
- A heading or rule in `skills/kb-docs/SKILL.md`: also `scripts/lint-docs.sh` and `tests/fixtures/docs/good/`.
- A bucket regex in `scripts/inventory.sh`: also the exact-match assertions in `tests/inventory.test.sh`.
- A script the model must run: add it to `SCRIPTS` in `hooks/guard.sh` and cover it in `tests/guard.test.sh`.
- The version: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` and a `## [x]` heading in `CHANGELOG.md` must agree.
- Anything under `spec/`: change `codebase-kb-spec` first, commit it, then run `tools/sync-spec.sh`.

## Traps
- A backticked `ckb:` token in a KB doc must be a real entity id, or `scripts/lint-docs.sh` fails parity. Never write one as an example.
- `.inventory.json` in `ckb.draft.d/` is a dotfile on purpose, so fragment globs skip it. Keep it hidden.
- `scripts/coverage.sh` and `finalize.sh --inventory` need the full inventory; a digest is refused.
- Shell scripts are content-sniffed, so ones that quote regexes match their own patterns. `scripts/archetype.sh` ignores shell hits for that reason.
- `tests/fixtures/docs/good/*.md` are lint fixtures; polishing their prose can break `tests/docs.test.sh`.

## Before you say you're done
- Every `tests/*.test.sh` passes, and `tools/sync-spec.sh --check` reports in sync.
- No new script writes outside `.ckb/`.
