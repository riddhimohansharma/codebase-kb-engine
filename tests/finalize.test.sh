#!/usr/bin/env bash
# finalize.test.sh — producer conformance (CKB v0.2): golden end-to-end KB, polyglot normalization, failure paths, freshness.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
unset KB_DIR CKB_METRICS CKB_TELEMETRY DO_NOT_TRACK; export CKB_STATE_DIR="$T/state"; : > "$T/r"
ok(){ if eval "$2"; then echo P >> "$T/r"; echo "PASS $1"; else echo F >> "$T/r"; echo "FAIL $1"
      [ -f "$T/r.dumped" ] || { : > "$T/r.dumped"; echo "  --- finalize output:"; sed 's/^/  | /' "$T/out" 2>/dev/null | tail -25; }; fi; }
G(){ git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
mkrepo(){ # $1 dir, $2 json with cited paths -> git repo where every cited file exists (60 lines each)
  mkdir -p "$1"; git -C "$1" init -q -b main
  for f in $(jq -r '[.. | objects | select(has("path") and has("line")) | .path] + [.. | objects | .manifest_path? // empty] + [.entities.api_specs[]?.path] | map(select(type == "string")) | unique | .[]' "$2" | sed 's#^\./##' | grep -v '^/' | grep -v '^ckb'); do
    mkdir -p "$1/$(dirname "$f")"; seq 1 60 > "$1/$f"; done
  G "$1" add -A && G "$1" commit -qm init; }

# ===================== 1. golden repo: consistent draft + 8 passing docs => complete =====================
GOLD="$T/shop"; FX="$ROOT/tests/fixtures/docs"
mkrepo "$GOLD" "$FX/ckb.json"; git -C "$GOLD" remote add origin "https://user:s3cret@GitHub.com/Acme/Shop.git"
KB="$(cd "$T" && "$ROOT/scripts/resolve-kb.sh" "$GOLD" | sed -n 's/^KB_DIR=//p')"
mkgold(){ jq '{entities, relations, repo_profile: (.repo_profile // {})}' "$FX/ckb.json" > "$KB/ckb.draft.json"; cp "$FX"/good/*.md "$KB/"; }
mkgold; "$ROOT/scripts/finalize.sh" "$GOLD" "$KB" >"$T/out" 2>&1; rc=$?
A="$KB/ckb.json"; M="$KB/manifest.json"; q(){ jq -r "$1" "$A"; }
ok "golden: finalize exits 0, status complete"        '[ $rc -eq 0 ] && [ "$(jq -r .status "$M")" = complete ]'
ok "golden: ckb_version 0.2, schema+semantic pass"    '[ "$(q .ckb_version)" = 0.2 ] && [ "$(jq -r ".validation.structural+\"/\"+.validation.semantic" "$M")" = "pass/pass" ]'
ok "golden: 8 docs + 90-reference + ckb.json hashed"  '[ "$(jq "[.outputs[] | select(.present and (.sha256|length)==64)] | length" "$M")" = 10 ]'
ok "golden: no doc lint violations recorded"          '[ "$(jq ".validation.docs | length" "$M")" = 0 ]'
ok "golden: front-matter injected with source commit" 'head -20 "$KB/03-business-rules.md" | grep -q "^source_commit: \"$(git -C "$GOLD" rev-parse HEAD)\""'
ok "golden: 90-reference.md generated from ckb.json"  'grep -q "^ckb_doc: \"reference\"" "$KB/90-reference.md" && grep -q "pkg:" "$KB/90-reference.md"'
ok "golden: coverage present, no uncited manifests"   '[ "$(q ".coverage.buckets.manifests.uncited | length")" = 0 ] && [ "$(q ".coverage.files_total")" -gt 0 ]'
ok "golden: repo.url canonical, credentials stripped" '[ "$(q .repo.url)" = "https://github.com/Acme/Shop" ] && ! grep -rq s3cret "$KB"'
ok "golden: README indexes 8 docs + reference"        '[ "$(grep -cE "^\| \[(0[0-7]|90)-" "$KB/README.md")" = 9 ]'
ok "golden: .gitattributes + .gitignore (draft.d)"    'grep -qx "\* linguist-generated=true" "$KB/.gitattributes" && grep -qx "ckb.draft.d/" "$KB/.gitignore"'
ok "golden: draft removed; producer did not commit"   '[ ! -e "$KB/ckb.draft.json" ] && grep -q "^COMMIT_HINT=git add ckb" "$T/out" && [ "$(git -C "$GOLD" rev-list --count HEAD)" = 1 ]'
cp "$A" "$T/a1"; for f in "$KB"/0*.md; do cp "$f" "$T/$(basename "$f").1"; done
mkgold; "$ROOT/scripts/finalize.sh" "$GOLD" "$KB" >"$T/out" 2>&1
ok "determinism: artifact identical except generated_at" '[ "$(jq -c "del(.repo.generated_at)" "$A" | shasum)" = "$(jq -c "del(.repo.generated_at)" "$T/a1" | shasum)" ]'
ok "determinism: docs byte-identical across runs"        'for f in "$KB"/0*.md; do cmp -s "$f" "$T/$(basename "$f").1" || exit 1; done'

# docs may reference entities as `ckb:<type>:<local-id>`; finalize must rewrite them to final ids
WF="$(jq -r '.entities.workflows[0].id' "$FX/ckb.json")"
jq --arg w "$WF" '{entities, relations, repo_profile: (.repo_profile // {})} | .entities.workflows[0].id = "wf.local1"' "$FX/ckb.json" > "$KB/ckb.draft.json"
cp "$FX"/good/*.md "$KB/"; for f in "$KB"/02-functional-workflows.md; do sed "s#ckb:$WF#ckb:workflow:wf.local1#g" "$f" > "$T/x" && cp "$T/x" "$f"; done
"$ROOT/scripts/finalize.sh" "$GOLD" "$KB" >"$T/out" 2>&1; rc=$?
ok "docs marker ckb:<type>:<local-id> rewritten to final id" '[ $rc -eq 0 ] && grep -q "ckb:$WF" "$KB/02-functional-workflows.md" && ! grep -q "wf.local1" "$KB/02-functional-workflows.md"'
F="$ROOT/scripts/freshness.sh"
ok "freshness: fresh right after generation"           '"$F" "$GOLD" >/dev/null'
G "$GOLD" add ckb && G "$GOLD" commit -qm kb
touch "$GOLD/.DS_Store" "$KB/.DS_Store"
ok "freshness: committed ckb + OS junk stays fresh"     '"$F" "$GOLD" | grep -q "FRESHNESS=fresh"'
rm -f "$GOLD/.DS_Store" "$KB/.DS_Store"
echo "// dirty" >> "$GOLD/src/db.ts"
ok "freshness: uncommitted source edit -> stale"        '{ "$F" "$GOLD" || true; } | grep -q "REASON=dirty-worktree"'
G "$GOLD" commit -qam src
ok "freshness: committed source change -> stale (1)"    '"$F" "$GOLD" >"$T/f"; [ $? -eq 1 ] && grep -q "1-source-files-changed" "$T/f"'
ok "freshness: no artifact -> none (4)"                 '"$F" "$T" "$T/nokb" >/dev/null; [ $? -eq 4 ]'

# draft.d fragments are the sole source; a stale merged draft is ignored
mkdir -p "$KB/ckb.draft.d"; jq '{entities: {components: .entities.components, interfaces: .entities.interfaces}, relations}' "$FX/ckb.json" > "$KB/ckb.draft.d/a.json"
jq '{entities: (.entities | del(.components, .interfaces)), repo_profile: (.repo_profile // {})}' "$FX/ckb.json" > "$KB/ckb.draft.d/b.json"
echo '{"entities":{"components":[{"id":"ghost","name":"ghost","module_id":"ghost","kind":"service","confidence":"confirmed","provenance":[]}]}}' > "$KB/ckb.draft.json"
cp "$FX"/good/*.md "$KB/"; "$ROOT/scripts/finalize.sh" "$GOLD" "$KB" >"$T/out" 2>&1
ok "draft.d: fragments merged, stale ckb.draft.json ignored" '[ "$(q "[.entities.components[].id] | index(\"component:ghost\")")" = null ] && [ "$(q ".entities.interfaces | length")" -gt 0 ]'
ok "draft.d: removed after a complete run"            '[ "$(jq -r .status "$M")" != complete ] || [ ! -e "$KB/ckb.draft.d" ]'

# ===================== 2. polyglot normalization (docs don't match -> incomplete, JSON still checked) =====================
POLY="$T/poly"; PD="$ROOT/tests/fixtures/polyglot-draft.json"
mkrepo "$POLY" "$PD"; git -C "$POLY" remote add origin "git@github.com:acme/poly.git"
PKB="$(cd "$T" && "$ROOT/scripts/resolve-kb.sh" "$POLY" | sed -n 's/^KB_DIR=//p')"
cp "$PD" "$PKB/ckb.draft.json"; cp "$FX"/good/*.md "$PKB/"
"$ROOT/scripts/finalize.sh" "$POLY" "$PKB" >"$T/out" 2>&1; rc=$?
P="$PKB/ckb.json"; PM="$PKB/manifest.json"; p(){ jq -r "$1" "$P"; }; ids(){ jq -r "[.entities.$1[].id] | .[]" "$P"; }
ok "poly: artifact accepted (valid), docs mismatch -> incomplete" '[ $rc -eq 1 ] && [ "$(jq -r .status "$PM")" = incomplete ] && [ "$(jq -r .validation.semantic "$PM")" = pass ]'
ok "poly: parity violations reported"                 '[ "$(jq ".validation.docs.parity | length" "$PM")" -gt 0 ]'
ok "poly: ssh remote -> canonical https url"          '[ "$(p .repo.url)" = "https://github.com/acme/poly" ]'
for want in "interface:http:provides:orders-api:GET:/users/{id}/posts" "interface:http:provides:_:GET:/users/{pk}" "interface:http:provides:_:GET:/static/{wildcard}" \
            "interface:http:provides:_:GET:/files/{wildcard}" "interface:http:provides:_:GET:/orders/{order_id}" "interface:http:provides:_:ANY:/users/{param}" \
            "interface:http:provides:_:GET:/items/{item_id}" "interface:http:provides:_:POST:/items/{item_id}" "interface:http:consumes:payments:POST:/payments" \
            "interface:http:consumes:user-service:GET:/health" "interface:http:consumes:billing:GET:/health" "interface:event:consumes:sqs:orders-created" \
            "interface:event:provides:sns:order-events" "interface:rpc:provides:graphql:Query/user" "interface:websocket:provides:_:/socket"; do
  ok "poly: interface $want" 'ids interfaces | grep -qxF "$want"'; done
for want in "pkg:npm/%40acme/shared" "pkg:pypi/django-rest-framework" "pkg:maven/org.springframework/spring-core" "pkg:nuget/newtonsoft.json" \
            "pkg:composer/laravel/framework" "pkg:cargo/serde-json" "pkg:golang/golang.org/x/net" "pkg:docker/library/node" "pkg:github/actions/checkout" \
            "pkg:pub/flutter_bloc" "pkg:hex/phoenix" "pkg:luarocks/lua-resty-http" "pkg:npm/lodash" "pkg:cocoapods/AFNetworking"; do
  ok "poly: dependency purl $want" 'p ".entities.dependencies[].purl" | grep -qxF "$want"'; done
ok "poly: workspace dep marked source=workspace"      '[ "$(p ".entities.dependencies[] | select(.purl==\"pkg:npm/%40acme/shared\") | .source")" = workspace ]'
ok "poly: datastore ids (quotes, default schema, instance)" 'ids datastores | grep -qx "datastore:postgres:DATABASE_URL:users" && ids datastores | grep -qx "datastore:mssql:_:orders"'
ok "poly: artifact + service + external + api_spec"   'ids artifacts | grep -qx "artifact:pkg:docker/ghcr.io/acme/orders" && ids services | grep -qx "service:orders-api" && ids external_services | grep -qx "external:collector.newrelic.com" && ids api_specs | grep -qx "api_spec:docs/openapi.yaml"'
ok "poly: config value never stored; DSN is secret"   '! grep -q "postgres://u:p" "$P" && [ "$(p ".entities.config_keys[] | select(.name==\"DATABASE_URL\") | .is_secret")" = true ]'
ok "poly: provides->consumes relation corrected"      '[ "$(p "[.relations[] | select(.to==\"interface:http:consumes:payments:POST:/payments\") | .kind] | .[0]")" = consumes ]'
ok "poly: disallowed triple dropped with warning"     '! p ".relations[].from" | grep -q "^datastore:" && jq -e "[.warnings[] | select(test(\"not allowed by the spec\"))] | length > 0" "$PM" >/dev/null'
ok "poly: multi-method relation fans out to both"     '[ "$(p "[.relations[] | select(.to|test(\"/items/\"))] | length")" = 2 ]'
ok "poly: confidence_summary matches claims"          '[ "$(p ".confidence_summary | [.confirmed,.inferred,.unknown] | add")" = "$(p "[.entities[][], (.relations // [])[]] | length")" ]'

# self-improvement loop: feedback persists across runs, recurrence is counted, candidates surface
ok "feedback: next_run_focus + recurring recorded"    'jq -e ".feedback.next_run_focus | type == \"array\"" "$PM" >/dev/null && jq -e ".feedback.recurring | length > 0" "$PM" >/dev/null'
cp "$PD" "$PKB/ckb.draft.json"; "$ROOT/scripts/finalize.sh" "$POLY" "$PKB" >"$T/out" 2>&1
ok "feedback: recurrence counted on second run"       'jq -e "[.feedback.recurring[] | select(.runs >= 2)] | length > 0" "$PM" >/dev/null'
ok "feedback: improvement candidate surfaced"         'jq -e "[.feedback.improve_candidates[] | select(test(\"not allowed by the spec\"))] | length == 1" "$PM" >/dev/null'

# anonymous local run metrics + stats
RUNS="$T/state/runs.jsonl"
ok "metrics: one record per finalize run"            '[ -s "$RUNS" ] && [ "$(wc -l < "$RUNS" | tr -d " ")" -ge 3 ]'
ok "metrics: record is anonymous (no paths/urls/names)" '! grep -qE "/Users/|/private/|/tmp/|https?://|github\.com|shop|acme|poly" "$RUNS"'
ok "metrics: repo is a salted 12-hex hash"           'tail -1 "$RUNS" | jq -e ".repo | test(\"^[0-9a-f]{12}$\")" >/dev/null'
ok "metrics: carries status, coverage, entities"     'tail -1 "$RUNS" | jq -e "has(\"status\") and has(\"coverage\") and has(\"entities\") and has(\"duration_s\")" >/dev/null'
n0="$(wc -l < "$RUNS" | tr -d " ")"; cp "$PD" "$PKB/ckb.draft.json"; CKB_METRICS=off "$ROOT/scripts/finalize.sh" "$POLY" "$PKB" >"$T/out" 2>&1
ok "metrics: CKB_METRICS=off records nothing"        '[ "$(wc -l < "$RUNS" | tr -d " ")" = "$n0" ]'
"$ROOT/scripts/stats.sh" --json > "$T/stats.json"
ok "stats: summary counts runs and statuses"         'jq -e ".runs >= 3 and (.status | length) >= 1 and .repos >= 2" "$T/stats.json" >/dev/null'
"$ROOT/scripts/stats.sh" > "$T/stats.txt" 2>&1
ok "stats: human summary renders"                    'grep -q "local run stats" "$T/stats.txt" && grep -q "^telemetry:" "$T/stats.txt"'
"$ROOT/scripts/stats.sh" --submit > "$T/sub" 2>&1
ok "stats: --submit without --yes only previews"     'grep -q "PREVIEW ONLY" "$T/sub" || grep -q "GitHub CLI) is required" "$T/sub"'

# telemetry: on by default with notice; opt-outs honoured; payload is the anonymous record and passes the relay's validator
FK="$T/fakebin"; mkdir -p "$FK"; cat > "$FK/curl" <<'FAKE'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in @*) cat "${a#@}" >> "$CURL_LOG";; esac; done; echo >> "$CURL_LOG"; exit 0
FAKE
chmod +x "$FK/curl"; export CURL_LOG="$T/curl.log"; : > "$CURL_LOG"
tel(){ cp "$PD" "$PKB/ckb.draft.json"; env PATH="$FK:$PATH" CKB_TELEMETRY_SYNC=1 CKB_TELEMETRY_URL="https://relay.test/v1/report" "$@" "$ROOT/scripts/finalize.sh" "$POLY" "$PKB" >"$T/out" 2>&1; }
rm -f "$T/state/telemetry-notice-shown" "$T/state/telemetry"
tel
ok "telemetry: default ON sends one report"           '[ "$(grep -c . "$CURL_LOG")" = 1 ]'
ok "telemetry: first run prints the notice once"      'grep -q "^TELEMETRY_NOTICE=" "$T/out"'
tel; ok "telemetry: notice not repeated"              '! grep -q "^TELEMETRY_NOTICE=" "$T/out" && [ "$(grep -c . "$CURL_LOG")" = 2 ]'
ok "telemetry: payload is anonymous"                  '! grep -qE "/Users/|/private/|https?://|github|acme|poly|DATABASE_URL" "$CURL_LOG"'
if command -v node >/dev/null && [ -f "$ROOT/../codebase-kb-telemetry/src/index.js" ]; then
  head -1 "$CURL_LOG" > "$T/rec.json"
  ok "telemetry: payload passes the relay validator"  'node --input-type=module -e "import {validate} from \"$ROOT/../codebase-kb-telemetry/src/index.js\"; import fs from \"fs\"; const e = validate(JSON.parse(fs.readFileSync(\"$T/rec.json\",\"utf8\"))); if (e.length) { console.error(e); process.exit(1); }"'
fi
n="$(grep -c . "$CURL_LOG")"
tel DO_NOT_TRACK=1;     ok "telemetry: DO_NOT_TRACK=1 sends nothing"       '[ "$(grep -c . "$CURL_LOG")" = "$n" ]'
tel CKB_TELEMETRY=off;  ok "telemetry: CKB_TELEMETRY=off sends nothing"    '[ "$(grep -c . "$CURL_LOG")" = "$n" ]'
"$ROOT/scripts/telemetry.sh" off >/dev/null; tel; ok "telemetry: saved off sends nothing" '[ "$(grep -c . "$CURL_LOG")" = "$n" ]'
"$ROOT/scripts/telemetry.sh" on >/dev/null
cp "$PD" "$PKB/ckb.draft.json"; env PATH="$FK:$PATH" CKB_TELEMETRY_SYNC=1 CKB_TELEMETRY_URL= "$ROOT/scripts/finalize.sh" "$POLY" "$PKB" >"$T/out" 2>&1
ok "telemetry: no endpoint configured sends nothing"  '[ "$(grep -c . "$CURL_LOG")" = "$n" ]'
cp "$PD" "$PKB/ckb.draft.json"; env PATH="$FK:$PATH" CKB_TELEMETRY_SYNC=1 CKB_TELEMETRY_URL="http://insecure.test/x" "$ROOT/scripts/finalize.sh" "$POLY" "$PKB" >"$T/out" 2>&1
ok "telemetry: plain http endpoint refused"           '[ "$(grep -c . "$CURL_LOG")" = "$n" ]'

# ===================== 3. failure paths =====================
run_gold(){ mkgold; "$1/scripts/finalize.sh" "$GOLD" "$KB" >"$T/out" 2>&1; }
run_gold "$ROOT"; good="$(shasum < "$A")"
PL="$T/plug"; mkdir -p "$PL" && cp -R "$ROOT/." "$PL/" 2>/dev/null; rm -rf "$PL/.git"
jq '.required += ["x-impossible"]' "$PL/spec/v0.2/ckb.schema.json" > "$T/s" && mv "$T/s" "$PL/spec/v0.2/ckb.schema.json"
if command -v uvx >/dev/null; then
  run_gold "$PL"; rc=$?
  ok "invalid: exit 1, status=invalid"                '[ $rc -eq 1 ] && [ "$(jq -r .status "$M")" = invalid ]'
  ok "invalid: previous good ckb.json NOT overwritten" '[ "$(shasum < "$A")" = "$good" ]'
  ok "invalid: candidate kept as ckb.json.rejected"   '[ -s "$KB/ckb.json.rejected" ]'
  ok "invalid: draft kept, no commit hint"            '[ -e "$KB/ckb.draft.json" ] && ! grep -q COMMIT_HINT "$T/out"'
  ok "invalid: freshness refuses to skip"             '! "$ROOT/scripts/freshness.sh" "$GOLD" >/dev/null'
fi
NOUV="$(printf '%s' "$PATH" | tr ':' '\n' | while read -r d; do [ -x "$d/uvx" ] || printf '%s:' "$d"; done)"
mkgold; PATH="$NOUV" "$ROOT/scripts/finalize.sh" "$GOLD" "$KB" >"$T/out" 2>&1; rc=$?
ok "no uvx -> unverified, exit 1, no hint"            '[ $rc -eq 1 ] && [ "$(jq -r .status "$M")" = unverified ] && ! grep -q COMMIT_HINT "$T/out"'
run_gold "$ROOT"
ok "valid run clears rejected candidate"              '[ ! -e "$KB/ckb.json.rejected" ] && [ "$(jq -r .status "$M")" = complete ]'
printf 'DB_PASSWORD=Sup3rS3cretValue_9xQ\n' > "$GOLD/.env"
mkgold; echo "pw is Sup3rS3cretValue_9xQ here [?]" >> "$KB/05-operations.md"; "$ROOT/scripts/finalize.sh" "$GOLD" "$KB" >"$T/out" 2>&1
ok "secret value from .env redacted in KB"            '! grep -rqF Sup3rS3cretValue_9xQ "$KB" && grep -q "\[REDACTED\]" "$KB/05-operations.md"'
ok "redaction recorded; manifest hash matches file"   'jq -e "[.warnings[] | select(startswith(\"redacted\"))] | length == 1" "$M" >/dev/null && [ "$(jq -r ".outputs[] | select(.file==\"05-operations.md\") | .sha256" "$M")" = "$(shasum -a 256 "$KB/05-operations.md" | cut -d" " -f1)" ]'
rm -f "$GOLD/.env"
mkgold; rm "$KB/07-decisions.md"; "$ROOT/scripts/finalize.sh" "$GOLD" "$KB" >"$T/out" 2>&1; rc=$?
ok "missing doc -> status=incomplete"                 '[ $rc -ne 0 ] && [ "$(jq -r .status "$M")" = incomplete ]'
rm -f "$KB/.ckb-output"; mkgold; "$ROOT/scripts/finalize.sh" "$GOLD" "$KB" >"$T/out" 2>&1; rc=$?
ok "refuses dir without .ckb-output marker"           '[ $rc -eq 2 ]'

pass=$(grep -c P "$T/r"); fail=$(grep -c F "$T/r"); echo "---"; echo "finalize tests: $pass passed, $fail failed"; [ "$fail" -eq 0 ]
