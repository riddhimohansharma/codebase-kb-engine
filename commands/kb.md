---
description: Generate a read-only knowledge base for this repo or a repo URL — 5 docs + a CKB v0.1 ckb.json + manifest.json. Never modifies the analysed repo.
argument-hint: "[<repo-url> [branch]] [focus]"
---
Produce the knowledge base for the target below. Follow the `kb` skill (human docs) and the `ckb-contract` skill (machine artifact). The analysed repo is READ-ONLY; the guard blocks any write outside the KB dir.

Arguments: `$ARGUMENTS`

**1. Mode.** If the first argument starts with `https://`, `http://`, `ssh://`, `git://`, or matches `user@host:path`, this is **URL mode**: argument 2 (if present and it contains no spaces) is the branch; anything after is focus. Otherwise **local mode**: the target is the current working directory and all arguments are focus.

**2. Target + output dir.** Run exactly one of:
- local: `"${CLAUDE_PLUGIN_ROOT}/scripts/resolve-kb.sh" .`
- URL:   `"${CLAUDE_PLUGIN_ROOT}/scripts/clone.sh" clone "<url>" [branch]` → note `JOB_DIR`, `CLONE_DIR`, `NAME`, `BRANCH`, `REPO_URL`; then `"${CLAUDE_PLUGIN_ROOT}/scripts/resolve-kb.sh" "<CLONE_DIR>" --url-mode --name "<NAME>"`

Record `REPO_ROOT`, `KB_DIR`, `ADD_DIR_HINT` and the start time (`date -u +%Y-%m-%dT%H:%M:%SZ`). If a script exits non-zero, show its message verbatim to the user (it contains the exact fix, e.g. a `claude --add-dir …` line), run step 8 if in URL mode, and STOP. Do not improvise another location.

**3. Permission probe.** Write `<KB_DIR>/manifest.json` with `{"status":"running"}` using the Write tool. If that Write is denied or fails, print exactly one line — the `ADD_DIR_HINT` value — explain it grants the KB dir, run step 8 if in URL mode, and STOP.

**4. Recon.** Use the `scout` subagent for wide reads of `<REPO_ROOT>` (give it the absolute path): languages, entrypoints, components, HTTP routes, events, RPC, dependency manifests, datastores/migrations, config/env, CI/IaC, business logic. Every fact comes back with `path:line`, paths relative to `<REPO_ROOT>`.

**5. Human docs.** Write all five files to `<KB_DIR>` with absolute paths, per the `kb` skill: `00-overview.md`, `01-technical-architecture.md`, `02-functional-workflows.md`, `03-business-rules.md`, `04-system-context-and-gaps.md`. If focus was given, weight toward it but still write all five.

**6. Machine draft.** Write `<KB_DIR>/ckb.draft.json` per the `ckb-contract` skill — the same facts as the docs, never more. Business rules and workflows must match those in `03` and `02` by name.

**7. Finalize.** Run `"${CLAUDE_PLUGIN_ROOT}/scripts/finalize.sh" "<REPO_ROOT>" "<KB_DIR>" --started-at "<start>"` — in URL mode add `--mode url --url "<REPO_URL>" --branch "<BRANCH>"`. It derives IDs, normalizes join keys, writes `ckb.json` + `manifest.json`, and validates. If `STATUS` is not `complete`, read the reported violations, fix `ckb.draft.json` (or the missing doc), and re-run — at most 2 retries; then report the remaining violations honestly.

**8. URL mode cleanup — always, even after failure.** Run `"${CLAUDE_PLUGIN_ROOT}/scripts/clone.sh" destroy "<JOB_DIR>"` and confirm the `DESTROYED=` line. Never push, and never copy source into the KB beyond short citations.

**Finish** with: the `STATUS=` line from finalize, a one-line index of files written, the confidence summary, and the top 3 `unknown`/`[?]` items worth verifying.
