#!/usr/bin/env bash
# finalize.sh — build ckb.json + manifest.json from the model-written draft, then validate.
# Usage: finalize.sh <repo_root> <kb_dir> [--mode local|url] [--url URL] [--branch BRANCH] [--started-at ISO] [--audit S/T]
# Reads <kb_dir>/ckb.draft.json; writes <kb_dir>/ckb.json and <kb_dir>/manifest.json; removes the draft on success.
# Exit: 0 complete · 1 invalid/incomplete/unverified (draft kept; a previous valid ckb.json is never overwritten by an invalid one) · 2 usage/precondition.
# Status: complete only when BOTH schema (uvx) and semantic checks pass; schema skipped => unverified.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
DOCS="00-overview.md 01-technical-architecture.md 02-functional-workflows.md 03-business-rules.md 04-system-context-and-gaps.md 05-operations.md 06-security-and-data.md 07-decisions.md"
die(){ code="$1"; shift; printf '%s\n' "$@" >&2; exit "$code"; }
repo="${1:-}"; kb="${2:-}"; shift 2 2>/dev/null || die 2 "usage: finalize.sh <repo_root> <kb_dir> [opts]"
mode=local; url=""; branch=""; started=""; audit=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) mode="$2"; shift ;; --url) url="$2"; shift ;; --branch) branch="$2"; shift ;; --started-at) started="$2"; shift ;;
    --audit) audit="$2"; shift ;;   # "<supported>/<total>" from the claim audit
    *) die 2 "unknown option: $1" ;;
  esac; shift
done
[ -d "$repo" ] || die 2 "repo_root not a dir: $repo"
prev_manifest="$(mktemp)"; [ -f "$kb/manifest.json" ] && jq -e '.feedback' "$kb/manifest.json" >/dev/null 2>&1 && cp "$kb/manifest.json" "$prev_manifest" || echo '{}' > "$prev_manifest"
[ -f "$kb/.ckb-output" ] || die 2 "REFUSED: '$kb' is not a CKB output dir (no .ckb-output marker; run resolve-kb.sh first)"
draft="$kb/ckb.draft.json"
# large repos: scouts write one fragment per area/collection into ckb.draft.d/. When fragments exist they are the ONLY
# source (a stale merged ckb.draft.json from a failed run must never override corrected fragments).
if [ -d "$kb/ckb.draft.d" ] && ls "$kb"/ckb.draft.d/*.json >/dev/null 2>&1; then
  for f in "$kb"/ckb.draft.d/*.json; do jq -e . "$f" >/dev/null 2>&1 || die 1 "draft fragment is not valid JSON: $f"; done
  cat "$kb"/ckb.draft.d/*.json | jq -s '
    reduce .[] as $x ({entities: {}, relations: [], repo_profile: {}};
      .entities = (reduce (($x.entities // {}) | to_entries[]) as $kv (.entities; .[$kv.key] = ((.[$kv.key] // []) + ($kv.value // []))))
      | .relations += ($x.relations // [])
      | .repo_profile = (.repo_profile + ($x.repo_profile // {})))' > "$kb/ckb.draft.json.merged" \
    && mv -f "$kb/ckb.draft.json.merged" "$draft"
fi
[ -f "$draft" ] || die 2 "missing draft: $draft (or $kb/ckb.draft.d/*.json)"
jq -e . "$draft" >/dev/null 2>&1 || die 1 "draft is not valid JSON: $draft"

git -C "$repo" rev-parse HEAD >/dev/null 2>&1 || die 2 "REFUSED: '$repo' is not a git work tree with a commit; CKB requires commit_sha."
sha="$(git -C "$repo" rev-parse HEAD)"
# branch: symbolic ref, else CI-provided ref, else a name for the detached commit, else HEAD (warned)
[ -n "$branch" ] || branch="$(git -C "$repo" symbolic-ref --short -q HEAD || true)"
[ -n "$branch" ] || branch="${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-${CI_COMMIT_REF_NAME:-}}}"
[ -n "$branch" ] || branch="$(git -C "$repo" describe --tags --exact-match HEAD 2>/dev/null || git -C "$repo" name-rev --name-only --no-undefined HEAD 2>/dev/null | sed -E 's#^remotes/[^/]+/##; s#[~^].*$##' || true)"
extra_warn=""; [ -n "$branch" ] || { branch=HEAD; extra_warn="detached HEAD: repo.branch recorded as HEAD"; }
if [ -z "$url" ]; then url="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"; fi
[ -n "$url" ] || url="file://$(cd "$repo" && pwd -P)"
url="$(printf '%s' "$url" | sed -E 's#^([a-zA-Z][a-zA-Z0-9+.-]*://)[^/@]*@#\1#')"   # never persist userinfo/tokens
# canonical repo identity (CKB v0.2): https://<lowercase-host>/<path>, no .git, no port, no trailing slash; ssh/scp forms -> https
case "$url" in
  file://*) : ;;
  *) url="$(printf '%s' "$url" | sed -E 's#^[A-Za-z0-9._-]+@([^:/]+):#https://\1/#; s#^(ssh|git|git\+ssh|https?)://#https://#; s#^https://([^/@]*@)#https://#; s#^https://([^/:]+):[0-9]+/#https://\1/#; s#\.git/?$##; s#/+$##')"
     host="$(printf '%s' "$url" | sed -E 's#^https://([^/]+).*#\1#' | tr 'A-Z' 'a-z')"; url="https://$host/${url#https://*/}" ;;
esac
dirty=false; [ -n "$(git -C "$repo" status --porcelain -- . ':(exclude)ckb' ':(exclude,glob)**/.DS_Store' ':(exclude,glob)**/Thumbs.db' ':(exclude,glob)**/desktop.ini' 2>/dev/null | head -1)" ] && dirty=true   # the KB itself never counts
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
gen_ver="$(jq -r .version "$ROOT/.claude-plugin/plugin.json")"
repo_obj="$(jq -nc --arg u "$url" --arg b "$branch" --arg s "$sha" --arg t "$now" '{url:$u, branch:$b, commit_sha:$s, generated_at:$t}')"
gen_obj="$(jq -nc --arg v "$gen_ver" '{name:"codebase-kb-engine", version:$v}')"

# Secret redaction (the KB is committed): any secret-looking VALUE from the repo's env/key/config files that appears
# verbatim in the KB is replaced with [REDACTED] in every KB file. Values are never printed.
redacted=0
redact_values(){ git -C "$repo" ls-files -co --exclude-standard | grep -E '(^|/)\.env[^/]*$|(^|/)[^/]*(secret|credential|newrelic)[^/]*$|\.(pem|key|p12|pfx)$|(^|/)(application|config|settings)[^/]*\.(properties|ya?ml|json|ini|toml)$' \
  | while IFS= read -r f; do [ -f "$repo/$f" ] || continue
      grep -hoE '(pass(word)?|secret|token|key|credential|auth|private|license|dsn|conn)[A-Za-z0-9_.-]*[[:space:]]*[:=][[:space:]]*["'"'"']?[^"'"'"'[:space:],#}]{12,}' "$repo/$f" 2>/dev/null \
        | sed -E "s/^[^:=]*[:=][[:space:]]*[\"']?//"
      case "$f" in *.env*|*.pem|*.key|*.p12|*.pfx) grep -hoE '=[[:space:]]*["'"'"']?[^"'"'"'[:space:]#]{12,}' "$repo/$f" 2>/dev/null | sed -E "s/^=[[:space:]]*[\"']?//" ;; esac
      grep -hoE "['\"][A-Za-z0-9+/_=-]{24,}['\"]" "$repo/$f" 2>/dev/null | tr -d "'\""
    done | sort -u | grep -vE '^(true|false|null|https?://[^/]*/?|[a-z]+(\.[a-z]+)+)$'; }
# Citation verification input: line counts for every cited file that really exists in the repo (tracked or
# untracked-but-not-ignored), outside ckb/. normalize.jq downgrades any claim whose citations don't resolve.
rroot="$(cd "$repo" && pwd -P)"; aroot="$(cd "$repo" && pwd)"
roots="$(jq -nc --arg a "$rroot" --arg b "$aroot" --arg c "${repo%/}" '[$a, $b, $c] | unique')"
tmpd="$(mktemp -d)"; trap 'rm -rf "$tmpd"' EXIT
git -C "$repo" ls-files -co --exclude-standard > "$tmpd/files" 2>/dev/null
jq -r --argjson roots "$roots" '[.. | objects | select(has("path") and has("line")) | .path | strings] | unique | .[]
  | . as $p | ([$roots[] | select($p | startswith(. + "/"))] | first) as $r | (if $r then $p[($r|length)+1:] else $p end) | sub("^(\\./)+"; "")' "$draft" \
  | grep -v -e '^/' -e '\.\.' -e '^ckb$' -e '^ckb/' | sort -u > "$tmpd/cited"
grep -Fxf "$tmpd/files" "$tmpd/cited" | while IFS= read -r f; do [ -f "$repo/$f" ] && printf '%s\t%s\n' "$f" "$(wc -l < "$repo/$f" | tr -d ' ')"; done \
  | jq -Rn '[inputs | split("\t") | {key: .[0], value: (.[1] | tonumber)}] | from_entries' > "$tmpd/lines.json"

out="$(jq -c --argjson repo "$repo_obj" --argjson generator "$gen_obj" --argjson roots "$roots" --argjson lines "$(cat "$tmpd/lines.json")" \
        -L "$ROOT/spec/v0.2" -f "$ROOT/scripts/normalize.jq" "$draft")" \
  || die 1 "normalize failed on draft (jq error above)"
[ -n "$extra_warn" ] && out="$(printf '%s' "$out" | jq -c --arg w "$extra_warn" '.warnings += [$w]')"
# Write the candidate first; it replaces ckb.json only if it passes validation.
printf '%s' "$out" | jq '.artifact' > "$kb/ckb.json.candidate"
# local -> final id map for the docs; also accept markers written as <type>:<local-id> (e.g. ckb:workflow:core.wf.x)
printf '%s' "$out" | jq '(.idmap // {}) | to_entries | map(., {key: ((.value | split(":")[0]) + ":" + .key), value}) | from_entries' > "$tmpd/idmap.json"

# Coverage: deterministic inventory of the repo vs. what the draft cites (completeness gate) + repo_profile languages
cov_uncited_manifests=""
if [ -x "$ROOT/scripts/inventory.sh" ] && [ -x "$ROOT/scripts/coverage.sh" ] && "$ROOT/scripts/inventory.sh" "$repo" > "$tmpd/inventory.json" 2>"$tmpd/inv.err"; then
  "$ROOT/scripts/coverage.sh" "$tmpd/inventory.json" "$kb/ckb.json.candidate" > "$tmpd/coverage.json" 2>>"$tmpd/inv.err" || : > "$tmpd/coverage.json"
  if jq -e 'type == "object"' "$tmpd/coverage.json" >/dev/null 2>&1; then
    jq --slurpfile cov "$tmpd/coverage.json" --slurpfile inv "$tmpd/inventory.json" '
      .coverage = $cov[0]
      | if (.repo_profile.languages // []) == [] and (($inv[0].languages // []) | length) > 0
        then .repo_profile = ({languages: [], frameworks: [], build_tools: [], owners: []} + (.repo_profile // {}) + {languages: [$inv[0].languages[] | {name, files}]})
        else . end' "$kb/ckb.json.candidate" > "$tmpd/cand" && mv -f "$tmpd/cand" "$kb/ckb.json.candidate"
    cov_uncited_manifests="$(jq -r '.buckets.manifests.uncited // [] | .[]' "$tmpd/coverage.json")"
  fi
fi

vout="$("$ROOT/scripts/validate.sh" "$kb/ckb.json.candidate")"; vrc=$?
last="$(printf '%s\n' "$vout" | tail -1)"
structural="$(printf '%s' "$last" | sed -E 's/.*STRUCTURAL=([a-z]+).*/\1/')"
semantic="$(printf '%s' "$last" | sed -E 's/.*SEMANTIC=([a-z]+).*/\1/')"
status=complete; [ $vrc -eq 0 ] || status=invalid
[ "$status" = complete ] && [ "$structural" != pass ] && status=unverified   # never "complete" without the schema check
if [ "$status" = invalid ]; then mv -f "$kb/ckb.json.candidate" "$kb/ckb.json.rejected"; else mv -f "$kb/ckb.json.candidate" "$kb/ckb.json"; rm -f "$kb/ckb.json.rejected"; fi
art="$kb/ckb.json"; [ "$status" = invalid ] && art="$kb/ckb.json.rejected"

# Docs pipeline (only when an artifact was accepted): front-matter + local->final id rewrite, generated reference, lint + parity
docs_lint='{}'; docmeta_out=""
if [ "$status" != invalid ]; then
  docmeta_out="$("$ROOT/scripts/docmeta.sh" "$kb" "$kb/ckb.json" --idmap "$tmpd/idmap.json" 2>&1)" || true
  rm -f "$kb/90-reference.md"   # legacy name (<= 0.9.3); the generated reference is now 09-reference.md
  "$ROOT/scripts/reference.sh" "$kb/ckb.json" > "$kb/09-reference.md.tmp" 2>/dev/null && mv -f "$kb/09-reference.md.tmp" "$kb/09-reference.md" || rm -f "$kb/09-reference.md.tmp"
fi

# Secret redaction (the KB is committed): any secret-looking VALUE from repo config found verbatim in the KB -> [REDACTED]
redact_values > "$tmpd/secrets"
while IFS= read -r v; do
  [ "${#v}" -ge 12 ] || continue
  for f in "$kb"/*.md "$kb"/ckb.json; do
    [ -f "$f" ] && grep -qF -- "$v" "$f" && { V="$v" perl -0pi -e 's/\Q$ENV{V}\E/[REDACTED]/g' "$f"; redacted=$((redacted+1)); }
  done
done < "$tmpd/secrets"

if [ "$status" != invalid ]; then
  docs_lint="$("$ROOT/scripts/lint-docs.sh" "$kb" --parity "$kb/ckb.json" 2>/dev/null)"; lrc=$?
  printf '%s' "$docs_lint" | jq -e . >/dev/null 2>&1 || docs_lint='{"lint":["lint-docs produced no JSON"]}'
  [ $lrc -ne 0 ] && [ "$status" != invalid ] && status=incomplete
fi
[ -n "$cov_uncited_manifests" ] && [ "$status" != invalid ] && status=incomplete   # dependency map must be complete

outputs="$(cd "$kb" && for f in $DOCS 09-reference.md ckb.json; do
  if [ -f "$f" ]; then printf '%s\t%s\t%s\n' "$f" "$(shasum -a 256 "$f" | cut -d' ' -f1)" "$(wc -c < "$f" | tr -d ' ')"; else printf '%s\tMISSING\t0\n' "$f"; fi; done)"
missing="$(printf '%s\n' "$outputs" | awk -F'\t' '$2=="MISSING"{print $1}')"
[ -n "$missing" ] && [ "$status" != invalid ] && status=incomplete

job_id="$(printf '%s|%s|%s' "$url" "$sha" "$now" | shasum -a 256 | cut -c1-16)"
jq -n --arg id "$job_id" --arg mode "$mode" --arg started "${started:-$now}" --arg finished "$now" --arg status "$status" \
  --argjson repo "$repo_obj" --argjson generator "$gen_obj" --argjson dirty "$dirty" \
  --arg structural "$structural" --arg semantic "$semantic" --arg vout "$vout" --arg outputs "$outputs" \
  --argjson norm "$out" --slurpfile art "$art" --argjson lint "$docs_lint" --arg redacted "$redacted" --arg uncited "$cov_uncited_manifests" --slurpfile prev "$prev_manifest" '
  {ckb_version: ($art[0].ckb_version // "0.2"),
   job: {id: $id, mode: $mode, started_at: $started, finished_at: $finished, generator: $generator},
   status: $status,
   repo: ($repo + {dirty_worktree: $dirty}),
   outputs: [$outputs | split("\n")[] | select(. != "") | split("\t") | {file: .[0], sha256: (if .[1] == "MISSING" then null else .[1] end), bytes: (.[2] | tonumber), present: (.[1] != "MISSING")}],
   validation: {structural: $structural, semantic: $semantic,
                messages: [$vout | split("\n")[] | select(startswith("  ")) | ltrimstr("  ")],
                docs: ($lint | with_entries(select((.value | type) == "array" and (.value | length) > 0)))},
   coverage: ($art[0].coverage // null),
   confidence_summary: $art[0].confidence_summary,
   entity_counts: (($art[0].entities | map_values(length)) + {relations: ($art[0].relations // [] | length)}),
   warnings: ($norm.warnings
              + (if ($redacted | tonumber) > 0 then ["redacted \($redacted) occurrence(s) of secret values copied from repo config into the KB"] else [] end)
              + [$uncited | split("\n")[] | select(. != "") | "coverage: manifest not cited by any dependency: \(.)"]),
   feedback: (
     # self-improvement loop (local only): what the next run should target, and misses that keep recurring
     ([$norm.warnings[] | sub(": .*$"; "") | sub(" \\(.*$"; "") | sub(" \u0027.*$"; "")] | group_by(.) | map({key: .[0], value: length}) | from_entries) as $sig
     | ($prev[0].feedback.recurring // {}) as $pr
     | {next_run_focus: ((([($art[0].coverage.buckets // {})[] | .uncited[]?]
                         + [$norm.warnings[] | select(startswith("downgraded")) | capture("(?<c>[a-z_]+)/(?<id>.+)$")? | .id])
                        | unique | .[0:200])),
        recurring: ($sig | with_entries(.value = {count: .value, runs: ((($pr[.key].runs // 0) + 1))})),
        improve_candidates: [ ($sig | keys[]) as $k | select(($pr[$k].runs // 0) >= 1)
                              | select($k | test("unrecognised|without a known ecosystem|not allowed by the spec|generated/vendored"))
                              | "recurring across runs: \($k) — consider a normalizer alias/rule (open an issue upstream)" ]}),
   token_usage: null,
   token_usage_note: "Not observable from inside the session. Headless runs: read usage from `claude -p --output-format json`."}' > "$kb/manifest.json.tmp" \
  && mv -f "$kb/manifest.json.tmp" "$kb/manifest.json" || die 1 "manifest generation failed (jq error above)"

# Committed-KB hygiene: collapse generated files in PR diffs; deterministic human index (no timestamps).
printf '* linguist-generated=true\n' > "$kb/.gitattributes"
printf '# transient producer files and OS junk; never commit\nckb.draft.json\nckb.draft.d/\nckb.json.candidate\nckb.json.rejected\nmanifest.json.tmp\n09-reference.md.tmp\n.DS_Store\nThumbs.db\ndesktop.ini\n' > "$kb/.gitignore"
jq -r --arg status "$status" '
  "# Codebase knowledge base\n",
  "Generated by `\(.generator.name)` \(.generator.version) · CKB \(.ckb_version) · source commit `\(.repo.commit_sha[0:12])` (\(.repo.branch)) · status **\($status)**\n",
  "| Document | Audience | Contents |", "|---|---|---|",
  "| [00-overview.md](00-overview.md) | everyone | Summary, glossary, ownership, macro context |",
  "| [01-technical-architecture.md](01-technical-architecture.md) | engineers, architects | C4 containers and components, data model, interfaces, dependencies, configuration |",
  "| [02-functional-workflows.md](02-functional-workflows.md) | product, engineers | Capabilities and end-to-end workflows |",
  "| [03-business-rules.md](03-business-rules.md) | product, QA | Rule catalog with enforcement sites |",
  "| [04-system-context-and-gaps.md](04-system-context-and-gaps.md) | architects | C4 system context, contracts, risks, open questions |",
  "| [05-operations.md](05-operations.md) | ops, on-call | Build, run, test, deploy, observe, roll back |",
  "| [06-security-and-data.md](06-security-and-data.md) | security | Trust boundaries, auth, data classification, secrets by name |",
  "| [07-decisions.md](07-decisions.md) | architects | Decision log (ADR-lite, evidence-based) |",
  "| [09-reference.md](09-reference.md) | everyone, tools | Generated tables from ckb.json |",
  "| [ckb.json](ckb.json) | tools | Machine-readable CKB artifact |\n",
  "Claims: \(.confidence_summary.confirmed) confirmed · \(.confidence_summary.inferred) inferred · \(.confidence_summary.unknown) unknown.",
  (if .coverage then "Coverage: " + ([.coverage.buckets | to_entries[] | select(.value.found > 0) | "\(.key) \(.value.cited)/\(.value.found)"] | join(" · ")) + ".\n" else "" end),
  "**Freshness:** this KB is current while nothing outside `ckb/` has changed since the source commit (`git diff --quiet \(.repo.commit_sha[0:12]) HEAD -- . \u0027:(exclude)ckb\u0027`). Regenerate with `/kb`."
' "$kb/ckb.json" > "$kb/README.md" 2>/dev/null || true

# Anonymous local run metrics (performance and quality stats; never paths, names, code, URLs or values).
# Stored in $CKB_STATE_DIR (default ~/.local/state/codebase-kb-engine/runs.jsonl). Disable with CKB_METRICS=off.
if [ "${CKB_METRICS:-on}" != off ]; then
  sdir="${CKB_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/codebase-kb-engine}"
  if mkdir -p "$sdir" 2>/dev/null; then
    [ -s "$sdir/salt" ] || { LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom 2>/dev/null | head -c 32 > "$sdir/salt"; chmod 600 "$sdir/salt" 2>/dev/null; }
    rid="$(printf '%s|%s' "$(cat "$sdir/salt" 2>/dev/null)" "$url" | shasum -a 256 | cut -c1-12)"
    t0="$(date -j -u -f %Y-%m-%dT%H:%M:%SZ "${started:-$now}" +%s 2>/dev/null || date -u -d "${started:-$now}" +%s 2>/dev/null || echo 0)"
    t1="$(date -u +%s)"; dur=$(( t0 > 0 ? t1 - t0 : -1 ))
    jq -c -n --arg ver "$gen_ver" --arg mode "$mode" --arg status "$status" --arg rid "$rid" --argjson dur "$dur" \
       --arg os "$(uname -s | tr 'A-Z' 'a-z')" --arg jqv "$(jq --version 2>/dev/null)" --arg uv "$(command -v uvx >/dev/null && echo yes || echo no)" \
       --arg audit "$audit" --arg day "$(date -u +%Y-%m-%d)" --slurpfile m "$kb/manifest.json" '
      ($m[0]) as $mf
      | def bucket(n): if n < 100 then "<100" elif n < 1000 then "100-999" elif n < 10000 then "1k-9.9k" else "10k+" end;
      def wkind: # fixed vocabulary: free text from warnings never leaves the machine
          if startswith("downgraded") then "downgraded_unverifiable_citation"
          elif startswith("dropped malformed relation") then "relation_malformed"
          elif startswith("dropped relation with unknown kind") then "relation_unknown_kind"
          elif startswith("dropped relation with unresolved") then "relation_unresolved"
          elif startswith("dropped relation not allowed") then "relation_not_allowed"
          elif startswith("dropped unresolved applies_to") then "ref_unresolved_applies_to"
          elif startswith("dropped unresolved workflow") then "ref_unresolved_step"
          elif startswith("local id") then "local_id_ambiguous"
          elif startswith("config key") then "config_value_dropped"
          elif startswith("citation in generated") then "citation_generated_code"
          elif test("^unrecognised [a-z_]+ [a-z_]+ ") then "enum_unrecognised:" + (capture("^unrecognised (?<c>[a-z_]+) (?<f>[a-z_]+) ") | "\(.c).\(.f)")
          elif startswith("dependency without a known ecosystem") then "purl_generic"
          elif startswith("dropped external service") then "external_no_hostname"
          elif startswith("datastore") then "instance_key_dsn_dropped"
          elif startswith("coverage: manifest") then "coverage_manifest_uncited"
          elif startswith("redacted") then "secret_redacted"
          elif startswith("detached HEAD") then "detached_head"
          else "other" end;
      {schema: 1, day: $day, plugin_version: $ver, ckb_version: $mf.ckb_version, mode: $mode, status: $status, repo: $rid,
       duration_s: $dur, os: $os, jq: $jqv, uv: ($uv == "yes"),
       size: bucket(($mf.coverage.files_total // 0)),
       coverage: (($mf.coverage.buckets // {}) | map_values({found, cited})),
       entities: ($mf.entity_counts // {}), confidence: ($mf.confidence_summary // {}),
       validation: {structural: $mf.validation.structural, semantic: $mf.validation.semantic,
                    rules_failed: ([$mf.validation.messages[]? | (capture("(?<r>R[0-9]+)") | .r)?] | unique)},
       docs_violations: (($mf.validation.docs // {}) | map_values(length)),
       warnings: ([$mf.warnings[]? | wkind] | group_by(.) | map({key: .[0], value: length}) | from_entries),
       audit: (if ($audit | test("^[0-9]+/[0-9]+$")) then ($audit | split("/") | {supported: (.[0] | tonumber), total: (.[1] | tonumber)}) else null end)}' \
       >> "$sdir/runs.jsonl" 2>"$tmpd/metrics.err" || echo "  note: run metrics not recorded ($(head -c 200 "$tmpd/metrics.err"))" >&2
    # anonymous report to the maintainer (on by default; DO_NOT_TRACK / CKB_TELEMETRY=off / `telemetry off` disable it)
    rec_f="$(mktemp)"; tail -1 "$sdir/runs.jsonl" > "$rec_f" 2>/dev/null
    telemetry_notice="$("$ROOT/scripts/telemetry.sh" notice 2>/dev/null)"
    "$ROOT/scripts/telemetry.sh" send "$rec_f" 2>/dev/null || true
    [ "${CKB_TELEMETRY_SYNC:-}" = 1 ] && rm -f "$rec_f"
  fi
fi

printf '%s\n' "$vout"
[ -n "$docmeta_out" ] && printf '%s\n' "$docmeta_out" | tail -1
[ "$docs_lint" != '{}' ] && printf '%s' "$docs_lint" | jq -r 'to_entries[] | select((.value | type) == "array" and (.value | length) > 0) | "  docs: \(.key): \(.value | join("; "))"' 2>/dev/null | head -40
[ -n "$cov_uncited_manifests" ] && printf '  coverage: manifest not cited: %s\n' $cov_uncited_manifests | head -20
if [ "$status" = complete ]; then rm -f "$draft"; rm -rf "$kb/ckb.draft.d"; fi
[ "$status" = complete ] && [ "$mode" = local ] && printf 'COMMIT_HINT=git add ckb && git commit -m "docs(ckb): knowledge base for %s"\n' "$(printf '%s' "$sha" | cut -c1-7)"
[ -n "${telemetry_notice:-}" ] && printf '%s\n' "$telemetry_notice"
printf 'STATUS=%s KB_DIR=%s JOB_ID=%s WARNINGS=%s%s\n' "$status" "$kb" "$job_id" "$(jq '.warnings | length' "$kb/manifest.json")" "${missing:+ MISSING=$(echo $missing | tr ' ' ',')}"
[ "$status" = complete ]
