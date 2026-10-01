#!/usr/bin/env bash
# docmeta.sh — deterministic YAML front-matter + final-ID rewrite for the 8 model-written KB docs.
# Usage: docmeta.sh <kb_dir> <ckb.json> [--idmap <idmap.json>]
#   idmap.json: {"<local id>": "<final id>", ...}; rewrites ids inside `ckb:<id>` markers.
# Per doc: (1) strip an existing leading front-matter block, (2) rewrite `ckb:` markers via the idmap,
# (3) regenerate each <a id="..."></a> anchor that heads a "### heading + `ckb:<id>`" block from its marker
# (lowercase, non [a-z0-9] -> '-'), (4) prepend fresh front-matter. No timestamps: re-running is a no-op.
# confidence: PER-DOC counts over entities whose id appears in a `ckb:` marker in the doc OR whose provenance
#   "path:line" is cited in the doc (confidence_scope: doc). Relations are not counted.
# Output: one line "DOCMETA updated=<n> missing=<n> ids_rewritten=<n>".
# Exit: 0 all 8 docs processed · 1 some docs missing (present ones still processed) or a write failed · 2 usage/precondition.
set -uo pipefail
die(){ code="$1"; shift; printf '%s\n' "$@" >&2; exit "$code"; }
DOCS="00-overview.md 01-technical-architecture.md 02-functional-workflows.md 03-business-rules.md 04-system-context-and-gaps.md 05-operations.md 06-security-and-data.md 07-decisions.md"
kb="${1:-}"; art="${2:-}"; shift 2 2>/dev/null || die 2 "usage: docmeta.sh <kb_dir> <ckb.json> [--idmap <idmap.json>]"
idmap=""
while [ $# -gt 0 ]; do
  case "$1" in --idmap) idmap="${2:-}"; [ $# -ge 2 ] && shift ;; *) die 2 "unknown option: $1" ;; esac; shift
done
[ -d "$kb" ] || die 2 "kb_dir not a dir: $kb"
jq -e '(.repo.commit_sha | type) == "string"' "$art" >/dev/null 2>&1 || die 2 "artifact missing, not JSON, or lacks repo.commit_sha: $art"
if [ -n "$idmap" ]; then jq -e 'type == "object"' "$idmap" >/dev/null 2>&1 || die 2 "idmap missing or not a JSON object: $idmap"; fi
tmpd="$(mktemp -d)"; trap 'rm -rf "$tmpd"' EXIT
: > "$tmpd/map.tsv"
[ -n "$idmap" ] && jq -r 'to_entries[] | select((.value | type) == "string") | [.key, .value] | @tsv' "$idmap" > "$tmpd/map.tsv"

meta(){ case "$1" in   # ckb_doc|title|audience|diataxis
  00-*) echo "overview|Overview|everyone: new engineers, product, leadership|explanation" ;;
  01-*) echo "technical-architecture|Technical architecture|engineers, architects|explanation" ;;
  02-*) echo "functional-workflows|Functional workflows|engineers, product, QA|explanation" ;;
  03-*) echo "business-rules|Business rules|product, engineers, QA, compliance|reference" ;;
  04-*) echo "system-context-and-gaps|System context and gaps|architects, tech leads|explanation" ;;
  05-*) echo "operations|Operations|engineers, SRE, on-call|how-to" ;;
  06-*) echo "security-and-data|Security and data|security, compliance, engineers|reference" ;;
  07-*) echo "decisions|Decisions|architects, tech leads|explanation" ;;
esac; }

BODY_AWK='
function san(s){ s = tolower(s); gsub(/[^a-z0-9]/, "-", s); return s }
function trim(s){ sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
BEGIN { if (mapfile != "") while ((getline l < mapfile) > 0) { t = index(l, "\t"); if (t > 1) M[substr(l, 1, t - 1)] = substr(l, t + 1) } }
NR == 1 && $0 == "---" { fm = 1; hold[++nh] = $0; next }
fm == 1 { hold[++nh] = $0; if ($0 == "---") { fm = 2; nh = 0 }; next }
{
  out = ""; rest = $0
  while ((p = index(rest, "`ckb:")) > 0) {
    out = out substr(rest, 1, p + 4); rest = substr(rest, p + 5)
    q = index(rest, "`"); if (q == 0) break
    id = substr(rest, 1, q - 1); if (id in M) { id = M[id]; nrw++ }
    out = out id; rest = substr(rest, q)
  }
  L[++n] = out rest
}
END {
  if (fm == 1) { n = 0; for (i = 1; i <= nh; i++) L[++n] = hold[i] }   # unterminated: not front-matter, keep as-is
  for (i = 1; i <= n; i++) {
    if (L[i] !~ /^<a id="[^"]*"><\/a>$/) continue
    j = i + 1; while (j <= n && trim(L[j]) == "") j++
    if (j > n || L[j] !~ /^#+ /) continue
    k = j + 1; while (k <= n && trim(L[k]) == "") k++
    m = (k <= n) ? trim(L[k]) : ""
    if (m ~ /^`ckb:[^`]+`$/) L[i] = "<a id=\"" san(substr(m, 6, length(m) - 6)) "\"></a>"
  }
  for (i = 1; i <= n; i++) print L[i]
  print nrw + 0 > cntfile
}'

updated=0; missing=0; rewritten=0; failed=0
for d in $DOCS; do
  f="$kb/$d"
  [ -f "$f" ] || { missing=$((missing+1)); printf 'docmeta: missing %s\n' "$d" >&2; continue; }
  awk -v mapfile="$tmpd/map.tsv" -v cntfile="$tmpd/cnt" "$BODY_AWK" "$f" > "$tmpd/body" || { failed=1; continue; }
  rewritten=$((rewritten + $(cat "$tmpd/cnt")))
  { grep -oE '`ckb:[^`]+`' "$tmpd/body" || true; } | sed 's/^`ckb://; s/`$//' | sort -u | jq -R . | jq -s . > "$tmpd/refs.json"
  { grep -oE '[A-Za-z0-9_./-]+[.][A-Za-z0-9]+:[0-9]+' "$tmpd/body" || true; } | sed 's#^\./##' | sort -u | jq -R . | jq -s . > "$tmpd/cites.json"
  m="$(meta "$d")"
  jq -r --arg ex "':(exclude)ckb'" --arg doc "${m%%|*}" --arg rest "${m#*|}" --slurpfile refs "$tmpd/refs.json" --slurpfile cites "$tmpd/cites.json" '
    ($rest | split("|")) as $r
    | ($refs[0] | map({key: ., value: true}) | from_entries) as $R
    | ($cites[0] | map({key: ., value: true}) | from_entries) as $P
    | [(.entities // {}) | .[]? | .[]? | objects
        | select(($R[.id // ""] // false) or any(.provenance[]?; ($P["\(.path):\(.line)"] // false)))] as $hit
    | "---",
      "ckb_doc: \($doc | tojson)",
      "title: \($r[0] | tojson)",
      "audience: \($r[1] | tojson)",
      "diataxis: \($r[2] | tojson)",
      "source_commit: \(.repo.commit_sha | tojson)",
      "branch: \((.repo.branch // "") | tojson)",
      "generator: \(("\(.generator.name // "codebase-kb-engine") \(.generator.version // "")" | sub(" $"; "")) | tojson)",
      "ckb_version: \((.ckb_version // "") | tojson)",
      "confidence_scope: \"doc\"",
      "confidence:",
      "  confirmed: \([$hit[] | select(.confidence == "confirmed")] | length)",
      "  inferred: \([$hit[] | select(.confidence == "inferred")] | length)",
      "  unknown: \([$hit[] | select(.confidence != "confirmed" and .confidence != "inferred")] | length)",
      "freshness_cmd: \(("git diff --quiet " + .repo.commit_sha + " HEAD -- . " + $ex) | tojson)",
      "---"' "$art" > "$tmpd/fm" || { failed=1; continue; }
  cat "$tmpd/fm" "$tmpd/body" > "$tmpd/new" && mv -f "$tmpd/new" "$f" || { failed=1; continue; }
  updated=$((updated+1))
done
printf 'DOCMETA updated=%s missing=%s ids_rewritten=%s\n' "$updated" "$missing" "$rewritten"
[ "$missing" -eq 0 ] && [ "$failed" -eq 0 ]
