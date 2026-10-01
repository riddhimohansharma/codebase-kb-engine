#!/usr/bin/env bash
# stats.sh — summarize this machine's anonymous /kb run metrics (performance, quality, recurring issues).
# Usage: stats.sh [--json] [--last N]        summary of local runs (default: all)
#        stats.sh --submit [--last N]         PREVIEW the anonymized report that would be filed (sends nothing)
#        stats.sh --submit --yes [--last N]   file it as a GitHub issue on the plugin repo (needs `gh` signed in)
# Data: ${CKB_STATE_DIR:-~/.local/state/codebase-kb-engine}/runs.jsonl (written by finalize.sh; CKB_METRICS=off disables).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SDIR="${CKB_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/codebase-kb-engine}"; RUNS="$SDIR/runs.jsonl"
json=0; submit=0; last=0; yes=0
while [ $# -gt 0 ]; do case "$1" in --json) json=1 ;; --submit) submit=1 ;; --yes) yes=1 ;; --last) last="${2:?}"; shift ;; *) echo "usage: stats.sh [--json] [--last N] [--submit]" >&2; exit 2 ;; esac; shift; done
[ -s "$RUNS" ] || { echo "No runs recorded yet (${RUNS}). Run /kb first, or metrics are disabled (CKB_METRICS=off)."; exit 0; }
summary="$( (if [ "$last" -gt 0 ]; then tail -n "$last" "$RUNS"; else cat "$RUNS"; fi) | jq -s '
  def pct(a; b): if b > 0 then ((a * 1000 / b) | round / 10) else null end;
  def median: sort | if length == 0 then null else .[(length / 2 | floor)] end;
  def p90: sort | if length == 0 then null else .[((length * 0.9) | floor | if . >= length then length - 1 else . end)] end;
  . as $r | ($r | length) as $n
  | {schema: 1, runs: $n, repos: ([$r[].repo] | unique | length),
     plugin_versions: ([$r[].plugin_version] | group_by(.) | map({key: .[0], value: length}) | from_entries),
     status: ([$r[].status] | group_by(.) | map({key: .[0], value: length}) | from_entries),
     complete_rate_pct: pct(([$r[] | select(.status == "complete")] | length); $n),
     duration_s: {median: ([$r[].duration_s | select(. >= 0)] | median), p90: ([$r[].duration_s | select(. >= 0)] | p90)},
     size_buckets: ([$r[].size] | group_by(.) | map({key: .[0], value: length}) | from_entries),
     coverage_pct: ([$r[].coverage | to_entries[]] | group_by(.key) | map({key: .[0].key, value: pct(([.[].value.cited] | add); ([.[].value.found] | add))}) | from_entries | with_entries(select(.value != null))),
     confirmed_pct: pct(([$r[].confidence.confirmed // 0] | add); ([$r[].confidence | ((.confirmed // 0) + (.inferred // 0) + (.unknown // 0))] | add)),
     audit_supported_pct: pct(([$r[].audit | select(.) | .supported] | add // 0); ([$r[].audit | select(.) | .total] | add // 0)),
     rules_failed: ([$r[].validation.rules_failed[]?] | group_by(.) | map({key: .[0], value: length}) | from_entries),
     top_docs_violations: ([$r[].docs_violations | to_entries[]] | group_by(.key) | map({key: .[0].key, value: ([.[].value] | add)}) | sort_by(-.value) | .[0:10] | from_entries),
     top_warnings: ([$r[].warnings | to_entries[]] | group_by(.key) | map({key: .[0].key, value: ([.[].value] | add)}) | sort_by(-.value) | .[0:10] | from_entries),
     environments: {os: ([$r[].os] | unique), jq: ([$r[].jq] | unique), uv_missing_runs: ([$r[] | select(.uv | not)] | length)}}')"
if [ "$submit" = 1 ]; then
  command -v gh >/dev/null || { echo "gh (GitHub CLI) is required to submit; run: gh auth login" >&2; exit 2; }
  body="$(printf '## Anonymous codebase-kb-engine stats report\n\nGenerated locally by `stats.sh --submit`. Contains only aggregate counts — no repository names, paths, code, URLs or values.\n\n```json\n%s\n```\n' "$summary")"
  printf '%s\n' "$body"
  if [ "$yes" != 1 ]; then printf '\nPREVIEW ONLY — nothing was sent. To post this exact text as a public issue on riddhimohansharma/codebase-kb-engine, run: stats.sh --submit --yes\n'; exit 0; fi
  printf '%s' "$body" | gh issue create -R riddhimohansharma/codebase-kb-engine --title "Stats report: v$(jq -r '.plugin_versions | keys | join(",")' <<<"$summary"), $(jq -r .runs <<<"$summary") runs" --body-file - --label stats 2>/dev/null \
    || printf '%s' "$body" | gh issue create -R riddhimohansharma/codebase-kb-engine --title "Stats report: $(jq -r .runs <<<"$summary") runs" --body-file -
  exit $?
fi
if [ "$json" = 1 ]; then printf '%s\n' "$summary"; exit 0; fi
jq -r '
  "codebase-kb-engine — local run stats (\(.runs) runs, \(.repos) repos)",
  "  status:        \(.status | to_entries | map("\(.key)=\(.value)") | join("  "))   complete \(.complete_rate_pct)%",
  "  duration:      median \(.duration_s.median // "?")s   p90 \(.duration_s.p90 // "?")s",
  "  confirmed:     \(.confirmed_pct // "?")% of claims   audit supported \(.audit_supported_pct // "n/a")%",
  "  coverage:      \(.coverage_pct | to_entries | map("\(.key) \(.value)%") | join("  "))",
  "  rules failed:  \(.rules_failed | if length == 0 then "none" else (to_entries | map("\(.key)×\(.value)") | join(" ")) end)",
  "  top warnings:", (.top_warnings | to_entries[] | "    \(.value)× \(.key)"),
  "  top doc lint:", (.top_docs_violations | to_entries[] | "    \(.value)× \(.key)"),
  "  versions:      \(.plugin_versions | to_entries | map("\(.key)=\(.value)") | join("  "))",
  "Share an anonymized copy with the maintainer: stats.sh --submit"' <<<"$summary"
"$ROOT/scripts/telemetry.sh" status | sed -n 1p
