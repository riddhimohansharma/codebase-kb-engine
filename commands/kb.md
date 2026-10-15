---
description: Generate the repo's knowledge base in <repo>/.ckb/ (8 docs + generated reference + CKB v0.2 ckb.json + manifest.json), ready to commit. Read-only toward the code; skips when the KB is already fresh.
argument-hint: "[--force] [--fresh] [--no-agent-context] [<repo-url> [branch]] [focus]"
---
Produce the knowledge base for the target below. The code is READ-ONLY: the guard allows writes only inside the KB dir (the one-time `CLAUDE.md` seed in step 2b is made by a plugin script, never by you), and you never commit, push, or edit source.

Arguments: `$ARGUMENTS`

**Rule:** run each `${CLAUDE_PLUGIN_ROOT}/scripts/*` command **on its own**, never chained with `;`, `&&` or `|`. Plugin scripts are pre-approved only as standalone commands.

**1. Mode.** Remove a leading `--force`, `--fresh` and `--no-agent-context` flag (any order) if present and remember them. `--fresh` ignores any saved checkpoint and starts the analysis from scratch. If the next argument starts with `https://`, `http://`, `ssh://`, `git://`, or matches `user@host:path`, this is **URL mode**: the following argument (if present and it contains no spaces) is the branch, and anything after that is focus. Otherwise this is **local mode** (the standard): the target is the current git repo, the KB is `<repo-root>/.ckb/`, and all arguments are focus.

**2. Target + output dir.** Run exactly one of:
- local: `"${CLAUDE_PLUGIN_ROOT}/scripts/resolve-kb.sh" .`
- URL: `"${CLAUDE_PLUGIN_ROOT}/scripts/clone.sh" clone "<url>" [branch]`, then note `JOB_DIR`, `CLONE_DIR`, `NAME`, `BRANCH` and `REPO_URL`. Then run `"${CLAUDE_PLUGIN_ROOT}/scripts/resolve-kb.sh" "<CLONE_DIR>" --url-mode --name "<NAME>"`.

If the output includes a `MIGRATED=` line, tell the user the visible `ckb/` folder was renamed to the canonical hidden `.ckb/` and pass on its commit instruction. If it includes an `ADOPTED=` line, tell the user an unmarked `.ckb/` holding only producer files was marked as the KB. Record `REPO_ROOT`, `KB_DIR`, `ADD_DIR_HINT` and the start time (`date -u +%Y-%m-%dT%H:%M:%SZ`). If a script exits non-zero, show its message verbatim, run step 11 if in URL mode, and STOP.

**2a. Telemetry notice.** Run `"${CLAUDE_PLUGIN_ROOT}/scripts/telemetry.sh" notice` on its own. If it prints a `TELEMETRY_NOTICE=` line, show its text to the user verbatim now, before any report is sent; it prints nothing after the first time or when telemetry is off.

**2b. First-run agent context (local mode only, default on).** Unless `--no-agent-context` was given, run `"${CLAUDE_PLUGIN_ROOT}/scripts/agent-context.sh" "<REPO_ROOT>" --seed` on its own, before the analysis. On a repository's first run, with no `CLAUDE.md` or `AGENTS.md` present, it creates `CLAUDE.md` from facts the manifests and inventory prove (create-only, never overwrites, never in URL mode). Report its `SEED=` line verbatim: `created` means the user should review `CLAUDE.md` and commit it with the KB; `skipped:<reason>` means nothing was written (`/kb-agent-context` proposes a file instead). Never edit or create `CLAUDE.md` yourself. If the run is later stopped, the seed stays and is not repeated.

**3. Freshness (local mode).** Run `"${CLAUDE_PLUGIN_ROOT}/scripts/freshness.sh" "<REPO_ROOT>"`.
- If it prints `FRESHNESS=fresh` and `--force` was not given, report that the committed KB already describes the current source (quote the line) and STOP without writing anything.
- If it prints `FRESHNESS=stale` with an `ANALYSED=` sha, an **incremental refresh** is allowed. Run `git -C "<REPO_ROOT>" diff --name-only <ANALYSED> HEAD -- . ':(exclude).ckb' ':(exclude)CLAUDE.md' ':(exclude)AGENTS.md'`, give that list to the scouts as priority, and keep the existing names and headings for entities whose citations still resolve.
- If uncommitted source changes exist, warn the user that the KB will describe uncommitted work.
- **Self-improvement:** if `<KB_DIR>/manifest.json` from a previous run has a `feedback` block, read it. Give `feedback.next_run_focus` (files left uncited and claims downgraded last time) to the scouts as **first priority**. In the final report, list every `feedback.improve_candidates` entry as a suggested rule improvement for the plugin maintainer.

**3b. Freshness (URL mode).** Run `"${CLAUDE_PLUGIN_ROOT}/scripts/freshness.sh" --shallow "<CLONE_DIR>"`. The clone is depth 1, so this compares trees against the commit the committed KB analysed.
- If it prints `FRESHNESS=unknown` with `REASON=need-commit`, run `"${CLAUDE_PLUGIN_ROOT}/scripts/clone.sh" fetch-commit "<JOB_DIR>" <ANALYSED>` and re-run the check **once**. If the fetch fails, carry on with a full run.
- If it prints `FRESHNESS=fresh` and `--force` was not given, report that the repository already commits a KB at `.ckb/` describing this exact source (quote the line, and say it can be read in the repo), run step 11, and STOP. Nothing was generated.
- Otherwise (`stale`, `none`, `unknown`) continue with a full run.

**4. Permission probe.** Write `<KB_DIR>/manifest.json` with `{"status":"running"}` using the Write tool. If it is denied, print exactly one line, the `ADD_DIR_HINT` value, run step 11 if in URL mode, and STOP.

**4a. Checkpoint (resume, never restart).** Run `"${CLAUDE_PLUGIN_ROOT}/scripts/checkpoint.sh" begin "<KB_DIR>" "<REPO_ROOT>"` on its own (add `--fresh`→`--force` when `--fresh` was given, and `--focus "<focus>"` when a focus was given). It prints `RESUME=yes` when an earlier interrupted run of the **same commit, same uncommitted changes, same plugin version and same focus** left usable work, or `RESUME=fresh` (with a `REASON=`) after clearing anything stale. Then run `"${CLAUDE_PLUGIN_ROOT}/scripts/checkpoint.sh" status "<KB_DIR>"` and read its `PENDING=` line: **that is the work left.** Tell the user in one line when you are resuming and what is already done. Skip every step whose work is not in `PENDING`: step 5 if the inventory is done (the file is reused), step 6 for scopes already done, step 7 for docs already done, step 8 if `audit` is done. **If you ever lose context, run `checkpoint.sh status` and continue from `PENDING`; never restart a run that has a checkpoint.**

**4b. Contracts.** Do **not** load `kb-docs` or `ckb-contract` yourself: the scouts and writers load what they need, and you write neither fragments nor docs. Load `codebase-kb-engine:ckb-contract` (Skill tool) **only if** step 8 or 9 requires you to edit a fragment by hand, and follow it exactly when you do.

**5. Inventory (deterministic).** Run `"${CLAUDE_PLUGIN_ROOT}/scripts/inventory.sh" "<REPO_ROOT>" --out "<KB_DIR>/ckb.draft.d/.inventory.json"`. The full inventory (every candidate file per bucket: manifests, lockfiles, routes, events, datastores, migrations, iac, ci, config, api_specs) goes to that file; you get only a small **digest**: counts per bucket, languages, workspaces, areas by `tier` (`source`/`test`/`docs`), and up to 7 pre-packed `scopes`. Generated, vendored and `.ckb/` paths are already excluded. **The file is the checklist:** every manifest and API spec in it must end up cited. Scouts read their own slice with `kbq.sh inventory`; **never paste inventory lists into a prompt.**

**Context discipline (cost and speed).** You are the orchestrator. **Do not Read source files, fragments, docs or `ckb.json` in full.**
- Use `"${CLAUDE_PLUGIN_ROOT}/scripts/kbq.sh"` (`summary`, `names`, `ids`, `claims`, `anchors`, `status`, `inventory`). It is pre-approved and returns compact output.
- Subagents do the reading and writing, and reply with one-line summaries.

**6. Recon in parallel.** The digest's `scopes` are already packed (source areas weighted over test and docs), at most 7. Launch **all pending scouts in a single message** (on a resume only the `scout:` entries of `PENDING`; a scope that already has a valid fragment is not re-run):
- one `scout-inventory` subagent, scope name `inventory`, for the mechanical buckets (manifests, lockfiles, iac, ci, config, api_specs, migrations);
- one `scout` subagent per digest scope, for components, interfaces, events, datastores, business rules and workflows.

Give each scout only: the absolute root, `KB_DIR`, the `kbq.sh` path, its **scope name**, an area slug for local-id prefixes (use the scope name), the priority list (incremental changes plus `feedback.next_run_focus`), and **its `fragment` path**: `<KB_DIR>/ckb.draft.d/<scope>.json`. Each scout fetches its own slice with `kbq.sh inventory <KB_DIR> <scope>`, writes its own fragment and replies with a one-line summary. Count the scouts you launch, and every re-dispatch, for step 9.

**Retry policy:**
- A scout that errors, hits maxTurns, or reports a non-empty `unscanned` list is re-dispatched **once** with the **same scope name** (its slice is fetched by that name, so never invent a new one) and a priority list restricted to the unscanned paths, or half its scope's paths.
- If it still fails, the writer lists the scope under `04` → Open questions as `[?] not scanned: <paths>`. **Never fill the gap by inference.**
- Never retry a guard-blocked command with a workaround.

**7. Human docs.** (On a resume write only the `doc:` entries of `PENDING`.) Run `kbq.sh summary <KB_DIR>` to confirm the fragments exist. Then launch `kb-writer` subagents **in parallel**, for example one for `00`–`03` and one for `04`–`07`. Give them `KB_DIR`, `REPO_ROOT`, the doc list, the focus, and the `kbq.sh` path. If focus was given, they weight toward it but still write all 8.

**8. Claim audit.** (Skip when `audit` is done.) After the audit, run `"${CLAUDE_PLUGIN_ROOT}/scripts/checkpoint.sh" mark "<KB_DIR>" audit <supported>/<audited>` on its own. Run `kbq.sh claims <KB_DIR> 15` and give its JSON to the `auditor` subagent. For every verdict that isn't `supported`, ask the owning scout scope's fragment to be corrected: downgrade to `inferred`, or fix the line. A one-line Edit to that fragment is fine (load `ckb-contract` first, see 4b).

**9. Finalize.** Before each attempt run `"${CLAUDE_PLUGIN_ROOT}/scripts/checkpoint.sh" mark "<KB_DIR>" finalize` on its own. Run `"${CLAUDE_PLUGIN_ROOT}/scripts/finalize.sh" "<REPO_ROOT>" "<KB_DIR>" --started-at "<start>" --audit "<supported>/<audited>" --inventory "<KB_DIR>/ckb.draft.d/.inventory.json" --attempt <1 or 2> --scouts <scouts launched> --writers <writers launched> --retries <re-dispatches>` (the step 8 audit counts; the inventory file is reused instead of walking the repo again; the counts are recorded locally for benchmarking). In URL mode, add `--mode url --url "<REPO_URL>" --branch "<BRANCH>"`. It does the following:
- merges `ckb.draft.d/`, inventories the repo and computes coverage;
- derives IDs and normalizes everything;
- lints the docs, checks that the docs and the JSON agree, injects doc front-matter, rewrites local ids to final ids in the docs, and generates `08-reference.md`;
- redacts secrets, validates, and writes `ckb.json`, `manifest.json`, `README.md`, `.gitattributes` and `.gitignore`.

If `STATUS` is not `complete`, run `kbq.sh status <KB_DIR>` and read the reported violations:
- **missing headings / parity / lint:** fix the doc, with a targeted Edit or a `kb-writer` re-run for that doc.
- **schema / semantic:** fix the fragment.
- **`coverage … uncited`:** run one scout on exactly those files and add its fragment.

Then re-run finalize, at most 2 times in total. After that, report what remains honestly.

**10. Report.** If finalize printed a `TELEMETRY_NOTICE=` line, show its text to the user once, verbatim. Then give the `STATUS=` line, the coverage summary (cited out of found per bucket), the confidence summary, the audit result, and the top 3 open questions. In local mode, end with the `COMMIT_HINT` command. **Do not run it yourself.**

**11. URL mode cleanup: always, even after failure.** Run `"${CLAUDE_PLUGIN_ROOT}/scripts/clone.sh" destroy "<JOB_DIR>"` and confirm the `DESTROYED=` line. Never push, and never copy source into the KB beyond short citations.
