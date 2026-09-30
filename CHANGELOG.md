# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/). Versioning: [SemVer](https://semver.org/). The plugin `name` `codebase-kb-engine` is permanent.

## [0.5.0] — 2026-09-30

### Added
- **`ckb.json`**: a machine-readable artifact conforming to the CKB v0.1 spec (vendored in `spec/v0.1/`), plus **`manifest.json`** (job identity, status, outputs with sha256, validation, confidence roll-up).
- `scripts/finalize.sh` + `scripts/normalize.jq`: deterministic spec IDs, join-key normalization (HTTP paths across Express, Next.js, Flask and template syntaxes; npm/pypi names), duplicate merging, reference remapping, and automatic downgrade of uncited claims to `unknown`.
- `/kb-validate`: JSON Schema + semantic rules R1–R6, reported per rule. It never reports a skipped check as a pass.
- **Repo-URL mode**: `/kb <url> [branch]` makes a shallow, push-disabled clone in a sandbox and destroys it after the job, even on failure. URLs with embedded credentials are refused, and the default branch is detected rather than assumed.
- **Output directory resolution** (`scripts/resolve-kb.sh`): `$KB_DIR`, else a `<repo>-kb` sibling. The resolver refuses any location inside the target repo and prints the exact `claude --add-dir` line when it can't write. This works in marketplace installs, where no wrapper sets `KB_DIR`.
- `/kb-unlock` and the `ckb-contract` skill.
- `tools/sync-spec.sh`: vendors the spec from a ckb-spec checkout and records the source commit in `spec/v0.1/SOURCE`. With `--check`, it detects drift.
- `tests/guard.test.sh` (66 safety checks) and `tests/finalize.test.sh`.

### Verified
- End-to-end headless run on an Express/Postgres/Kafka fixture repo. It produced 5 docs, `ckb.json` and `manifest.json` with status `complete`. Schema and semantic checks passed, all 28 citations resolve, and the repo was byte-identical afterwards. In an armed session, a prompted Write and an `rm` inside the repo were blocked.

### Fixed
- The pipe-to-shell rule never fired on macOS: BSD grep rejected an empty regex alternative. Writes stayed blocked by the allowlist regardless.
- Plugin scripts no longer trigger approval prompts. The guard pre-approves them, verified by real path, because headless runs can't answer a prompt.
- `--add-dir` is silently ignored for a path that doesn't exist at launch, so the KB dir is now created up front and the hint includes `mkdir -p`.

### Changed
- **Renamed** `repository-kb-engine` to `codebase-kb-engine`, and filled in the marketplace manifest fields.
- **The read-only gate is now session-scoped.** It enforces only after an engine command or plugin script runs in the session (or under `CKB_ENFORCE=always`, which the local wrappers set). Before this, an installed plugin would have gated every session.
- KB writes are allowed only inside a dir carrying a `.ckb-output` marker, never inside the analysed repo or the session's work tree, with symlinks resolved. Unknown tools (including MCP tools) are blocked while the gate is enforcing.
- The doctrine skill no longer forbids KB writes; it forbids modifying the analysed repo.

## [0.4.1]
- Previous internal release as `repository-kb-engine` (local wrapper only).
