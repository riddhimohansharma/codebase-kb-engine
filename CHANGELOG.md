# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/). Versioning: [SemVer](https://semver.org/). The plugin `name` `codebase-kb-engine` is permanent.

## [0.8.0] — 2026-10-01

Expert-panel review (knowledge-graph, polyglot static analysis, knowledge-base practice, plugin reliability): 54 findings, all P0/P1 fixed.

### Security (P0)
- **Guard bypasses closed:**
  - `git -C … commit/checkout`, `git -c` config and exec overrides, `--output`/`--ext-diff`/`-O`.
  - `find -delete`/`-exec`, `sort -o`, sed `w`/`e`, awk `system()`, `tree -o`, `yq -i`; `xxd` removed from the allowlist.
  - Environment overrides that run code: `GIT_*`, `PAGER`, `LD_PRELOAD`/`DYLD_*`, `PATH`, `BASH_ENV`, …
  - Arming now works without jq.
- **Arming is scoped to `/kb` and `/kb-validate`.** `/map`, `/hunt` and `/plan` (and other plugins' `/plan`) no longer lock the session.
- The `doctrine` and `leverage` skills are no longer loaded in ordinary sessions (`disable-model-invocation`).
- The hook parses its input in one jq pass, and pure-read tools exit early.

### Graph and dependency completeness (CKB v0.2)
- Emits **CKB v0.2**:
  - **purl** dependency identity, one entity per manifest declaration, with `source` (`workspace` and `path` for monorepo internals).
  - **What the repo provides:** artifacts it publishes and services it deploys.
  - Config keys (names only, `is_secret`), external SaaS services, API spec files, repo profile, coverage.
- Outbound call targets are part of interface IDs, so calls to different services no longer merge.
- IDs come from the spec's shared `derive.jq`. Relations are restricted to the spec's allowed triples, and role mismatches are auto-corrected.

### Polyglot coverage
- `scripts/inventory.sh` (deterministic, about 0.5 s per repo) inventories manifests, lockfiles, routes, events, ORMs/datastores, migrations, IaC, CI, config and API specs across 30+ ecosystems. It detects workspaces and excludes generated and vendored code. `scripts/coverage.sh` compares the inventory with what the KB cites, and an uncited manifest keeps the KB `incomplete`.
- The normalizer handles:
  - route syntaxes for Ruby `#{}`, Django `(?P<>)`, Laravel `{id?}`, Gin `*path`, Axum `{*rest}`, JAX-RS `{ id }`, nginx modifiers and regex groups, Go `%d`, and Kotlin/Dart `$var`;
  - literal ids and UUIDs, which become `{id}`;
  - multi-method routes, which become one entity per method;
  - outbound hosts, normalized;
  - event topics in SQS-URL, ARN and Pub/Sub path forms;
  - ORM quoting and default schemas;
  - 25+ ecosystems' manifests (Gradle catalogs, `Directory.Packages.props`, `pubspec`, `mix.exs`, `.rockspec`, Dockerfile `FROM`, Actions `uses:`, …) with per-ecosystem name canonicalization.
- Scouts:
  - The `scout` agent (sonnet) has a full polyglot checklist: route prefix composition for 20+ frameworks, event placeholders, the RPC/GraphQL convention, ORM table naming. It returns JSON fragments.
  - New `scout-inventory` (haiku) for the mechanical buckets.
  - `/kb` runs up to 8 scouts in parallel, with a retry policy. Drafts can be split into `ckb/ckb.draft.d/`.

### Knowledge-base practice
- **8 docs**, adding `05-operations.md`, `06-security-and-data.md` and `07-decisions.md`, plus a generated `90-reference.md`. Required headings are arc42/C4/Diátaxis-aligned, with C4 context, container and component diagrams, an ERD and per-workflow sequence diagrams.
- `scripts/lint-docs.sh` (sections, diagrams, confidence tags, size, secrets, anchors, docs/JSON parity), `scripts/docmeta.sh` (deterministic YAML front-matter, local→final id rewrite, stable anchors) and `scripts/reference.sh`.
- The `kb` skill is renamed `kb-docs` (with frontmatter `name`), and `/kb` loads both skills explicitly.
- **Claim audit:** the `auditor` agent (haiku) checks up to 15 confirmed claims against their source lines before finalize.

### Changed
- `repo.url` is canonical (`https://host/owner/repo`; ssh/scp forms converted, `.git`, ports and credentials stripped).

### Tests
- guard 125, finalize 71, docs 98, inventory 50, all passing on jq 1.6, 1.7 and 1.8. CI runs all four suites.

## [0.7.0] — 2026-09-30

### Changed
- **The KB folder is now `<repo>/ckb/`, visible in Finder, Explorer and `ls`.** It was the hidden `.ckb/`. This follows codebase-kb-spec, which moved the canonical location. Everything that referred to the folder is updated: the guard's write rule, freshness pathspec, R7 filtering, docs and tests.

### Added
- **Automatic migration:** on the next `/kb`, an existing plugin-made `.ckb/` (carrying the marker) is renamed to `ckb/`. A `.ckb/` without the marker is left alone, and an existing `ckb/` is never overwritten. If `.ckb/` was committed, commit the rename: `git add -A .ckb ckb`.
- `ckb/.gitignore` keeps transient files (draft, candidate, rejected, tmp) and OS junk out of commits.

### Fixed
- OS junk files (`.DS_Store`, `Thumbs.db`, `desktop.ini`) created by Finder or Explorer no longer count as uncommitted source changes. Previously, just opening the repo in Finder made the KB look stale.

## [0.6.1] — 2026-09-30

### Changed
- The spec repository is now **`codebase-kb-spec`**, renamed from `ckb-spec`. Links, `tools/sync-spec.sh` defaults and the vendored schema `$id` are updated, and the spec is re-vendored at `codebase-kb-spec@e884f8f`.

### Fixed
- **Linux/jq 1.7:** `manifest.json` generation failed with a jq syntax error, because jq 1.7 rejects an unparenthesized `a + b` as an object value and jq 1.8 accepts it. Ubuntu CI caught it. Both test suites now pass on jq 1.6, 1.7 and 1.8.
- `finalize.sh` now fails loudly if writing `manifest.json` fails, instead of leaving a stale or empty manifest. The conformance test prints the finalize output on its first failure, which helps diagnose CI.

## [0.6.0] — 2026-09-30

### Changed
- **The KB now lives in the repo at `<repo-root>/.ckb/`** and is committed with the code. This is the CKB spec's canonical location. The old sibling `../<repo>-kb/` directory and the `KB_DIR` override for local mode are gone. `KB_DIR` now applies only to URL mode, whose default output is `<name>-ckb/`.
- The guard allows writes inside a git work tree only at exactly `<work-tree>/.ckb`. Nested `.ckb` dirs, look-alike names, forged markers elsewhere, and symlinked `.ckb` dirs are all refused.
- The marker file is static, so there are no paths or timestamps to commit. Local mode no longer needs `--add-dir`.
- The vendored spec is now `codebase-kb-spec@582b39d`: in-repo location, freshness rule, and rule R7.

### Added
- `scripts/freshness.sh`, implementing the spec's rule: fresh at `Y` if and only if nothing outside `.ckb/` changed since `commit_sha`. `/kb` skips when the KB is fresh; `/kb --force` overrides. `/kb-validate` reports freshness.
- R7 enforcement: analysis ignores `.ckb/`, and citations or components inside `.ckb/` are dropped.
- `.ckb/README.md`, a deterministic index, and `.ckb/.gitattributes` (`linguist-generated`).
- A `COMMIT_HINT` at the end of a run. The producer never commits.
- **Citation verification**: every `path:line` is checked against the real file (tracked or untracked-but-not-ignored, outside `.ckb/`) and its line count. Absolute paths under the repo root are made relative. Claims that don't verify are downgraded to `unknown`.
- **Secret redaction**: secret values from the repo's env, key and config files that appear in the KB are replaced with `[REDACTED]` and recorded in the warnings. The skills also tell the model to cite secrets by name and location only.
- **Robust normalization**: enum synonyms are coerced (`postgresql`, `devDependencies`, `rw`, `app.all`, `graphql`, …). Package keys are inferred from the manifest file and stripped of versions and extras. Absolute URLs, host placeholders, literal ids and wildcards in HTTP paths are normalized. SQL schema and table names are lowercased. Missing `symbol`, `topic` and rpc fields get defaults. Empty workflows get a placeholder step. Ambiguous local ids and unresolved references are dropped with warnings, and unknown relation kinds are dropped.
- New status `unverified`: nothing is marked `complete` unless the schema check actually ran.
- **An invalid candidate never replaces a good `ckb.json`.** It is kept as `ckb.json.rejected`.
- Freshness is stricter: uncommitted source edits and a non-complete last run both force regeneration, and shallow clones are reported with a fix.
- `repo.branch` on a detached HEAD falls back to CI ref variables, then the tag, then `name-rev`.
- Docs: full [User Manual](docs/USER_MANUAL.md). Headless runs use `/codebase-kb-engine:kb`, because the short `/kb` sometimes isn't expanded in `-p` mode.
- Tests: guard 81, finalize 51.

### Verified
- Live run on a real 63-file Node.js service: status `complete`, schema and semantic checks pass, 109 claims (108 confirmed), and all 73 cited `path:line` locations resolve. No secret values appear in the KB, and the source tree is unchanged (only `.ckb/` was added; nothing was committed).

## [0.5.0] — 2026-09-30

### Added
- **`ckb.json`**: a machine-readable artifact conforming to the CKB v0.1 spec (vendored in `spec/v0.1/`), plus **`manifest.json`** (job identity, status, outputs with sha256, validation, confidence roll-up).
- `scripts/finalize.sh` + `scripts/normalize.jq`: deterministic spec IDs, join-key normalization (HTTP paths across Express, Next.js, Flask and template syntaxes; npm/pypi names), duplicate merging, reference remapping, and automatic downgrade of uncited claims to `unknown`.
- `/kb-validate`: JSON Schema + semantic rules R1–R6, reported per rule. It never reports a skipped check as a pass.
- **Repo-URL mode**: `/kb <url> [branch]` makes a shallow, push-disabled clone in a sandbox and destroys it after the job, even on failure. URLs with embedded credentials are refused, and the default branch is detected rather than assumed.
- **Output directory resolution** (`scripts/resolve-kb.sh`): `$KB_DIR`, else a `<repo>-kb` sibling. The resolver refuses any location inside the target repo and prints the exact `claude --add-dir` line when it can't write. This works in marketplace installs, where no wrapper sets `KB_DIR`.
- `/kb-unlock` and the `ckb-contract` skill.
- `tools/sync-spec.sh`: vendors the spec from a codebase-kb-spec checkout and records the source commit in `spec/v0.1/SOURCE`. With `--check`, it detects drift.
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
