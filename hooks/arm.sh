#!/usr/bin/env bash
# arm.sh — scopes the read-only gate to sessions that use this plugin.
# UserPromptSubmit: /kb or /kb-validate (optionally namespaced codebase-kb-engine:) ARMS the session;
#   /map, /hunt, /plan do NOT arm (their names collide with other plugins' commands, e.g. /plan);
#                   /kb-unlock DISARMS it (only a human-typed prompt can do this — the model cannot).
# SessionEnd:       disarms. Stale arm files (>24h) are purged.
# Never blocks a prompt (always exit 0).
set -uo pipefail
payload="$(cat)"
STATE="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}/ckb-guard}/armed"
jqget(){ command -v jq >/dev/null 2>&1 && printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null; }
rawget(){ printf '%s' "$payload" | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed -E 's/.*"([^"]*)"$/\1/'; }   # jq-less fallback
sid="$(jqget '.session_id')"; [ -z "$sid" ] && sid="$(rawget session_id)"; sid="$(printf '%s' "$sid" | tr -cd 'A-Za-z0-9_-')"
event="$(jqget '.hook_event_name')"; [ -z "$event" ] && event="$(rawget hook_event_name)"
[ -n "$sid" ] || exit 0
mkdir -p "$STATE" 2>/dev/null && chmod 700 "$STATE" 2>/dev/null
find "$STATE" -type f -mmin +1440 -delete 2>/dev/null

case "$event" in
  SessionEnd) rm -f "$STATE/$sid"; exit 0 ;;
  UserPromptSubmit)
    prompt="$(jqget '.prompt')"; [ -z "$prompt" ] && prompt="$(rawget prompt)"
    if printf '%s' "$prompt" | grep -qE '^[[:space:]]*/(codebase-kb-engine:)?kb-unlock([[:space:]]|$)'; then
      rm -f "$STATE/$sid"; echo "[codebase-kb-engine] Read-only mode OFF for this session."; exit 0
    fi
    if printf '%s' "$prompt" | grep -qE '^[[:space:]]*/(codebase-kb-engine:)?(kb|kb-validate)([[:space:]]|$)'; then
      : > "$STATE/$sid"
      echo "[codebase-kb-engine] Read-only mode ON for this session: the repo cannot be modified; writes are allowed only inside <repo>/ckb/ (the knowledge base). The user can type /kb-unlock to release."
    fi ;;
esac
exit 0
