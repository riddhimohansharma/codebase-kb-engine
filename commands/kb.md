---
description: Generate the repo's knowledge base in <repo>/ckb/ (8 docs + generated reference + CKB v0.2 ckb.json + manifest.json), ready to commit. Read-only toward the code; skips when the KB is already fresh.
argument-hint: "[--force] [<repo-url> [branch]] [focus]"
---
Produce the knowledge base for the target below. The code is READ-ONLY: the guard allows writes only inside the KB dir, and you never commit, push, or edit source.

Arguments: `$ARGUMENTS`

**Rule:** run each `${CLAUDE_PLUGIN_ROOT}/scripts/*` command **on its own**, never chained with `;`, `&&` or `|`. Plugin scripts are pre-approved only as standalone commands.

**1. Mode.** Remove a leading `--force` flag if present and remember it. If the next argument starts with `https://`, `http://`, `ssh://`, `git://`, or matches `user@host:path`, this is **URL mode**: the following argument (if present and it contains no spaces) is the branch, and anything after that is focus. Otherwise this is **local mode** (the standard): the target is the current git repo, the KB is `<repo-root>/ckb/`, and all arguments are focus.

**2. Target + output dir.** Run exactly one of:
- local: `"${CLAUDE_PLUGIN_ROOT}/scripts/resolve-kb.sh" .`
- URL: `"${CLAUDE_PLUGIN_ROOT}/scripts/clone.sh" clone "<url>" [branch]`, then note `JOB_DIR`, `CLONE_DIR`, `NAME`, `BRANCH` and `REPO_URL`. Then run `"${CLAUDE_PLUGIN_ROOT}/scripts/resolve-kb.sh" "<CLONE_DIR>" --url-mode --name "<NAME>"`.

If the output includes a `MIGRATED=` line, tell the user the legacy hidden `.ckb/` was renamed to `ckb/` and pass on its commit instruction. Record `REPO_ROOT`, `KB_DIR`, `ADD_DIR_HINT` and the start time (`date -u +%Y-%m-%dT%H:%M:%SZ`). If a script exits non-zero, show its message verbatim, run step 11 if in URL mode, and STOP.

**3. Freshness (local mode).** Run `"${CLAUDE_PLUGIN_ROOT}/scripts/freshness.sh" "<REPO_ROOT>"`.
- If it prints `FRESHNESS=fresh` and `--force` was not given, report that the committed KB already describes the current source (quote the line) and STOP without writing anything.
- If it prints `FRESHNESS=stale` with an `ANALYSED=` sha, an **incremental refresh** is allowed. Run `git -C "<REPO_ROOT>" diff --name-only <ANALYSED> HEAD -- . ':(exclude)ckb'`, give that list to the scouts as priority, and keep the existing names and headings for entities whose citations still resolve.
- If uncommitted source changes exist, warn the user that the KB will describe uncommitted work.
- **Self-improvement:** if `<KB_DIR>/manifest.json` from a previous run has a `feedback` block, read it. Give `feedback.next_run_focus` (files left uncited and claims downgraded last time) to the scouts as **first priority**. In the final report, list every `feedback.improve_candidates` entry as a suggested rule improvement for the plugin maintainer.

**4. Permission probe.** Write `<KB_DIR>/manifest.json` with `{"status":"running"}` using the Write tool. If it is denied, print exactly one line, the `ADD_DIR_HINT` value, run step 11 if in URL mode, and STOP.

**4b. Load the contracts** (only now, so a fresh KB costs nothing extra). Invoke the Skill tool for `codebase-kb-engine:kb-docs` (the human docs) and `codebase-kb-engine:ckb-contract` (the machine artifact). Follow both exactly.

**5. Inventory (deterministic).** Run `"${CLAUDE_PLUGIN_ROOT}/scripts/inventory.sh" "<REPO_ROOT>"`. It returns the language mix, workspaces, `areas`, and every candidate file per bucket (manifests, lockfiles, routes, events, datastores, migrations, iac, ci, config, api_specs). Generated, vendored and `ckb/` paths are already excluded. **This list is your checklist:** every manifest and API spec in it must end up cited.

**Context discipline (cost and speed).** You are the orchestrator. **Do not Read source files, fragments, docs or `ckb.json` in full.**
- Use `"${CLAUDE_PLUGIN_ROOT}/scripts/kbq.sh"` (`summary`, `names`, `ids`, `claims`, `anchors`, `status`). It is pre-approved and returns compact output.
- Subagents do the reading and writing, and reply with one-line summaries.

**6. Recon in parallel.** Split the work into at most 8 scopes and launch **all scouts in a single message**:
- one `scout-inventory` subagent for the mechanical buckets (manifests, lockfiles, iac, ci, config, api_specs, migrations);
- one `scout` subagent per top `area` (a workspace member or top-level directory) for components, interfaces, events, datastores, business rules and workflows.

Give each scout the absolute root, its path scope, its slice of the inventory, an area slug for local-id prefixes, the priority list (incremental changes plus `feedback.next_run_focus`), and **its `fragment` path**: `<KB_DIR>/ckb.draft.d/<scope>.json`. Each scout writes its own fragment and replies with a one-line summary.

**Retry policy:**
- A scout that errors, hits maxTurns, or reports a non-empty `unscanned` list is re-dispatched **once**, with a narrower scope (the unscanned paths, or half its scope).
- If it still fails, the writer lists the scope under `04` → Open questions as `[?] not scanned: <paths>`. **Never fill the gap by inference.**
- Never retry a guard-blocked command with a workaround.

**7. Human docs.** Run `kbq.sh summary <KB_DIR>` to confirm the fragments exist. Then launch `kb-writer` subagents **in parallel**, for example one for `00`–`03` and one for `04`–`07`. Give them `KB_DIR`, `REPO_ROOT`, the doc list, the focus, and the `kbq.sh` path. If focus was given, they weight toward it but still write all 8.

**8. Claim audit.** Run `kbq.sh claims <KB_DIR> 15` and give its JSON to the `auditor` subagent. For every verdict that isn't `supported`, ask the owning scout scope's fragment to be corrected: downgrade to `inferred`, or fix the line. A one-line Edit to that fragment is fine.

**9. Finalize.** Run `"${CLAUDE_PLUGIN_ROOT}/scripts/finalize.sh" "<REPO_ROOT>" "<KB_DIR>" --started-at "<start>" --audit "<supported>/<audited>"` (the step 8 audit counts). In URL mode, add `--mode url --url "<REPO_URL>" --branch "<BRANCH>"`. It does the following:
- merges `ckb.draft.d/`, inventories the repo and computes coverage;
- derives IDs and normalizes everything;
- lints the docs, checks that the docs and the JSON agree, injects doc front-matter, rewrites local ids to final ids in the docs, and generates `90-reference.md`;
- redacts secrets, validates, and writes `ckb.json`, `manifest.json`, `README.md`, `.gitattributes` and `.gitignore`.

If `STATUS` is not `complete`, run `kbq.sh status <KB_DIR>` and read the reported violations:
- **missing headings / parity / lint:** fix the doc, with a targeted Edit or a `kb-writer` re-run for that doc.
- **schema / semantic:** fix the fragment.
- **`coverage … uncited`:** run one scout on exactly those files and add its fragment.

Then re-run finalize, at most 2 times in total. After that, report what remains honestly.

**10. Report.** Give the `STATUS=` line, the coverage summary (cited out of found per bucket), the confidence summary, the audit result, and the top 3 open questions. In local mode, end with the `COMMIT_HINT` command. **Do not run it yourself.**

**11. URL mode cleanup: always, even after failure.** Run `"${CLAUDE_PLUGIN_ROOT}/scripts/clone.sh" destroy "<JOB_DIR>"` and confirm the `DESTROYED=` line. Never push, and never copy source into the KB beyond short citations.
