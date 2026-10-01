#!/usr/bin/env bash
# finalize.test.sh — producer conformance on a fixture (plan §4.1): normalization, IDs, determinism, validation, manifest.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
unset KB_DIR; : > "$T/r"
ok(){ if eval "$2"; then echo P >> "$T/r"; echo "PASS $1"; else echo F >> "$T/r"; echo "FAIL $1"; [ -f "$T/r.dumped" ] || { : > "$T/r.dumped"; echo "  --- finalize output:"; sed 's/^/  | /' "$T/out" 2>/dev/null | tail -25; echo "  --- manifest.json:"; head -c 600 "${M:-/dev/null}" 2>/dev/null | sed 's/^/  | /'; }; fi; }
REPO="$T/shop"; mkdir -p "$REPO" && git -C "$REPO" init -q -b main && echo x > "$REPO/a.ts"
git -C "$REPO" add -A && git -C "$REPO" -c user.email=t@t -c user.name=t commit -qm init
git -C "$REPO" remote add origin "https://user:s3cret@github.com/acme/shop.git"
# materialize every file the fixture cites (except the deliberately bad ones) so citations verify
for f in $(jq -r '[.. | objects | select(has("path") and has("line")) | .path] | unique | .[]' "$ROOT/tests/fixtures/messy-draft.json" | sed 's#^\./##' | grep -v '^/'); do
  mkdir -p "$REPO/$(dirname "$f")"; seq 1 60 > "$REPO/$f"; done
git -C "$REPO" add -A && git -C "$REPO" -c user.email=t@t -c user.name=t commit -qm fixtures
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
ok "KB is <repo>/ckb (in-repo standard)"       '[ "$KB" = "$REPO/ckb" ]'
ok "README.md index + .gitattributes written"   '[ -s "$KB/README.md" ] && grep -qx "\* linguist-generated=true" "$KB/.gitattributes"'
ok "README index is deterministic (no timestamps)" '! grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}T" "$KB/README.md"'
ok "writing ckb does not mark worktree dirty"  '[ "$(jq -r .repo.dirty_worktree "$M")" = false ]'
ok "commit hint printed, producer did not commit" 'grep -q "^COMMIT_HINT=git add ckb" "$T/out" && [ "$(git -C "$REPO" rev-list --count HEAD)" = 2 ]'
ok "ckb/.gitignore keeps transient files out of commits" 'grep -qx "ckb.draft.json" "$KB/.gitignore" && grep -qx ".DS_Store" "$KB/.gitignore"'
F="$ROOT/scripts/freshness.sh"
ok "freshness: fresh right after generation"    '"$F" "$REPO" >/dev/null'
git -C "$REPO" add ckb && git -C "$REPO" -c user.email=t@t -c user.name=t commit -qm kb
touch "$REPO/.DS_Store" "$REPO/ckb/.DS_Store"
ok "OS junk (.DS_Store) does not make the KB stale" '"$F" "$REPO" | grep -q "FRESHNESS=fresh"'
rm -f "$REPO/.DS_Store" "$REPO/ckb/.DS_Store"
ok "freshness: committing ckb keeps it fresh"  '"$F" "$REPO" | grep -q "FRESHNESS=fresh"'
echo y >> "$REPO/a.ts"; git -C "$REPO" -c user.email=t@t -c user.name=t commit -qam src
ok "freshness: source change -> stale (exit 1)" '"$F" "$REPO" >"$T/f"; [ $? -eq 1 ] && grep -q "FRESHNESS=stale.*1-source-files-changed" "$T/f"'
jq '.repo.commit_sha = "ffffffffffffffffffffffffffffffffffffffff"' "$A" > "$T/x" && cp "$A" "$T/a.bak" && mv "$T/x" "$A"
ok "freshness: unknown commit -> unknown (exit 3)" '"$F" "$REPO" >/dev/null; [ $? -eq 3 ]'
cp "$T/a.bak" "$A"
ok "freshness: no artifact -> none (exit 4)"    '"$F" "$T" "$T/nokb" >/dev/null; [ $? -eq 4 ]'
jq '.entities.components += [{"id":"kbc","name":"kb","module_id":"ckb","kind":"other","confidence":"confirmed","provenance":[{"path":"ckb/00-overview.md","line":1}]}] | .entities.dependencies[0].provenance = [{"path":"ckb/ckb.json","line":3}]' "$ROOT/tests/fixtures/messy-draft.json" > "$KB/ckb.draft.json"
"$ROOT/scripts/finalize.sh" "$REPO" "$KB" >"$T/out" 2>&1
ok "R7: ckb component dropped"                 '[ "$(jq "[.entities.components[] | select(.module_id|startswith(\"ckb\"))] | length" "$A")" = 0 ]'
ok "R7: ckb citation dropped -> claim unknown" '[ "$(jq -r .entities.dependencies[0].confidence "$A")" = unknown ] && ! grep -q "\"path\": \"ckb" "$A"'
ok "R7 artifact still validates"                '[ "$(jq -r .status "$M")" = complete ]'
# invalid path: a plugin copy with an impossible schema requirement must never overwrite the good ckb.json
run; good="$(shasum < "$A")"
P="$T/plug"; mkdir -p "$P" && cp -R "$ROOT/." "$P/" 2>/dev/null; rm -rf "$P/.git"
jq '.required += ["x-impossible"]' "$P/spec/v0.1/ckb.schema.json" > "$T/s" && mv "$T/s" "$P/spec/v0.1/ckb.schema.json"
cp "$ROOT/tests/fixtures/messy-draft.json" "$KB/ckb.draft.json"
"$P/scripts/finalize.sh" "$REPO" "$KB" >"$T/out" 2>&1; rc=$?
if command -v uvx >/dev/null; then
ok "invalid artifact -> exit 1, status=invalid"   '[ $rc -eq 1 ] && [ "$(jq -r .status "$M")" = invalid ]'
ok "previous valid ckb.json NOT overwritten"      '[ "$(shasum < "$A")" = "$good" ]'
ok "rejected candidate kept for inspection"       '[ -s "$KB/ckb.json.rejected" ]'
ok "draft kept for repair on failure"             '[ -e "$KB/ckb.draft.json" ]'
ok "no commit hint on failure"                    '! grep -q COMMIT_HINT "$T/out"'
ok "freshness: last run invalid -> not fresh"     '! "$ROOT/scripts/freshness.sh" "$REPO" >/dev/null'
fi
PATH_NOUV="$(printf '%s' "$PATH" | tr ':' '\n' | while read -r d; do [ -x "$d/uvx" ] || printf '%s:' "$d"; done)"
cp "$ROOT/tests/fixtures/messy-draft.json" "$KB/ckb.draft.json"
PATH="$PATH_NOUV" "$ROOT/scripts/finalize.sh" "$REPO" "$KB" >"$T/out" 2>&1; rc=$?
ok "no uvx -> status=unverified, exit 1, no hint" '[ $rc -eq 1 ] && [ "$(jq -r .status "$M")" = unverified ] && ! grep -q COMMIT_HINT "$T/out"'
run
ok "valid run clears the rejected candidate"      '[ ! -e "$KB/ckb.json.rejected" ] && [ "$(jq -r .status "$M")" = complete ]'
echo "// dirty" >> "$REPO/a.ts"
ok "freshness: uncommitted source edits -> not fresh" '{ "$ROOT/scripts/freshness.sh" "$REPO" || true; } | grep -q "REASON=dirty-worktree"'
git -C "$REPO" checkout -q -- a.ts
# secret redaction: a value from .env copied into a doc must be redacted, never committed
printf 'DB_PASSWORD=Sup3rS3cretValue_9xQ\n' > "$REPO/.env"
run; echo "pw is Sup3rS3cretValue_9xQ here" >> "$KB/01-technical-architecture.md"; cp "$ROOT/tests/fixtures/messy-draft.json" "$KB/ckb.draft.json"
"$ROOT/scripts/finalize.sh" "$REPO" "$KB" >"$T/out" 2>&1
ok "secret value from .env redacted in KB"     '! grep -rqF Sup3rS3cretValue_9xQ "$KB" && grep -q "\[REDACTED\]" "$KB/01-technical-architecture.md"'
ok "redaction recorded in manifest warnings"   'jq -e "[.warnings[] | select(startswith(\"redacted\"))] | length == 1" "$M" >/dev/null'
ok "manifest sha256 matches redacted file"     '[ "$(jq -r ".outputs[] | select(.file==\"01-technical-architecture.md\") | .sha256" "$M")" = "$(shasum -a 256 "$KB/01-technical-architecture.md" | cut -d" " -f1)" ]'
rm -f "$REPO/.env"
rm "$KB/03-business-rules.md"; run; rc=$?
ok "missing doc -> status=incomplete"           '[ $rc -ne 0 ] && [ "$(jq -r .status "$M")" = incomplete ]'
rm -f "$KB/.ckb-output"; run; rc=$?
ok "refuses dir without .ckb-output marker"     '[ $rc -eq 2 ]'
pass=$(grep -c P "$T/r"); fail=$(grep -c F "$T/r"); echo "---"; echo "finalize tests: $pass passed, $fail failed"; [ "$fail" -eq 0 ]
