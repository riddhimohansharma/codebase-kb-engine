# Codebase KB Engine

A Claude Code plugin that generates a **verifiable knowledge base for any repository** and never modifies the repository.

Each run produces:

| File | For | Contents |
|---|---|---|
| `00-overview.md` | people | Elevator pitch, executive summary, glossary, macro context |
| `01-technical-architecture.md` | people | Components, data model, interfaces, dependencies, deployment, non-functional posture (mermaid) |
| `02-functional-workflows.md` | people | Capabilities, actors, end-to-end workflows, state machines (mermaid) |
| `03-business-rules.md` | people | Rule catalog with enforcement sites and a traceability matrix |
| `04-system-context-and-gaps.md` | people | System-of-systems map, contracts exposed and consumed, risks, unknowns |
| **`ckb.json`** | machines | The same facts in the open **CKB v0.1** format ([spec](https://github.com/riddhimohansharma/ckb-spec)) |
| `manifest.json` | machines | Job identity, status, output checksums, validation result, confidence roll-up |

Every claim cites `path:line` and carries a confidence level: **confirmed** (stated at the cited line), **inferred** (derived from structure), or **unknown** (looked for, not determinable). Nothing inferred is presented as fact.

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
mkdir -p ../myrepo-kb && claude -p "/kb" --add-dir ../myrepo-kb --output-format json
```

The JSON output includes token usage. `manifest.json` records `token_usage: null` because a session can't observe its own usage.

### Where output goes

1. `$KB_DIR` if set, otherwise
2. a sibling of the repo: `../<repo-name>-kb/`. In URL mode, the sibling is placed next to your current git work tree (or inside the current directory if you're not in one).

The KB is **never written inside the analysed repo**, and the resolver refuses to try. If Claude Code hasn't been granted the output directory, `/kb` prints one line to copy, for example `mkdir -p /path/to/myrepo-kb && claude --add-dir /path/to/myrepo-kb`, and stops. The only thing it leaves behind is the empty, marked output directory, which is created on purpose because Claude Code ignores `--add-dir` for a path that doesn't exist yet. An existing, non-empty directory is used only if it carries the `.ckb-output` marker, so an unrelated folder can't be overwritten.

## Safety model

"Read-only" is enforced by a hook, not merely requested in a prompt.

**Scope.** The gate arms for a session when you run `/kb`, `/kb-validate`, `/map`, `/hunt` or `/plan`, or when any of the plugin's scripts runs. Arming only ever adds restrictions, so the model may trigger it but can't undo it. Only a human-typed `/kb-unlock`, or the end of the session, disarms it. **Sessions that never use the plugin are not affected at all.**

**While armed, the gate fails closed:**

| Action | Result |
|---|---|
| Write or Edit inside a `.ckb-output` directory | allowed |
| Write or Edit anywhere else, including the analysed repo, the session's work tree, `..` paths, and symlinks that escape the KB directory | **blocked** |
| Read, Grep, Glob, and read-only shell (`git status`, `git log`, `ls`, `cat`, `find`, `jq`, …) | allowed |
| Redirection to files, `rm`, `mv`, `cp`, `tee`, `sed -i`, installers, builds, `git commit/push/reset/…`, pipe-to-shell | **blocked** |
| The plugin's own scripts, matched by resolved real path (look-alikes are blocked) | allowed |
| Any tool not on the known read-only list, including MCP tools | **blocked** |

**Repo-URL mode contract.** Remote repos are shallow-cloned (`--depth 1`, no tags, hooks disabled, LFS smudge off) into a private sandbox (`$CKB_CLONE_BASE`, default `$TMPDIR/ckb-clones`). The clone's push URL is disabled and the gate also blocks `git push`, so **nothing is ever pushed to origin**. **No source is kept** beyond the short citations in the KB. **The clone is deleted when the job ends**, including after a failure, and the deletion is verified. URLs with embedded credentials (`https://user:token@…`) are refused; use your git credential helper or SSH. Credentials are also stripped from any URL recorded in `ckb.json`.

> Deletion is `rm -rf` followed by an existence check. On SSDs and APFS, overwriting blocks can't guarantee erasure, so the plugin doesn't pretend to. For sensitive code, use full-disk encryption (FileVault).

In headless URL mode, grant the sandbox so the analysis can read it: `CKB_CLONE_BASE=$HOME/.cache/ckb-clones claude -p "/kb <url>" --add-dir $HOME/.cache/ckb-clones --add-dir <kb-dir>`. Both directories must exist before launch.

## The machine artifact (`ckb.json`)

`ckb.json` conforms to **CKB v0.1**, an open, versioned spec. The schema and semantic rules are vendored in [`spec/v0.1/`](spec/v0.1/) and pinned to a ckb-spec commit in `spec/v0.1/SOURCE`. The plugin reads nothing outside its own directory.

> CKB v0.1 is a **draft**: it may change incompatibly before 1.0. Every artifact declares `"ckb_version": "0.1"`.

The model writes a draft, and `scripts/finalize.sh` makes it trustworthy:

- **Stable IDs** are derived from normalized join keys (`interface:http:provides:GET:/users/{id}`, `dependency:npm:@org/pkg`, `datastore:postgres:public.orders`). Re-running on the same commit yields the same IDs, and the artifact differs only in `generated_at`.
- **Normalization:** `/users/:id`, `/users/[id]`, `/users/<int:id>` and `/users/${id}` all become `/users/{id}`. npm and pypi names are canonicalized (PEP 503 for pypi).
- **Integrity:** duplicate entities are merged with their provenance unioned. References are resolved, and dangling or malformed references are dropped with a warning. Any claim without a valid citation is **downgraded to `unknown`**.
- **Validation:** the artifact is checked against the JSON Schema and semantic rules R1–R6 (unique IDs, prefixes, resolvable references, confidence counts, step order, line ranges). The result is recorded in `manifest.json` with `status` `complete`, `incomplete` or `invalid`.

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
tests/guard.test.sh       # 66 safety checks (gate, resolver, clone sandbox)
tests/finalize.test.sh    # conformance: normalization, IDs, determinism, validation, manifest
claude plugin validate .  # manifest checks
tools/sync-spec.sh --check # vendored spec matches ckb-spec (pin in spec/v0.1/SOURCE)
claude --plugin-dir .     # load without installing
```

Optional wrapper (sets `CKB_ENFORCE=always` for the whole session): `bash bootstrap.sh`, then `repokb doctor`, `repokb kb ~/code/app`, or `repokb run ~/code/app`.

Security issues: see [SECURITY.md](SECURITY.md). Contributing: [CONTRIBUTING.md](CONTRIBUTING.md).

**Known limits:** the gate parses shell text, so it's a strong guard, not a sandbox; for untrusted code, also use Claude Code's sandbox mode. Paths containing spaces in the plugin's install location will fail closed (blocked), not open.

## License

[MIT](LICENSE) © 2026 Riddhi Mohan Sharma
