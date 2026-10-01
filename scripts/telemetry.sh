#!/usr/bin/env bash
# telemetry.sh — anonymous usage reports for codebase-kb-engine (ON by default, easy to turn off).
# Each /kb run's anonymous record (see README "Metrics and privacy") is sent to the maintainer's relay, which stores it
# in a private GitHub repo. Records contain no repository names, paths, code, URLs or values.
# Off if any of: DO_NOT_TRACK=1 · CKB_TELEMETRY=off · CKB_METRICS=off · `telemetry.sh off` (saved per machine).
# Usage: telemetry.sh status | on | off | send <record.json> | notice
set -uo pipefail
SDIR="${CKB_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/codebase-kb-engine}"
URL="${CKB_TELEMETRY_URL:-}"            # set to the deployed relay endpoint (…/v1/report) at release time
DEFAULT_URL="https://codebase-kb-telemetry.codebase-kb.workers.dev/v1/report"
[ -z "$URL" ] && URL="$DEFAULT_URL"
why_off(){
  case "${DO_NOT_TRACK:-}" in 1|true|TRUE|yes) echo "DO_NOT_TRACK is set"; return ;; esac
  case "${CKB_TELEMETRY:-}" in off|0|false|no) echo "CKB_TELEMETRY=${CKB_TELEMETRY}"; return ;; esac
  [ "${CKB_METRICS:-on}" = off ] && { echo "CKB_METRICS=off"; return; }
  [ "$(cat "$SDIR/telemetry" 2>/dev/null)" = off ] && { echo "turned off on this machine"; return; }
  echo ""; }
case "${1:-status}" in
  status) r="$(why_off)"
    if [ -n "$r" ]; then echo "telemetry: OFF ($r)"; else echo "telemetry: ON — anonymous run reports are shared with the maintainer"; fi
    echo "endpoint: ${URL:-not configured (nothing is sent)}"; echo "turn off: codebase-kb-engine telemetry off  (or CKB_TELEMETRY=off, DO_NOT_TRACK=1)" ;;
  on)  mkdir -p "$SDIR" && echo on  > "$SDIR/telemetry" && echo "telemetry: ON" ;;
  off) mkdir -p "$SDIR" && echo off > "$SDIR/telemetry" && echo "telemetry: OFF (saved for this machine)" ;;
  notice) # print the one-time notice (only when telemetry is on)
    [ -n "$(why_off)" ] && exit 0; [ -e "$SDIR/telemetry-notice-shown" ] && exit 0
    mkdir -p "$SDIR" && : > "$SDIR/telemetry-notice-shown"
    echo "TELEMETRY_NOTICE=codebase-kb-engine shares an anonymous run report (version, status, timings, coverage and quality counts; never repo names, paths, code or values) to help improve the plugin. Turn off any time: 'codebase-kb-engine telemetry off' or CKB_TELEMETRY=off." ;;
  send) f="${2:-}"; [ -f "$f" ] || exit 0
    [ -n "$(why_off)" ] && exit 0; [ -z "$URL" ] && exit 0
    case "$URL" in https://*) ;; *) [ "${CKB_TELEMETRY_ALLOW_INSECURE:-}" = 1 ] || exit 0 ;; esac
    command -v curl >/dev/null || exit 0
    if [ "${CKB_TELEMETRY_SYNC:-}" = 1 ]; then
      curl -fsS -m 3 -X POST -H 'content-type: application/json' --data-binary @"$f" "$URL" >/dev/null 2>&1 || true
    else
      ( curl -fsS -m 3 -X POST -H 'content-type: application/json' --data-binary @"$f" "$URL" >/dev/null 2>&1; rm -f "$f" ) &
      exit 0
    fi ;;
  *) echo "usage: telemetry.sh status|on|off|send <file>|notice" >&2; exit 2 ;;
esac
