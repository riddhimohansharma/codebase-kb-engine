# Codebase KB Engine

A Claude Code plugin that generates a **verifiable knowledge base inside any repository**, at `<repo>/ckb/`, ready to commit alongside the code. Generation is read-only: the plugin writes only to `ckb/` and never edits source or commits.

Each run produces, in `ckb/`:

| File | For | Contents |
|---|---|---|
| `00-overview.md` | everyone | Summary, glossary, ownership, macro context |
| `01-technical-architecture.md` | engineers, architects | **C4** containers and components, data model (ERD), interfaces, dependencies, configuration reference, deployment, non-functional posture |
| `02-functional-workflows.md` | product, engineers | Capabilities, actors, end-to-end workflows (sequence diagrams), state machines |
| `03-business-rules.md` | product, QA | Rule catalog (ID, statement, rationale, trigger, outcome, exceptions, enforcement site) and traceability |
| `04-system-context-and-gaps.md` | architects | **C4** system context, contracts exposed and consumed, risks, open questions |
| `05-operations.md` | ops, on-call | Build, run locally, test, deploy and environments, observability, alerts and failure modes, rollback |
| `06-security-and-data.md` | security | Trust boundaries, AuthN/AuthZ, data classification, secrets inventory (names only), findings |
| `07-decisions.md` | architects | Evidence-based decision log (ADR-lite) |
| `90-reference.md` | everyone, tools | Generated tables from `ckb.json`: interfaces, dependencies, artifacts, services, datastores, config, external services, API specs, relations |
| **`ckb.json`** | machines | The same facts in the open **CKB v0.2** format ([spec](https://github.com/riddhimohansharma/codebase-kb-spec)), built for cross-repo graphs |
| `manifest.json` | machines | Job identity, status, coverage, output checksums, validation (schema, rules, doc lint), confidence roll-up |
| `README.md`, `.gitattributes`, `.gitignore` | GitHub | Browsable index; generated-file marking; keeps transient files out of commits |

Every claim cites `path:line` and carries a confidence level: **confirmed** (stated at the cited line), **inferred** (derived from structure), or **unknown** (looked for, not determinable). Nothing inferred is presented as fact.

**Full documentation: [User Manual](docs/USER_MANUAL.md)**, covering commands, output reference, freshness, URL mode, CI, safety, configuration and troubleshooting.

## Install

```text
/plugin marketplace add riddhimohansharma/codebase-kb-engine
/plugin install codebase-kb-engine@codebase-kb-engine
```

From a terminal: `claude plugin marketplace add riddhimohansharma/codebase-kb-engine && claude plugin install codebase-kb-engine@codebase-kb-engine`. Updates arrive when the plugin version changes: `/plugin marketplace update codebase-kb-engine`.

**Requirements:** Claude Code, `git`, `jq` 1.6 or later, and [`uv`](https://docs.astral.sh/uv/) (optional, strongly recommended). Without `uv`, the JSON Schema check in `/kb-validate` is reported as **SKIPPED**, never as passed.

## Use

```text
/kb                                   # analyse the repo you're in
/kb billing                           # same, weighted toward a subsystem
/kb https://github.com/org/repo       # analyse a remote repo (default branch detected, not assumed)
/kb git@github.com:org/repo.git dev   # a specific branch
/kb-validate                          # check the generated ckb.json against the spec
/kb-unlock                            # leave read-only mode for this session
```

Headless:

```bash
claude -p "/codebase-kb-engine:kb" --output-format json      # ckb/ is inside the repo: no --add-dir needed
```

The JSON output includes token usage. `manifest.json` records `token_usage: null` because a session can't observe its own usage.

### Where output goes: `ckb/`, committed with the code

The KB lives at **`<repo-root>/ckb/`**, the canonical location in the [CKB spec](https://github.com/riddhimohansharma/codebase-kb-spec), so every repo's knowledge base is found the same way:

```bash
/kb                                         # writes ckb/, prints the commit command
git add ckb && git commit -m "docs(ckb): knowledge base for <sha>"    # you (or CI) commit; the plugin never does
```

- **Freshness.** `ckb.json` records the analysed source commit. The KB is **fresh** while nothing outside `ckb/` has changed since then, so committing `ckb/` itself never makes it stale. `/kb` checks this first and **skips regeneration when the KB is fresh**; use `/kb --force` to regenerate anyway. `/kb-validate` reports freshness too.
- **No self-contamination.** Analysis ignores `ckb/`, and any citation that points into it is dropped (spec rule R7).
- **Uncommitted changes** outside `ckb/` are allowed but flagged: the manifest records `dirty_worktree: true`. Commit source first for an exact match.
- **URL mode** (`/kb <url>`) analyses a repo you're not working in. Output goes to `$KB_DIR`, or `<name>-ckb/` next to your current work tree, using the same layout. It is never committed, because the clone is deleted.
- An existing, non-empty `ckb/` without the `.ckb-output` marker is never overwritten, and a symlinked `ckb` is refused.

## Safety model

"Read-only" is enforced by a hook, not merely requested in a prompt.

**Scope.** The gate arms for a session when you run `/kb` or `/kb-validate` (also as `/codebase-kb-engine:kb…`), or when any of the plugin's scripts runs. Commands from other plugins with similar names, such as another `/plan`, never arm it. Arming only ever adds restrictions, so the model may trigger it but can't undo it. Only a human-typed `/kb-unlock`, the end of the session, or 24 hours after arming disarms it. With `CKB_ENFORCE=always`, which the wrappers set, it cannot be disarmed until the session ends. **Sessions that never use the plugin are not affected at all.**

**While armed, the gate fails closed:**

| Action | Result |
|---|---|
| Write or Edit inside `<repo>/ckb/` (exactly that directory, at the work-tree root, carrying the `.ckb-output` marker) | allowed |
| Write or Edit in the URL-mode output dir (outside any work tree, carrying the marker) | allowed |
| Write or Edit anywhere else in the repo, including source, config, `.gitattributes`, a nested `src/ckb/`, look-alikes such as `.ckb-evil/`, `..` paths, and symlinks out of `ckb/` | **blocked** |
| Read, Grep, Glob, and read-only shell (`git status`, `git log`, `ls`, `cat`, `find`, `jq`, …) | allowed |
| Redirection to files, `rm`, `mv`, `cp`, `tee`, `sed -i`, installers, builds, any git write (including `git -C … commit` and `git -c …` overrides), `find -delete/-exec`, `sort -o`, `sed w/e`, `awk system()`, code-running env overrides (`GIT_*`, `PAGER`, `LD_PRELOAD`, …), pipe-to-shell | **blocked** |
| The plugin's own scripts, matched by resolved real path (look-alikes are blocked) | allowed |
| Any tool not on the known read-only list, including MCP tools | **blocked** |

**Repo-URL mode contract.** Remote repos are shallow-cloned (`--depth 1`, no tags, hooks disabled, LFS smudge off) into a private sandbox (`$CKB_CLONE_BASE`, default `$TMPDIR/ckb-clones`). The clone's push URL is disabled and the gate also blocks `git push`, so **nothing is ever pushed to origin**. **No source is kept** beyond the short citations in the KB. **The clone is deleted when the job ends**, including after a failure, and the deletion is verified. URLs of the form `scheme://user:password@…` are refused. Don't pass a bare token as userinfo either; use your git credential helper or SSH. Credentials are also stripped from any URL recorded in `ckb.json`.

> Deletion is `rm -rf` followed by an existence check. On SSDs and APFS, overwriting blocks can't guarantee erasure, so the plugin doesn't pretend to. For sensitive code, use full-disk encryption (FileVault).

In headless URL mode, grant the sandbox so the analysis can read it: `CKB_CLONE_BASE=$HOME/.cache/ckb-clones claude -p "/kb <url>" --add-dir $HOME/.cache/ckb-clones --add-dir <kb-dir>`. Both directories must exist before launch.

## The machine artifact (`ckb.json`): graph-ready, polyglot

`ckb.json` conforms to **CKB v0.2**, an open, versioned spec. The schema, the semantic rules and the normative ID derivation (`derive.jq`) are vendored in [`spec/v0.2/`](spec/v0.2/) and pinned in `spec/v0.2/SOURCE`. v0.1 is still vendored, so older artifacts keep validating. The plugin reads nothing outside its own directory.

> CKB 0.x is a **draft**: it may change incompatibly before 1.0. Every artifact declares its `ckb_version`.

**What a consumer can build from many repos' `ckb.json`:**

| Question | Join |
|---|---|
| Which repos depend on package X, and which repo **builds** X? | `dependencies[].purl` ↔ `artifacts[].purl`. Package URLs (purl) cover npm, PyPI, Maven, Go, Cargo, NuGet, RubyGems, Composer, pub, Hex, CocoaPods, SwiftPM, Conan, Hackage, CRAN, Julia, LuaRocks, conda, Docker images, GitHub Actions, Terraform and Helm |
| Who calls this endpoint? | `interfaces` (provides: `service_key` + method + path) ↔ (consumes: `http.host` + method + path) |
| Who publishes or consumes this topic? | `event.transport` + `event.topic` |
| Who reads or writes this table? | `datastore` engine + instance + schema + table |
| What runs where, configured how, calling which SaaS? | `services`, `config_keys` (names only), `external_services`, `api_specs` |

Relations come from a fixed table of allowed `(from, kind, to)` triples (`provides`, `consumes`, `depends_on`, `builds`, `deploys_as`, `reads`, `writes`, `configured_by`, `uses_external`, `specified_by`, …), so every edge has a known meaning.

**The model writes a draft, and `scripts/finalize.sh` makes it trustworthy:**
- **Coverage:** a deterministic inventory of the repo (30+ manifest types, 20+ web frameworks, events, ORMs, migrations, IaC, CI, config, API specs; generated and vendored code excluded) is compared with what the KB cites. **A manifest that no dependency cites keeps the KB `incomplete`.**
- **Stable IDs** come from the spec's `derive.jq`. Re-running on the same commit changes only `generated_at`.
- **Normalization:**
  - Route params from every framework become `{param}`, and multi-method routes split into one entity per method.
  - Outbound hosts are normalized (`USER_SERVICE_URL` → `user-service`, and `.svc.cluster.local` is dropped).
  - Topic ARN and URL forms are reduced to the name.
  - ORM identifiers are unquoted and default schemas dropped.
  - purls are canonicalized per ecosystem.
- **Integrity:**
  - Every citation is checked against the real file and line, and unverifiable claims are downgraded to `unknown`.
  - Disallowed relations, unresolved references and config values are dropped, with warnings.
  - Secret values are redacted.
- **Docs quality:**
  - All 8 docs are linted for required sections, diagrams, confidence tags and size.
  - Rule and workflow names must match between the docs and `ckb.json`.
  - Deterministic front-matter (source commit, confidence, freshness command) and stable anchors keyed to entity IDs are injected for RAG and citation.
- **Validation:** the JSON Schema plus rules R1–R12. Status is `complete` only if all of the above pass; otherwise `incomplete`, `invalid` or `unverified`.

## Other commands

| Command | What it does |
|---|---|
| `/map` | Three-altitude reconnaissance: strategy, architecture, execution |
| `/hunt [theme]` | Finds initiatives and ranks them by Leverage = (Value × Durability × Confidence) / Effort |
| `/plan <initiative>` | A five-step change plan and a unified diff as text. Nothing is applied |

All three are read-only by instruction. They don't arm the gate, because short names like `/plan` collide with other plugins.

## Local development

```bash
git clone https://github.com/riddhimohansharma/codebase-kb-engine && cd codebase-kb-engine
tests/guard.test.sh       # 125 safety checks (gate, bypass regressions, arming scope, resolver, clone sandbox)
tests/finalize.test.sh    # 71 conformance checks: golden end-to-end KB, polyglot normalization, failure paths, freshness
tests/docs.test.sh        # 98 doc-quality checks: lint rules, parity, front-matter, reference
tests/inventory.test.sh   # 50 recon checks: polyglot inventory, exclusions, workspaces, coverage
claude plugin validate .  # manifest checks
tools/sync-spec.sh --check # vendored spec matches codebase-kb-spec (pin in spec/v0.1/SOURCE)
claude --plugin-dir .     # load without installing
```

Optional wrapper (sets `CKB_ENFORCE=always` for the whole session): `bash bootstrap.sh`, then `repokb doctor`, `repokb kb ~/code/app`, or `repokb run ~/code/app`. Output always goes to `~/code/app/ckb/`; the wrapper's `--kb-dir` applies only to URL mode.

Security issues: see [SECURITY.md](SECURITY.md). Contributing: [CONTRIBUTING.md](CONTRIBUTING.md).

**Known limits:** the gate parses shell text, so it's a strong guard, not a sandbox; for untrusted code, also use Claude Code's sandbox mode. Paths containing spaces in the plugin's install location will fail closed (blocked), not open.

## License

[MIT](LICENSE) © 2026 Riddhi Mohan Sharma
