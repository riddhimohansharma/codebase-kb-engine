#!/usr/bin/env bash
# coverage.sh <inventory.json> <draft-or-ckb.json> [<repo_root>] — compute the CKB v0.2 `coverage` object.
# Per bucket: found = inventory file count; cited = inventory files cited by >=1 provenance path, manifest_path or
# api_spec path anywhere in the draft/artifact; uncited = the rest (sorted, max 200). Citations are normalized
# ("./" stripped, ":line[-end]" suffix stripped, <repo_root>/ prefix stripped when given). Prints JSON; exit 0.
set -euo pipefail
export LC_ALL=C
die(){ echo "coverage: $*" >&2; exit 2; }
[ $# -ge 2 ] || die "usage: coverage.sh <inventory.json> <draft-or-ckb.json> [<repo_root>]"
command -v jq >/dev/null 2>&1 || die "jq is required"
[ -r "$1" ] || die "cannot read inventory: $1"
[ -r "$2" ] || die "cannot read draft/artifact: $2"
jq -e 'type == "object" and (.buckets | type) == "object"' "$1" >/dev/null 2>&1 || die "not an inventory.json: $1"
jq -e 'type == "object"' "$2" >/dev/null 2>&1 || die "not a JSON object: $2"
root=""; if [ $# -ge 3 ]; then root="$(cd "$3" 2>/dev/null && pwd -P || printf '%s' "$3")"; fi
jq -n --slurpfile inv "$1" --slurpfile doc "$2" --arg root "$root" '
  def norm: tostring
    | (if $root != "" and startswith($root + "/") then .[($root | length) + 1:] else . end)
    | sub("^(\\./)+"; "") | sub(":[0-9]+(-[0-9]+)?$"; "");
  ["manifests","lockfiles","routes","events","datastores","migrations","iac","ci","config","api_specs"] as $B
  | $inv[0] as $i
  | ([$doc[0] | ..
       | objects
       | ((.provenance? // empty | if type == "array" then .[] else empty end | objects | .path? // empty),
          (.manifest_path? // empty),
          (if (.format? | type) == "string" then (.path? // empty) else empty end))
       | strings | norm]
     + [$doc[0] | (.entities? // {}) | (.api_specs? // []) | if type == "array" then .[] else empty end | objects | .path? // empty | strings | norm]
    ) as $paths
  | (reduce $paths[] as $p ({}; .[$p] = true)) as $cited
  | {
      files_total: ($i.files_total // 0),
      sampled: false,
      buckets: (reduce $B[] as $b ({};
        (($i.buckets[$b] // []) | unique) as $f
        | ([$f[] | select($cited[.] | not)]) as $u
        | .[$b] = {found: ($f | length), cited: (($f | length) - ($u | length)), uncited: $u[:200]}))
    }'
