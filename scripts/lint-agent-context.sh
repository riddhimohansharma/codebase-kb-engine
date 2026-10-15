#!/usr/bin/env bash
# lint-agent-context.sh — Core-level check of an agent-context file (CLAUDE.md / AGENTS.md body).
# Usage: lint-agent-context.sh <file> [--proposal]
#   final (default): the file is ready to commit; any unresolved `TODO(human)` anywhere, even in a comment, fails.
#   --proposal:      a generated proposal; `TODO(human)` lines are allowed and counted.
# Checks: H1 `# Agent context — <repo>`; exactly the six sections, in order, and no others; <= 400 words (HTML comments and
#   fenced code excluded); no [P]/[H] skeleton tags; no dates; no secret-looking values; no fetch-and-run instruction.
# Prints one `agent-context: <problem>` line per violation, then `WORDS=<n> TODOS=<n> RESULT=pass|fail`.
# Exit: 0 pass · 1 violations · 2 usage. Read-only. bash 3.2+, POSIX awk.
set -uo pipefail
f=""; proposal=0
while [ $# -gt 0 ]; do
  case "$1" in --proposal) proposal=1 ;; -*) echo "lint-agent-context: unknown option: $1" >&2; exit 2 ;; *) f="$1" ;; esac; shift
done
[ -n "$f" ] && [ -f "$f" ] || { echo "usage: lint-agent-context.sh <file> [--proposal]" >&2; exit 2; }

BUDGET=400
SECTIONS="Non-negotiables|Shape|Commands|Changing X obligates Y|Traps|Before you say you're done"
bad=0
v(){ printf 'agent-context: %s\n' "$1"; bad=$((bad + 1)); }

# the file without HTML comments (single- or multi-line)
body="$(awk '{ line=$0; out=""
  while (length(line) > 0) {
    if (c) { i=index(line,"-->"); if (i==0) line=""; else { line=substr(line,i+3); c=0 } }
    else   { i=index(line,"<!--"); if (i==0) { out=out line; line="" } else { out=out substr(line,1,i-1); line=substr(line,i+4); c=1 } }
  }
  print out }' "$f")"

first="$(printf '%s\n' "$body" | awk 'NF{print; exit}')"
printf '%s' "$first" | grep -q '^# Agent context — .\{1,\}$' || v "first line must be '# Agent context — <repo>' (got: ${first:-empty})"

got="$(printf '%s\n' "$body" | grep -E '^## ' | sed 's/^## //' | paste -sd'|' -)"
[ "$got" = "$SECTIONS" ] || v "sections must be exactly, in order: $SECTIONS (got: ${got:-none})"

words="$(printf '%s\n' "$body" | awk 'BEGIN{c=0} /^```/{fence=!fence; next} !fence{c+=NF} END{print c}')"
[ "$words" -le "$BUDGET" ] || v "$words words exceeds the $BUDGET-word budget; split the scope, do not raise the budget"

printf '%s\n' "$body" | grep -qE '\[(P|H)\]' && v "skeleton tag [P]/[H] left in the file"
printf '%s\n' "$body" | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}' && v "contains a date; the file must not go stale by the calendar"
printf '%s\n' "$body" | grep -qE 'AKIA[0-9A-Z]{12}|-----BEGIN [A-Z ]*PRIVATE KEY-----|ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|(password|secret|token|api[_-]?key)[ ]*[:=][ ]*[^ ]' && v "contains a secret-looking value"
printf '%s\n' "$body" | grep -qiE 'curl[^|]*\|[ ]*(ba)?sh|wget[^|]*\|[ ]*(ba)?sh|--dangerously|--no-verify|skip (the )?confirmation' && v "tells the agent to fetch and run something or skip a safety check"

todos="$(printf '%s\n' "$body" | grep -c 'TODO(human)' || true)"
if [ "$proposal" = 0 ] && grep -q 'TODO(human)' "$f"; then v "unresolved TODO(human): fill or delete every one, and delete the proposal comment"; fi

if [ "$bad" -eq 0 ]; then echo "WORDS=$words TODOS=$todos RESULT=pass"; exit 0; fi
echo "WORDS=$words TODOS=$todos RESULT=fail"; exit 1
