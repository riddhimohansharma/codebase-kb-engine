---
description: Generate the repo's knowledge base in <repo>/.ckb/ (5 docs + CKB v0.1 ckb.json + manifest.json), ready to commit. Read-only toward the code; skips when the KB is already fresh.
argument-hint: "[--force] [<repo-url> [branch]] [focus]"
---
Produce the knowledge base for the target below. Follow the `kb` skill (human docs) and the `ckb-contract` skill (machine artifact). The code is READ-ONLY: the guard allows writes only inside the KB dir, and you never commit, push, or edit source.

Arguments: `$ARGUMENTS`

**1. Mode.** Remove a leading `--force` flag if present and remember it. If the next argument starts with `https://`, `http://`, `ssh://`, `git://`, or matches `user@host:path`, this is **URL mode**: the following argument (if present and it contains no spaces) is the branch, and anything after that is focus. Otherwise this is **local mode** (the standard): the target is the current git repo, the KB is `<repo-root>/.ckb/`, and all arguments are focus.

**2. Target + output dir.** Run exactly one of:
- local: `"${CLAUDE_PLUGIN_ROOT}/scripts/resolve-kb.sh" .`
- URL:   `"${CLAUDE_PLUGIN_ROOT}/scripts/clone.sh" clone "<url>" [branch]`, then note `JOB_DIR`, `CLONE_DIR`, `NAME`, `BRANCH` and `REPO_URL`. Then run `"${CLAUDE_PLUGIN_ROOT}/scripts/resolve-kb.sh" "<CLONE_DIR>" --url-mode --name "<NAME>"`.

Record `REPO_ROOT`, `KB_DIR`, `ADD_DIR_HINT` and the start time (`date -u +%Y-%m-%dT%H:%M:%SZ`). If a script exits non-zero, show its message verbatim (it contains the exact fix), run step 9 if in URL mode, and STOP. Do not improvise another location.

**3. Freshness (local mode).** Run `"${CLAUDE_PLUGIN_ROOT}/scripts/freshness.sh" "<REPO_ROOT>"`. If it prints `FRESHNESS=fresh` and `--force` was not given, report that the committed KB already describes the current source (quote the line) and STOP without writing anything. Otherwise continue. Also run `git -C "<REPO_ROOT>" status --porcelain -- . ':(exclude).ckb'`. If it shows changes, warn the user that the KB will describe uncommitted work (the manifest records `dirty_worktree: true`), and recommend committing the source first.

**4. Permission probe.** Write `<KB_DIR>/manifest.json` with `{"status":"running"}` using the Write tool. If that Write is denied or fails, print exactly one line, the `ADD_DIR_HINT` value, run step 9 if in URL mode, and STOP.

**5. Recon.** Use the `scout` subagent for wide reads of `<REPO_ROOT>` (give it the absolute path, and tell it to **ignore `.ckb/` entirely**). Cover languages, entrypoints, components, HTTP routes, events, RPC, dependency manifests, datastores and migrations, config and env, CI and IaC, and business logic. Every fact comes back with `path:line`, relative to `<REPO_ROOT>`. Never cite `.ckb/`.

**6. Human docs.** Write all five files into `<KB_DIR>` using absolute paths, per the `kb` skill: `00-overview.md`, `01-technical-architecture.md`, `02-functional-workflows.md`, `03-business-rules.md`, `04-system-context-and-gaps.md`. If focus was given, weight toward it but still write all five.

**7. Machine draft.** Write `<KB_DIR>/ckb.draft.json` per the `ckb-contract` skill. It holds the same facts as the docs and never more. Business rules and workflows must match those in `03` and `02` by name.

**8. Finalize.** Run `"${CLAUDE_PLUGIN_ROOT}/scripts/finalize.sh" "<REPO_ROOT>" "<KB_DIR>" --started-at "<start>"`. In URL mode, add `--mode url --url "<REPO_URL>" --branch "<BRANCH>"`. It derives IDs, normalizes join keys, writes `ckb.json`, `manifest.json`, `README.md` and `.gitattributes`, and validates. If `STATUS` is not `complete`, read the violations, fix `ckb.draft.json` (or the missing doc), and re-run it, at most 2 times. Then report whatever violations remain, honestly.

**9. URL mode cleanup: always, even after failure.** Run `"${CLAUDE_PLUGIN_ROOT}/scripts/clone.sh" destroy "<JOB_DIR>"` and confirm the `DESTROYED=` line. Never push, and never copy source into the KB beyond short citations.

**Finish** with the `STATUS=` line, a one-line index of the files written, the confidence summary, and the top 3 `unknown`/`[?]` items to verify. In local mode, end with the `COMMIT_HINT` command so the user can commit `.ckb/`. **Do not run it yourself.**
