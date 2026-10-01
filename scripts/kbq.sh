#!/usr/bin/env bash
# kbq.sh — read-only queries over a KB dir, so /kb never needs ad-hoc jq/grep on large files (keeps the
# orchestrator's context small and avoids permission prompts). Output is compact; never prints secret values.
# Usage:
#   kbq.sh summary <kb_dir>                 counts per collection across ckb.draft.d/*.json (or ckb.json)
#   kbq.sh names <kb_dir>                   business-rule and workflow names (for 02/03 headings), one per line
#   kbq.sh ids <kb_dir> <collection>        local/final id <TAB> name for one collection
#   kbq.sh claims <kb_dir> [max=15]         audit sample: confirmed claims as JSON [{id, claim, path, line}]
#   kbq.sh anchors <doc.md>                 headings with their anchors and ckb: markers
#   kbq.sh status <kb_dir>                  status, validation, docs violations, coverage, top warnings from manifest.json
set -uo pipefail
die(){ echo "kbq: $*" >&2; exit 2; }
src(){ # JSON array of draft fragments, else the artifact
  if ls "$1"/ckb.draft.d/*.json >/dev/null 2>&1; then jq -s '.' "$1"/ckb.draft.d/*.json
  elif [ -f "$1/ckb.draft.json" ]; then jq -s '.' "$1/ckb.draft.json"
  elif [ -f "$1/ckb.json" ]; then jq -s '.' "$1/ckb.json"
  else die "no draft or ckb.json in $1"; fi; }
cmd="${1:-}"; shift || true
case "$cmd" in
  summary) [ -d "${1:-}" ] || die "usage: kbq.sh summary <kb_dir>"
    src "$1" | jq -r '[.[].entities // {} | to_entries[] | {k: .key, n: (.value | length)}] | group_by(.k) | map("\(.[0].k)=\(map(.n) | add)") | join(" ")' ;;
  names) [ -d "${1:-}" ] || die "usage: kbq.sh names <kb_dir>"
    src "$1" | jq -r '.[] | (.entities.business_rules // [])[] | "rule\t\(.name)"' ; src "$1" | jq -r '.[] | (.entities.workflows // [])[] | "workflow\t\(.name)"' ;;
  ids) [ -d "${1:-}" ] && [ -n "${2:-}" ] || die "usage: kbq.sh ids <kb_dir> <collection>"
    src "$1" | jq -r --arg c "$2" '.[] | (.entities[$c] // [])[] | "\(.id)\t\(.name // "")"' ;;
  claims) [ -d "${1:-}" ] || die "usage: kbq.sh claims <kb_dir> [max]"; max="${2:-15}"
    src "$1" | jq -c --argjson max "$max" '[.[] | .entities // {} |
        ([(.interfaces // [])[] | select(.role == "consumes")] | map(. + {_c: "interfaces", _p: 0})) +
        ([(.business_rules // [])[]] | map(. + {_c: "business_rules", _p: 1})) +
        ([(.datastores // [])[]] | map(. + {_c: "datastores", _p: 2})) | .[]]
      | map(select(.confidence == "confirmed" and ((.provenance // []) | length) > 0))
      | sort_by([._p, .provenance[0].path, .provenance[0].line]) | .[0:$max]
      | map({id, claim: ((.statement // (if .http then "\(.role) \(.http.method) \(.http.normalized_path) host=\(.http.host // "?")" else null end) // (if .table then "\(.access) \(.engine) table \(.table)" else null end) // .name) | tostring),
             path: .provenance[0].path, line: .provenance[0].line})' ;;
  anchors) [ -f "${1:-}" ] || die "usage: kbq.sh anchors <doc.md>"
    grep -nE '^#{2,3} |^<a id=|^`ckb:' "$1" | cut -c1-200 ;;
  status) [ -f "${1:-}/manifest.json" ] || die "usage: kbq.sh status <kb_dir> (no manifest.json)"
    jq -r '"status=\(.status) structural=\(.validation.structural) semantic=\(.validation.semantic)",
           (.validation.messages // [] | .[0:15][] | "  rule: \(.)"),
           ((.validation.docs // {}) | to_entries[] | "  docs: \(.key): \(.value[0:8] | join("; "))"),
           ((.coverage.buckets // {}) | to_entries[] | select(.value.found > 0) | "  coverage: \(.key) \(.value.cited)/\(.value.found)" + (if (.value.uncited | length) > 0 then " uncited: \(.value.uncited[0:10] | join(", "))" else "" end)),
           (.warnings // [] | .[0:15][] | "  warn: \(.)")' "$1/manifest.json" ;;
  *) die "usage: kbq.sh summary|names|ids|claims|anchors|status ..." ;;
esac
