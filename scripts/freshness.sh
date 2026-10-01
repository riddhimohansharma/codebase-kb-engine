#!/usr/bin/env bash
# freshness.sh — CKB freshness rule: fresh at Y  <=>  `git diff --quiet <commit_sha> Y -- . ':(exclude)ckb'`
# Usage: freshness.sh <repo_root> [<kb_dir>] [<Y=HEAD>]
# Prints: FRESHNESS=fresh|stale|unknown|none ANALYSED=<sha> AT=<sha> [GENERATOR=<ver>] [REASON=...]
# Exit: 0 fresh · 1 stale · 3 unknown · 4 no artifact · 2 usage
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
repo="${1:-}"; [ -d "$repo" ] || { echo "usage: freshness.sh <repo_root> [kb_dir] [ref]" >&2; exit 2; }
kb="${2:-$repo/ckb}"; y="${3:-HEAD}"
art="$kb/ckb.json"
[ -f "$art" ] || { echo "FRESHNESS=none REASON=no-artifact"; exit 4; }
sha="$(jq -r '.repo.commit_sha // empty' "$art" 2>/dev/null)"
gen="$(jq -r '.generator.version // "?"' "$art" 2>/dev/null)"
at="$(git -C "$repo" rev-parse --verify -q "$y^{commit}")" || { echo "FRESHNESS=unknown REASON=ref-not-found:$y"; exit 3; }
# producer-side guards (the spec rule compares commits; these make /kb's skip decision safe)
mst="$(jq -r '.status // "missing"' "$kb/manifest.json" 2>/dev/null || echo missing)"
[ "$mst" = complete ] || { echo "FRESHNESS=unknown ANALYSED=${sha:-none} AT=$at REASON=last-run-status-$mst"; exit 3; }
if [ "$y" = HEAD ] && [ -n "$(git -C "$repo" status --porcelain -- . ':(exclude)ckb' ':(exclude,glob)**/.DS_Store' ':(exclude,glob)**/Thumbs.db' ':(exclude,glob)**/desktop.ini' 2>/dev/null | head -1)" ]; then
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
if git -C "$repo" diff --quiet "$sha" "$at" -- . ':(exclude)ckb'; then
  mine="$(jq -r .version "$ROOT/.claude-plugin/plugin.json")"
  note=""; [ "$gen" != "$mine" ] && note=" NOTE=generated-by-$gen-current-is-$mine"
  echo "FRESHNESS=fresh ANALYSED=$sha AT=$at GENERATOR=$gen$note"; exit 0
fi
n="$(git -C "$repo" diff --name-only "$sha" "$at" -- . ':(exclude)ckb' | wc -l | tr -d ' ')"
echo "FRESHNESS=stale ANALYSED=$sha AT=$at GENERATOR=$gen REASON=$n-source-files-changed"; exit 1
