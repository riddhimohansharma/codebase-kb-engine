# repository-kb-engine

A portable, **read-only** Claude Code plugin you point at any repository. Runs fully
locally (no network). A fail-closed hook blocks every edit/delete/install/build — its one
permitted write is a knowledge base under `KB_DIR`, outside the repo.

---

## Fast start (3 steps)

```bash
# 1. unzip into a FRESH parent folder (not one already named repository-kb-engine)
unzip -o repository-kb-engine.zip -d ~/tools

# 2. one command: fixes permissions, wires PATH (fish/zsh/bash), health-checks
bash ~/tools/repository-kb-engine/bootstrap.sh

# 3. open a NEW terminal, then:
repokb doctor
repokb kb /path/to/your-repo          # KB -> /path/to/your-repo-kb; repo untouched
```

That's it. Requires Claude Code + `jq` (`brew install jq`). `bootstrap.sh` self-heals the
executable bit, auto-corrects accidental double-nesting, and installs `repokb` to `~/.local/bin`.

**No PATH? / prefer explicit:** just call it by path — `~/tools/repository-kb-engine/repokb kb <repo>`.

---

## The `repokb` command

```
repokb kb    <repo> [focus]   Full knowledge base (headless) into KB_DIR
repokb map   <repo>           Tri-lens recon (headless)
repokb hunt  <repo> [theme]   Leverage-ranked initiatives (headless)
repokb plan  <repo> <what>    Five-step plan + patch as text (headless)
repokb run   <repo> [--...]   Interactive session (human)
repokb doctor                 Environment + engine health
repokb install [dir]          (Re)link repokb onto PATH; default ~/.local/bin
repokb help | version
```

Global: `--json` (machine-readable), `--dry-run` (print the command, don't run),
`--kb-dir DIR`. Env: `KB_DIR`, `REPOKB_MODEL`, `REPOKB_MAX_TURNS`.

- **Human:** `repokb run ~/code/app` → interactive; `/kb /map /hunt /plan` available.
- **AI / automation:** `repokb kb ~/code/app --json` → headless, no prompts, emits
  `STATUS=OK KB_DIR=... FILES=5` and a real exit code. Safety is unchanged — the
  `PreToolUse` hook fires in every permission mode, so pre-approving tools never lets a
  write escape `KB_DIR`.

---

## Usage guide (step-by-step)

**Setup** — see [Fast start](#fast-start-3-steps) above (unzip, `bootstrap.sh`, `repokb doctor`).

**Day-to-day**

1. Point it at a repo (read-only — nothing in the repo is ever touched):
   ```bash
   repokb kb ~/code/myapp
   ```
   Generates the 5 knowledge-base files into `~/code/myapp-kb` (sibling folder, auto-created).
2. Or run a narrower command depending on what you need:
   ```bash
   repokb map  ~/code/myapp                # tri-lens recon
   repokb hunt ~/code/myapp billing        # leverage-ranked initiatives, optionally scoped to a theme
   repokb plan ~/code/myapp "add caching"  # 5-step plan + patch, as text
   ```
3. Focus a KB run on one area instead of the whole repo:
   ```bash
   repokb kb ~/code/myapp billing
   ```
4. Interactive mode (human-in-the-loop, slash commands `/kb /map /hunt /plan` available):
   ```bash
   repokb run ~/code/myapp
   ```

**Automation / scripting**

5. Machine-readable output:
   ```bash
   repokb kb ~/code/myapp --json
   ```
6. Preview without executing (prints the exact `claude` command it would run):
   ```bash
   repokb kb ~/code/myapp --dry-run
   ```
7. Override output location or env:
   ```bash
   repokb kb ~/code/myapp --kb-dir /custom/path
   KB_DIR=/custom/path repokb kb ~/code/myapp
   REPOKB_MODEL=... REPOKB_MAX_TURNS=... repokb kb ~/code/myapp
   ```

**Checking results**

8. Read the KB output — see the five-file table below. Every claim cites `path:line`;
   legend `[C]` confirmed · `[I]` inferred · `[?]` unknown.
9. Exit code / status line tells you if it worked: `STATUS=OK KB_DIR=... FILES=5` on success.

**If something breaks** — see [Troubleshooting](#troubleshooting) below, or run `repokb doctor` /
`repokb help` any time.

---

## Knowledge base (`repokb kb`) — five files in `KB_DIR` (default `<repo>-kb`)

| File | Contents |
|---|---|
| `00-overview.md` | appname, KB metadata, summary, glossary, macro context. |
| `01-technical-architecture.md` | components, data model, interfaces/contracts, dependencies, runtime/deploy, non-functional (security/PHI/perf/reliability), mermaid. |
| `02-functional-workflows.md` | capabilities, actors, workflows (mermaid), state machines, integrations. |
| `03-business-rules.md` | rule catalog (rule → `path:line`), invariants, authz/compliance, traceability. |
| `04-system-context-and-gaps.md` | system-of-systems map, contracts exposed/consumed, boundaries, risks, to-verify. |

Every claim cites `path:line`; each doc carries a legend `[C]` confirmed · `[I]` inferred · `[?]` unknown. Micro + macro views.

---

## Package layout (one folder, files at the same level)

```
repository-kb-engine/
├── bootstrap.sh          one-shot setup
├── repokb                the CLI
├── run.sh                legacy interactive launcher
├── README.md
├── .claude-plugin/       plugin.json, marketplace.json
├── commands/             kb, map, hunt, plan
├── agents/               scout, auditor
├── skills/               kb, doctrine, leverage
└── hooks/                hooks.json, guard.sh   (fail-closed read-only gate)
```

The zip contains exactly this one folder. A stray `files.zip` or a second copy is not part
of the package — delete extras. Everything resolves relative to this folder; no hardcoded paths.

---

## Enforcement model

`hooks/guard.sh` runs on every `PreToolUse` (main agent + subagents):
- **Write/Edit/MultiEdit:** only inside `KB_DIR` (no `..`); anything else blocked. `NotebookEdit` blocked.
- **Deletes:** blocked everywhere.
- **Reads allowed:** `Read`, `Grep`, `Glob`, `WebFetch`, `WebSearch`, `Task`, `TodoWrite`, `BashOutput`.
- **Bash default-deny:** only read-only heads (`ls`, `cat`, `grep`, `rg`, `find`, `git` read-subcommands,
  `jq`, `awk`/`sed` without `-i`, …); blocks redirections (except `/dev`), in-place edits, destructive
  coreutils, package/build/deploy tools, pipe-to-shell, `$(...)`/loop bypasses.
- **Fails closed** on unparseable input or unknown tool/command — even without `jq`.

Boundary: a policy layer, not an OS sandbox. Keep interpreters (`python`/`node`/`ruby`/`perl`) off
the Bash allowlist for a hard guarantee.

## Troubleshooting

- `fish: Unknown command: repokb` → PATH not set: `bash bootstrap.sh` again, open a new terminal, or call by full path.
- `exists but is not an executable file` → `chmod +x <folder>/repokb <folder>/hooks/guard.sh`; or just `repokb doctor` self-heals the hook.
- `MISSING: …` in `doctor` → `repokb` isn't beside its components; you unzipped into a same-named folder (double-nested). Re-run `bootstrap.sh` (it auto-corrects) or point at the inner folder.

## Requirements
Claude Code · `jq` · macOS/Linux (`bash`; BSD-safe tools).
