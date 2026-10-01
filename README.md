# Codebase KB Engine

A Claude Code plugin that generates a **verifiable knowledge base inside any repository**, at `<repo>/ckb/`, ready to commit alongside the code. Generation is read-only: the plugin writes only to `ckb/` and never edits source or commits.

Each run produces, in `ckb/`:

| File | For | Contents |
|---|---|---|
| `00-overview.md` | people | Elevator pitch, executive summary, glossary, macro context |
| `01-technical-architecture.md` | people | Components, data model, interfaces, dependencies, deployment, non-functional posture (mermaid) |
| `02-functional-workflows.md` | people | Capabilities, actors, end-to-end workflows, state machines (mermaid) |
| `03-business-rules.md` | people | Rule catalog with enforcement sites and a traceability matrix |
| `04-system-context-and-gaps.md` | people | System-of-systems map, contracts exposed and consumed, risks, unknowns |
| **`ckb.json`** | machines | The same facts in the open **CKB v0.1** format ([spec](https://github.com/riddhimohansharma/codebase-kb-spec)) |
| `manifest.json` | machines | Job identity, status, output checksums, validation result, confidence roll-up |
| `README.md`, `.gitattributes` | GitHub | Browsable index; marks the directory as generated so PR diffs collapse it |

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

**Scope.** The gate arms for a session when you run `/kb`, `/kb-validate`, `/map`, `/hunt` or `/plan`, or when any of the plugin's scripts runs. Arming only ever adds restrictions, so the model may trigger it but can't undo it. Only a human-typed `/kb-unlock`, the end of the session, or 24 hours after arming disarms it. With `CKB_ENFORCE=always`, which the wrappers set, it cannot be disarmed until the session ends. **Sessions that never use the plugin are not affected at all.**

**While armed, the gate fails closed:**

| Action | Result |
|---|---|
| Write or Edit inside `<repo>/ckb/` (exactly that directory, at the work-tree root, carrying the `.ckb-output` marker) | allowed |
| Write or Edit in the URL-mode output dir (outside any work tree, carrying the marker) | allowed |
| Write or Edit anywhere else in the repo, including source, config, `.gitattributes`, a nested `src/ckb/`, look-alikes such as `.ckb-evil/`, `..` paths, and symlinks out of `ckb/` | **blocked** |
| Read, Grep, Glob, and read-only shell (`git status`, `git log`, `ls`, `cat`, `find`, `jq`, …) | allowed |
| Redirection to files, `rm`, `mv`, `cp`, `tee`, `sed -i`, installers, builds, `git commit/push/reset/…`, pipe-to-shell | **blocked** |
| The plugin's own scripts, matched by resolved real path (look-alikes are blocked) | allowed |
| Any tool not on the known read-only list, including MCP tools | **blocked** |

**Repo-URL mode contract.** Remote repos are shallow-cloned (`--depth 1`, no tags, hooks disabled, LFS smudge off) into a private sandbox (`$CKB_CLONE_BASE`, default `$TMPDIR/ckb-clones`). The clone's push URL is disabled and the gate also blocks `git push`, so **nothing is ever pushed to origin**. **No source is kept** beyond the short citations in the KB. **The clone is deleted when the job ends**, including after a failure, and the deletion is verified. URLs of the form `scheme://user:password@…` are refused. Don't pass a bare token as userinfo either; use your git credential helper or SSH. Credentials are also stripped from any URL recorded in `ckb.json`.

> Deletion is `rm -rf` followed by an existence check. On SSDs and APFS, overwriting blocks can't guarantee erasure, so the plugin doesn't pretend to. For sensitive code, use full-disk encryption (FileVault).

In headless URL mode, grant the sandbox so the analysis can read it: `CKB_CLONE_BASE=$HOME/.cache/ckb-clones claude -p "/kb <url>" --add-dir $HOME/.cache/ckb-clones --add-dir <kb-dir>`. Both directories must exist before launch.

## The machine artifact (`ckb.json`)

`ckb.json` conforms to **CKB v0.1**, an open, versioned spec. The schema and semantic rules are vendored in [`spec/v0.1/`](spec/v0.1/) and pinned to a codebase-kb-spec commit in `spec/v0.1/SOURCE`. The plugin reads nothing outside its own directory.

> CKB v0.1 is a **draft**: it may change incompatibly before 1.0. Every artifact declares `"ckb_version": "0.1"`.

The model writes a draft, and `scripts/finalize.sh` makes it trustworthy:

- **Stable IDs** are derived from normalized join keys (`interface:http:provides:GET:/users/{id}`, `dependency:npm:@org/pkg`, `datastore:postgres:public.orders`). Re-running on the same commit yields the same IDs, and the artifact differs only in `generated_at`.
- **Normalization:** `/users/:id`, `/users/[id]`, `/users/<int:id>` and `/users/${id}` all become `/users/{id}`. npm and cargo names are lowercased, pypi names follow PEP 503, version and extras suffixes are stripped, and an unprefixed name gets its ecosystem from its manifest file (`package.json` → `npm:`).
- **Integrity:** duplicate entities are merged with their provenance unioned. Draft IDs are remapped to final IDs, and references that don't resolve are dropped with a warning. **Every citation is checked against the real file and line**; any claim whose citations don't verify is downgraded to `unknown`. Enum values are coerced to the spec (for example `postgresql` becomes `postgres`). **Secret values copied from repo config are redacted.**
- **Validation:** the artifact is checked against the JSON Schema and semantic rules R1–R7 (unique IDs, prefixes, resolvable references, confidence counts, step order, line ranges, no self-citation). The result is recorded in `manifest.json` with `status` `complete`, `incomplete` or `invalid`.

## Other commands

| Command | What it does |
|---|---|
| `/map` | Three-altitude reconnaissance: strategy, architecture, execution |
| `/hunt [theme]` | Finds initiatives and ranks them by Leverage = (Value × Durability × Confidence) / Effort |
| `/plan <initiative>` | A five-step change plan and a unified diff as text. Nothing is applied |

All three are read-only and arm the gate like `/kb`.

## Local development

```bash
git clone https://github.com/riddhimohansharma/codebase-kb-engine && cd codebase-kb-engine
tests/guard.test.sh       # 86 safety checks (gate, resolver, clone sandbox)
tests/finalize.test.sh    # 53 conformance checks: normalization, IDs, determinism, freshness, R7, manifest
claude plugin validate .  # manifest checks
tools/sync-spec.sh --check # vendored spec matches codebase-kb-spec (pin in spec/v0.1/SOURCE)
claude --plugin-dir .     # load without installing
```

Optional wrapper (sets `CKB_ENFORCE=always` for the whole session): `bash bootstrap.sh`, then `repokb doctor`, `repokb kb ~/code/app`, or `repokb run ~/code/app`. Output always goes to `~/code/app/ckb/`; the wrapper's `--kb-dir` applies only to URL mode.

Security issues: see [SECURITY.md](SECURITY.md). Contributing: [CONTRIBUTING.md](CONTRIBUTING.md).

**Known limits:** the gate parses shell text, so it's a strong guard, not a sandbox; for untrusted code, also use Claude Code's sandbox mode. Paths containing spaces in the plugin's install location will fail closed (blocked), not open.

## License

[MIT](LICENSE) © 2026 Riddhi Mohan Sharma
