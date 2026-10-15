#!/usr/bin/env bash
# checkpoint.test.sh — scripts/checkpoint.sh: resumable /kb runs. State comes from disk; the run key refuses stale resumes.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$T/xdg" HOME="$T"
pass=0; fail=0
ok(){ if eval "$2"; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1"; fi; }
C="$ROOT/scripts/checkpoint.sh"
commit(){ git -C "$1" add -A && git -C "$1" -c user.email=t@t -c user.name=t commit -qm "${2:-i}"; }
R="$T/r"; cp -R "$ROOT/tests/fixtures/polyglot" "$R"; rm -rf "$R/node_modules"; git -C "$R" init -q -b main; commit "$R"
"$ROOT/scripts/resolve-kb.sh" "$R" >/dev/null; KB="$R/.ckb"; DD="$KB/ckb.draft.d"
st(){ "$C" status "$KB" | sed -n 1p; }   # the JSON line (sed reads all input: head -1 would SIGPIPE the script under pipefail)
pend(){ "$C" status "$KB" | sed -n 's/^PENDING=//p'; }
inv(){ "$ROOT/scripts/inventory.sh" "$R" --out "$DD/.inventory.json" >/dev/null; }

ok "begin on a new KB dir is fresh (no-checkpoint)"            '"$C" begin "$KB" "$R" | grep -q "^RESUME=fresh REASON=no-checkpoint KEY=[0-9a-f]\{64\}$"'
ok "begin again with nothing changed resumes"                  '"$C" begin "$KB" "$R" | grep -q "^RESUME=yes KEY="'
ok "status before any work: everything pending"                '[ "$(pend)" = "$(pend | grep "^inventory,")" ] && pend | grep -q "doc:00-overview.md" && pend | grep -q "audit$"'
inv; echo '{"entities":{}}' > "$DD/root.json"; printf 'not json {' > "$DD/apps-web.json"; : > "$DD/infra.json"
ok "status: inventory done once a full inventory file exists"  'st | jq -e ".inventory == true and (.scopes.expected | length) >= 6" >/dev/null'
ok "status: a valid fragment is done"                          'st | jq -e ".scopes.done | index(\"root\") != null" >/dev/null'
ok "status: an invalid-JSON fragment stays pending (half-written file never trusted)" 'st | jq -e ".scopes.pending | index(\"apps-web\") != null" >/dev/null'
ok "status: an empty fragment stays pending"                   'st | jq -e ".scopes.pending | index(\"infra\") != null" >/dev/null'
ok "status: the inventory scout is expected and pending until its fragment exists" 'pend | grep -q "scout:inventory"'
printf '# o\n' > "$KB/00-overview.md"; : > "$KB/01-technical-architecture.md"
ok "status: a written doc is done, an empty doc stays pending" 'st | jq -e ".docs.done == [\"00-overview.md\"] and (.docs.pending | index(\"01-technical-architecture.md\") != null)" >/dev/null'
ok "mark audit records the result and removes audit from PENDING" '"$C" mark "$KB" audit 14/15 | grep -q "^MARKED=audit 14/15$" && ! pend | grep -q "audit"'
ok "mark audit rejects a malformed value"                      '"$C" mark "$KB" audit lots >/dev/null 2>&1; [ $? -eq 2 ]'
ok "mark finalize counts attempts"                             '"$C" mark "$KB" finalize >/dev/null; "$C" mark "$KB" finalize | grep -q "attempts=2" && st | jq -e ".finalize_attempts == 2" >/dev/null'
ok "an interrupted run resumes with its work intact"           '"$C" begin "$KB" "$R" | grep -q "^RESUME=yes" && [ -s "$DD/root.json" ] && [ -f "$DD/.inventory.json" ] && [ -s "$KB/00-overview.md" ]'

# the key: anything that changes what the fragments describe forbids reuse
fresh(){ "$C" begin "$KB" "$R" "$@" | grep -q "^RESUME=fresh"; }
redo(){ inv; echo '{"entities":{}}' > "$DD/root.json"; }
ok "a new commit invalidates the checkpoint and clears the draft" 'echo "x" > "$R/new.txt"; commit "$R" two; fresh && [ ! -e "$DD/root.json" ]'
redo; "$C" begin "$KB" "$R" >/dev/null
ok "an uncommitted source edit invalidates it"                 'redo; echo change >> "$R/README.md"; fresh && [ ! -e "$DD/root.json" ]'
git -C "$R" checkout -q -- README.md; "$C" begin "$KB" "$R" >/dev/null
ok "an untracked source file invalidates it"                   'redo; echo u > "$R/untracked.txt"; fresh; r=$?; rm -f "$R/untracked.txt"; [ $r -eq 0 ]'
"$C" begin "$KB" "$R" >/dev/null
ok "touching only .ckb does not invalidate (the KB is not source)" 'redo; echo x > "$KB/notes.txt"; "$C" begin "$KB" "$R" | grep -q "^RESUME=yes"; r=$?; rm -f "$KB/notes.txt"; [ $r -eq 0 ]'
ok "an untracked CLAUDE.md seed does not invalidate"           'echo seed > "$R/CLAUDE.md"; "$C" begin "$KB" "$R" | grep -q "^RESUME=yes"; r=$?; rm -f "$R/CLAUDE.md"; [ $r -eq 0 ]'
ok "a different focus invalidates"                             'redo; "$C" begin "$KB" "$R" --focus billing | grep -q "^RESUME=fresh REASON=source-or-plugin-or-focus-changed"'
ok "the same focus resumes"                                    '"$C" begin "$KB" "$R" --focus billing | grep -q "^RESUME=yes"'
ok "--force always starts fresh"                               'redo; "$C" begin "$KB" "$R" --focus billing --force | grep -q "^RESUME=fresh REASON=forced" && [ ! -e "$DD/root.json" ]'
ok "a different plugin version invalidates"                    'redo; "$C" begin "$KB" "$R" >/dev/null; jq ".key = \"stale\"" "$DD/.checkpoint.json" > "$T/c.json" && cp "$T/c.json" "$DD/.checkpoint.json"; "$C" begin "$KB" "$R" | grep -q "^RESUME=fresh"'
ok "a fresh start resets audit and attempts"                   '"$C" mark "$KB" audit 1/1 >/dev/null; "$C" begin "$KB" "$R" --force >/dev/null; st | jq -e ".audit == null and .finalize_attempts == 0" >/dev/null'
ok "docs from an earlier KB run are not counted as done after a fresh start" 'printf "# old\n" > "$KB/02-functional-workflows.md"; sleep 1; "$C" begin "$KB" "$R" --force >/dev/null; ! st | jq -e ".docs.done | index(\"02-functional-workflows.md\") != null" >/dev/null'

# safety: this script is pre-approved by the guard, so it must refuse everything but its own files
ok "refuses an unmarked dir"                                   'mkdir -p "$T/un/.ckb"; "$C" begin "$T/un/.ckb" "$R" >/dev/null 2>&1; [ $? -eq 2 ] && [ ! -e "$T/un/.ckb/ckb.draft.d" ]'
mkdir -p "$T/real"; : > "$T/real/.ckb-output"; ln -s "$T/real" "$T/linkkb"
ok "refuses a symlinked KB dir"                                '"$C" begin "$T/linkkb" "$R" >/dev/null 2>&1; [ $? -eq 2 ] && [ ! -e "$T/real/ckb.draft.d" ]'
mkdir -p "$T/kb2"; : > "$T/kb2/.ckb-output"; mkdir -p "$T/elsewhere"; ln -s "$T/elsewhere" "$T/kb2/ckb.draft.d"
ok "refuses a symlinked draft dir (no write-through, no rm -rf through the link)" 'echo keep > "$T/elsewhere/f"; "$C" begin "$T/kb2" "$R" >/dev/null 2>&1; [ $? -eq 2 ] && [ -f "$T/elsewhere/f" ]'
ok "status and mark refuse an unmarked dir too"                '"$C" status "$T/un/.ckb" >/dev/null 2>&1; [ $? -eq 2 ] && "$C" mark "$T/un/.ckb" audit 1/1 >/dev/null 2>&1; [ $? -eq 2 ]'
ok "mark without a checkpoint is an error"                     'mkdir -p "$T/kb3"; : > "$T/kb3/.ckb-output"; "$C" mark "$T/kb3" finalize >/dev/null 2>&1; [ $? -eq 2 ]'
ok "status without a checkpoint says so (no crash)"            '[ "$("$C" status "$T/kb3" | head -1)" = "{\"checkpoint\":false}" ]'
ok "usage errors exit 2"                                       '"$C" >/dev/null 2>&1; [ $? -eq 2 ] && "$C" begin "$KB" >/dev/null 2>&1; [ $? -eq 2 ] && "$C" begin "$KB" "$R" --bogus >/dev/null 2>&1; [ $? -eq 2 ]'
ok "begin writes only inside ckb.draft.d (nothing new in the repo outside .ckb)" '[ -z "$(git -C "$R" status --porcelain -- . ":(exclude).ckb")" ]'

# end to end: an interrupted run, resumed, yields the same artifact as an uninterrupted one
FX="$ROOT/tests/fixtures/docs"; GOLD="$T/gold"; mkdir -p "$GOLD"; git -C "$GOLD" init -q -b main
for f in $(jq -r '[.. | objects | select(has("path") and has("line")) | .path] + [.. | objects | .manifest_path? // empty] + [.entities.api_specs[]?.path] | map(select(type == "string")) | unique | .[]' "$FX/ckb.json"); do mkdir -p "$GOLD/$(dirname "$f")"; seq 1 60 > "$GOLD/$f"; done; commit "$GOLD"
"$ROOT/scripts/resolve-kb.sh" "$GOLD" >/dev/null; GKB="$GOLD/.ckb"
mkfrag(){ mkdir -p "$GKB/ckb.draft.d"; jq '{entities, relations, repo_profile: (.repo_profile // {})}' "$FX/ckb.json" > "$GKB/ckb.draft.d/all.json"; cp "$FX"/good/*.md "$GKB/"; }
"$C" begin "$GKB" "$GOLD" >/dev/null; mkfrag
ok "interrupted before finalize: status lists the docs as done and the scopes pending" '"$C" status "$GKB" | sed -n 1p | jq -e ".docs.pending | length == 0" >/dev/null'
"$C" begin "$GKB" "$GOLD" | grep -q "^RESUME=yes" && CKB_TELEMETRY=off "$ROOT/scripts/finalize.sh" "$GOLD" "$GKB" >"$T/f1.out" 2>&1; cp "$GKB/ckb.json" "$T/resumed.json" 2>/dev/null
ok "resumed run finalizes complete"                            '[ "$(jq -r .status "$GKB/manifest.json")" = complete ]'
GOLD2="$T/gold2"; cp -R "$GOLD" "$GOLD2"; rm -rf "$GOLD2/.ckb"; "$ROOT/scripts/resolve-kb.sh" "$GOLD2" >/dev/null; GKB2="$GOLD2/.ckb"
mkdir -p "$GKB2/ckb.draft.d"; jq '{entities, relations, repo_profile: (.repo_profile // {})}' "$FX/ckb.json" > "$GKB2/ckb.draft.d/all.json"; cp "$FX"/good/*.md "$GKB2/"; CKB_TELEMETRY=off "$ROOT/scripts/finalize.sh" "$GOLD2" "$GKB2" >"$T/f2.out" 2>&1
ok "resumed and uninterrupted runs produce the same entities and relations" '[ "$(jq -S "{entities, relations}" "$T/resumed.json" | sha256sum)" = "$(jq -S "{entities, relations}" "$GKB2/ckb.json" | sha256sum)" ]'

# wiring
ok "kb.md runs begin and status, and says never restart"       'grep -q "checkpoint.sh\" begin" "$ROOT/commands/kb.md" && grep -q "checkpoint.sh\" status" "$ROOT/commands/kb.md" && grep -q "never restart" "$ROOT/commands/kb.md"'
ok "kb.md documents --fresh"                                   'grep -q -- "--fresh" "$ROOT/commands/kb.md"'
ok "the guard pre-approves checkpoint.sh by plugin path"       'grep -q "|checkpoint.sh" "$ROOT/hooks/guard.sh"'

echo "checkpoint tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
