#!/usr/bin/env bash
# lint-docs.sh — structural lint for the 8 model-written KB docs (contract: skills/kb-docs/SKILL.md).
# Usage: lint-docs.sh <kb_dir> [--parity <ckb.json>]
#        lint-docs.sh --spec            print the required-heading spec as JSON {"<doc>":["<## heading>",...]}
# Output: JSON {"<doc>":[violation,...], ...} on stdout. All 8 doc keys are always present; "parity" only with --parity.
# Exit: 0 no violations · 1 violations · 2 usage/precondition.
# Portable: bash 3.2+, POSIX awk (BSD/mawk/gawk), jq 1.6+.
set -uo pipefail
die(){ code="$1"; shift; printf '%s\n' "$@" >&2; exit "$code"; }
DOCS="00-overview.md 01-technical-architecture.md 02-functional-workflows.md 03-business-rules.md 04-system-context-and-gaps.md 05-operations.md 06-security-and-data.md 07-decisions.md"

headings(){ case "$1" in
  00-overview.md) printf '%s\n' "Elevator pitch" "Executive summary" "Stakeholders and users" "Quality goals" "Glossary" "Macro context" "How to read this KB" ;;
  01-technical-architecture.md) printf '%s\n' "First-principles core" "Containers (C4 L2)" "Components (C4 L3)" "Data model" "Interfaces" "Dependencies" "Configuration reference" "Deployment" "Non-functional posture" ;;
  02-functional-workflows.md) printf '%s\n' "Actors" "Capabilities" "Workflows" "State machines" "Error and edge handling" ;;
  03-business-rules.md) printf '%s\n' "Rule catalog" "Traceability" ;;
  04-system-context-and-gaps.md) printf '%s\n' "System context (C4 L1)" "Contracts exposed" "Contracts consumed" "Assumptions" "Risks and tech debt" "Open questions" ;;
  05-operations.md) printf '%s\n' "Build" "Run locally" "Test" "Deploy and environments" "Observability" "Alerts and failure modes" "Rollback" ;;
  06-security-and-data.md) printf '%s\n' "Trust boundaries" "AuthN/AuthZ model" "Data classification" "Secrets inventory" "Security findings" "Compliance notes" ;;
  07-decisions.md) printf '%s\n' "Decision log" "Existing ADRs" ;;
esac; }
budget(){ case "$1" in
  00-*) echo "300 1000" ;; 01-*) echo "400 1800" ;; 02-*|03-*) echo "300 1800" ;;
  04-*|06-*|07-*) echo "300 1500" ;; 05-*) echo "300 1200" ;;
esac; }

if [ "${1:-}" = "--spec" ]; then
  for d in $DOCS; do headings "$d" | jq -R . | jq -sc --arg d "$d" '{($d): .}'; done | jq -s 'add'
  exit 0
fi
kb="${1:-}"; [ $# -gt 0 ] && shift
parity=""
while [ $# -gt 0 ]; do
  case "$1" in --parity) parity="${2:-}"; [ $# -ge 2 ] && shift ;; *) die 2 "unknown option: $1" ;; esac; shift
done
[ -n "$kb" ] || die 2 "usage: lint-docs.sh <kb_dir> [--parity <ckb.json>] | --spec"
[ -d "$kb" ] || die 2 "kb_dir not a dir: $kb"
if [ -n "$parity" ]; then jq -e 'type == "object"' "$parity" >/dev/null 2>&1 || die 2 "parity artifact missing or not JSON: $parity"; fi
tmpd="$(mktemp -d)"; trap 'rm -rf "$tmpd"' EXIT
: > "$tmpd/v"

# One pass per doc. Prints one violation per line. Front-matter and fenced code are excluded from prose checks.
LINT_AWK='
function trim(s){ sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function san(s){ s = tolower(s); gsub(/[^a-z0-9]/, "-", s); return s }
function v(m){ print m }
function close_fence(){
  if (flang == "mermaid") {
    nmer++
    if (ftype ~ /^C4Container/) c4cont = 1
    if (ftype ~ /^C4Context/) c4ctx = 1
    if (ftype ~ /^sequenceDiagram/ && cur3 > 0) SEQ[cur3]++
    if (flen > 40) v("L" fstart ": mermaid block of " flen " lines (max 40)")
  } else if (flen > 15) v("L" fstart ": code block of " flen " lines (max 15)")
  infence = 0
}
function slugid(val, pre){ return (val ~ ("^" pre "-[a-z0-9]+(-[a-z0-9]+)*$")) }
BEGIN {
  nreq = split(req, R, "|"); split(bud, B, " ")
  CITE = "[A-Za-z0-9_./-]+[.][A-Za-z0-9]+:[0-9]+"
  CKBCITE = "[^A-Za-z0-9_./-]([.]/)?ckb/[A-Za-z0-9_./-]+:[0-9]"
  ANCHOR_SECS["01-technical-architecture.md|Components (C4 L3)"] = 1
  ANCHOR_SECS["01-technical-architecture.md|Interfaces"] = 1
  ANCHOR_SECS["02-functional-workflows.md|Workflows"] = 1
  ANCHOR_SECS["03-business-rules.md|Rule catalog"] = 1
  nf = split("id|statement|rationale|trigger|outcome|exceptions|enforced at|confidence", RF, "|")
  na_ = split("status|context|decision|consequences|evidence|confidence", AF, "|")
}
NR == 1 && $0 == "---" { fm = 1; next }
fm == 1 { if ($0 == "---") fm = 2; next }
{
  line = $0
  if (index(line, "ckb.draft")) v("L" NR ": mentions ckb.draft* (never reference draft files)")
  if (infence) {
    if (line ~ /^[ ]*(```|~~~)[ ]*$/) { close_fence(); prevnb = "```"; next }
    flen++
    t = trim(line); if (ftype == "" && t != "" && t !~ /^%%/) ftype = t
    next
  }
  if (line ~ /^[ ]*(```|~~~)/) {
    infence = 1; fstart = NR; flen = 0; ftype = ""; want = 0
    flang = line; sub(/^[ ]*(```|~~~)[ ]*/, "", flang); flang = tolower(trim(flang))
    next
  }
  words += NF
  if (line ~ CITE && !(index(line, "[C]") || index(line, "[I]") || index(line, "[?]")))
    v("L" NR ": citation without [C]/[I]/[?] tag")
  if ((" " line) ~ CKBCITE) v("L" NR ": cites ckb/ (the KB must not cite itself)")
  if (index(line, "Not applicable") && !index(line, "[?]")) v("L" NR ": Not applicable line without [?]")
  if (line ~ /^## /) {
    h2 = trim(substr(line, 4)); if (h2 in seen2) v("L" NR ": duplicate heading: ## " h2)
    seen2[h2] = NR; content[h2] = 0; cur3 = 0; want = 0; prevnb = line; next
  }
  if (line ~ /^### /) {
    n3++; H3[n3] = trim(substr(line, 5)); H3sec[n3] = h2; H3line[n3] = NR; H3prev[n3] = prevnb; H3next[n3] = ""
    cur3 = n3; want = n3; prevnb = line; next
  }
  if (trim(line) == "") next
  if (want) { H3next[want] = trim(line); want = 0 }
  prevnb = line
  if (h2 != "") content[h2]++
  if (index(line, "Not applicable")) na[h2] = 1
  if (h2 == "Open questions" && line ~ /^\|[ ]*Q-/) {
    q = line; sub(/^\|[ ]*/, "", q); sub(/[ ]*\|.*$/, "", q)
    if (!slugid(q, "Q") || q ~ /^Q-[0-9]+$/) v("L" NR ": open-question id not a slug (Q-<slug>): " q)
    nq++
  }
  if (cur3 > 0) {
    l = line; gsub(/\*/, "", l)
    if (l ~ /^[ ]*-[ ]+[A-Za-z][A-Za-z ]*:/) {
      f = l; sub(/^[ ]*-[ ]+/, "", f); val = f; sub(/:.*$/, "", f); f = tolower(trim(f))
      sub(/^[^:]*:/, "", val); val = trim(val)
      if (!((cur3, f) in FLD)) FLD[cur3, f] = val
    }
  }
}
END {
  if (fm == 1) v("unterminated front-matter")
  if (infence) v("L" fstart ": unterminated code fence")
  last = 0
  for (i = 1; i <= nreq; i++) {
    h = R[i]
    if (!(h in seen2)) { v("missing required heading: ## " h); continue }
    if (seen2[h] < last) v("heading out of order: ## " h)
    last = seen2[h]
    if (content[h] == 0) {
      has3 = 0; for (k = 1; k <= n3; k++) if (H3sec[k] == h) has3 = 1
      if (!has3) v("empty section: ## " h " (write: Not applicable — <reason> [?])")
    }
  }
  split(bud, B, " ")
  if (words < B[1] + 0) v("word count " words " below budget " B[1])
  if (words > B[2] + 0) v("word count " words " above budget " B[2])
  for (k = 1; k <= n3; k++) {
    if (!((doc "|" H3sec[k]) in ANCHOR_SECS)) continue
    a = H3prev[k]; m = H3next[k]
    okA = (a ~ /^<a id="[a-z0-9-]+"><\/a>$/); okM = (m ~ /^`ckb:[^`]+`$/)
    if (!okA) v("L" H3line[k] ": ### " H3[k] ": missing <a id=\"...\"></a> anchor line before heading")
    if (!okM) v("L" H3line[k] ": ### " H3[k] ": missing `ckb:<id>` marker line after heading")
    if (okA && okM) {
      aid = a; sub(/^<a id="/, "", aid); sub(/"><\/a>$/, "", aid)
      mid = substr(m, 6, length(m) - 6)
      if (aid != san(mid)) v("L" H3line[k] ": ### " H3[k] ": anchor id " aid " != sanitized marker " san(mid))
    }
  }
  if (doc == "01-technical-architecture.md") {
    if (nmer < 2) v("needs >=2 mermaid blocks (found " (nmer + 0) ")")
    if (!c4cont) v("needs a C4Container mermaid diagram")
  }
  if (doc == "02-functional-workflows.md") {
    nw = 0
    for (k = 1; k <= n3; k++) if (H3sec[k] == "Workflows") {
      nw++; if (!SEQ[k]) v("L" H3line[k] ": workflow ### " H3[k] " has no sequenceDiagram")
    }
    if (nw == 0 && !na["Workflows"]) v("no ### workflow under ## Workflows")
  }
  if (doc == "03-business-rules.md") {
    nr = 0
    for (k = 1; k <= n3; k++) if (H3sec[k] == "Rule catalog") {
      nr++
      for (j = 1; j <= nf; j++) if (!((k, RF[j]) in FLD)) v("L" H3line[k] ": rule ### " H3[k] ": missing bullet " RF[j])
      if ((k, "id") in FLD) {
        id = FLD[k, "id"]
        if (!slugid(id, "BR") || id ~ /^BR-[0-9]+$/) v("L" H3line[k] ": rule ### " H3[k] ": ID not a slug (BR-<slug>): " id)
        if (id in SEENID) v("L" H3line[k] ": duplicate rule ID " id)
        SEENID[id] = 1
      }
      if (((k, "confidence") in FLD) && FLD[k, "confidence"] !~ /\[(C|I|\?)\]/) v("L" H3line[k] ": rule ### " H3[k] ": Confidence must be [C], [I] or [?]")
    }
    if (nr == 0 && !na["Rule catalog"]) v("no ### rule under ## Rule catalog")
  }
  if (doc == "04-system-context-and-gaps.md") {
    if (nmer < 1) v("needs >=1 mermaid block (found 0)")
    if (!c4ctx) v("needs a C4Context mermaid diagram")
    if (nq + 0 == 0 && !na["Open questions"]) v("## Open questions has no table row with a Q-<slug> id")
  }
  if (doc == "07-decisions.md") {
    nd = 0
    for (k = 1; k <= n3; k++) if (H3sec[k] == "Decision log") {
      nd++
      if (H3[k] !~ /^ADR-[a-z0-9]+(-[a-z0-9]+)*(:|$)/ || H3[k] ~ /^ADR-[0-9]+(:|$)/) v("L" H3line[k] ": ### " H3[k] ": heading must be ADR-<slug>: <title>")
      for (j = 1; j <= na_; j++) if (!((k, AF[j]) in FLD)) v("L" H3line[k] ": ADR ### " H3[k] ": missing bullet " AF[j])
      if (((k, "status") in FLD) && FLD[k, "status"] !~ /^(observed|inferred)/) v("L" H3line[k] ": ADR ### " H3[k] ": Status must be observed or inferred")
    }
    if (nd == 0 && !na["Decision log"]) v("no ### ADR-<slug> under ## Decision log")
  }
}'

for d in $DOCS; do
  f="$kb/$d"
  if [ ! -f "$f" ]; then printf '%s\tmissing\n' "$d" >> "$tmpd/v"; continue; fi
  awk -v doc="$d" -v req="$(headings "$d" | tr '\n' '|' | sed 's/|$//')" -v bud="$(budget "$d")" "$LINT_AWK" "$f" \
    | awk -v d="$d" '{ print d "\t" $0 }' >> "$tmpd/v"
  # value-shaped secrets and run timestamps (line numbers only; never echo the match)
  for pat in 'AKIA[0-9A-Z]{16}' '-----BEGIN [A-Z ]*PRIVATE KEY' 'gh[pousr]_[A-Za-z0-9]{36}' 'xox[baprs]-[A-Za-z0-9-]{10,}' 'sk-[A-Za-z0-9]{32,}' 'AIza[0-9A-Za-z_-]{35}'; do
    grep -nE -e "$pat" "$f" 2>/dev/null | cut -d: -f1 | while IFS= read -r n; do printf '%s\tL%s: possible secret value (never write values)\n' "$d" "$n"; done >> "$tmpd/v"
  done
  grep -nE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}' "$f" 2>/dev/null | cut -d: -f1 \
    | while IFS= read -r n; do printf '%s\tL%s: run timestamp (no dates/timestamps; front-matter carries freshness)\n' "$d" "$n"; done >> "$tmpd/v"
done

keys="$DOCS"
if [ -n "$parity" ]; then
  keys="$keys parity"
  # "<### heading>\t<marker id>" for each ### under a given ## section
  PAIRS_AWK='
  function trim(s){ sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  NR == 1 && $0 == "---" { fm = 1; next }
  fm == 1 { if ($0 == "---") fm = 2; next }
  /^[ ]*(```|~~~)/ { inf = !inf; next }
  inf { next }
  /^## / { h2 = trim(substr($0, 4)); flush(); next }
  /^### / { flush(); if (h2 == sec) { name = trim(substr($0, 5)); want = 1 }; next }
  trim($0) == "" { next }
  want { m = trim($0); if (m ~ /^`ckb:[^`]+`$/) mk = substr(m, 6, length(m) - 6); want = 0 }
  function flush(){ if (name != "") print name "\t" mk; name = ""; mk = ""; want = 0 }
  END { flush() }'
  for spec in "02-functional-workflows.md|Workflows|wf" "03-business-rules.md|Rule catalog|br"; do
    d="${spec%%|*}"; rest="${spec#*|}"; sec="${rest%%|*}"; tag="${rest#*|}"
    if [ -f "$kb/$d" ]; then awk -v sec="$sec" "$PAIRS_AWK" "$kb/$d"; fi \
      | jq -Rn '[inputs | select(length > 0) | split("\t") | {n: .[0], m: (.[1] // "")}]' > "$tmpd/$tag.json"
  done
  for d in $DOCS; do
    [ -f "$kb/$d" ] && { grep -oE '`ckb:[^`]+`' "$kb/$d" 2>/dev/null || true; } | sed 's/^`ckb://; s/`$//' | sort -u | jq -R --arg d "$d" '{d: $d, id: .}'
  done | jq -s . > "$tmpd/refs.json"
  jq -r --slurpfile wf "$tmpd/wf.json" --slurpfile br "$tmpd/br.json" --slurpfile refs "$tmpd/refs.json" '
    def norm: ascii_downcase | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");
    def check($doc; $what; $ents; $heads):
      ($ents | map({key: (.name // "" | norm), value: .id}) | from_entries) as $byname
      | ($heads | map(.n | norm)) as $hn
      | ($ents[] | select((.name // "" | norm) as $x | $hn | index([$x]) | not)
          | "parity\t\($doc): \($what) in ckb.json has no ### heading: \(.name)"),
        ($heads[] | (.n | norm) as $x
          | if ($byname | has($x)) | not then "parity\t\($doc): ### \(.n) has no \($what) in ckb.json"
            elif .m != "" and .m != $byname[$x] then "parity\t\($doc): ### \(.n) marker ckb:\(.m) is not its id \($byname[$x])"
            else empty end);
    ([.entities // {} | .[]? | .[]? | .id? // empty] | map({key: ., value: true}) | from_entries) as $ids
    | check("02-functional-workflows.md"; "workflow"; (.entities.workflows // []); $wf[0]),
      check("03-business-rules.md"; "business_rule"; (.entities.business_rules // []); $br[0]),
      ($refs[0][] | .id as $i | select(($ids | has($i)) | not) | "parity\t\(.d): unresolved ckb:\(.id)")
  ' "$parity" >> "$tmpd/v" || die 2 "parity check failed (jq error above)"
fi

printf '%s\n' $keys | jq -R . | jq -s . > "$tmpd/keys.json"
jq -Rn --slurpfile k "$tmpd/keys.json" '
  [inputs | select(length > 0) | split("\t") | {f: .[0], m: (.[1:] | join("\t"))}] as $v
  | reduce $k[0][] as $f ({}; .[$f] = [$v[] | select(.f == $f) | .m])' < "$tmpd/v"
[ ! -s "$tmpd/v" ]
