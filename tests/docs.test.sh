#!/usr/bin/env bash
# docs.test.sh — human-docs pipeline: lint-docs.sh (every rule + parity), docmeta.sh (front-matter, idempotence, idmap),
# reference.sh (generated tables). Scripts run under the same bash as this file: `/bin/bash tests/docs.test.sh` tests 3.2.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
SH="${BASH:-bash}"; FX="$ROOT/tests/fixtures/docs"; K="$T/kb"; A="$FX/ckb.json"; : > "$T/r"
ok(){ if eval "$2"; then echo P >> "$T/r"; echo "PASS $1"; else echo F >> "$T/r"; echo "FAIL $1"; sed 's/^/  | /' "$T/lint.json" 2>/dev/null | head -30; fi; }
lint(){ "$SH" "$ROOT/scripts/lint-docs.sh" "$@"; }
dm(){ "$SH" "$ROOT/scripts/docmeta.sh" "$@"; }
ref(){ "$SH" "$ROOT/scripts/reference.sh" "$@"; }
fresh(){ rm -rf "$K"; cp -R "$FX/good" "$K"; : > "$T/lint.json"; }
# portable in-place edits (no sed -i)
sedit(){ f="$K/$1"; shift; sed "$@" "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }
aedit(){ f="$K/$1"; shift; awk "$@" "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }
add(){ printf '%s\n' "$2" >> "$K/$1"; }
# has <doc-key> <substring>: lint exits 1 and that key lists a violation containing the substring
has(){ lint "$K" ${P:+--parity "$P"} > "$T/lint.json"; rc=$?; [ $rc -eq 1 ] && jq -e --arg k "$1" --arg s "$2" '.[$k] // [] | any(contains($s))' "$T/lint.json" >/dev/null; }
clean(){ lint "$K" ${P:+--parity "$P"} > "$T/lint.json"; }
P=""

# ---------- lint: baseline + spec ----------
fresh
ok "good KB lints clean (exit 0)"                  'clean'
ok "output keys = the 8 docs, all empty"           '[ "$(jq -c "[keys[], (map(length) | add)]" "$T/lint.json")" = "[\"00-overview.md\",\"01-technical-architecture.md\",\"02-functional-workflows.md\",\"03-business-rules.md\",\"04-system-context-and-gaps.md\",\"05-operations.md\",\"06-security-and-data.md\",\"07-decisions.md\",0]" ]'
P="$A"; ok "good KB passes --parity, parity key present" 'clean && jq -e ".parity == []" "$T/lint.json" >/dev/null'; P=""
lint --spec > "$T/spec.json"
ok "--spec lists 8 docs"                           '[ "$(jq "keys | length" "$T/spec.json")" = 8 ]'
ok "every spec heading is documented in SKILL.md"  'jq -r ".[][]" "$T/spec.json" | while IFS= read -r h; do grep -qF "\`## $h\`" "$ROOT/skills/kb-docs/SKILL.md" || { echo "  undocumented: $h"; exit 1; }; done'
ok "SKILL.md frontmatter name: kb-docs"            'sed -n 2p "$ROOT/skills/kb-docs/SKILL.md" | grep -qx "name: kb-docs"'
ok "old skills/kb removed"                         '[ ! -e "$ROOT/skills/kb" ]'

# ---------- lint: presence, headings, sections ----------
fresh; rm "$K/05-operations.md"
ok "missing doc reported as [\"missing\"]"         'has 05-operations.md missing && [ "$(jq -c ".[\"05-operations.md\"]" "$T/lint.json")" = "[\"missing\"]" ]'
fresh; aedit 01-technical-architecture.md '$0 != "## Data model"'
ok "missing required heading"                      'has 01-technical-architecture.md "missing required heading: ## Data model"'
fresh; aedit 07-decisions.md 'NR==1{print;next} /^## Existing ADRs/{e=1} e{E=E $0 "\n";next} {R=R $0 "\n"} END{printf "%s%s", E, R}'
ok "required heading out of order"                 'has 07-decisions.md "heading out of order: ## Existing ADRs"'
fresh; add 00-overview.md "## Glossary"; add 00-overview.md "Extra. [?]"
ok "duplicate ## heading"                          'has 00-overview.md "duplicate heading: ## Glossary"'
fresh; aedit 05-operations.md '{print} /^## Rollback/{exit}'
ok "empty required section"                        'has 05-operations.md "empty section: ## Rollback"'
fresh; aedit 01-technical-architecture.md 'p{print "Not applicable — single container, no orchestration [?]"; p=0; next} {print} /^## Deployment$/{p=1}'
ok "Not applicable — <reason> [?] satisfies a section" 'clean'
fresh; aedit 01-technical-architecture.md 'p{print "Not applicable — single container"; p=0; next} {print} /^## Deployment$/{p=1}'
ok "Not applicable without [?] flagged"            'has 01-technical-architecture.md "Not applicable line without [?]"'

# ---------- lint: diagrams + code blocks ----------
fresh; aedit 01-technical-architecture.md '/^```mermaid/{n++; if (n>1) {print "```text"; next}} {print}'
ok "01 needs >=2 mermaid blocks"                   'has 01-technical-architecture.md "needs >=2 mermaid blocks (found 1)"'
fresh; sedit 01-technical-architecture.md 's/^C4Container$/flowchart TB/'
ok "01 needs a C4Container diagram"                'has 01-technical-architecture.md "needs a C4Container"'
fresh; aedit 02-functional-workflows.md '/^```mermaid/{n++; if (n==2) {print "```text"; next}} {print}'
ok "02 every workflow needs a sequenceDiagram"     'has 02-functional-workflows.md "workflow ### Refund order has no sequenceDiagram"'
fresh; aedit 02-functional-workflows.md '/^## State machines/{s=0} s{next} {print} /^## Workflows/{s=1}'
ok "02 needs >=1 workflow under ## Workflows"      'has 02-functional-workflows.md "no ### workflow under ## Workflows"'
fresh; sedit 04-system-context-and-gaps.md 's/^```mermaid$/```text/'
ok "04 needs >=1 mermaid block"                    'has 04-system-context-and-gaps.md "needs >=1 mermaid block"'
ok "04 needs a C4Context diagram"                  'jq -e ".[\"04-system-context-and-gaps.md\"] | any(contains(\"C4Context\"))" "$T/lint.json" >/dev/null'
fresh; { echo '```sh'; seq 1 16; echo '```'; } >> "$K/05-operations.md"
ok "code block >15 lines flagged"                  'has 05-operations.md "code block of 16 lines (max 15)"'
fresh; { echo '```sh'; seq 1 15; echo '```'; } >> "$K/05-operations.md"
ok "code block of exactly 15 lines allowed"        'clean'
fresh; { echo '```mermaid'; echo 'flowchart LR'; seq 1 40 | sed 's/^/  n/'; echo '```'; } >> "$K/04-system-context-and-gaps.md"
ok "mermaid >40 lines flagged"                     'has 04-system-context-and-gaps.md "mermaid block of 41 lines (max 40)"'
fresh; echo '```' >> "$K/06-security-and-data.md"
ok "unterminated code fence flagged"               'has 06-security-and-data.md "unterminated code fence"'

# ---------- lint: budgets ----------
fresh; aedit 00-overview.md 'NR<=12'
ok "word budget: below minimum"                    'has 00-overview.md "below budget 300"'
fresh; { echo "## Appendix"; awk 'BEGIN{for(i=0;i<120;i++) print "lorem ipsum dolor sit amet consectetur adipiscing elit sed do"}'; } >> "$K/00-overview.md"
ok "word budget: above maximum"                    'has 00-overview.md "above budget 1000"'
fresh; { echo '```text'; awk 'BEGIN{for(i=0;i<10;i++){for(j=0;j<150;j++) printf "w "; print ""}}'; echo '```'; } >> "$K/00-overview.md"
ok "words inside code fences are not counted"      'clean'

# ---------- lint: citations, tags, forbidden refs, secrets ----------
fresh; add 02-functional-workflows.md "Handler at src/api/routes.ts:12 is the entry."
ok "citation without confidence tag"               'has 02-functional-workflows.md "citation without [C]/[I]/[?] tag"'
fresh; printf '%s\n' '```text' 'src/api/routes.ts:12' '```' >> "$K/02-functional-workflows.md"
ok "citations inside code fences exempt"           'clean'
fresh; add 04-system-context-and-gaps.md "Regenerate from ckb.draft.json when needed. [?]"
ok "ckb.draft mention flagged"                     'has 04-system-context-and-gaps.md "mentions ckb.draft"'
fresh; add 04-system-context-and-gaps.md "- Index lives at ckb/README.md:3 [C]"
ok "citing ckb/ flagged"                           'has 04-system-context-and-gaps.md "cites ckb/"'
fresh; add 04-system-context-and-gaps.md "- Copy at ./ckb/00-overview.md:1 [C]"
ok "citing ./ckb/ flagged"                         'has 04-system-context-and-gaps.md "cites ckb/"'
fresh; add 04-system-context-and-gaps.md "- Vendored at docs/ckb/notes.md:3 [C]"
ok "nested docs/ckb/ path is not the KB (allowed)" 'clean'
fresh; add 06-security-and-data.md "- Hardcoded key AKIAABCDEFGHIJKLMNOP in config [C]"
ok "secret-shaped value flagged"                   'has 06-security-and-data.md "possible secret value"'
ok "violation never echoes the secret value"       '! grep -q AKIAABCDEFGHIJKLMNOP "$T/lint.json"'
fresh; add 06-security-and-data.md "-----BEGIN RSA PRIVATE KEY-----"
ok "private key block flagged"                     'has 06-security-and-data.md "possible secret value"'
fresh; add 05-operations.md "Generated 2026-09-30T10:00:00Z by the run. [?]"
ok "run timestamp flagged"                         'has 05-operations.md "run timestamp"'

# ---------- lint: 03 rules ----------
fresh; aedit 03-business-rules.md '/\*\*Rationale:\*\*/ && !d {d=1; next} {print}'
ok "03 rule missing a bullet"                      'has 03-business-rules.md "rule ### Refunds require admin: missing bullet rationale"'
fresh; sedit 03-business-rules.md 's/BR-order-total-positive/BR-1/'
ok "03 sequential rule ID rejected"                'has 03-business-rules.md "ID not a slug (BR-<slug>): BR-1"'
fresh; sedit 03-business-rules.md 's/BR-order-total-positive/BR_Order/'
ok "03 non-slug rule ID rejected"                  'has 03-business-rules.md "ID not a slug (BR-<slug>): BR_Order"'
fresh; sedit 03-business-rules.md 's/BR-refunds-require-admin/BR-order-total-positive/'
ok "03 duplicate rule ID"                          'has 03-business-rules.md "duplicate rule ID BR-order-total-positive"'
fresh; sedit 03-business-rules.md 's/^- \*\*Confidence:\*\* \[C\]$/- **Confidence:** high/'
ok "03 Confidence must be a tag"                   'has 03-business-rules.md "Confidence must be [C], [I] or [?]"'
fresh; aedit 03-business-rules.md '/^## Traceability/{s=0} s{next} {print} /^## Rule catalog/{s=1; print "Intro only. [?]"}'
ok "03 needs >=1 rule under ## Rule catalog"       'has 03-business-rules.md "no ### rule under ## Rule catalog"'
fresh; aedit 03-business-rules.md '$0 != "## Traceability"'
ok "03 ## Traceability required"                   'has 03-business-rules.md "missing required heading: ## Traceability"'

# ---------- lint: anchors + markers ----------
fresh; aedit 02-functional-workflows.md '$0 != "<a id=\"workflow-place-order\"></a>"'
ok "missing anchor before workflow heading"        'has 02-functional-workflows.md "### Place order: missing <a id"'
fresh; aedit 02-functional-workflows.md '$0 != "`ckb:workflow:place-order`"'
ok "missing ckb marker after workflow heading"     'has 02-functional-workflows.md "### Place order: missing \`ckb:<id>\` marker"'
fresh; sedit 01-technical-architecture.md 's/id="component-src-api"/id="component-api"/'
ok "anchor must equal sanitized marker"            'has 01-technical-architecture.md "anchor id component-api != sanitized marker component-src-api"'
fresh; sedit 03-business-rules.md 's/^<a id="business-rule-order-total-positive"><\/a>$//'
ok "03 rule anchor required"                       'has 03-business-rules.md "### Order total must be positive: missing <a id"'

# ---------- lint: 04 open questions, 07 ADRs ----------
fresh; sedit 04-system-context-and-gaps.md 's/Q-who-issues-admin-role/Q-1/'
ok "04 sequential question id rejected"            'has 04-system-context-and-gaps.md "open-question id not a slug (Q-<slug>): Q-1"'
fresh; aedit 04-system-context-and-gaps.md '!/^\| Q-/'
ok "04 open questions need Q-<slug> rows"          'has 04-system-context-and-gaps.md "no table row with a Q-<slug> id"'
fresh; sedit 07-decisions.md 's/^### ADR-events-without-outbox:/### ADR-003:/'
ok "07 ADR heading must be ADR-<slug>"             'has 07-decisions.md "### ADR-003: Publish events directly after insert: heading must be ADR-<slug>"'
fresh; sedit 07-decisions.md 's/^- \*\*Status:\*\* inferred$/- **Status:** accepted/'
ok "07 ADR status observed|inferred"               'has 07-decisions.md "Status must be observed or inferred"'
fresh; aedit 07-decisions.md '!/\*\*Evidence:\*\*/'
ok "07 ADR missing Evidence bullet"                'has 07-decisions.md "missing bullet evidence"'

# ---------- lint: usage ----------
lint >/dev/null 2>&1;                    ok "usage: no args -> exit 2"           '[ $? -eq 2 ]'
lint "$T/nope" >/dev/null 2>&1;          ok "usage: missing kb dir -> exit 2"    '[ $? -eq 2 ]'
echo nope > "$T/bad.json"; fresh
lint "$K" --parity "$T/bad.json" >/dev/null 2>&1; ok "usage: non-JSON parity artifact -> exit 2" '[ $? -eq 2 ]'
lint "$K" --bogus >/dev/null 2>&1;       ok "usage: unknown option -> exit 2"   '[ $? -eq 2 ]'

# ---------- lint: parity ----------
P="$A"
fresh; sedit 03-business-rules.md 's/^### Refunds require admin$/### Refunds need admin/'
ok "parity: ckb rule without ### heading"          'has parity "business_rule in ckb.json has no ### heading: Refunds require admin"'
ok "parity: ### rule without ckb entity"           'has parity "### Refunds need admin has no business_rule in ckb.json"'
fresh; sedit 03-business-rules.md 's/^### Refunds require admin$/### refunds REQUIRE   admin/'
ok "parity: names match case/space-insensitively"  'clean'
fresh; sedit 02-functional-workflows.md 's/^### Refund order$/### Refund an order/'
ok "parity: workflow heading mismatch"             'has parity "workflow in ckb.json has no ### heading: Refund order"'
jq '.entities.workflows += [{"id":"workflow:cancel-order","name":"Cancel order","steps":[{"order":1,"description":"x"}],"confidence":"unknown","provenance":[]}]' "$A" > "$T/a2.json"
fresh; P="$T/a2.json"
ok "parity: extra ckb workflow reported"           'has parity "workflow in ckb.json has no ### heading: Cancel order"'
P="$A"
fresh; sedit 01-technical-architecture.md 's#^`ckb:component:src/worker`$#`ckb:component:src/wrk`#'
ok "parity: unresolved ckb marker"                 'has parity "01-technical-architecture.md: unresolved ckb:component:src/wrk"'
fresh; sedit 03-business-rules.md 's/^`ckb:business_rule:order-total-positive`$/`ckb:business_rule:refunds-require-admin`/'
ok "parity: marker must be the named entity's id"  'has parity "### Order total must be positive marker ckb:business_rule:refunds-require-admin is not its id business_rule:order-total-positive"'
P=""

# ---------- docmeta ----------
fresh; dm "$K" "$A" > "$T/dm.out"; rc=$?
D3="$K/03-business-rules.md"
ok "docmeta exit 0, all 8 updated"                 '[ $rc -eq 0 ] && grep -qx "DOCMETA updated=8 missing=0 ids_rewritten=0" "$T/dm.out"'
ok "front-matter starts the doc"                   '[ "$(head -1 "$D3")" = "---" ] && grep -qx "ckb_doc: \"business-rules\"" "$D3"'
ok "front-matter fields present"                   'for k in ckb_doc title audience diataxis source_commit branch generator ckb_version confidence freshness_cmd; do grep -q "^$k:" "$D3" || exit 1; done'
ok "front-matter values from ckb.json"             'grep -qx "source_commit: \"0123456789abcdef0123456789abcdef01234567\"" "$D3" && grep -qx "branch: \"main\"" "$D3" && grep -qx "generator: \"codebase-kb-engine 0.8.0\"" "$D3" && grep -qx "ckb_version: \"0.2\"" "$D3"'
ok "freshness_cmd exact"                           'grep -qxF "freshness_cmd: \"git diff --quiet 0123456789abcdef0123456789abcdef01234567 HEAD -- . '"':(exclude)ckb'"'\"" "$D3"'
ok "no generated_at / timestamps"                  '! grep -rqE "generated_at|[0-9]{4}-[0-9]{2}-[0-9]{2}T" "$K"'
ok "per-doc confidence counts (03: 1/1/0)"         '[ "$(sed -n "/^confidence:/,/^  unknown/p" "$D3" | tr -d " \n")" = "confidence:confirmed:1inferred:1unknown:0" ]'
ok "body preserved byte-for-byte"                  'for f in "$FX"/good/*.md; do awk "NR==1&&\$0==\"---\"{fm=1;next} fm==1{if(\$0==\"---\")fm=2;next} {print}" "$K/$(basename "$f")" | cmp -s - "$f" || exit 1; done'
ok "lint passes after docmeta (front-matter skipped)" 'P="$A" clean'
shasum "$K"/*.md > "$T/s1"; dm "$K" "$A" >/dev/null
ok "docmeta idempotent (second run no-op)"         'shasum "$K"/*.md | cmp -s - "$T/s1"'
jq '.repo.branch = "release/1.x"' "$A" > "$T/a3.json"; dm "$K" "$T/a3.json" >/dev/null
ok "re-run replaces front-matter (single block)"   'grep -qx "branch: \"release/1.x\"" "$D3" && [ "$(grep -c "^ckb_doc:" "$D3")" = 1 ] && [ "$(grep -c "^---$" "$D3")" = 2 ]'
# idmap: model wrote local ids; finalize maps them to final ids
fresh
sedit 03-business-rules.md 's/^`ckb:business_rule:order-total-positive`$/`ckb:r1`/; s/^<a id="business-rule-order-total-positive"><\/a>$/<a id="r1"><\/a>/'
sedit 02-functional-workflows.md 's/^`ckb:workflow:place-order`$/`ckb:wf place`/; s/^<a id="workflow-place-order"><\/a>$/<a id="wf-place"><\/a>/'
printf '%s\n' '{"r1":"business_rule:order-total-positive","wf place":"workflow:place-order","unused":"component:x"}' > "$T/idmap.json"
ok "before idmap: local ids unresolved"            'P="$A" has parity "unresolved ckb:r1"'
dm "$K" "$A" --idmap "$T/idmap.json" > "$T/dm.out"
ok "idmap rewrites markers (count reported)"       'grep -q "ids_rewritten=2" "$T/dm.out" && grep -qx "\`ckb:business_rule:order-total-positive\`" "$D3" && ! grep -q "ckb:r1" "$D3"'
ok "idmap regenerates anchors from final ids"      'grep -qx "<a id=\"business-rule-order-total-positive\"></a>" "$D3" && grep -qx "<a id=\"workflow-place-order\"></a>" "$K/02-functional-workflows.md"'
ok "after idmap: lint --parity clean"              'P="$A" clean'
fresh; sedit 01-technical-architecture.md 's/id="component-src-api"/id="stale"/'; dm "$K" "$A" >/dev/null
ok "stale anchor regenerated from marker"          'grep -qx "<a id=\"component-src-api\"></a>" "$K/01-technical-architecture.md"'
fresh; rm "$K/07-decisions.md"; dm "$K" "$A" > "$T/dm.out" 2>/dev/null; rc=$?
ok "missing doc -> exit 1, others still processed" '[ $rc -eq 1 ] && grep -q "missing=1" "$T/dm.out" && [ "$(head -1 "$K/06-security-and-data.md")" = "---" ]'
dm >/dev/null 2>&1;                       ok "docmeta usage: no args -> exit 2"      '[ $? -eq 2 ]'
fresh; dm "$K" "$T/bad.json" >/dev/null 2>&1; ok "docmeta: invalid artifact -> exit 2" '[ $? -eq 2 ]'
dm "$K" "$A" --idmap "$T/bad.json" >/dev/null 2>&1; ok "docmeta: invalid idmap -> exit 2" '[ $? -eq 2 ]'

# ---------- reference ----------
ref "$A" > "$T/ref.md"; rc=$?
ok "reference exit 0"                              '[ $rc -eq 0 ]'
ok "reference front-matter ckb_doc: reference"     '[ "$(head -1 "$T/ref.md")" = "---" ] && grep -qx "ckb_doc: \"reference\"" "$T/ref.md" && grep -qx "confidence_scope: \"global\"" "$T/ref.md" && grep -qx "  confirmed: 14" "$T/ref.md"'
ok "reference sections in order"                   '[ "$(grep "^## " "$T/ref.md" | tr "\n" "|")" = "## Interfaces|## Dependencies|## Artifacts|## Services|## Datastores|## Config keys|## External services|## API specs|## Relations|" ]'
ok "dependency row has all fields"                 'grep -qxF "| \`pkg:npm/express\` | package.json | runtime | ^4.19.0 | 4.19.2 | registry | [C] | package.json:9 |" "$T/ref.md"'
ok "config keys: names + is_secret only"           'grep -qxF "| \`STRIPE_KEY\` | env | true | [C] | src/api/pay.ts:3 |" "$T/ref.md"'
ok "interfaces: http detail + provenance count"    'grep -qF "| POST /v1/charges @api.stripe.com |" "$T/ref.md" && grep -qF "src/api/pay.ts:8 (+1) |" "$T/ref.md"'
ok "table cells escape |"                          'grep -qF "stripe \\| charge" "$T/ref.md"'
ok "services/artifacts/datastores/external/api_specs rows" 'grep -qF "| \`shop-api\` | k8s | 8080 | staging, prod |" "$T/ref.md" && grep -qF "| \`pkg:docker/acme/shop-api\` | container_image |" "$T/ref.md" && grep -qF "| \`datastore:postgres:DATABASE_URL:public.orders\` | postgres | DATABASE_URL | public | orders | readwrite |" "$T/ref.md" && grep -qF "| \`api.stripe.com\` | Stripe | payments |" "$T/ref.md" && grep -qF "| \`openapi.yaml\` | openapi | 3.0.3 |" "$T/ref.md"'
ok "relations sorted by from,kind,to"              '[ "$(sed -n "/^## Relations/,\$p" "$T/ref.md" | grep "^| \`" | cut -d"|" -f3 | tr -d " " | tr "\n" ,)" = "deploys_as,enforces,provides," ]'
ok "reference has no timestamps"                   '! grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}T" "$T/ref.md"'
jq '.entities |= map_values(reverse) | .relations |= reverse' "$A" > "$T/rev.json"
ok "reference deterministic under input reordering" 'ref "$T/rev.json" | cmp -s - "$T/ref.md"'
printf '%s\n' '{"ckb_version":"0.2","repo":{"commit_sha":"abc"}}' > "$T/min.json"
ref "$T/min.json" > "$T/ref2.md"; rc=$?
ok "reference works with all collections absent"   '[ $rc -eq 0 ] && [ "$(grep -c "^_None recorded._$" "$T/ref2.md")" = 9 ]'
ok "reference: invalid artifact -> exit 2"         'ref "$T/bad.json" >/dev/null 2>&1; [ $? -eq 2 ]'
ok "reference: no args -> exit 2"                  'ref >/dev/null 2>&1; [ $? -eq 2 ]'

pass=$(grep -c P "$T/r"); fail=$(grep -c F "$T/r"); echo "---"; echo "docs tests: $pass passed, $fail failed"; [ "$fail" -eq 0 ]
