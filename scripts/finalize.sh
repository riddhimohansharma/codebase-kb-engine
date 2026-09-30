#!/usr/bin/env bash
# finalize.sh — build ckb.json + manifest.json from the model-written draft, then validate.
# Usage: finalize.sh <repo_root> <kb_dir> [--mode local|url] [--url URL] [--branch BRANCH] [--started-at ISO]
# Reads <kb_dir>/ckb.draft.json; writes <kb_dir>/ckb.json and <kb_dir>/manifest.json; removes the draft on success.
# Exit: 0 valid · 1 artifact invalid (manifest status=invalid, draft kept) · 2 usage/precondition.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
die(){ code="$1"; shift; printf '%s\n' "$@" >&2; exit "$code"; }
repo="${1:-}"; kb="${2:-}"; shift 2 2>/dev/null || die 2 "usage: finalize.sh <repo_root> <kb_dir> [opts]"
mode=local; url=""; branch=""; started=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) mode="$2"; shift ;; --url) url="$2"; shift ;; --branch) branch="$2"; shift ;; --started-at) started="$2"; shift ;;
    *) die 2 "unknown option: $1" ;;
  esac; shift
done
[ -d "$repo" ] || die 2 "repo_root not a dir: $repo"
[ -f "$kb/.ckb-output" ] || die 2 "REFUSED: '$kb' is not a CKB output dir (no .ckb-output marker; run resolve-kb.sh first)"
draft="$kb/ckb.draft.json"
[ -f "$draft" ] || die 2 "missing draft: $draft"
jq -e . "$draft" >/dev/null 2>&1 || die 1 "draft is not valid JSON: $draft"

git -C "$repo" rev-parse HEAD >/dev/null 2>&1 || die 2 "REFUSED: '$repo' is not a git work tree with a commit; CKB requires commit_sha."
sha="$(git -C "$repo" rev-parse HEAD)"
[ -n "$branch" ] || branch="$(git -C "$repo" symbolic-ref --short -q HEAD || echo HEAD)"
if [ -z "$url" ]; then url="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"; fi
[ -n "$url" ] || url="file://$(cd "$repo" && pwd -P)"
url="$(printf '%s' "$url" | sed -E 's#^([a-zA-Z][a-zA-Z0-9+.-]*://)[^/@]*@#\1#')"   # never persist userinfo/tokens
dirty=false; [ -n "$(git -C "$repo" status --porcelain 2>/dev/null | head -1)" ] && dirty=true
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
gen_ver="$(jq -r .version "$ROOT/.claude-plugin/plugin.json")"
repo_obj="$(jq -nc --arg u "$url" --arg b "$branch" --arg s "$sha" --arg t "$now" '{url:$u, branch:$b, commit_sha:$s, generated_at:$t}')"
gen_obj="$(jq -nc --arg v "$gen_ver" '{name:"codebase-kb-engine", version:$v}')"

out="$(jq -c --argjson repo "$repo_obj" --argjson generator "$gen_obj" -f "$ROOT/scripts/normalize.jq" "$draft")" \
  || die 1 "normalize failed on draft (jq error above)"
printf '%s' "$out" | jq '.artifact' > "$kb/ckb.json"

vout="$("$ROOT/scripts/validate.sh" "$kb/ckb.json")"; vrc=$?
last="$(printf '%s\n' "$vout" | tail -1)"
structural="$(printf '%s' "$last" | sed -E 's/.*STRUCTURAL=([a-z]+).*/\1/')"
semantic="$(printf '%s' "$last" | sed -E 's/.*SEMANTIC=([a-z]+).*/\1/')"
status=complete; [ $vrc -eq 0 ] || status=invalid

outputs="$(cd "$kb" && for f in 00-overview.md 01-technical-architecture.md 02-functional-workflows.md 03-business-rules.md 04-system-context-and-gaps.md ckb.json; do
  if [ -f "$f" ]; then printf '%s\t%s\t%s\n' "$f" "$(shasum -a 256 "$f" | cut -d' ' -f1)" "$(wc -c < "$f" | tr -d ' ')"; else printf '%s\tMISSING\t0\n' "$f"; fi; done)"
missing="$(printf '%s\n' "$outputs" | awk -F'\t' '$2=="MISSING"{print $1}')"
[ -n "$missing" ] && status=incomplete
[ $vrc -eq 0 ] || status=invalid

job_id="$(printf '%s|%s|%s' "$url" "$sha" "$now" | shasum -a 256 | cut -c1-16)"
jq -n --arg id "$job_id" --arg mode "$mode" --arg started "${started:-$now}" --arg finished "$now" --arg status "$status" \
  --argjson repo "$repo_obj" --argjson generator "$gen_obj" --argjson dirty "$dirty" \
  --arg structural "$structural" --arg semantic "$semantic" --arg vout "$vout" --arg outputs "$outputs" \
  --argjson norm "$out" --slurpfile art "$kb/ckb.json" '
  {ckb_version: "0.1",
   job: {id: $id, mode: $mode, started_at: $started, finished_at: $finished, generator: $generator},
   status: $status,
   repo: ($repo + {dirty_worktree: $dirty}),
   outputs: [$outputs | split("\n")[] | select(. != "") | split("\t") | {file: .[0], sha256: (if .[1] == "MISSING" then null else .[1] end), bytes: (.[2] | tonumber), present: (.[1] != "MISSING")}],
   validation: {structural: $structural, semantic: $semantic,
                messages: [$vout | split("\n")[] | select(startswith("  ")) | ltrimstr("  ")]},
   confidence_summary: $art[0].confidence_summary,
   entity_counts: ($art[0].entities | map_values(length)) + {relations: ($art[0].relations // [] | length)},
   warnings: $norm.warnings,
   token_usage: null,
   token_usage_note: "Not observable from inside the session. Headless runs: read usage from `claude -p --output-format json`."}' > "$kb/manifest.json"

printf '%s\n' "$vout"
if [ "$status" = complete ]; then rm -f "$draft"; fi
printf 'STATUS=%s KB_DIR=%s JOB_ID=%s WARNINGS=%s%s\n' "$status" "$kb" "$job_id" "$(printf '%s' "$out" | jq '.warnings | length')" "${missing:+ MISSING=$(echo $missing | tr ' ' ',')}"
[ "$status" = complete ]
