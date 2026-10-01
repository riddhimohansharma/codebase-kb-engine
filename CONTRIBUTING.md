# Contributing

- **Run the checks** before opening a PR: `tests/guard.test.sh`, `tests/finalize.test.sh`, `claude plugin validate . --strict`, `tools/sync-spec.sh --check`. CI runs the same checks on Linux and macOS.
- **Safety changes** (`hooks/`, `scripts/`) need a test that fails without the change.
- **Output format.** `ckb.json` follows the CKB spec in `spec/`. Don't edit `spec/` by hand: fix the spec upstream in codebase-kb-spec, then run `tools/sync-spec.sh`.
- **Releases.** Bump `version` in both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, and add a `CHANGELOG.md` entry. Users receive updates only when the version string changes.
- The plugin name `codebase-kb-engine` is permanent.
