#!/usr/bin/env bash
# templates.test.sh — templates/agent-context: structure and budget of every skeleton and seed, and that every repo path
# a seed mentions still exists (the anti-rot check: a seed that names a renamed file misleads every agent that reads it).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
TPL="$ROOT/templates/agent-context"
pass=0; fail=0
ok(){ if eval "$2"; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1"; fi; }
SECTIONS="Non-negotiables|Shape|Commands|Changing X obligates Y|Traps|Before you say you're done"
words(){ awk 'BEGIN{c=0} /^```/{f=!f; next} !f{c+=NF} END{print c}' "$1"; }
sections(){ grep -E '^## ' "$1" | sed 's/^## //' | paste -sd'|' -; }

ok "README and modifiers exist"                      '[ -s "$TPL/README.md" ] && [ -s "$TPL/modifiers.md" ]'
ok "README states the admission rule and the 400-word budget" 'grep -q "would otherwise do the wrong thing" "$TPL/README.md" && grep -q "400 words" "$TPL/README.md"'
ok "README is honest that the engine proposes but never writes CLAUDE.md/AGENTS.md" 'grep -q "never writes \`CLAUDE.md\` or \`AGENTS.md\` itself" "$TPL/README.md"'

for s in A-service B-monorepo C-library D-infrastructure E-contract; do
  f="$TPL/$s.md"
  ok "skeleton $s: H1 is '# Agent context — <repo>'"   '[ -f "$f" ] && grep -m1 "^# " "$f" | grep -q "^# Agent context — "'
  ok "skeleton $s: the six sections, in order, and no others" '[ "$(sections "$f")" = "$SECTIONS" ]'
  ok "skeleton $s: has both [P] projected and [H] human lines" 'grep -q "\[P\]" "$f" && grep -q "\[H\]" "$f"'
  ok "skeleton $s: within the 400-word budget"         '[ "$(words "$f")" -le 400 ]'
  ok "skeleton $s: every bullet is tagged [P] or [H]"   '! grep -E "^- " "$f" | grep -vqE "^- \[(P|H)\]"'
done

# the modifiers file: four additive blocks
ok "modifiers: exactly +events, +datastore, +deploy, +polyglot" '[ "$(grep -E "^## " "$TPL/modifiers.md" | paste -sd"|" -)" = "## +events|## +datastore|## +deploy|## +polyglot" ]'

# ---- the seeds ----
# repo-path check: backticked tokens that look like repo paths must exist in one of the project's three repos
# (seeds legitimately point at siblings, e.g. "update derive.jq in codebase-kb-spec"); bare names are found anywhere in them
check_paths(){ # <seed.md> <repo dir>; prints missing tokens
  local seed="$1" dir="$2" tok r roots found
  roots="$dir"; for r in codebase-kb-engine codebase-kb-spec; do [ -d "$dir/../$r" ] && roots="$roots $dir/../$r"; done
  grep -oE '`[^`]+`' "$seed" | tr -d '`' | sort -u | while IFS= read -r tok; do
    case "$tok" in *" "*|*"<"*|*'$'*|*"="*|*":"*|*"("*|*"{"*|.ckb*|ckb.draft.d*|.inventory.json|"~"*|"/"*) continue ;; esac
    printf '%s' "$tok" | grep -qE '^[A-Za-z0-9_.*/-]+$' || continue
    case "$tok" in */*) ;; *) printf '%s' "$tok" | grep -qE '\.(md|sh|json|jq|py|toml|lock|yml|yaml)$|^LICENSE$' || continue ;; esac
    found=0
    for r in $roots; do
      if printf '%s' "$tok" | grep -q '/'; then
        compgen -G "$r/$tok" >/dev/null && { found=1; break; }
      else
        [ -n "$(find "$r" -name "$tok" -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.venv/*' 2>/dev/null | head -1)" ] && { found=1; break; }
      fi
    done
    [ "$found" = 1 ] || printf '%s\n' "$tok"
  done
}
seed(){ # <name> <repo dir or empty to skip>
  local nm="$1" f="$TPL/dogfood/$1.md" dir="$2"   # nm is read by the eval in ok(), whose own $1 is the label
  ok "seed $1: H1 names the repo"                      'grep -m1 "^# " "$f" | grep -qx "# Agent context — $nm"'
  ok "seed $1: the six sections, in order, and no others" '[ "$(sections "$f")" = "$SECTIONS" ]'
  ok "seed $1: within the 400-word budget"             '[ "$(words "$f")" -le 400 ]'
  ok "seed $1: passes scripts/lint-agent-context.sh (strict)"   '"$ROOT/scripts/lint-agent-context.sh" "$f" >/dev/null'
  ok "seed $1: no [P]/[H] tags left in a finished seed" '! grep -qE "\[(P|H)\]" "$f"'
  ok "seed $1: no dates, no secret-looking values"      '! grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}|AKIA[0-9A-Z]{12}|(password|secret|token)[ ]*[:=]" "$f"'
  ok "seed $1: no instruction to fetch and run anything" '! grep -qiE "curl[^|]*\|[ ]*(ba)?sh|wget[^|]*\|[ ]*(ba)?sh|--dangerously|--no-verify|skip (the )?confirmation" "$f"'
  if [ -n "$dir" ] && [ -d "$dir" ]; then
    miss="$(check_paths "$f" "$dir")"
    ok "seed $1: every repo path it mentions exists (missing: ${miss:-none})" '[ -z "$miss" ]'
  else echo "SKIP seed $1: repo not found next to this one (path check)"; fi
}
seed codebase-kb-engine "$ROOT"
seed codebase-kb-spec  "$ROOT/../codebase-kb-spec"

# the path checker must be able to fail, or the anti-rot guarantee is vacuous
printf '# x\n\nSee `scripts/does-not-exist.sh` and `scripts/finalize.sh` and `nope.json`.\n' > "${TMPDIR:-/tmp}/ckb-tpl-probe.$$.md"
miss="$(check_paths "${TMPDIR:-/tmp}/ckb-tpl-probe.$$.md" "$ROOT")"; rm -f "${TMPDIR:-/tmp}/ckb-tpl-probe.$$.md"
ok "path checker flags a missing path and a missing bare file, and passes an existing one" '[ "$miss" = "nope.json
scripts/does-not-exist.sh" ]'

echo "templates tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
