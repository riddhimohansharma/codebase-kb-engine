#!/usr/bin/env bash
# arm.sh — scopes the read-only gate to sessions that use this plugin.
# UserPromptSubmit: an engine command (/kb, /kb-validate, /map, /hunt, /plan) ARMS the session;
#                   /kb-unlock DISARMS it (only a human-typed prompt can do this — the model cannot).
# SessionEnd:       disarms. Stale arm files (>24h) are purged.
# Never blocks a prompt (always exit 0).
set -uo pipefail
payload="$(cat)"
STATE="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}/ckb-guard}/armed"
jqget(){ command -v jq >/dev/null 2>&1 && printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null; }
sid="$(jqget '.session_id' | tr -cd 'A-Za-z0-9_-')"
event="$(jqget '.hook_event_name')"
[ -n "$sid" ] || exit 0
mkdir -p "$STATE" 2>/dev/null && chmod 700 "$STATE" 2>/dev/null
find "$STATE" -type f -mmin +1440 -delete 2>/dev/null

case "$event" in
  SessionEnd) rm -f "$STATE/$sid"; exit 0 ;;
  UserPromptSubmit)
    prompt="$(jqget '.prompt')"
    if printf '%s' "$prompt" | grep -qE '^[[:space:]]*/(codebase-kb-engine:)?kb-unlock([[:space:]]|$)'; then
      rm -f "$STATE/$sid"; echo "[codebase-kb-engine] Read-only mode OFF for this session."; exit 0
    fi
    if printf '%s' "$prompt" | grep -qE '^[[:space:]]*/(codebase-kb-engine:)?(kb|kb-validate|map|hunt|plan)([[:space:]]|$)'; then
      : > "$STATE/$sid"
      echo "[codebase-kb-engine] Read-only mode ON for this session: the repo cannot be modified; writes are allowed only inside a CKB output dir (marked .ckb-output). The user can type /kb-unlock to release."
    fi ;;
esac
exit 0
