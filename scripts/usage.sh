#!/usr/bin/env bash
# usage.sh — token usage and cost for a /kb run, recorded LOCALLY (manifest.json + the local runs.jsonl row). Never sent upstream.
#   usage.sh transcript <session.jsonl>   print the session's usage as JSON (main thread + sub-agents, de-duplicated)
#   usage.sh record <kb_dir> [json|-]     headless runs: patch usage/cost from `claude -p --output-format json` (stdin by default)
#   usage.sh backfill                     SessionEnd hook payload on stdin: patch the last /kb run of an interactive session
# Why a script: a session cannot observe its own usage while it runs, so finalize.sh records `token_usage: null` and this fills it in.
# Facts it relies on (verified against real Claude Code transcripts):
#   · sub-agent (scout/writer/auditor) usage is NOT in the main transcript; it lives in <session>/subagents/agent-*.jsonl.
#   · every content block of one API response is logged as its own line with the SAME usage, so lines must be de-duplicated
#     by message id or the totals are ~2x too high.
#   · transcripts carry no cost. Cost is only known for headless runs (claude -p reports total_cost_usd); otherwise it stays null.
# bash 3.2+, jq 1.6+. Always exits 0 from `backfill` (a hook must never fail a session); other commands exit 2 on usage errors.
set -uo pipefail
die(){ echo "usage: $*" >&2; exit 2; }
SDIR="${CKB_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/codebase-kb-engine}"
RUNS="$SDIR/runs.jsonl"
ARMED="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}/ckb-guard}/armed"

# sum one session: $1 = main transcript. Prints a JSON object.
sum_transcript(){
  local main="$1" dir sub files=() n_sub=0
  dir="$(dirname "$main")/$(basename "$main" .jsonl)/subagents"
  files+=("$main")
  if [ -d "$dir" ]; then for f in "$dir"/agent-*.jsonl; do [ -f "$f" ] && { files+=("$f"); n_sub=$((n_sub + 1)); }; done; fi
  # how many sub-agents did the main thread start? if it started some but none were found, the total undercounts
  local started; started="$(jq -c 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and (.name == "Task" or .name == "Agent"))' "$main" 2>/dev/null | wc -l | tr -d ' ')"
  cat "${files[@]}" 2>/dev/null | jq -s --argjson started "${started:-0}" --argjson found "$n_sub" '
    [.[] | select(.message.usage != null)
         | {id: (.message.id // .requestId // .uuid), u: .message.usage, m: (.message.model // null)}]
    | unique_by(.id) as $msgs
    | def sum(f): [$msgs[] | .u[f] // 0] | add // 0;
      (sum("input_tokens")) as $in | (sum("output_tokens")) as $out | (sum("cache_read_input_tokens")) as $cr | (sum("cache_creation_input_tokens")) as $cc
    | {source: "transcript", messages: ($msgs | length), input_tokens: $in, output_tokens: $out,
       cache_read_input_tokens: $cr, cache_creation_input_tokens: $cc,
       cache_hit_pct: (if ($in + $cr + $cc) > 0 then (($cr * 1000 / ($in + $cr + $cc)) | round / 10) else null end),
       models: ([$msgs[].m | select(. != null)] | unique), subagent_files: $found, subagents_started: $started,
       scope: (if $started > 0 and $found == 0 then "main-thread-only" else "session" end),
       cost_usd: null}'
}

# patch a usage object into the manifest (when given) and into the local runs.jsonl row for $job
patch(){ # $1 job id, $2 usage json, $3 optional manifest path
  local job="$1" tu="$2" man="${3:-}"
  if [ -n "$man" ] && [ -f "$man" ]; then
    jq --argjson tu "$tu" --arg job "$job" 'if (.job.id // "") == $job then .token_usage = $tu | .token_usage_note = "Recorded locally by scripts/usage.sh (" + ($tu.source) + ", scope " + ($tu.scope) + "). Cost is only known for headless runs." else . end' "$man" > "$man.tmp.$$" \
      && mv -f "$man.tmp.$$" "$man" || rm -f "$man.tmp.$$"
  fi
  if [ -f "$RUNS" ]; then
    jq -c --arg job "$job" --argjson tu "$tu" 'if .job_id == $job then . + {token_usage: $tu, cost_usd: $tu.cost_usd, usage_scope: $tu.scope} else . end' "$RUNS" > "$RUNS.tmp.$$" \
      && mv -f "$RUNS.tmp.$$" "$RUNS" || rm -f "$RUNS.tmp.$$"
  fi
}

cmd="${1:-}"; shift || true
case "$cmd" in
  transcript) [ -f "${1:-}" ] || die "usage.sh transcript <session.jsonl>"
    sum_transcript "$1" ;;
  record) kb="${1:-}"; [ -d "$kb" ] || die "usage.sh record <kb_dir> [json|-]"
    [ -f "$kb/.ckb-output" ] || { echo "usage: REFUSED: $kb is not a CKB output dir" >&2; exit 2; }
    src="${2:--}"; json="$(if [ "$src" = - ]; then cat; else cat "$src"; fi)"
    printf '%s' "$json" | jq -e 'type == "object" and (.usage | type == "object")' >/dev/null 2>&1 || { echo "usage: input is not claude -p --output-format json (no .usage)" >&2; exit 2; }
    job="$(jq -r '.job.id // empty' "$kb/manifest.json" 2>/dev/null)"; [ -n "$job" ] || { echo "usage: $kb/manifest.json has no job id (run finalize first)" >&2; exit 2; }
    tu="$(printf '%s' "$json" | jq -c '{source: "claude-p", messages: (.num_turns // null), input_tokens: (.usage.input_tokens // 0), output_tokens: (.usage.output_tokens // 0),
         cache_read_input_tokens: (.usage.cache_read_input_tokens // 0), cache_creation_input_tokens: (.usage.cache_creation_input_tokens // 0),
         cache_hit_pct: (((.usage.input_tokens // 0) + (.usage.cache_read_input_tokens // 0) + (.usage.cache_creation_input_tokens // 0)) as $t
                         | if $t > 0 then (((.usage.cache_read_input_tokens // 0) * 1000 / $t) | round / 10) else null end),
         models: ((.modelUsage // {}) | keys), scope: "headless", cost_usd: (.total_cost_usd // null)}')"
    patch "$job" "$tu" "$kb/manifest.json"; printf '%s\n' "$tu" ;;
  backfill)
    payload="$(cat)"
    sid="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9_-')"
    [ -n "$sid" ] && [ -f "$ARMED/$sid.kbstart" ] && [ -f "$RUNS" ] || exit 0          # not a /kb session, or nothing to patch
    start="$(cat "$ARMED/$sid.kbstart" 2>/dev/null)"
    tp="$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)"
    if [ -z "$tp" ] || [ ! -f "$tp" ]; then tp="$(ls "$HOME"/.claude/projects/*/"$sid".jsonl 2>/dev/null | head -1)"; fi
    [ -n "$tp" ] && [ -f "$tp" ] || exit 0                                              # transcript unavailable: leave token_usage null, never estimate
    job="$(jq -rs --arg s "$start" '[.[] | select(.token_usage == null and ((.finished_at // "") >= $s))] | last | .job_id // empty' "$RUNS" 2>/dev/null)"
    [ -n "$job" ] || exit 0
    tu="$(sum_transcript "$tp")" || exit 0
    cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"; man=""
    if [ -n "$cwd" ] && root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"; then man="$root/.ckb/manifest.json"; fi
    patch "$job" "$tu" "$man"; exit 0 ;;
  *) die "usage.sh transcript <session.jsonl> | record <kb_dir> [json|-] | backfill" ;;
esac
