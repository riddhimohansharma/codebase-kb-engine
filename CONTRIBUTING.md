# Contributing

**All contributions require the [Contributor License Agreement](CLA.md).** The CLA check on your first pull request asks you to sign. The project is licensed under PolyForm Shield 1.0.0, and the CLA lets the maintainer include accepted contributions in any edition of the product.

- **Run the checks** before opening a PR: `tests/guard.test.sh`, `tests/finalize.test.sh`, `claude plugin validate . --strict`, `tools/sync-spec.sh --check`. CI runs the same checks on Linux and macOS.
- **Safety changes** (`hooks/`, `scripts/`) need a test that fails without the change.
- **Output format.** `ckb.json` follows the CKB spec in `spec/` (CC BY-ND 4.0, vendored unmodified). Never edit `spec/`. Spec changes are made only by the spec's editor upstream in codebase-kb-spec; propose them as an issue there.
- **Releases.** Bump `version` in both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, and add a `CHANGELOG.md` entry. Users receive updates only when the version string changes.
- The plugin name `codebase-kb-engine` is permanent.
