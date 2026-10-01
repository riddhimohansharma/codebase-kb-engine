#!/usr/bin/env bash
# inventory.test.sh — scripts/inventory.sh + scripts/coverage.sh on the polyglot fixture: exclusions, buckets,
# workspaces, languages, areas, size cap, determinism, read-only-ness, coverage counts.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
# isolate from the user's git config / global excludes so the fixture's node_modules/ etc. are really tracked
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$T/xdg" HOME="$T"
pass=0; fail=0
ok(){ if eval "$2"; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1"; fi; }
REPO="$T/poly"; cp -R "$ROOT/tests/fixtures/polyglot" "$REPO"
# runtime-only files: a KB dir that must be ignored, a >1MB source file whose route must NOT be sniffed,
# and a vendored node_modules file in case a packager dropped the committed one
mkdir -p "$REPO/ckb" "$REPO/node_modules/left-pad" "$REPO/apps/web/src/huge"
echo '{"ckb_version":"0.2"}' > "$REPO/ckb/ckb.json"
[ -f "$REPO/node_modules/left-pad/index.js" ] || echo 'app.get("/never")' > "$REPO/node_modules/left-pad/index.js"
{ echo 'app.get("/huge", h);'; awk 'BEGIN { for (i = 0; i < 12000; i++) printf "%0100d\n", i }'; } > "$REPO/apps/web/src/huge/big.js"
git -C "$REPO" init -q -b main && git -C "$REPO" add -A && git -C "$REPO" -c user.email=t@t -c user.name=t commit -qm init
echo 'process.env.UNTRACKED_FLAG' > "$REPO/apps/web/src/untracked.js"   # untracked but not ignored -> included (-o)
git -C "$REPO" status --porcelain > "$T/st.before"
t0=$(date +%s)
"$ROOT/scripts/inventory.sh" "$REPO" > "$T/inv.json" 2> "$T/inv.err"; rc=$?
t1=$(date +%s)
I="$T/inv.json"; q(){ jq -r "$1" "$I"; }
has(){ jq -e --arg b "$1" --arg p "$2" '.buckets[$b] | index($p) != null' "$I" >/dev/null; }
hasnt(){ ! has "$1" "$2"; }
anyb(){ jq -e --arg p "$1" '[.buckets[][]] | index($p) != null' "$I" >/dev/null; }
ok "inventory exits 0 with valid JSON"            '[ $rc -eq 0 ] && jq -e "type == \"object\"" "$I" >/dev/null'
ok "inventory writes nothing to stderr"            '[ ! -s "$T/inv.err" ]'
ok "inventory is read-only (git status unchanged)" '[ "$(git -C "$REPO" status --porcelain)" = "$(cat "$T/st.before")" ]'
ok "top-level keys"                                '[ "$(q "[keys[]] | join(\",\")")" = "areas,buckets,excluded_by,excluded_total,files_total,languages,submodules,workspaces" ]'
ok "all 10 contract buckets present"               '[ "$(q ".buckets | keys | join(\",\")")" = "api_specs,ci,config,datastores,events,iac,lockfiles,manifests,migrations,routes" ]'
ok "bucket lists are sorted + unique"              '[ "$(q "[.buckets[] | (. == (unique))] | all")" = true ]'
# exclusions
ok "node_modules excluded"                         '! anyb node_modules/left-pad/index.js && ! anyb node_modules/left-pad/package.json'
ok "*.pb.go excluded"                              '! anyb services/gateway/api/items.pb.go'
ok "*.d.ts excluded"                               '! anyb packages/ui/src/index.d.ts'
ok "Code generated DO NOT EDIT header excluded"    '! anyb services/gateway/internal/zz_deepcopy.go'
ok "ckb/ excluded"                                 '! anyb ckb/ckb.json'
ok "excluded_by counts (dir 2, name 2, header 1, ckb 1)" '[ "$(q ".excluded_by | [.vendored_dir,.generated_name,.generated_header,.ckb] | join(\",\")")" = "2,2,1,1" ]'
ok "excluded_total = sum"                          '[ "$(q ".excluded_total")" = 6 ]'
ok "files_total counts included files (incl. untracked)" '[ "$(q .files_total)" = 38 ]'
ok ">1MB file not content-sniffed"                 'hasnt routes apps/web/src/huge/big.js'
ok "untracked non-ignored file included"           'has config apps/web/src/untracked.js'
# buckets
ok "manifests: polyglot set"                       'for p in package.json apps/web/package.json packages/ui/package.json services/orders/pom.xml services/orders/orders-api/pom.xml services/catalog/requirements.txt services/gateway/go.mod services/storefront/Gemfile services/gateway/Dockerfile infra/terraform/main.tf go.work; do has manifests $p || exit 1; done'
ok "lockfiles: npm, go.sum, Gemfile.lock"          '[ "$(q ".buckets.lockfiles | join(\",\")")" = "package-lock.json,services/gateway/go.sum,services/storefront/Gemfile.lock" ]'
ok "routes: spring, django, chi, rails, express, nginx" '[ "$(q ".buckets.routes | join(\",\")")" = "apps/web/src/server.js,infra/nginx/nginx.conf,services/catalog/catalog/urls.py,services/gateway/main.go,services/orders/orders-api/src/main/java/com/acme/orders/OrderController.java,services/storefront/config/routes.rb" ]'
ok "events: kafkajs producer"                      '[ "$(q ".buckets.events | join(\",\")")" = "apps/web/src/server.js" ]'
ok "datastores: JPA @Entity + Django model"        '[ "$(q ".buckets.datastores | join(\",\")")" = "services/catalog/catalog/models.py,services/orders/orders-api/src/main/java/com/acme/orders/Order.java" ]'
ok "migrations: Flyway V1__ + Django migrations/"  '[ "$(q ".buckets.migrations | join(\",\")")" = "services/catalog/catalog/migrations/0001_initial.py,services/orders/orders-api/src/main/resources/db/migration/V1__init.sql" ]'
ok "iac: tf, Dockerfile, compose, nginx, k8s by content" '[ "$(q ".buckets.iac | join(\",\")")" = "docker-compose.yml,infra/nginx/nginx.conf,infra/terraform/main.tf,services/gateway/Dockerfile,services/gateway/kube.yaml" ]'
ok "ci: github workflow"                           '[ "$(q ".buckets.ci | join(\",\")")" = ".github/workflows/ci.yml" ]'
ok "config: .env.example, application.yml, settings.py, env readers" 'for p in .env.example services/orders/orders-api/src/main/resources/application.yml services/catalog/catalog/settings.py packages/ui/src/index.ts services/gateway/main.go apps/web/src/server.js; do has config $p || exit 1; done'
ok "config: no false positive on plain util"       'hasnt config apps/web/src/util.js'
ok "api_specs: openapi + proto"                    '[ "$(q ".buckets.api_specs | join(\",\")")" = "api/openapi.yaml,proto/orders/v1/orders.proto" ]'
# workspaces / languages / areas
ok "npm workspaces resolved (glob + literal)"      '[ "$(q ".workspaces[] | select(.tool==\"npm\") | .members | join(\",\")")" = "apps/web,packages/ui" ]'
ok "turbo inherits package-manager members"        '[ "$(q ".workspaces[] | select(.tool==\"turbo\") | .members | join(\",\")")" = "apps/web,packages/ui" ]'
ok "maven <modules> resolved relative to pom"      '[ "$(q ".workspaces[] | select(.tool==\"maven\") | .root + \":\" + (.members | join(\",\"))")" = "services/orders:services/orders/orders-api" ]'
ok "go.work use resolved"                          '[ "$(q ".workspaces[] | select(.tool==\"go\") | .members | join(\",\")")" = "services/gateway" ]'
ok "languages use linguist names, sorted by count" '[ "$(q "[.languages[].files] == ([.languages[].files] | sort | reverse)")" = true ] && [ "$(q "[.languages[] | select(.name==\"JavaScript\") | .files][0]")" = 4 ] && [ "$(q "[.languages[].name] | index(\"Protocol Buffer\") != null")" = true ] && [ "$(q "[.languages[] | select(.name==\"Go\") | .files][0]")" = 1 ]'
ok "languages exclude generated/vendored files"    '[ "$(q "[.languages[] | select(.name==\"TypeScript\") | .files][0]")" = 1 ]'
ok "areas cover every included file exactly once"  '[ "$(q "[.areas[].files] | add")" = "$(q .files_total)" ]'
ok "areas: workspace members are their own area"   '[ "$(q "[.areas[] | select(.workspace_member) | .path] | sort | join(\",\")")" = "apps/web,packages/ui,services/gateway,services/orders/orders-api" ]'
ok "areas: dir holding members is split one level"  '[ "$(q "[.areas[] | select(.path==\"services/catalog\" or .path==\"services/storefront\")] | length")" = 2 ]'
ok "areas sorted by size desc, unique slugs"       '[ "$(q "[.areas[].files] == ([.areas[].files] | sort | reverse)")" = true ] && [ "$(q "[.areas[].area] | (length == (unique | length))")" = true ]'
"$ROOT/scripts/inventory.sh" "$REPO" > "$T/inv2.json" 2>/dev/null
ok "deterministic: second run byte-identical"      'cmp -s "$I" "$T/inv2.json"'
ok "usage error on missing dir -> exit 2"          '"$ROOT/scripts/inventory.sh" "$T/nope" >/dev/null 2>&1; [ $? -eq 2 ]'
# coverage
cat > "$T/draft.json" <<'EOF'
{ "entities": {
    "components": [ { "id": "c1", "name": "web", "module_id": "apps/web", "kind": "service", "confidence": "confirmed",
                      "provenance": [ { "path": "./apps/web/src/server.js", "line": 5 } ] } ],
    "interfaces": [ { "id": "i1", "name": "GET /orders/{id}", "kind": "http", "role": "provides", "confidence": "confirmed",
                      "provenance": [ { "path": "services/orders/orders-api/src/main/java/com/acme/orders/OrderController.java:8", "line": 8 },
                                      { "path": "__ROOT__/services/storefront/config/routes.rb", "line": 2 } ] } ],
    "dependencies": [ { "id": "d1", "name": "express", "purl": "pkg:npm/express", "manifest_path": "apps/web/package.json", "scope": "runtime",
                        "source": "registry", "confidence": "confirmed", "provenance": [ { "path": "apps/web/package.json", "line": 1 } ] },
                      { "id": "d2", "name": "chi", "purl": "pkg:golang/github.com/go-chi/chi/v5", "manifest_path": "services/gateway/go.mod",
                        "scope": "runtime", "source": "registry", "confidence": "confirmed", "provenance": [] } ],
    "api_specs": [ { "id": "a1", "name": "orders openapi", "path": "api/openapi.yaml", "format": "openapi", "confidence": "confirmed", "provenance": [] } ]
  },
  "relations": [] }
EOF
awk -v r="$REPO" '{ gsub(/__ROOT__/, r); print }' "$T/draft.json" > "$T/draft2.json"
"$ROOT/scripts/coverage.sh" "$I" "$T/draft2.json" "$REPO" > "$T/cov.json" 2> "$T/cov.err"; crc=$?
c(){ jq -r "$1" "$T/cov.json"; }
ok "coverage exits 0 with JSON"                    '[ $crc -eq 0 ] && [ ! -s "$T/cov.err" ] && jq -e . "$T/cov.json" >/dev/null'
ok "coverage: files_total + sampled=false"         '[ "$(c ".files_total")" = "$(q .files_total)" ] && [ "$(c .sampled)" = false ]'
ok "coverage: all 10 buckets"                      '[ "$(c ".buckets | keys | length")" = 10 ]'
ok "coverage: found == inventory counts"           '[ "$(c "[.buckets | to_entries | sort_by(.key)[] | .value.found] | join(\",\")")" = "$(jq -r "[.buckets | to_entries | sort_by(.key)[] | .value | length] | join(\",\")" "$I")" ]'
ok "coverage: routes cited 3 (./, :line, abs root)" '[ "$(c .buckets.routes.cited)" = 3 ] && [ "$(c ".buckets.routes.uncited | length")" = 3 ]'
ok "coverage: manifests cited via manifest_path"   '[ "$(c .buckets.manifests.cited)" = 2 ] && [ "$(c ".buckets.manifests.uncited | index(\"apps/web/package.json\")")" = null ]'
ok "coverage: api_specs cited via api_spec path"   '[ "$(c .buckets.api_specs.cited)" = 1 ] && [ "$(c ".buckets.api_specs.uncited | join(\",\")")" = "proto/orders/v1/orders.proto" ]'
ok "coverage: events + config cite the same file"  '[ "$(c .buckets.events.cited)" = 1 ] && [ "$(c .buckets.config.cited)" = 1 ]'
ok "coverage: uncited sorted, cited<=found (R12)"  '[ "$(c "[.buckets[] | (.uncited == (.uncited | sort)) and .cited <= .found and (.uncited | length) <= .found] | all")" = true ]'
ok "coverage: uncited capped at 200"               'jq "{files_total: 300, buckets: {config: [range(0;300) | \"f\(.)\"]}}" -n > "$T/biginv.json"; [ "$("$ROOT/scripts/coverage.sh" "$T/biginv.json" "$T/draft.json" | jq ".buckets.config | [.found, (.uncited|length)] | join(\",\")" -r)" = "300,200" ]'
ok "coverage: bad input -> exit 2"                 'echo "[]" > "$T/bad.json"; "$ROOT/scripts/coverage.sh" "$T/bad.json" "$T/draft.json" >/dev/null 2>&1; [ $? -eq 2 ]'
echo "inventory runtime on fixture: $((t1 - t0))s (jq $(jq --version 2>&1))"
echo "inventory tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
