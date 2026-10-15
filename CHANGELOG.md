# Changelog

## [Unreleased]
- Scanner noise: the detection fixtures (12 manifests, six ecosystems) are marked vendored in `.gitattributes` and excluded by `trivy.yaml` and `.snyk`; `SECURITY.md` says what they are.
- Telemetry stays on by default and is now fully transparent: `docs/TELEMETRY.md` shows the exact payload (checked against the upstream allowlist by a test), the first-run notice is shown at the start of `/kb` before anything is sent, and an organization can turn it off for everyone through Claude Code's managed settings (`CKB_TELEMETRY=off` in `env`).
- First run seeds `CLAUDE.md` by default: the first `/kb` in a repository creates it from proven lines only (create-only, once, never overwriting; skipped for existing `CLAUDE.md`/`AGENTS.md`, symlinks, gitignored paths, submodules, URL mode, sparse repos). Opt out with `/kb --no-agent-context` or `CKB_AGENT_CONTEXT=off`. Recorded in `manifest.json` as `agent_context`.
- Freshness ignores the repo-root `CLAUDE.md` and `AGENTS.md` (CKB freshness rule updated in the spec), so committing them never makes the KB stale.

## [0.10.0] — 2026-10-15
- `/kb-agent-context` proposes a `CLAUDE.md` / `AGENTS.md` for any repo in seconds, with no model spend: the archetype's template filled only with lines the manifests, lockfiles and buckets prove, `TODO(human)` for the rest. It writes only `.ckb/agent-context.proposed.md` (git-ignored) and never touches `CLAUDE.md` or `AGENTS.md`.
- `scripts/lint-agent-context.sh` checks a finished file: six sections in order, at most 400 words, no TODO, no skeleton tags, no dates, no secrets.
- Added CODE_OF_CONDUCT.md and GitHub issue templates (bug, expressiveness gap); security reports are routed to the private channel.
- Generated reference is now `08-reference.md`, so the `.ckb/` numbering is contiguous 00–08 (was `09-reference.md`, leaving 08 empty). Old `09-`/`90-reference.md` files are removed on regeneration and tolerated by `resolve-kb.sh`.
- The KB folder is the hidden `.ckb/` (was `ckb/`). A marked `ckb/` migrates automatically, and an unmarked `.ckb/` holding only producer files is adopted; anything else is refused, never overwritten. `COMMIT_HINT` now says `git add .ckb`.
- Inventory: shell scripts (`sh`, `bash`) are now content-sniffed. Areas carry a `tier` (`source`, `test`, `docs`) and content-sniffed entries are marked in `sniffed`. `inventory.sh --out FILE` writes the full inventory and prints a ~2 KB digest; `kbq.sh inventory` gives each scout only its slice. Scouts are packed into at most 7 scopes plus the inventory scout.
- `/kb <url>` skips regeneration when the repository's committed `.ckb/` is already fresh: `freshness.sh --shallow` compares trees against the analysed commit, fetched with the new `clone.sh fetch-commit`.
- `finalize.sh --inventory` reuses the orchestrator's inventory instead of walking the repo again; a digest is refused.
- `/kb` no longer loads the two contract skills in the orchestrator; scouts and writers load what they need.
- Run metrics: per-phase timings, fan-out and attempts are recorded in `manifest.json` (`perf`) and the local run record. `scripts/usage.sh` adds token usage and cost: exact for headless runs, and from the session transcript (main thread plus sub-agents, de-duplicated) for interactive ones. The upstream report is now an explicit allowlist, so none of this leaves the machine. `/kb-stats` shows it.
- `tools/bench.sh`: never reports telemetry, records cache-hit and phase timings, gates wall time and cache-hit rate (recall tolerance 0.05, cost +20%), and `--compare NEW BASE` evaluates the gate offline.
- `scripts/archetype.sh` classifies a repo (service, monorepo, library, infrastructure, contract) from the inventory; `templates/agent-context/` holds the matching `CLAUDE.md`/`AGENTS.md` seeds, including finished seeds for this project's three repos.

## [0.9.4] — 2026-10-01
- Generated reference renamed to `09-reference.md` (was `90-reference.md`; the old file is removed on regeneration).
- CKB brand icon and logo; README title "Codebase KB Engine — Codebase Knowledge Base Engine".
- Fixed run metrics and reports not being recorded on jq 1.7 (Linux).

## [0.9.3] — 2026-10-01
- Telemetry endpoint moved to `codebase-kb-telemetry.codebase-kb.workers.dev`.

## [0.9.2] — 2026-10-01
- Anonymous usage reports go live (relay endpoint configured).

## [0.9.1] — 2026-10-01
- Anonymous usage reports, on by default with a first-run notice; opt out with `telemetry off`, `CKB_TELEMETRY=off` or `DO_NOT_TRACK=1`.
- Warning categories reported as fixed IDs only.

## [0.9.0] — 2026-10-01
- Anonymous local run metrics; `/kb-stats` summary with opt-in, confirmed report submission.
- Maintainer tools: `tools/bench.sh` (pinned polyglot suite, route accuracy) and `tools/adoption.sh`.

## [0.8.2] — 2026-10-01
- CLI wrapper renamed from `repokb` to `codebase-kb-engine`.

## [0.8.1] — 2026-10-01
- `repokb` headless runs allow the Agent and Skill tools and use namespaced commands.
- `/kb` loads its skills after the freshness check; plugin scripts run as standalone commands.

## [0.8.0] — 2026-10-01
- Emits CKB v0.2: purl dependencies, artifacts, services, config keys, external services, API specs.
- Polyglot inventory and a coverage gate; parallel scouts; claim audit; self-improving feedback loop.
- Eight docs plus a generated reference; doc lint, parity check and front-matter.
- Guard hardening: git global options, `find`/`sort`/`sed`/`awk` write modes, environment overrides.
- Read-only mode arms only on `/kb` and `/kb-validate`.

## [0.7.0] — 2026-09-30
- KB folder is the visible `ckb/` (was `.ckb/`); legacy folders migrate automatically.

## [0.6.1] — 2026-09-30
- Spec repository renamed to `codebase-kb-spec`.
- Fixed manifest generation on jq 1.7.

## [0.6.0] — 2026-09-30
- KB is written inside the repo and committed by the user.
- Freshness check, citation verification, secret redaction.

## [0.5.0] — 2026-09-30
- First release as `codebase-kb-engine`: CKB v0.1 output, repo-URL mode, session-scoped read-only guard.
