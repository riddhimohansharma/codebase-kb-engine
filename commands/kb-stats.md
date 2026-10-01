---
description: Show this machine's anonymous codebase-kb-engine run stats (success rate, duration, coverage, recurring issues); optionally share them with the maintainer.
argument-hint: "[--json] [--last N] [--submit]"
---
Run `"${CLAUDE_PLUGIN_ROOT}/scripts/stats.sh" $ARGUMENTS` on its own and show the output to the user as-is.

- If `--submit` was **not** given, end with one line explaining that `/kb-stats --submit` posts this anonymized summary as a GitHub issue on the plugin repo, and that it holds only counts (no repo names, paths, code or values).
- If `--submit` **was** given, the script only prints a preview and sends nothing. Show the preview, and ask the user to confirm in chat. **Only after an explicit yes**, run `"${CLAUDE_PLUGIN_ROOT}/scripts/stats.sh" --submit --yes` with the same `--last` if any. Never add `--yes` on your own.
