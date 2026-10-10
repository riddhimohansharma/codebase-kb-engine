#!/usr/bin/env bash
# bench.test.sh — tools/bench.sh regression gate, offline (--compare on synthetic results; no model runs, no cost).
# Each threshold is tested just inside and just outside its boundary, so changing a constant is caught.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok(){ if eval "$2"; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1"; fi; }
B="$ROOT/tools/bench.sh"

# row <run> <repo> <status> <recall|null> <cost> <wall_s> <cache_hit_pct|null>
row(){ jq -nc --arg run "$1" --arg repo "$2" --arg st "$3" --argjson rc "$4" --argjson cost "$5" --argjson wall "$6" --argjson ch "$7" \
  '{run:$run, repo:$repo, status:$st, cost_usd:$cost, wall_s:$wall, tokens:{cache_hit_pct:$ch}, route_accuracy:{recall:$rc, precision:0.9}}'; }
BASE="$T/base.jsonl"; row R1 app complete 0.90 4.0 1000 80 > "$BASE"
# new <run> <status> <recall> <cost> <wall> <cache> -> exit code of the gate
gate(){ local f="$T/new.jsonl"; row "$@" > "$f"; "$B" --compare "$f" "$BASE" > "$T/out" 2>&1; echo $?; }
reg(){ grep -q "REGRESSIONS" "$T/out"; }

ok "identical run: no regressions, exit 0"                       '[ "$(gate R2 app complete 0.90 4.0 1000 80)" = 0 ] && grep -q "no regressions" "$T/out"'
ok "status complete -> incomplete is a regression"               '[ "$(gate R2 app incomplete 0.90 4.0 1000 80)" = 1 ] && reg && grep -q "status complete -> incomplete" "$T/out"'
ok "recall drop of 0.06 (> 0.05) is a regression"                '[ "$(gate R2 app complete 0.84 4.0 1000 80)" = 1 ] && grep -q "recall" "$T/out"'
ok "recall drop of 0.04 (< 0.05) is tolerated"                   '[ "$(gate R2 app complete 0.86 4.0 1000 80)" = 0 ]'
ok "cost +22% (> +20%) is a regression"                          '[ "$(gate R2 app complete 0.90 4.9 1000 80)" = 1 ] && grep -q "cost" "$T/out"'
ok "cost +17% (< +20%) is tolerated"                             '[ "$(gate R2 app complete 0.90 4.7 1000 80)" = 0 ]'
ok "wall time +30% (> +25%) is a regression"                     '[ "$(gate R2 app complete 0.90 4.0 1300 80)" = 1 ] && grep -q "wall" "$T/out"'
ok "wall time +20% (< +25%) is tolerated"                        '[ "$(gate R2 app complete 0.90 4.0 1200 80)" = 0 ]'
ok "cache-hit drop of 12 points (> 10) is a regression"          '[ "$(gate R2 app complete 0.90 4.0 1000 68)" = 1 ] && grep -q "cache hit" "$T/out"'
ok "cache-hit drop of 8 points (< 10) is tolerated"              '[ "$(gate R2 app complete 0.90 4.0 1000 72)" = 0 ]'
ok "cache-hit improving is never a regression"                   '[ "$(gate R2 app complete 0.90 4.0 1000 95)" = 0 ]'
ok "several regressions are all reported"                        '[ "$(gate R2 app incomplete 0.50 9.0 5000 10)" = 1 ] && [ "$(grep -cE "status|recall|cost|wall|cache hit" "$T/out")" -ge 5 ]'
ok "null recall / null cache are skipped, not crashed on"        '[ "$(gate R2 app complete null 4.0 1000 null)" = 0 ]'
ok "a repo absent from the baseline is ignored"                  '[ "$(gate R2 other incomplete 0.1 99 99999 1)" = 0 ]'
ok "only the latest run in the new file is judged"               '{ row R2 app incomplete 0.9 4 1000 80; row R3 app complete 0.9 4 1000 80; } > "$T/two.jsonl"; "$B" --compare "$T/two.jsonl" "$BASE" >/dev/null 2>&1'
ok "thresholds are overridable via env"                          'row R2 app complete 0.90 4.9 1000 80 > "$T/new.jsonl"; BENCH_COST_INC=1.5 "$B" --compare "$T/new.jsonl" "$BASE" >/dev/null 2>&1'
ok "--compare with a missing file is a usage error (exit 2)"     '"$B" --compare "$T/nope.jsonl" "$BASE" >/dev/null 2>&1; [ $? -eq 2 ]'
ok "--dry-run still works and spends nothing"                    '"$B" --dry-run --only golang-gin-realworld 2>&1 | grep -q "would run: golang-gin-realworld"'
ok "benchmark runs never report telemetry upstream"              'grep -q "CKB_TELEMETRY=off claude -p" "$B"'
ok "benchmark patches exact usage via usage.sh record"           'grep -q "usage.sh\" record" "$B"'

echo "bench tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
