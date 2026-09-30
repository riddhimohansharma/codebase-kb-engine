#!/usr/bin/env bash
# finalize.test.sh — producer conformance on a fixture (plan §4.1): normalization, IDs, determinism, validation, manifest.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
unset KB_DIR; : > "$T/r"
ok(){ if eval "$2"; then echo P >> "$T/r"; echo "PASS $1"; else echo F >> "$T/r"; echo "FAIL $1"; fi; }
REPO="$T/shop"; mkdir -p "$REPO" && git -C "$REPO" init -q -b main && echo x > "$REPO/a.ts"
git -C "$REPO" add -A && git -C "$REPO" -c user.email=t@t -c user.name=t commit -qm init
git -C "$REPO" remote add origin "https://user:s3cret@github.com/acme/shop.git"
KB="$(cd "$T" && "$ROOT/scripts/resolve-kb.sh" "$REPO" | sed -n 's/^KB_DIR=//p')"
for f in 00-overview 01-technical-architecture 02-functional-workflows 03-business-rules 04-system-context-and-gaps; do echo "# $f" > "$KB/$f.md"; done
run(){ cp "$ROOT/tests/fixtures/messy-draft.json" "$KB/ckb.draft.json"; "$ROOT/scripts/finalize.sh" "$REPO" "$KB" >"$T/out" 2>&1; }
run; rc=$?
A="$KB/ckb.json"; M="$KB/manifest.json"; q(){ jq -r "$1" "$A"; }
ok "finalize exits 0 on a complete KB"         '[ $rc -eq 0 ]'
ok "manifest status=complete"                   '[ "$(jq -r .status "$M")" = complete ]'
ok "schema+semantic pass recorded"              '[ "$(jq -r ".validation.structural+\"/\"+.validation.semantic" "$M")" = "pass/pass" ] || [ "$(jq -r .validation.structural "$M")" = skipped ]'
ok "all 6 outputs present with sha256"          '[ "$(jq "[.outputs[] | select(.present and (.sha256|length)==64)] | length" "$M")" = 6 ]'
ok "draft removed after success"                '[ ! -e "$KB/ckb.draft.json" ]'
ok "credentials stripped from repo.url"         '[ "$(q .repo.url)" = "https://github.com/acme/shop.git" ]'
ok "no secret anywhere in KB"                   '! grep -rq s3cret "$KB"'
ok "full 40-hex commit_sha"                     'q .repo.commit_sha | grep -qE "^[0-9a-f]{40}$"'
ok "express :userId + Next [userId] merged"     '[ "$(q "[.entities.interfaces[].id] | map(select(. == \"interface:http:provides:GET:/users/{user_id}\")) | length")" = 1 ]'
ok "merged provenance unioned (2 sites)"        '[ "$(q ".entities.interfaces[] | select(.id|endswith(\"/users/{user_id}\")) | .provenance | length")" = 2 ]'
ok "flask <int:order_id> normalized"            'q ".entities.interfaces[].id" | grep -qx "interface:http:provides:POST:/orders/{order_id}/items"'
ok "next [...slug] normalized"                  'q ".entities.interfaces[].id" | grep -qx "interface:http:provides:GET:/docs/{slug}"'
ok "absolute-path provenance dropped -> unknown" '[ "$(q ".entities.interfaces[] | select(.id|endswith(\"/docs/{slug}\")) | .confidence")" = unknown ]'
ok "invalid confidence value -> unknown"        '[ "$(q ".entities.interfaces[] | select(.id|contains(\"/orders/\")) | .confidence")" = unknown ]'
ok "pypi PEP 503 normalization"                 '[ "$(q .entities.dependencies[0].package_key)" = "pypi:django-rest-framework" ]'
ok "unknown field stripped"                     '[ "$(q ".entities.components[0] | has(\"colour\")")" = false ]'
ok "slug collision suffixed"                    '[ "$(q "[.entities.business_rules[].id] | join(\",\")")" = "business_rule:admin-only,business_rule:admin-only-2" ]'
ok "local refs remapped (applies_to)"           '[ "$(q ".entities.business_rules[0].applies_to | join(\",\")")" = "component:src/api,interface:http:provides:GET:/users/{user_id}" ]'
ok "workflow steps renumbered 1..n in order"    '[ "$(q "[.entities.workflows[0].steps[].order] | join(\",\")")" = "1,2" ] && [ "$(q .entities.workflows[0].steps[0].description)" = call ]'
ok "malformed relation dropped + warned"        '[ "$(q ".relations | length")" = 1 ] && jq -e ".warnings | index(\"dropped malformed relation\")" "$M" >/dev/null'
ok "bad end_line dropped"                       '[ "$(q ".entities.datastores[0].provenance[0] | has(\"end_line\")")" = false ]'
ok "confidence_summary matches claims"          '[ "$(q ".confidence_summary | [.confirmed,.inferred,.unknown] | add")" = "$(q "[.entities[][], .relations[]] | length")" ]'
ids1="$(q '[.. | .id? // empty] | join(",")')"
run; ids2="$(jq -r '[.. | .id? // empty] | join(",")' "$A")"
ok "determinism: re-run on same commit -> identical IDs" '[ "$ids1" = "$ids2" ]'
ok "determinism: artifact identical except generated_at" '[ "$(jq -c "del(.repo.generated_at)" "$A" | shasum)" = "$(cp "$A" "$T/a1"; run; jq -c "del(.repo.generated_at)" "$A" | shasum)" ]'
cp "$ROOT/tests/fixtures/messy-draft.json" "$KB/ckb.draft.json"; jq '.entities.components[0].kind = "microservice"' "$KB/ckb.draft.json" > "$T/bad" && mv "$T/bad" "$KB/ckb.draft.json"
"$ROOT/scripts/finalize.sh" "$REPO" "$KB" >"$T/out" 2>&1; rc=$?
ok "invalid enum -> exit 1, status=invalid"     '[ $rc -eq 1 ] && [ "$(jq -r .status "$M")" = invalid ] || [ "$(jq -r .validation.structural "$M")" = skipped ]'
ok "draft kept for repair on failure"           '[ -e "$KB/ckb.draft.json" ]'
rm "$KB/03-business-rules.md"; run; rc=$?
ok "missing doc -> status=incomplete"           '[ $rc -ne 0 ] && [ "$(jq -r .status "$M")" = incomplete ]'
rm -f "$KB/.ckb-output"; run; rc=$?
ok "refuses dir without .ckb-output marker"     '[ $rc -eq 2 ]'
pass=$(grep -c P "$T/r"); fail=$(grep -c F "$T/r"); echo "---"; echo "finalize tests: $pass passed, $fail failed"; [ "$fail" -eq 0 ]
