#!/usr/bin/env bash
# bench.sh — maintainer benchmark: run /kb headless on a pinned polyglot suite and record cost, speed, coverage,
# quality and route accuracy vs ground truth. Results append to <out>/results.jsonl (one line per repo per run).
# Usage: tools/bench.sh [--suite FILE] [--only a,b] [--model M] [--out DIR] [--baseline FILE] [--dry-run]
#        tools/bench.sh --compare NEW.jsonl BASE.jsonl     evaluate the regression gate only (no model runs)
#   --baseline/--compare: exit 1 on regressions: status, route recall, cost, wall time, cache-hit rate. Thresholds (override via env):
#     BENCH_RECALL_DROP=0.05  BENCH_COST_INC=1.2 (+20%)  BENCH_WALL_INC=1.25 (+25%)  BENCH_CACHE_DROP=10 (percentage points)
# Runs never report telemetry upstream (CKB_TELEMETRY=off), so benchmark runs cannot pollute the maintainer's dataset.
# Cost: roughly $3–11 per repo per run. Clones go to a temp dir that is always deleted.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
suite="$ROOT/tools/bench/suite.json"; only=""; model="sonnet"; dry=0; baseline=""; cmp_new=""; cmp_base=""
out="${XDG_STATE_HOME:-$HOME/.local/state}/codebase-kb-engine/bench"
while [ $# -gt 0 ]; do case "$1" in
  --suite) suite="$2"; shift ;; --only) only="$2"; shift ;; --model) model="$2"; shift ;; --out) out="$2"; shift ;;
  --baseline) baseline="$2"; shift ;; --dry-run) dry=1 ;; --compare) cmp_new="${2:-}"; cmp_base="${3:-}"; shift 2 ;;
  *) echo "unknown option: $1" >&2; exit 2 ;; esac; shift; done
mkdir -p "$out"; ver="$(jq -r .version "$ROOT/.claude-plugin/plugin.json")"; run_id="$(date -u +%Y%m%dT%H%M%SZ)"
TOOLS="Read,Grep,Glob,Bash,Write,Edit,Task,Agent,Skill,TodoWrite"
# route key: METHOD + path with an optional leading /api removed and every {param} collapsed to {}
gate(){ # gate <results.jsonl> <baseline.jsonl> <run id>: print regressions, exit 1 if any
  local reg
  reg="$(jq -s -r --arg run "$3" --slurpfile b "$2" --argjson rd "${BENCH_RECALL_DROP:-0.05}" --argjson ci "${BENCH_COST_INC:-1.2}" \
        --argjson wi "${BENCH_WALL_INC:-1.25}" --argjson cd "${BENCH_CACHE_DROP:-10}" '
    ($b | group_by(.repo) | map({key: .[0].repo, value: (sort_by(.run) | last)}) | from_entries) as $base
    | [.[] | select(.run == $run) | . as $n | $base[$n.repo] as $o | select($o != null)
       | (if $o.status == "complete" and $n.status != "complete" then "\($n.repo): status \($o.status) -> \($n.status)" else empty end),
         (if ($o.route_accuracy.recall != null and $n.route_accuracy.recall != null and ($n.route_accuracy.recall < $o.route_accuracy.recall - $rd)) then "\($n.repo): recall \($o.route_accuracy.recall) -> \($n.route_accuracy.recall)" else empty end),
         (if ($o.cost_usd // 0) > 0 and ($n.cost_usd // 0) > ($o.cost_usd * $ci) then "\($n.repo): cost $\($o.cost_usd) -> $\($n.cost_usd)" else empty end),
         (if ($o.wall_s // 0) > 0 and ($n.wall_s // 0) > ($o.wall_s * $wi) then "\($n.repo): wall \($o.wall_s)s -> \($n.wall_s)s" else empty end),
         (if ($o.tokens.cache_hit_pct != null and $n.tokens.cache_hit_pct != null and ($n.tokens.cache_hit_pct < $o.tokens.cache_hit_pct - $cd)) then "\($n.repo): cache hit \($o.tokens.cache_hit_pct)% -> \($n.tokens.cache_hit_pct)%" else empty end)] | .[]' "$1")"
  if [ -n "$reg" ]; then echo; echo "REGRESSIONS vs baseline:"; printf '  %s\n' "$reg"; return 1; else echo; echo "no regressions vs baseline"; return 0; fi
}
if [ -n "$cmp_new" ]; then
  [ -f "$cmp_new" ] && [ -f "$cmp_base" ] || { echo "usage: bench.sh --compare NEW.jsonl BASE.jsonl" >&2; exit 2; }
  gate "$cmp_new" "$cmp_base" "$(jq -rs 'map(.run) | max' "$cmp_new")"; exit $?
fi
NORM='def k: (.[0:index(" ")]) + " " + (.[index(" ")+1:] | sub("^/api(?=/|$)"; "") | gsub("\\{[^}]*\\}"; "{}") | if . == "" then "/" else . end);'
jq -c '.repos[]' "$suite" | while IFS= read -r r; do
  name="$(jq -r .name <<<"$r")"; [ -n "$only" ] && ! printf ',%s,' "$only" | grep -q ",$name," && continue
  url="$(jq -r .url <<<"$r")"; commit="$(jq -r .commit <<<"$r")"; gt="$(jq -r '.ground_truth // empty' <<<"$r")"
  if [ "$dry" = 1 ]; then echo "would run: $name @ ${commit:0:12} ($url) model=$model gt=${gt:-none}"; continue; fi
  w="$(mktemp -d)"; echo "== $name @ ${commit:0:12}"
  if ! { git -C "$w" init -q && git -C "$w" remote add origin "$url" && GIT_TERMINAL_PROMPT=0 git -C "$w" fetch -q --depth 1 origin "$commit" && git -C "$w" checkout -q FETCH_HEAD; }; then
    echo "   fetch failed"; rm -rf "$w"; continue; fi
  t0=$(date +%s)
  ( cd "$w" && CKB_STATE_DIR="$out/state" CKB_TELEMETRY=off claude -p "/codebase-kb-engine:kb" --plugin-dir "$ROOT" --permission-mode acceptEdits \
      --allowedTools "$TOOLS" --model "$model" --max-turns 250 --output-format json ) > "$w.run.json" 2>"$w.err"
  t1=$(date +%s); kb="$w/.ckb"
  [ -f "$kb/manifest.json" ] && CKB_STATE_DIR="$out/state" "$ROOT/scripts/usage.sh" record "$kb" "$w.run.json" >/dev/null 2>&1   # patch exact usage/cost into the manifest and the local run row
  acc='null'
  if [ -n "$gt" ] && [ -f "$kb/ckb.json" ]; then
    acc="$(jq -n --slurpfile a "$kb/ckb.json" --slurpfile g "$ROOT/tools/bench/ground-truth/$gt.json" "$NORM"'
      ([$g[0].http_provides[] | k] | unique) as $want
      | ([$a[0].entities.interfaces[]? | select(.kind == "http" and .role == "provides") | "\(.http.method) \(.http.normalized_path)" | k] | unique) as $got
      | ([$want[] | select(. as $x | $got | index($x))]) as $hit
      | {gt: ($want | length), found: ($got | length), matched: ($hit | length),
         recall: (if ($want | length) > 0 then (($hit | length) * 1000 / ($want | length) | round / 1000) else null end),
         precision: (if ($got | length) > 0 then (($hit | length) * 1000 / ($got | length) | round / 1000) else null end),
         missing: [$want[] | select(. as $x | $hit | index($x) | not)]}')"
  fi
  jq -c -n --arg suite "$(jq -r .suite "$suite")" --arg ver "$ver" --arg run "$run_id" --arg name "$name" --arg commit "$commit" \
     --arg lang "$(jq -r .language <<<"$r")" --arg model "$model" --argjson wall "$((t1 - t0))" --argjson acc "$acc" \
     --slurpfile res <(jq -c . "$w.run.json" 2>/dev/null || echo '{}') --slurpfile man <(jq -c . "$kb/manifest.json" 2>/dev/null || echo '{}') '
    ($res[0]) as $x | ($man[0]) as $m
    | {suite: $suite, run: $run, plugin_version: $ver, repo: $name, commit: $commit, language: $lang, model: $model,
       status: ($m.status // "no-manifest"), wall_s: $wall, turns: $x.num_turns, cost_usd: $x.total_cost_usd,
       permission_denials: ($x.permission_denials // [] | length),
       tokens: ($x.usage // {}) as $u | (($u.input_tokens // 0) + ($u.cache_read_input_tokens // 0) + ($u.cache_creation_input_tokens // 0)) as $tot
               | {input: $u.input_tokens, output: $u.output_tokens, cache_read: $u.cache_read_input_tokens, cache_creation: $u.cache_creation_input_tokens,
                  cache_hit_pct: (if $tot > 0 then ((($u.cache_read_input_tokens // 0) * 1000 / $tot) | round / 10) else null end)},
       phase_s: ($m.perf.phase_s // null), finalize_s: ($m.perf.finalize_s // null),
       validation: {structural: $m.validation.structural, semantic: $m.validation.semantic, docs: (($m.validation.docs // {}) | map_values(length))},
       coverage: (($m.coverage.buckets // {}) | map_values({found, cited})), entities: ($m.entity_counts // {}),
       confidence: ($m.confidence_summary // {}), warnings: ($m.warnings // [] | length), route_accuracy: $acc}' >> "$out/results.jsonl"
  tail -1 "$out/results.jsonl" | jq -r '"   status=\(.status) cost=$\(.cost_usd // "?") turns=\(.turns // "?") wall=\(.wall_s)s denials=\(.permission_denials) recall=\(.route_accuracy.recall // "n/a") precision=\(.route_accuracy.precision // "n/a")"'
  rm -rf "$w" "$w.run.json" "$w.err"
done
[ "$dry" = 1 ] && exit 0
echo; echo "results: $out/results.jsonl"
jq -s -r --arg run "$run_id" '[.[] | select(.run == $run)] | (["REPO","STATUS","COST$","TURNS","WALL_S","CACHE%","RECALL","PREC","CONFIRMED%"] | @tsv),
  (.[] | [.repo, .status, ((.cost_usd // 0) * 100 | round / 100), .turns, .wall_s, (.tokens.cache_hit_pct // "-"), (.route_accuracy.recall // "-"), (.route_accuracy.precision // "-"),
          (if (.confidence.confirmed // 0) > 0 then ((.confidence.confirmed * 100 / ((.confidence.confirmed // 0) + (.confidence.inferred // 0) + (.confidence.unknown // 0))) | round) else "-" end)] | @tsv)' "$out/results.jsonl" | column -t
if [ -n "$baseline" ] && [ -f "$baseline" ]; then gate "$out/results.jsonl" "$baseline" "$run_id" || exit 1; fi
