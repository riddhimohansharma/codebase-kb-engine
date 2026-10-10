#!/usr/bin/env bash
# usage.test.sh — scripts/usage.sh: token usage recording for /kb runs (headless + interactive), local only.
# Synthetic transcripts encode the facts verified against real Claude Code transcripts: sub-agent usage lives in
# <session>/subagents/*.jsonl, and one API response is logged once PER CONTENT BLOCK with identical usage.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export CKB_STATE_DIR="$T/state" CLAUDE_PLUGIN_DATA="$T/data" CKB_TELEMETRY=off; unset CKB_METRICS DO_NOT_TRACK
pass=0; fail=0
ok(){ if eval "$2"; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1"; fi; }
U="$ROOT/scripts/usage.sh"

# one logged line: id, input, output, cache_read, cache_creation, content block type, model
line(){ jq -nc --arg id "$1" --argjson i "$2" --argjson o "$3" --argjson cr "$4" --argjson cc "$5" --arg b "${6:-text}" --arg m "${7:-claude-sonnet-5-5}" \
  '{type:"assistant", uuid:("u-"+$id+$b), requestId:("req_"+$id), message:{id:$id, model:$m, content:[{type:$b}],
    usage:{input_tokens:$i, output_tokens:$o, cache_read_input_tokens:$cr, cache_creation_input_tokens:$cc}}}'; }
SID="11111111-2222-3333-4444-555555555555"; PROJ="$T/proj"; mkdir -p "$PROJ/$SID/subagents"
MAIN="$PROJ/$SID.jsonl"
{ line msg_A 10 100 1000 50 thinking; line msg_A 10 100 1000 50 text; line msg_A 10 100 1000 50 tool_use      # ONE response, three logged lines
  line msg_B 20 200 2000 0 text
  jq -nc '{type:"assistant", message:{id:"msg_T", model:"claude-sonnet-5-5", content:[{type:"tool_use", name:"Task"}], usage:{input_tokens:5,output_tokens:5,cache_read_input_tokens:0,cache_creation_input_tokens:0}}}'
  echo '{"type":"user","message":{"content":"hi"}}'; } > "$MAIN"
{ line msg_C 7 70 700 0 thinking claude-haiku-5-5; line msg_C 7 70 700 0 text claude-haiku-5-5; } > "$PROJ/$SID/subagents/agent-aaa.jsonl"

# ---- transcript summing ----
r="$("$U" transcript "$MAIN")"
ok "transcript: one response logged 3x is counted once (A=10/100, B=20/200, T=5/5, C=7/70)" '[ "$(printf "%s" "$r" | jq -c "[.messages,.input_tokens,.output_tokens]")" = "[4,42,375]" ]'
ok "transcript: cache tokens summed after de-duplication"  '[ "$(printf "%s" "$r" | jq -c "[.cache_read_input_tokens,.cache_creation_input_tokens]")" = "[3700,50]" ]'
ok "transcript: sub-agent usage is included (main alone would be 35/305)" '[ "$(printf "%s" "$r" | jq .subagent_files)" = 1 ] && [ "$(printf "%s" "$r" | jq .input_tokens)" = 42 ]'
ok "transcript: scope is session when every started sub-agent was found" '[ "$(printf "%s" "$r" | jq -r .scope)" = session ] && [ "$(printf "%s" "$r" | jq .subagents_started)" = 1 ]'
ok "transcript: cache hit rate computed"                  '[ "$(printf "%s" "$r" | jq .cache_hit_pct)" = "97.6" ]'
ok "transcript: models listed, cost is null (transcripts carry none)" '[ "$(printf "%s" "$r" | jq -c ".models")" = "[\"claude-haiku-5-5\",\"claude-sonnet-5-5\"]" ] && [ "$(printf "%s" "$r" | jq .cost_usd)" = null ]'
rm -rf "$PROJ/$SID/subagents"
r2="$("$U" transcript "$MAIN")"
ok "transcript: sub-agents started but their files missing => scope main-thread-only (never a silent undercount)" '[ "$(printf "%s" "$r2" | jq -r .scope)" = main-thread-only ] && [ "$(printf "%s" "$r2" | jq .input_tokens)" = 35 ]'
mkdir -p "$PROJ/$SID/subagents"; { line msg_C 7 70 700 0 thinking claude-haiku-5-5; line msg_C 7 70 700 0 text claude-haiku-5-5; } > "$PROJ/$SID/subagents/agent-aaa.jsonl"
ok "transcript: missing file is a usage error"            '! "$U" transcript "$T/nope.jsonl" >/dev/null 2>&1'

# ---- a finished KB + local run rows to patch ----
REPO="$T/repo"; KB="$REPO/.ckb"; mkdir -p "$KB" "$T/state" && git -C "$REPO" init -q -b main && touch "$KB/.ckb-output"
mkman(){ jq -nc --arg j "$1" '{job:{id:$j}, status:"complete", token_usage:null, token_usage_note:"old"}' > "$KB/manifest.json"; }
mkruns(){ { jq -nc '{job_id:"jobOLD", finished_at:"2000-01-01T00:00:00Z", token_usage:null, status:"complete"}'
            jq -nc '{job_id:"jobNEW", finished_at:"2999-01-01T00:00:00Z", token_usage:null, status:"complete"}'; } > "$CKB_STATE_DIR/runs.jsonl"; }

# ---- headless: claude -p --output-format json ----
mkman jobNEW; mkruns
HJ='{"type":"result","num_turns":42,"total_cost_usd":3.21,"usage":{"input_tokens":100,"output_tokens":900,"cache_read_input_tokens":9000,"cache_creation_input_tokens":0},"modelUsage":{"claude-sonnet-5-5":{}}}'
printf '%s' "$HJ" | "$U" record "$KB" - > "$T/rec.out" 2>&1; rc=$?
ok "record: exits 0 and patches the manifest"            '[ $rc -eq 0 ] && jq -e ".token_usage.output_tokens == 900 and .token_usage.cost_usd == 3.21 and .token_usage.scope == \"headless\" and .token_usage.source == \"claude-p\"" "$KB/manifest.json" >/dev/null'
ok "record: patches the matching local run row, leaves others alone" '[ "$(jq -c "select(.job_id==\"jobNEW\") | [.token_usage.input_tokens,.cost_usd,.usage_scope]" "$CKB_STATE_DIR/runs.jsonl")" = "[100,3.21,\"headless\"]" ] && [ "$(jq -c "select(.job_id==\"jobOLD\") | .token_usage" "$CKB_STATE_DIR/runs.jsonl")" = null ]'
ok "record: cache hit rate from the usage block"         '[ "$(jq .token_usage.cache_hit_pct "$KB/manifest.json")" = "98.9" ]'
ok "record: refuses a dir that is not a CKB output dir"  'mkdir -p "$T/plain" && ! printf "%s" "$HJ" | "$U" record "$T/plain" - >/dev/null 2>&1'
ok "record: refuses input without .usage"                'mkman jobNEW; ! echo "{\"x\":1}" | "$U" record "$KB" - >/dev/null 2>&1 && [ "$(jq .token_usage "$KB/manifest.json")" = null ]'
ok "record: with no matching run row only the manifest is patched, nothing crashes" 'mkman jobNOROW; mkruns; printf "%s" "$HJ" | "$U" record "$KB" - >/dev/null 2>&1; [ "$(jq .token_usage.output_tokens "$KB/manifest.json")" = 900 ] && [ "$(jq -c "select(.token_usage != null)" "$CKB_STATE_DIR/runs.jsonl" | wc -l | tr -d " ")" = 0 ]'

# ---- interactive: /kb typed -> SessionEnd backfill via the hook ----
mkman jobNEW; mkruns
P="$(jq -nc --arg s "$SID" '{session_id:$s, hook_event_name:"UserPromptSubmit", prompt:"/kb"}')"; printf '%s' "$P" | "$ROOT/hooks/arm.sh" >/dev/null
ok "arm: first /kb prompt writes a stable start marker"   '[ -s "$CLAUDE_PLUGIN_DATA/armed/$SID.kbstart" ]'
m1="$(cat "$CLAUDE_PLUGIN_DATA/armed/$SID.kbstart")"; sleep 1; printf '%s' "$P" | "$ROOT/hooks/arm.sh" >/dev/null
ok "arm: the start marker is not rewritten by a later /kb" '[ "$(cat "$CLAUDE_PLUGIN_DATA/armed/$SID.kbstart")" = "$m1" ]'
E="$(jq -nc --arg s "$SID" --arg t "$MAIN" --arg c "$REPO" '{session_id:$s, hook_event_name:"SessionEnd", transcript_path:$t, cwd:$c}')"
printf '%s' "$E" | "$ROOT/hooks/arm.sh" >/dev/null 2>&1; rc=$?
ok "SessionEnd: hook exits 0"                              '[ $rc -eq 0 ]'
ok "SessionEnd: last /kb run of the session gets the session total (main + sub-agents)" '[ "$(jq -c "select(.job_id==\"jobNEW\") | [.token_usage.input_tokens,.token_usage.output_tokens,.usage_scope]" "$CKB_STATE_DIR/runs.jsonl")" = "[42,375,\"session\"]" ]'
ok "SessionEnd: a run that finished BEFORE /kb was typed is not touched" '[ "$(jq -c "select(.job_id==\"jobOLD\") | .token_usage" "$CKB_STATE_DIR/runs.jsonl")" = null ]'
ok "SessionEnd: the repo's manifest is patched too (found via the hook cwd)" 'jq -e ".token_usage.output_tokens == 375 and .token_usage.source == \"transcript\"" "$KB/manifest.json" >/dev/null'
ok "SessionEnd: markers removed"                            '[ ! -e "$CLAUDE_PLUGIN_DATA/armed/$SID.kbstart" ] && [ ! -e "$CLAUDE_PLUGIN_DATA/armed/$SID" ]'

# ---- never estimate, never fail ----
SID2="99999999-2222-3333-4444-555555555555"; mkman jobNEW; mkruns
printf '%s' "$(jq -nc --arg s "$SID2" '{session_id:$s, hook_event_name:"UserPromptSubmit", prompt:"/kb"}')" | "$ROOT/hooks/arm.sh" >/dev/null
printf '%s' "$(jq -nc --arg s "$SID2" --arg c "$REPO" '{session_id:$s, hook_event_name:"SessionEnd", transcript_path:"/nonexistent/x.jsonl", cwd:$c}')" | HOME="$T/nohome" "$ROOT/hooks/arm.sh" >/dev/null 2>&1; rc=$?
ok "unavailable transcript: exits 0 and token_usage stays null (never estimated)" '[ $rc -eq 0 ] && [ "$(jq -c "select(.job_id==\"jobNEW\") | .token_usage" "$CKB_STATE_DIR/runs.jsonl")" = null ] && [ "$(jq .token_usage "$KB/manifest.json")" = null ]'
printf '%s' "$(jq -nc --arg s "SID3" '{session_id:$s, hook_event_name:"SessionEnd"}')" | "$ROOT/hooks/arm.sh" >/dev/null 2>&1; rc=$?
ok "a session that never ran /kb is left alone"           '[ $rc -eq 0 ] && [ "$(jq -c "select(.job_id==\"jobNEW\") | .token_usage" "$CKB_STATE_DIR/runs.jsonl")" = null ]'
SID4="44444444-2222-3333-4444-555555555555"; mkman jobOTHER; mkruns
printf '%s' "$(jq -nc --arg s "$SID4" '{session_id:$s, hook_event_name:"UserPromptSubmit", prompt:"/kb"}')" | "$ROOT/hooks/arm.sh" >/dev/null
printf '%s' "$(jq -nc --arg s "$SID4" --arg t "$MAIN" --arg c "$REPO" '{session_id:$s, hook_event_name:"SessionEnd", transcript_path:$t, cwd:$c}')" | "$ROOT/hooks/arm.sh" >/dev/null 2>&1
ok "backfill: a manifest belonging to a DIFFERENT job is never overwritten (the run row still is)" '[ "$(jq .token_usage "$KB/manifest.json")" = null ] && [ "$(jq -c "select(.job_id==\"jobNEW\") | .token_usage.output_tokens" "$CKB_STATE_DIR/runs.jsonl")" = 375 ]'
printf 'garbage{' | "$U" backfill >/dev/null 2>&1; rc=$?
ok "backfill never fails on a garbage payload (a hook must not break a session)" '[ $rc -eq 0 ]'

# ---- privacy: usage data is local-only ----
ok "usage.sh has no network code"                         '! grep -qE "curl|wget|nc |/dev/tcp" "$ROOT/scripts/usage.sh"'

echo "usage tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
