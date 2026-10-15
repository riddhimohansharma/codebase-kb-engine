#!/usr/bin/env bash
# spec-companions.test.sh — the engine's use of the vendored CKB v0.3 companions (views, SBOM) and the ACC rule checker.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok(){ if eval "$2"; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1"; fi; }
Q="$ROOT/scripts/kbq.sh"; AC="$ROOT/spec/agent-context/v0.1"
mkdir -p "$T/kb"; cp "$ROOT/tests/fixtures/docs/ckb.json" "$T/kb/"
ok "spec v0.3 companions and ACC are vendored"            '[ -f "$ROOT/spec/v0.3/views.jq" ] && [ -f "$ROOT/spec/v0.3/cyclonedx.jq" ] && [ -f "$AC/rules.jq" ] && [ -f "$AC/acc.jq" ]'
ok "vendored spec is in sync with the spec repo (when present)" '[ ! -d "$ROOT/../codebase-kb-spec/.git" ] || "$ROOT/tools/sync-spec.sh" --check >/dev/null 2>&1'
ok "view summary works on a v0.2 artifact"                '"$Q" view "$T/kb" summary | jq -e ".repo.key == \"github.com/acme/shop\" and .counts.components == 2" >/dev/null'
ok "view impact names the component owning a path"       '"$Q" view "$T/kb" impact src/api/routes.ts | jq -e ".components == [\"component:src/api\"]" >/dev/null'
ok "view entity returns relations"                       'id="$(jq -r ".entities.components[0].id" "$T/kb/ckb.json")"; "$Q" view "$T/kb" entity "$id" | jq -e "has(\"out\") and has(\"in\")" >/dev/null'
ok "view output is bounded and cites path:line"          '"$Q" view "$T/kb" interfaces | jq -e "length <= 51 and all(.[]; (.at[0] // \"x:1\") | test(\":[0-9]+\"))" >/dev/null'
ok "view rejects an unknown view and missing args (exit 2)" '"$Q" view "$T/kb" nope >/dev/null 2>&1; [ $? -eq 2 ] && "$Q" view "$T/kb" impact >/dev/null 2>&1; [ $? -eq 2 ]'
ok "sbom is CycloneDX 1.6 with one component per direct dependency" '"$Q" sbom "$T/kb" | jq -e ".bomFormat == \"CycloneDX\" and .specVersion == \"1.6\" and (.components | length) == 2" >/dev/null'
acc(){ jq -R -s -L "$AC" -f "$AC/rules.jq" "$1"; }
ok "every dogfood seed conforms to ACC Core (spec checker)" 'for f in "$ROOT"/templates/agent-context/dogfood/*.md; do [ "$(acc "$f" | jq length)" = 0 ] || exit 1; done'
ok "engine lint and ACC Core agree on the seeds"           'for f in "$ROOT"/templates/agent-context/dogfood/*.md; do "$ROOT/scripts/lint-agent-context.sh" "$f" >/dev/null || exit 1; done'
D="$(mktemp -d)"; git -C "$D" init -q -b main; printf '[tool.pytest]\n' > "$D/pyproject.toml"; : > "$D/uv.lock"; mkdir -p "$D/db/migration"; : > "$D/db/migration/V1.sql"; git -C "$D" add -A; git -C "$D" -c user.email=t@t -c user.name=t commit -qm i
"$ROOT/scripts/agent-context.sh" "$D" | grep -v "TODO(human)" | grep -v "^<!--" > "$T/p.md"
ok "a generated proposal with its TODO lines filled conforms to ACC Core" '[ "$(acc "$T/p.md" | jq length)" = 0 ]'
ok "ACC Core rejects what the engine lint rejects (over budget)" 'cp "$T/p.md" "$T/big.md"; for i in $(seq 1 12); do printf -- "- %s\n" "$(awk "BEGIN{for(i=0;i<40;i++) printf \"w \"}" | sed "s/ $//")" >> "$T/big.md"; done; acc "$T/big.md" | jq -e "map(select(startswith(\"A2\"))) | length == 1" >/dev/null && ! "$ROOT/scripts/lint-agent-context.sh" "$T/big.md" >/dev/null'
rm -rf "$D"
echo "spec-companions tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
