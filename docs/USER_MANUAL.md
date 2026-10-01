# Codebase KB Engine: User Manual

Version 0.6.0 · CKB format v0.1 (draft)

1. [What it does](#1-what-it-does)
2. [Concepts](#2-concepts)
3. [Install, update, uninstall](#3-install-update-uninstall)
4. [Quick start](#4-quick-start)
5. [Commands](#5-commands)
6. [Output reference](#6-output-reference)
7. [Freshness and committing the KB](#7-freshness-and-committing-the-kb)
8. [Analysing a remote repo (URL mode)](#8-analysing-a-remote-repo-url-mode)
9. [Automation: headless and CI](#9-automation-headless-and-ci)
10. [Safety model](#10-safety-model)
11. [Configuration](#11-configuration)
12. [Troubleshooting](#12-troubleshooting)
13. [FAQ](#13-faq)
14. [Limits](#14-limits)

---

## 1. What it does

Codebase KB Engine reads a repository and writes a **knowledge base into the repo itself**, at `.ckb/`, for you to commit alongside the code:

- **Five documents for people**: overview, technical architecture, functional workflows, business rules, and system context and gaps, with mermaid diagrams.
- **One artifact for machines**: `ckb.json`, in the open [CKB format](https://github.com/riddhimohansharma/ckb-spec). Tools can use it to answer questions across many repositories, such as "who calls this endpoint?", "which repos depend on this package?" or "who writes this table?"

Every claim cites the source line it came from (`path:line`) and is labelled **confirmed**, **inferred** or **unknown**. Citations are **checked against the real files**: a claim whose file or line doesn't exist is downgraded to `unknown`. Secret values from repo config that end up in the KB are **redacted** before anything is written. Generation is read-only: the plugin writes nothing except `.ckb/`, never edits source, and never commits.

## 2. Concepts

| Term | Meaning |
|---|---|
| **KB** | The contents of `<repo-root>/.ckb/` |
| **CKB** | The open, versioned format of `ckb.json`. The spec is vendored in `spec/` |
| **Claim** | A single fact in the KB, such as a route, dependency, table, rule or workflow |
| **Provenance** | The `path:line` citation(s) behind a claim. Paths are relative to the repo root |
| **Confidence** | `confirmed`: stated at the cited line. `inferred`: derived from structure or naming. `unknown`: looked for but not determinable |
| **Join key** | A normalized identifier that is the same across repos. For example, `GET /users/{id}` is the same whether the code wrote it as `:id`, `[id]`, `<int:id>` or `${id}` |
| **Freshness** | Whether the KB still describes the code. See [§7](#7-freshness-and-committing-the-kb) |
| **Armed session** | A session in which the read-only gate is enforcing. See [§10](#10-safety-model) |

## 3. Install, update, uninstall

**Requirements:** Claude Code, `git`, `jq` 1.6 or later, and [`uv`](https://docs.astral.sh/uv/) (recommended; without it, schema validation is reported as *skipped*).

**Install** (in Claude Code):
```text
/plugin marketplace add riddhimohansharma/codebase-kb-engine
/plugin install codebase-kb-engine@codebase-kb-engine
```
From a terminal:
```bash
claude plugin marketplace add riddhimohansharma/codebase-kb-engine
claude plugin install codebase-kb-engine@codebase-kb-engine
```

**Update:** new versions are picked up when the plugin version changes. Run `/plugin marketplace update codebase-kb-engine`, then restart Claude Code.

**Uninstall:** `/plugin uninstall codebase-kb-engine@codebase-kb-engine`. Your committed `.ckb/` directories stay in their repos.

## 4. Quick start

```text
cd your-repo
claude
> /kb
```
When it finishes:
```bash
git add .ckb && git commit -m "docs(ckb): knowledge base for <sha>"
```
Open `.ckb/README.md` on GitHub to browse the KB. Run `/kb` again at any time: if no source has changed, it tells you the KB is fresh and does nothing.

## 5. Commands

### `/kb [--force] [focus]`: generate the KB for the current repo

**Steps:**
1. Resolves `<repo-root>/.ckb/` and refuses unsafe locations (see [§12](#12-troubleshooting)).
2. **Checks freshness.** If the committed KB still describes the source, it stops and writes nothing. `--force` regenerates anyway.
3. Warns if you have uncommitted changes outside `.ckb/`.
4. Analyses the repo read-only, with `.ckb/` excluded.
5. Writes the 5 docs and a draft artifact.
6. Finalizes: derives IDs, normalizes join keys, merges duplicates, drops invalid citations, validates, and writes `ckb.json`, `manifest.json`, `README.md` and `.gitattributes`.
7. Prints `STATUS=…`, a summary, the top 3 unknowns to verify, and the **commit command**. It does not run that command.

**Focus:** `/kb billing` still writes all five documents but weights them toward that subsystem.

**Status values:**

| Status | Meaning | What to do |
|---|---|---|
| `complete` | All outputs present, artifact valid | Commit `.ckb/` |
| `incomplete` | A document is missing | Re-run `/kb --force` |
| `unverified` | Schema check skipped (`uv` not installed) | Install uv and re-run |
| `invalid` | The candidate failed validation after 2 repair attempts. It is saved as `ckb.json.rejected`, and a previous good `ckb.json` is kept | See `manifest.json` → `validation.messages`, and report it if it recurs |

### `/kb <repo-url> [branch] [focus]`: analyse a remote repo

See [§8](#8-analysing-a-remote-repo-url-mode).

### `/kb-validate [path/to/ckb.json]`: check an artifact

Defaults to `<repo-root>/.ckb/ckb.json`. It reports one row per check (JSON Schema, then rules R1–R7) plus freshness. It never reports a skipped check as a pass.

| Rule | Checks |
|---|---|
| Schema | Structure, enums and join-key formats (needs `uv`) |
| R1 | Entity IDs are unique |
| R2 | Each ID prefix matches its collection |
| R3 | Every reference resolves |
| R4 | `confidence_summary` counts match the claims |
| R5 | Workflow steps are numbered 1..n |
| R6 | `end_line` ≥ `line` |
| R7 | Nothing cites or describes `.ckb/` |

### `/kb-unlock`: leave read-only mode

This releases the gate for the current session. Only a message **you** type can do this; the model cannot. It has no effect when `CKB_ENFORCE=always` is set (the wrapper sessions). The next engine command re-arms the gate.

### `/map`, `/hunt [theme]`, `/plan <initiative>`: analysis helpers

- `/map` is three-altitude reconnaissance: strategy, architecture and execution.
- `/hunt` ranks improvement initiatives by Leverage = (Value × Durability × Confidence) / Effort.
- `/plan` produces a five-step change plan and a unified diff **as text**.

All three are read-only and arm the gate.

## 6. Output reference

```
.ckb/
├── README.md                       index (deterministic; safe to commit)
├── 00-overview.md                  summary, glossary, macro context
├── 01-technical-architecture.md    components, data model, interfaces, dependencies, deployment
├── 02-functional-workflows.md      capabilities, actors, workflows, state machines
├── 03-business-rules.md            rule catalog, enforcement sites, traceability
├── 04-system-context-and-gaps.md   system map, contracts, risks, unknowns
├── ckb.json                        CKB v0.1 artifact
├── manifest.json                   job record
├── .gitattributes                  marks the directory linguist-generated (collapsed in PR diffs)
└── .ckb-output                     static marker the safety gate recognises
```

### `ckb.json`

| Field | Contents |
|---|---|
| `ckb_version` | `"0.1"` |
| `repo` | `url` (credentials stripped), `branch`, `commit_sha` (the **analysed** commit), `generated_at` |
| `generator` | `{name: "codebase-kb-engine", version}` |
| `confidence_summary` | Counts per level plus an `overall` roll-up |
| `entities.components` | Modules and services: `module_id`, `kind`, `language` |
| `entities.interfaces` | HTTP routes (`method`, `normalized_path`), events (`transport`, `topic`), RPC, CLI and library, each with `role` `provides` or `consumes` |
| `entities.dependencies` | Direct manifest dependencies as `package_key` (`npm:…`, `pypi:…`, `maven:g:a`, `go:…`, `cargo:…`, `nuget:…`, `gem:…`, `other:…`), with `scope`. npm and cargo names are lowercased, pypi follows PEP 503, and versions and extras are stripped |
| `entities.datastores` | `engine`, `schema`, `table`, `access` |
| `entities.business_rules` | `statement` and `applies_to`. Names match `03-business-rules.md` |
| `entities.workflows` | Ordered `steps` pointing at entities. Names match `02-functional-workflows.md` |
| `relations` | Edges within the repo (`calls`, `reads`, `writes`, `publishes`, …) |

**Entity IDs are deterministic**, for example `interface:http:provides:GET:/orders/{order_id}` or `dependency:npm:express`. Regenerating at the same commit changes only `generated_at`.

### `manifest.json`

`ckb_version` · `job` (id, mode, timestamps, generator) · `status` (`complete`, `incomplete`, `invalid` or `unverified`) · `repo` (plus `dirty_worktree`) · `outputs` for the 5 docs and `ckb.json` (file, sha256 or `null`, bytes, present) · `validation` (structural, semantic, messages) · `confidence_summary` · `entity_counts` · `warnings` (for example, claims downgraded to `unknown` for lack of a valid citation) · `token_usage` (always `null`) and `token_usage_note` (see [§9](#9-automation-headless-and-ci)).

## 7. Freshness and committing the KB

`ckb.json` records the **source commit that was analysed**. Committing `.ckb/` creates a new commit, and that's expected.

> **The KB is fresh at commit `Y` if and only if nothing outside `.ckb/` changed between the analysed commit and `Y`:**
> `git diff --quiet <commit_sha> Y -- . ':(exclude).ckb'`

| Result | Meaning | `/kb` does |
|---|---|---|
| `fresh` | The source is unchanged since analysis | Skips (use `--force` to regenerate) |
| `stale` | Source files changed | Regenerates |
| `unknown` | The analysed commit is missing or isn't an ancestor (rebased or force-pushed history) | Regenerates |
| `none` | No KB yet | Generates |

Check it yourself with `"<plugin>/scripts/freshness.sh" .`, or with `/kb-validate`. Exit codes: 0 fresh · 1 stale · 3 unknown · 4 no artifact · 2 usage.

The plugin is stricter than the spec rule when deciding to skip:
- **Uncommitted source changes** count as stale (`REASON=dirty-worktree`).
- A **last run that wasn't `complete`** gives `unknown`, so it regenerates.
- A **shallow clone** missing the analysed commit says so (`REASON=shallow-clone`); deepen it with `git fetch --deepen=200`.
- A **plugin upgrade** doesn't make the KB stale (see `NOTE=` in the output); run `/kb --force` after upgrading if you want the new generator's output.

Other exit codes: `validate.sh` 0 pass · 1 fail · 2 usage. `finalize.sh` 0 complete · 1 invalid, incomplete or unverified · 2 precondition.

**Recommended workflow:**
- Generate on your **default branch** after merges, then commit `.ckb/` in its own commit. This avoids merge conflicts in generated files.
- Keep `.ckb/` changes out of feature PRs. `.gitattributes` collapses them in GitHub diffs anyway.
- Commit your source before running `/kb`, so `dirty_worktree` is `false` and the KB matches `commit_sha` exactly.

## 8. Analysing a remote repo (URL mode)

```text
/kb https://github.com/org/repo            # default branch detected, not assumed
/kb git@github.com:org/repo.git release    # a specific branch
```

**Process:**
1. The repo is shallow-cloned (`--depth 1`, no tags, git hooks disabled, LFS skipped) into a private sandbox: `$CKB_CLONE_BASE`, or by default `$TMPDIR/ckb-clones`.
2. The clone's push URL is disabled, and the gate also blocks `git push`.
3. The same analysis runs.
4. The output goes to `$KB_DIR`, or to `<name>-ckb/` next to your current git work tree (or inside the current directory if you're not in one).
5. **The clone is deleted, even if the job fails**, and the deletion is verified.

URLs of the form `scheme://user:password@…` are refused. Don't pass a bare token as userinfo either; use your git credential helper or SSH instead. URL-mode output isn't committed anywhere. To put a KB into that repo, clone it yourself and run `/kb` inside it.

## 9. Automation: headless and CI

**Headless, local repo:**
```bash
cd your-repo
claude -p "/codebase-kb-engine:kb" --permission-mode acceptEdits \
  --allowedTools "Read,Grep,Glob,Bash,Write,Edit,Task,Agent,Skill,TodoWrite" \
  --output-format json > kb-run.json
jq -r '.result' kb-run.json            # summary, STATUS line, commit hint
jq '.total_cost_usd, .usage' kb-run.json   # token usage and cost (not visible from inside the session)
```
`.ckb/` is inside the working directory, so no `--add-dir` is needed. **In headless mode, use the namespaced form `/codebase-kb-engine:kb`.** In testing, the short `/kb` occasionally reached the model as plain text instead of running the command.

**Headless, URL mode:** both directories must exist before launch, because Claude Code ignores `--add-dir` for missing paths:
```bash
mkdir -p ~/.cache/ckb-clones ~/ckb/repo-ckb
CKB_CLONE_BASE=~/.cache/ckb-clones KB_DIR=~/ckb/repo-ckb \
  claude -p "/codebase-kb-engine:kb https://github.com/org/repo" --add-dir ~/.cache/ckb-clones --add-dir ~/ckb/repo-ckb \
  --permission-mode acceptEdits --allowedTools "Read,Grep,Glob,Bash,Write,Edit,Task,Agent,Skill,TodoWrite"
```

**CI pattern** (keeping many repos' KBs current). This is an example to adapt, not a supported action:
1. On pushes to the default branch, install Claude Code and this plugin (the commands in [§3](#3-install-update-uninstall)).
2. Run the headless command above. If the KB is fresh, it exits quickly without writing.
3. If `.ckb/` changed, commit it on a bot branch and open a PR, or commit it directly if your policy allows.

The freshness check is what keeps this cheap at scale: unchanged repos cost one short run.

## 10. Safety model

**When the gate is armed:**
- Typing `/kb`, `/kb-validate`, `/map`, `/hunt` or `/plan` arms it.
- The first run of any plugin script arms it.
- The local wrappers arm it for the whole session by setting `CKB_ENFORCE=always`.

**Disarming:** a human-typed `/kb-unlock`, the end of the session, or 24 hours after arming. With `CKB_ENFORCE=always` (the wrappers), `/kb-unlock` **cannot** disarm the gate; end the session instead. **Sessions that never use the plugin are unaffected.**

**While armed:**

| Action | Result |
|---|---|
| Write or Edit inside `<work-tree>/.ckb/` (exactly that path, carrying the marker) | allowed |
| Write or Edit anywhere else, including source, config, a nested `src/.ckb/`, look-alikes such as `.ckb-evil/`, `..` paths, and symlinks out of `.ckb/` | **blocked** |
| Read, Grep, Glob, and read-only shell (`git status`, `git log`, `ls`, `cat`, `find`, `jq`, …) | allowed |
| Redirects to files, `rm`, `mv`, `cp`, `tee`, `sed -i`, installers, builds, any git write (`commit`, `push`, `reset`, …), and pipe-to-shell | **blocked** |
| The plugin's own scripts (checked by real path; look-alike copies are blocked) | allowed, with no approval prompt |
| Any other tool, including MCP tools | **blocked** |

A blocked action returns a message starting `BLOCKED by codebase-kb-engine read-only mode:` that explains why.

## 11. Configuration

| Variable | Used by | Effect |
|---|---|---|
| `KB_DIR` | URL mode only | Output directory. It must be outside any git work tree and outside the clone sandbox. It is ignored in local mode, which always uses `.ckb/` |
| `CKB_CLONE_BASE` | URL mode | Sandbox for clones (default `$TMPDIR/ckb-clones`) |
| `CKB_ENFORCE=always` | Gate | Arm for the whole session (the local wrappers set this) |
| `CLAUDE_PLUGIN_DATA` | Gate | Where arm state is kept (set by Claude Code) |

## 12. Troubleshooting

| Message | Cause | Fix |
|---|---|---|
| `is not inside a git work tree` | Local mode needs a git repo | `git init` **and make at least one commit**, or use URL mode |
| `is not a git work tree with a commit` | The repo has no commits | Make an initial commit |
| `REFUSED: unsupported URL scheme` | Not `https://`, `ssh://`, `git://` or `user@host:path` | Use one of those forms |
| `clone failed: <url>` | Bad URL or branch, or no access | Check the URL, the branch, and your git credentials |
| `KB dir … is inside the ephemeral clone` / `inside the clone sandbox` / `inside the git work tree` | `KB_DIR` (URL mode) points somewhere unsafe | Set `KB_DIR` outside any repo and outside `$CKB_CLONE_BASE` |
| `unsupported ckb_version` | The artifact is from another CKB version | Use a plugin version that matches it, or regenerate |
| `status: unverified` | `uv` missing, so the schema check couldn't run | Install uv; nothing is marked complete without the schema check |
| `.ckb is a symlink` / `exists and is not a directory` | Unsafe KB path | Replace it with a real directory |
| `exists, is non-empty, and is not a CKB output dir` | Someone else's `.ckb/` | Move it aside, or adopt it with `touch .ckb/.ckb-output` |
| `is not writable` | Filesystem permissions | Fix the permissions, or analyse a clone with `/kb <url>` |
| One line: `mkdir -p … && claude --add-dir …` | Claude Code wasn't granted write access to the output dir | Run that line and re-run `/kb` |
| `FRESHNESS=fresh` and nothing happened | The KB already matches the source | That's expected. Use `/kb --force` to regenerate |
| `STRUCTURAL=skipped` | `uv` not installed | Install [uv](https://docs.astral.sh/uv/) |
| Headless run replies that `/kb` isn't installed | The short name didn't resolve | Use `/codebase-kb-engine:kb` |
| `BLOCKED by codebase-kb-engine read-only mode` during normal work | The session was armed by a KB command | Type `/kb-unlock`, or start a new session |
| `REFUSED: URL embeds credentials` | A token in the URL | Use a credential helper or SSH |
| `status: incomplete` / `invalid` | A missing doc, or validation failed | `/kb --force`. Details are in `manifest.json` → `validation.messages` and `warnings` |

## 13. FAQ

**Does it send my code anywhere?** It runs inside Claude Code and reads files the same way Claude Code always does. The plugin adds no network calls. URL mode uses `git clone` with your own credentials.

**Why is `commit_sha` older than the commit that contains `.ckb/`?** It records the source commit that was analysed. See [§7](#7-freshness-and-committing-the-kb).

**Can I edit the generated docs?** Yes, but the next regeneration overwrites them. Put lasting notes somewhere outside `.ckb/`.

**Monorepos?** One KB per git work tree, at its root. Submodules get their own `.ckb/`.

**Is CKB stable?** Not yet. v0.1 is a draft and may change before 1.0, so pin the plugin version if other tooling depends on the format.

## 14. Limits

- The gate inspects shell command text. It is a strong guardrail, not an OS sandbox; for untrusted code, also enable Claude Code's sandbox mode.
- Hooks run with your user privileges, as all Claude Code plugin hooks do.
- Analysis quality depends on the model. Every claim is cited, and anything uncited is downgraded to `unknown`, so check the "top unknowns" list.
- Clone deletion is `rm -rf`. On SSDs, that doesn't guarantee physical erasure.
- If the plugin's install path contains spaces, the gate fails closed and blocks the scripts.
