# Changelog

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
- License changed to PolyForm Shield 1.0.0.
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
