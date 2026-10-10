#!/usr/bin/env bash
# archetype.test.sh — scripts/archetype.sh: repo archetype + modifiers from inventory output only.
# Synthetic repos pin each rule (and each false-positive guard); the real repos in this workspace are the ground truth.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$T/xdg" HOME="$T"
pass=0; fail=0
ok(){ if eval "$2"; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1"; fi; }
A="$ROOT/scripts/archetype.sh"
# mk <name> <path>... : create a git repo with those files (content on stdin sections are written by the caller afterwards)
mk(){ local d="$T/$1"; shift; mkdir -p "$d"; git -C "$d" init -q -b main; local f; for f in "$@"; do mkdir -p "$d/$(dirname "$f")"; : > "$d/$f"; done; echo "$d"; }
commit(){ git -C "$1" add -A && git -C "$1" -c user.email=t@t -c user.name=t commit -qm i; }
cls(){ "$A" "$1" | jq -r '.archetype'; }
mods(){ "$A" "$1" | jq -r '.modifiers | join(",")'; }

# ---- the five primaries ----
d="$(mk svc pyproject.toml Dockerfile app.py README.md)"; printf '@app.route("/x")\ndef x(): pass\n' > "$d/app.py"; commit "$d"
ok "A: one ecosystem + routes + a Dockerfile => deployable service"      '[ "$(cls "$d")" = A ]'
ok "A: a Dockerfile adds the +deploy modifier"                           '[ "$(mods "$d")" = deploy ]'
d="$(mk lib pyproject.toml src/lib.py README.md)"; echo 'def f(): return 1' > "$d/src/lib.py"; commit "$d"
ok "C: one ecosystem, no routes, no iac => library/CLI"                  '[ "$(cls "$d")" = C ]'
d="$(mk mono package.json web/index.js go.mod api/main.go)"; commit "$d"
ok "B: two real ecosystems => workspace monorepo"                        '[ "$(cls "$d")" = B ]'
d="$(mk infra main.tf variables.tf .github/workflows/ci.yml README.md)"; commit "$d"
ok "D: iac+ci dominate and there is no application ecosystem => infrastructure" '[ "$(cls "$d")" = D ]'
d="$(mk docs schema.json README.md scripts/check.sh notes/a.md)"; commit "$d"
ok "E: no ecosystem, schemas/scripts/docs => contract and content"      '[ "$(cls "$d")" = E ]'

# ---- false-positive guards (each one misclassified a real repo before it existed) ----
d="$(mk fixonly pyproject.toml src/lib.py tests/fixtures/web/package.json tests/fixtures/svc/go.mod tests/fixtures/svc/main.go)"; commit "$d"
ok "TESTPATH: manifests under tests/fixtures are not the repo's own (stays C, not B)" '[ "$(cls "$d")" = C ]'
d="$(mk shellself README.md scripts/x.sh scripts/y.sh)"; printf 'app.get("/x")\nkafkajs\nredis\n' > "$d/scripts/x.sh"; printf 'router.post("/y")\n' > "$d/scripts/y.sh"; commit "$d"
ok "shell hits never classify: a script quoting route/kafka patterns stays E"  '[ "$(cls "$d")" = E ] && [ "$(mods "$d")" = "" ]'
ok "...but shell hits still land in the inventory buckets (coverage keeps them)" '"$ROOT/scripts/inventory.sh" "$d" | jq -e "(.buckets.routes | index(\"scripts/x.sh\")) != null" >/dev/null'
d="$(mk noman README.md app.py Dockerfile u1.py u2.py u3.py u4.py u5.py u6.py)"; printf '@app.route("/x")\n' > "$d/app.py"; commit "$d"
ok "A needs exactly one real ecosystem: routes without any manifest fall to E"  '[ "$(cls "$d")" = E ]'
d="$(mk wsfix pyproject.toml src/a.py tests/fixtures/mono/package.json tests/fixtures/mono/apps/a/package.json tests/fixtures/mono/apps/b/package.json)"; printf '{"workspaces":["apps/*"]}\n' > "$d/tests/fixtures/mono/package.json"; commit "$d"
ok "TESTPATH: workspace members inside fixtures do not make a monorepo"  '[ "$(cls "$d")" = C ]'

# ---- modifiers ----
d="$(mk evsvc package.json server.js Dockerfile)"; printf 'const k = require("kafkajs");\napp.get("/x", h);\n' > "$d/server.js"; commit "$d"
ok "+events: a real event client alongside a service"                    '[ "$(cls "$d")" = A ] && "$A" "$d" | jq -e ".modifiers | index(\"events\") != null" >/dev/null'
d="$(mk dblib pyproject.toml src/lib.py db/migration/V1__init.sql)"; commit "$d"
ok "+datastore: migrations present"                                      '[ "$(cls "$d")" = C ] && [ "$(mods "$d")" = datastore ]'
d="$(mk poly package.json a.js go.mod b.go Cargo.toml c.rs)"; commit "$d"
ok "+polyglot: three real ecosystems"                                    '[ "$(cls "$d")" = B ] && "$A" "$d" | jq -e ".modifiers | index(\"polyglot\") != null" >/dev/null'
ok "precedence: D beats everything (an infra repo with a service-looking file stays D)" 'd="$(mk dprec main.tf variables.tf outputs.tf .github/workflows/ci.yml app.py)"; printf "@app.route(\"/x\")\n" > "$d/app.py"; commit "$d"; [ "$(cls "$d")" = D ]'

# ---- input forms and hygiene ----
"$ROOT/scripts/inventory.sh" "$T/svc" > "$T/inv.json" 2>/dev/null
ok "accepts an inventory.json file"                                      '[ "$("$A" "$T/inv.json" | jq -r .archetype)" = A ]'
ok "accepts an inventory on stdin (-)"                                   '[ "$("$A" - < "$T/inv.json" | jq -r .archetype)" = A ]'
ok "same input => byte-identical output (deterministic)"                 '[ "$("$A" "$T/svc")" = "$("$A" "$T/svc")" ]'
mkdir -p "$T/kbd" && touch "$T/kbd/.ckb-output" && "$ROOT/scripts/inventory.sh" "$T/svc" --out "$T/kbd/ckb.draft.d/.inventory.json" > "$T/digest.json" 2>/dev/null
ok "a capped DIGEST is refused with exit 2 (classification must see the full buckets)" '"$A" "$T/digest.json" > "$T/dg.out" 2>&1; rc=$?; [ $rc -eq 2 ] && grep -q "not a full inventory" "$T/dg.out"'
ok "usage errors exit 2"                                                 '"$A" >/dev/null 2>&1; [ $? -eq 2 ] && "$A" "$T/nope" >/dev/null 2>&1; [ $? -eq 2 ]'
ok "evidence block explains the call"                                    '"$A" "$T/svc" | jq -e ".evidence | has(\"ecosystems\") and has(\"routes\") and has(\"files_total\")" >/dev/null'
ok "archetype.sh writes nothing (read-only)"                             '[ -z "$(git -C "$T/svc" status --porcelain)" ]'

# ---- ground truth: the real repos in this workspace ----
ok "this engine repo is E (its 12 manifests are fixtures; its shell scripts quote regexes)" '[ "$(cls "$ROOT")" = E ] && [ "$(mods "$ROOT")" = "" ]'
ok "the polyglot fixture is B with +polyglot"                            '[ "$(cls "$ROOT/tests/fixtures/polyglot")" = B ] && "$A" "$ROOT/tests/fixtures/polyglot" | jq -e ".modifiers | index(\"polyglot\") != null" >/dev/null'
SPEC="$ROOT/../codebase-kb-spec"; GRAPH="$ROOT/../consumer-repo"
if [ -d "$SPEC/schema" ]; then ok "codebase-kb-spec is E"             '[ "$(cls "$SPEC")" = E ]'; else echo "SKIP codebase-kb-spec not found next to this repo"; fi
# the graph also reports +events: one docstring in mcp_server.py lists "Kafka, SQS, SNS". Modifiers are candidates that
# W4 confirms against ckb.json entities, so only the primary and the real datastore signal are asserted.
if [ -d "$GRAPH/src" ]; then ok "consumer-repo is C with +datastore" '[ "$(cls "$GRAPH")" = C ] && "$A" "$GRAPH" | jq -e ".modifiers | index(\"datastore\") != null" >/dev/null'; else echo "SKIP consumer-repo not found next to this repo"; fi

echo "archetype tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
