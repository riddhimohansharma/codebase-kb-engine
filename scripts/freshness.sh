#!/usr/bin/env bash
# freshness.sh — CKB freshness rule: fresh at Y  <=>  `git diff --quiet <commit_sha> Y -- . ':(exclude).ckb' ':(exclude)CLAUDE.md' ':(exclude)AGENTS.md'`
# Usage: freshness.sh <repo_root> [<kb_dir>] [<Y=HEAD>]
#        freshness.sh --shallow <clone_dir>   URL mode: the clone is depth 1, so there is no history to walk. The committed
#          <clone_dir>/.ckb records the commit it ANALYSED; committing the KB made a newer commit, so HEAD never equals it.
#          Instead: with the analysed commit present (clone.sh fetch-commit), compare TREES outside .ckb — no ancestry needed,
#          and identical content is a stronger statement than "is an ancestor". Missing commit => REASON=need-commit.
# Prints: FRESHNESS=fresh|stale|unknown|none ANALYSED=<sha> AT=<sha> [GENERATOR=<ver>] [REASON=...]
# Exit: 0 fresh · 1 stale · 3 unknown · 4 no artifact · 2 usage
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
if [ "${1:-}" = --shallow ]; then
  repo="${2:-}"; [ -d "$repo/.git" ] || { echo "usage: freshness.sh --shallow <clone_dir>" >&2; exit 2; }
  art="$repo/.ckb/ckb.json"
  if [ ! -f "$art" ]; then
    if [ -f "$repo/ckb/ckb.json" ]; then echo "FRESHNESS=none REASON=legacy-ckb-dir(the repo commits its KB at ckb/; regenerate to move it to .ckb/)"
    else echo "FRESHNESS=none REASON=no-artifact"; fi
    exit 4
  fi
  sha="$(jq -r '.repo.commit_sha // empty' "$art" 2>/dev/null)"; gen="$(jq -r '.generator.version // "?"' "$art" 2>/dev/null)"
  at="$(git -C "$repo" rev-parse --verify -q "HEAD^{commit}")" || { echo "FRESHNESS=unknown REASON=no-head"; exit 3; }
  mst="$(jq -r '.status // "missing"' "$repo/.ckb/manifest.json" 2>/dev/null || echo missing)"
  [ "$mst" = complete ] || { echo "FRESHNESS=unknown ANALYSED=${sha:-none} AT=$at REASON=committed-kb-status-$mst"; exit 3; }
  printf '%s' "$sha" | grep -qE '^[0-9a-f]{40}$' || { echo "FRESHNESS=unknown AT=$at REASON=artifact-has-no-commit_sha"; exit 3; }
  if ! git -C "$repo" cat-file -e "$sha^{commit}" 2>/dev/null; then
    echo "FRESHNESS=unknown ANALYSED=$sha AT=$at REASON=need-commit(run: clone.sh fetch-commit <job_dir> $sha)"; exit 3
  fi
  if git -C "$repo" diff --quiet "$sha" "$at" -- . ':(exclude).ckb' ':(exclude)CLAUDE.md' ':(exclude)AGENTS.md'; then
    echo "FRESHNESS=fresh ANALYSED=$sha AT=$at GENERATOR=$gen MODE=shallow-tree-compare"; exit 0
  fi
  n="$(git -C "$repo" diff --name-only "$sha" "$at" -- . ':(exclude).ckb' ':(exclude)CLAUDE.md' ':(exclude)AGENTS.md' | wc -l | tr -d ' ')"
  echo "FRESHNESS=stale ANALYSED=$sha AT=$at GENERATOR=$gen REASON=$n-source-files-changed MODE=shallow-tree-compare"; exit 1
fi
repo="${1:-}"; [ -d "$repo" ] || { echo "usage: freshness.sh <repo_root> [kb_dir] [ref]" >&2; exit 2; }
kb="${2:-$repo/.ckb}"; y="${3:-HEAD}"
art="$kb/ckb.json"
[ -f "$art" ] || { echo "FRESHNESS=none REASON=no-artifact"; exit 4; }
sha="$(jq -r '.repo.commit_sha // empty' "$art" 2>/dev/null)"
gen="$(jq -r '.generator.version // "?"' "$art" 2>/dev/null)"
at="$(git -C "$repo" rev-parse --verify -q "$y^{commit}")" || { echo "FRESHNESS=unknown REASON=ref-not-found:$y"; exit 3; }
# producer-side guards (the spec rule compares commits; these make /kb's skip decision safe)
mst="$(jq -r '.status // "missing"' "$kb/manifest.json" 2>/dev/null || echo missing)"
[ "$mst" = complete ] || { echo "FRESHNESS=unknown ANALYSED=${sha:-none} AT=$at REASON=last-run-status-$mst"; exit 3; }
if [ "$y" = HEAD ] && [ -n "$(git -C "$repo" status --porcelain -- . ':(exclude).ckb' ':(exclude)CLAUDE.md' ':(exclude)AGENTS.md' ':(exclude,glob)**/.DS_Store' ':(exclude,glob)**/Thumbs.db' ':(exclude,glob)**/desktop.ini' 2>/dev/null | head -1)" ]; then
  echo "FRESHNESS=stale ANALYSED=${sha:-none} AT=$at REASON=dirty-worktree(uncommitted-source-changes)"; exit 1
fi
if [ -n "$sha" ] && ! git -C "$repo" cat-file -e "$sha^{commit}" 2>/dev/null; then
  if [ "$(git -C "$repo" rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
    echo "FRESHNESS=unknown ANALYSED=$sha AT=$at REASON=shallow-clone(run: git fetch --deepen=200)"; exit 3
  fi
  echo "FRESHNESS=unknown ANALYSED=$sha AT=$at REASON=analysed-commit-not-in-repo"; exit 3
fi
[ -n "$sha" ] || { echo "FRESHNESS=unknown REASON=artifact-has-no-commit_sha"; exit 3; }
git -C "$repo" merge-base --is-ancestor "$sha" "$at" 2>/dev/null \
  || { echo "FRESHNESS=unknown ANALYSED=$sha AT=$at REASON=analysed-commit-not-ancestor"; exit 3; }
if git -C "$repo" diff --quiet "$sha" "$at" -- . ':(exclude).ckb' ':(exclude)CLAUDE.md' ':(exclude)AGENTS.md'; then
  mine="$(jq -r .version "$ROOT/.claude-plugin/plugin.json")"
  note=""; [ "$gen" != "$mine" ] && note=" NOTE=generated-by-$gen-current-is-$mine"
  echo "FRESHNESS=fresh ANALYSED=$sha AT=$at GENERATOR=$gen$note"; exit 0
fi
n="$(git -C "$repo" diff --name-only "$sha" "$at" -- . ':(exclude).ckb' ':(exclude)CLAUDE.md' ':(exclude)AGENTS.md' | wc -l | tr -d ' ')"
echo "FRESHNESS=stale ANALYSED=$sha AT=$at GENERATOR=$gen REASON=$n-source-files-changed"; exit 1
