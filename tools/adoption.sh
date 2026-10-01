#!/usr/bin/env bash
# adoption.sh — daily adoption snapshot for codebase-kb-engine from public GitHub signals (maintainer tool).
# GitHub keeps traffic for only 14 days: run daily (cron/launchd) and this tool stitches daily points into a lifetime history.
# Usage: tools/adoption.sh [--out DIR] [--json]
set -uo pipefail
R="riddhimohansharma/codebase-kb-engine"; json=0
out="${XDG_STATE_HOME:-$HOME/.local/state}/codebase-kb-engine/adoption"
while [ $# -gt 0 ]; do case "$1" in --out) out="$2"; shift ;; --json) json=1 ;; *) echo "unknown option: $1" >&2; exit 2 ;; esac; shift; done
command -v gh >/dev/null || { echo "gh (GitHub CLI) required" >&2; exit 2; }
mkdir -p "$out"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
gh api "repos/$R" > "$T/repo.json"
gh api "repos/$R/traffic/clones" > "$T/clones.json" 2>/dev/null || echo '{"clones":[]}' > "$T/clones.json"
gh api "repos/$R/traffic/views"  > "$T/views.json"  2>/dev/null || echo '{"views":[]}'  > "$T/views.json"
gh api "repos/$R/traffic/popular/referrers" > "$T/ref.json" 2>/dev/null || echo '[]' > "$T/ref.json"
kbs="$(gh api -X GET search/code -f q='"codebase-kb-engine" filename:ckb.json' --jq .total_count 2>/dev/null || echo null)"; sleep 2
anykb="$(gh api -X GET search/code -f q='"ckb_version" filename:ckb.json' --jq .total_count 2>/dev/null || echo null)"
reports="$(gh issue list -R "$R" -l stats --state all --json number --jq length 2>/dev/null || echo 0)"
tags="$(gh api "repos/$R/tags" --jq length 2>/dev/null || echo null)"
# stitch daily traffic into lifetime history (keyed by day; the latest value for a day wins)
for k in clones views; do
  [ -f "$out/$k-daily.json" ] || echo '{}' > "$out/$k-daily.json"
  jq --slurpfile n "$T/$k.json" --arg k "$k" '. + ([$n[0][$k][]? | {key: .timestamp[0:10], value: {count, uniques}}] | from_entries)' "$out/$k-daily.json" > "$T/$k.m" && mv "$T/$k.m" "$out/$k-daily.json"
done
snap="$(jq -c -n --arg day "$(date -u +%Y-%m-%d)" --slurpfile repo "$T/repo.json" --slurpfile ref "$T/ref.json" \
  --slurpfile cd "$out/clones-daily.json" --slurpfile vd "$out/views-daily.json" \
  --argjson kbs "$kbs" --argjson anykb "$anykb" --argjson reports "$reports" --argjson tags "$tags" '
  {day: $day, stars: $repo[0].stargazers_count, forks: $repo[0].forks_count, watchers: $repo[0].subscribers_count, open_issues: $repo[0].open_issues_count,
   clones_lifetime: ([$cd[0][].count] | add // 0), clone_uniques_daily_sum: ([$cd[0][].uniques] | add // 0),
   views_lifetime: ([$vd[0][].count] | add // 0), view_uniques_daily_sum: ([$vd[0][].uniques] | add // 0),
   committed_kbs_public: $kbs, any_ckb_public: $anykb, stats_reports: $reports, releases: $tags,
   top_referrers: [$ref[0][]? | {referrer, count}] | .[0:5]}')"
prev="$(tail -1 "$out/history.jsonl" 2>/dev/null || echo '{}')"
printf '%s\n' "$snap" >> "$out/history.jsonl"
if [ "$json" = 1 ]; then printf '%s\n' "$snap"; exit 0; fi
jq -r -n --argjson s "$snap" --argjson p "$prev" '
  def d(k): ($s[k] // 0) - ($p[k] // ($s[k] // 0)) | if . > 0 then " (+\(.))" elif . < 0 then " (\(.))" else "" end;
  "codebase-kb-engine adoption — \($s.day)",
  "  committed KBs in public repos: \($s.committed_kbs_public)\(d("committed_kbs_public"))   (any CKB: \($s.any_ckb_public))",
  "  clones (lifetime since tracking): \($s.clones_lifetime)\(d("clones_lifetime"))   daily-unique sum: \($s.clone_uniques_daily_sum)",
  "  views: \($s.views_lifetime)\(d("views_lifetime"))   stars: \($s.stars)\(d("stars"))   forks: \($s.forks)   watchers: \($s.watchers)",
  "  stats reports filed: \($s.stats_reports)\(d("stats_reports"))   releases: \($s.releases)",
  "  top referrers: \($s.top_referrers | map("\(.referrer) \(.count)") | join(", ") | if . == "" then "none yet" else . end)",
  "history: '"$out"'/history.jsonl"'
