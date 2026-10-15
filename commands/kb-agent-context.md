---
description: Propose an agent-context file (CLAUDE.md / AGENTS.md) for this repo from its manifests, lockfiles and inventory. No model spend, never overwrites. Writes only <repo>/.ckb/agent-context.proposed.md.
argument-hint: "[repo path]"
---
Propose the file every coding agent reads before it touches this repo. Deterministic and read-only toward the code: do not edit, create or copy CLAUDE.md or AGENTS.md yourself, and do not fill the TODO lines on the user's behalf.

1. Repo: `$ARGUMENTS` if given, otherwise the current directory. Run `"${CLAUDE_PLUGIN_ROOT}/scripts/resolve-kb.sh" "<repo>"` as its own command. It prints `REPO_ROOT=` and `KB_DIR=`. On a non-zero exit, show its message and stop.
2. Run `"${CLAUDE_PLUGIN_ROOT}/scripts/agent-context.sh" "<REPO_ROOT>" --out "<KB_DIR>/agent-context.proposed.md"` as its own command. Do not chain it with `;`, `&&` or `|`.
3. Report from its output: the archetype and modifiers, the word count against the 400-word budget, how many `TODO(human)` lines need a person, and the `NEXT=` line verbatim. Tell the user that those lines are what no script can know (a rule that is not in the code, a counter-intuitive fact, a public surface), and that they can type `/kb-unlock` and then ask you to fill them.
4. When the user has filled the TODO lines, they can check the result with `"${CLAUDE_PLUGIN_ROOT}/scripts/lint-agent-context.sh" "<file>"` (strict: no TODO, no skeleton tags, six sections, at most 400 words) before copying it to CLAUDE.md.
