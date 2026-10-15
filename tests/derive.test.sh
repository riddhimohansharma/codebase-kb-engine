#!/usr/bin/env bash
# derive.test.sh — normalize.jq derives provides/consumes/depends_on from entities (nearest-ancestor module_id) instead of the model.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
pass=0; fail=0
ok(){ if eval "$2"; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1"; fi; }
LINES='{"src/api/routes.ts":50,"src/worker/job.ts":50,"src/worker/sub/x.ts":50,"package.json":50,"src/worker/package.json":50,"lib/orphan.ts":50,"app.ts":50}'
norm(){ jq -c --argjson repo '{"url":"https://github.com/a/b","branch":"main","commit_sha":"0123456789abcdef0123456789abcdef01234567","generated_at":"2026-10-15T00:00:00Z"}' --argjson generator '{"name":"x","version":"1"}' --argjson roots '[]' --argjson lines "$LINES" -L "$ROOT/spec/v0.2" -f "$ROOT/scripts/normalize.jq" <<<"$1"; }
P(){ echo "{\"path\":\"$1\",\"line\":$2}"; }
comp(){ echo "{\"id\":\"c-$1\",\"name\":\"$1\",\"module_id\":\"$2\",\"kind\":\"service\",\"confidence\":\"confirmed\",\"provenance\":[$(P "$3" 1)]}"; }
iface(){ echo "{\"id\":\"i-$1\",\"name\":\"$1\",\"kind\":\"http\",\"role\":\"$2\",\"service_key\":\"s\",\"http\":{\"method\":\"GET\",\"path\":\"/$1\"},\"confidence\":\"confirmed\",\"provenance\":[$(P "$3" 3)]}"; }
dep(){ echo "{\"id\":\"d-$1\",\"name\":\"$1\",\"purl\":\"pkg:npm/$1\",\"manifest_path\":\"$2\",\"scope\":\"runtime\",\"source\":\"registry\",\"confidence\":\"confirmed\",\"provenance\":[$(P "$2" 5)]}"; }
mk(){ echo "{\"entities\":{\"components\":[$1],\"interfaces\":[$2],\"dependencies\":[$3]},\"relations\":$4}"; }
rels(){ norm "$1" | jq -c '[.artifact.relations[]? | {from: (.from | sub("^[a-z_]+:"; "")), to: (.to | sub("^[a-z_]+:[a-z]+:"; "")), kind}] | sort'; }
has(){ norm "$1" | jq -e "[.artifact.relations[]? | select(.kind == \"$2\")] | length $3" >/dev/null; }

ROOTC="$(comp root . app.ts)"; WORKC="$(comp worker src/worker src/worker/job.ts)"
D1="$(mk "$ROOTC,$WORKC" "$(iface orders provides src/api/routes.ts),$(iface jobs provides src/worker/job.ts)" "$(dep express package.json),$(dep bull src/worker/package.json)" '[]')"
ok "no model relations at all: every interface and dependency still gets an edge" '[ "$(norm "$D1" | jq ".artifact.relations | length")" = 4 ]'
rootid(){ norm "$1" | jq -r '.artifact.entities.components[] | select(.module_id == ".") | .id'; }
ok "an interface under src/api belongs to the root component"   'r="$(rootid "$D1")"; [ -n "$r" ] && norm "$D1" | jq -e --arg r "$r" "[.artifact.relations[] | select(.kind == \"provides\" and (.to | contains(\"orders\")))] | .[0].from == \$r" >/dev/null'
ok "nearest ancestor wins: an interface under src/worker belongs to worker, not root" 'norm "$D1" | jq -e "[.artifact.relations[] | select(.kind == \"provides\" and (.to | contains(\"jobs\")))] | .[0].from | contains(\"worker\")" >/dev/null'
ok "a dependency in a nested manifest goes to the nested component" 'norm "$D1" | jq -e "[.artifact.relations[] | select(.kind == \"depends_on\" and (.to | contains(\"bull\")))] | .[0].from | contains(\"worker\")" >/dev/null'
ok "a root manifest dependency goes to the root component"      'r="$(rootid "$D1")"; [ -n "$r" ] && norm "$D1" | jq -e --arg r "$r" "[.artifact.relations[] | select(.kind == \"depends_on\" and (.to | contains(\"express\")))] | .[0].from == \$r" >/dev/null'
D2="$(mk "$ROOTC" "$(iface feed consumes src/api/routes.ts)" "" '[]')"
ok "a consumes interface yields a consumes edge (role decides the kind)" 'has "$D2" consumes "== 1" && has "$D2" provides "== 0"'
ok "derived edges are inferred and carry the entity provenance" 'norm "$D1" | jq -e "[.artifact.relations[] | select(.kind == \"provides\")] | all(.confidence == \"inferred\" and (.provenance | length) >= 1)" >/dev/null'
ok "a model-written edge for the same triple is merged, not duplicated" 'D3="$(mk "$ROOTC" "$(iface orders provides src/api/routes.ts)" "" "[{\"from\":\"c-root\",\"to\":\"i-orders\",\"kind\":\"provides\",\"confidence\":\"confirmed\",\"provenance\":[$(P src/api/routes.ts 3)]}]")"; [ "$(norm "$D3" | jq "[.artifact.relations[] | select(.kind == \"provides\")] | length")" = 1 ]'
ok "no matching component: a warning, not a silent drop"        'D4="$(mk "$WORKC" "$(iface lost provides lib/orphan.ts)" "" "[]")"; norm "$D4" | jq -e "[.warnings[] | select(startswith(\"no component contains interface\"))] | length == 1" >/dev/null && has "$D4" provides "== 0"'
ok "an entity without valid provenance is skipped (nothing invented)" 'D5="$(mk "$ROOTC" "{\"id\":\"i-x\",\"name\":\"x\",\"kind\":\"http\",\"role\":\"provides\",\"service_key\":\"s\",\"http\":{\"method\":\"GET\",\"path\":\"/x\"},\"confidence\":\"confirmed\",\"provenance\":[]}" "" "[]")"; has "$D5" provides "== 0"'
ok "enforces/imports/other model edges are untouched"           'D6="$(mk "$ROOTC,$WORKC" "" "" "[{\"from\":\"c-root\",\"to\":\"c-worker\",\"kind\":\"imports\",\"confidence\":\"inferred\",\"provenance\":[$(P app.ts 1)]}]")"; has "$D6" imports "== 1"'
ok "output is deterministic"                                    '[ "$(norm "$D1")" = "$(norm "$D1")" ]'
ok "the contract no longer asks scouts to write provides/consumes/depends_on" '! grep -q "Every interface needs at least one" "$ROOT/skills/ckb-contract/SKILL.md" && ! grep -q "Every interface needs a \`provides\`" "$ROOT/agents/scout.md" && grep -q "derived by the normalizer" "$ROOT/skills/ckb-contract/SKILL.md"'
echo "derive tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
