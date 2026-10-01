#!/usr/bin/env bash
# finalize.sh — build ckb.json + manifest.json from the model-written draft, then validate.
# Usage: finalize.sh <repo_root> <kb_dir> [--mode local|url] [--url URL] [--branch BRANCH] [--started-at ISO]
# Reads <kb_dir>/ckb.draft.json; writes <kb_dir>/ckb.json and <kb_dir>/manifest.json; removes the draft on success.
# Exit: 0 complete · 1 invalid/incomplete/unverified (draft kept; a previous valid ckb.json is never overwritten by an invalid one) · 2 usage/precondition.
# Status: complete only when BOTH schema (uvx) and semantic checks pass; schema skipped => unverified.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
die(){ code="$1"; shift; printf '%s\n' "$@" >&2; exit "$code"; }
repo="${1:-}"; kb="${2:-}"; shift 2 2>/dev/null || die 2 "usage: finalize.sh <repo_root> <kb_dir> [opts]"
mode=local; url=""; branch=""; started=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) mode="$2"; shift ;; --url) url="$2"; shift ;; --branch) branch="$2"; shift ;; --started-at) started="$2"; shift ;;
    *) die 2 "unknown option: $1" ;;
  esac; shift
done
[ -d "$repo" ] || die 2 "repo_root not a dir: $repo"
[ -f "$kb/.ckb-output" ] || die 2 "REFUSED: '$kb' is not a CKB output dir (no .ckb-output marker; run resolve-kb.sh first)"
draft="$kb/ckb.draft.json"
[ -f "$draft" ] || die 2 "missing draft: $draft"
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
dirty=false; [ -n "$(git -C "$repo" status --porcelain -- . ':(exclude).ckb' 2>/dev/null | head -1)" ] && dirty=true   # the KB itself never counts
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
# untracked-but-not-ignored), outside .ckb/. normalize.jq downgrades any claim whose citations don't resolve.
rroot="$(cd "$repo" && pwd -P)"; aroot="$(cd "$repo" && pwd)"
roots="$(jq -nc --arg a "$rroot" --arg b "$aroot" --arg c "${repo%/}" '[$a, $b, $c] | unique')"
tmpd="$(mktemp -d)"; trap 'rm -rf "$tmpd"' EXIT
git -C "$repo" ls-files -co --exclude-standard > "$tmpd/files" 2>/dev/null
jq -r --argjson roots "$roots" '[.. | objects | select(has("path") and has("line")) | .path | strings] | unique | .[]
  | . as $p | ([$roots[] | select($p | startswith(. + "/"))] | first) as $r | (if $r then $p[($r|length)+1:] else $p end) | sub("^(\\./)+"; "")' "$draft" \
  | grep -v -e '^/' -e '\.\.' -e '^\.ckb$' -e '^\.ckb/' | sort -u > "$tmpd/cited"
grep -Fxf "$tmpd/files" "$tmpd/cited" | while IFS= read -r f; do [ -f "$repo/$f" ] && printf '%s\t%s\n' "$f" "$(wc -l < "$repo/$f" | tr -d ' ')"; done \
  | jq -Rn '[inputs | split("\t") | {key: .[0], value: (.[1] | tonumber)}] | from_entries' > "$tmpd/lines.json"

out="$(jq -c --argjson repo "$repo_obj" --argjson generator "$gen_obj" --argjson roots "$roots" --argjson lines "$(cat "$tmpd/lines.json")" \
        -f "$ROOT/scripts/normalize.jq" "$draft")" \
  || die 1 "normalize failed on draft (jq error above)"
[ -n "$extra_warn" ] && out="$(printf '%s' "$out" | jq -c --arg w "$extra_warn" '.warnings += [$w]')"
# Write the candidate first; it replaces ckb.json only if it passes validation.
printf '%s' "$out" | jq '.artifact' > "$kb/ckb.json.candidate"

vout="$("$ROOT/scripts/validate.sh" "$kb/ckb.json.candidate")"; vrc=$?
last="$(printf '%s\n' "$vout" | tail -1)"
structural="$(printf '%s' "$last" | sed -E 's/.*STRUCTURAL=([a-z]+).*/\1/')"
semantic="$(printf '%s' "$last" | sed -E 's/.*SEMANTIC=([a-z]+).*/\1/')"
status=complete; [ $vrc -eq 0 ] || status=invalid
[ "$status" = complete ] && [ "$structural" != pass ] && status=unverified   # never "complete" without the schema check
if [ "$status" = invalid ]; then mv -f "$kb/ckb.json.candidate" "$kb/ckb.json.rejected"; else mv -f "$kb/ckb.json.candidate" "$kb/ckb.json"; rm -f "$kb/ckb.json.rejected"; fi
art="$kb/ckb.json"; [ "$status" = invalid ] && art="$kb/ckb.json.rejected"

outputs="$(cd "$kb" && for f in 00-overview.md 01-technical-architecture.md 02-functional-workflows.md 03-business-rules.md 04-system-context-and-gaps.md ckb.json; do
  if [ -f "$f" ]; then printf '%s\t%s\t%s\n' "$f" "$(shasum -a 256 "$f" | cut -d' ' -f1)" "$(wc -c < "$f" | tr -d ' ')"; else printf '%s\tMISSING\t0\n' "$f"; fi; done)"
missing="$(printf '%s\n' "$outputs" | awk -F'\t' '$2=="MISSING"{print $1}')"
[ -n "$missing" ] && [ "$status" != invalid ] && status=incomplete

job_id="$(printf '%s|%s|%s' "$url" "$sha" "$now" | shasum -a 256 | cut -c1-16)"
jq -n --arg id "$job_id" --arg mode "$mode" --arg started "${started:-$now}" --arg finished "$now" --arg status "$status" \
  --argjson repo "$repo_obj" --argjson generator "$gen_obj" --argjson dirty "$dirty" \
  --arg structural "$structural" --arg semantic "$semantic" --arg vout "$vout" --arg outputs "$outputs" \
  --argjson norm "$out" --slurpfile art "$art" '
  {ckb_version: "0.1",
   job: {id: $id, mode: $mode, started_at: $started, finished_at: $finished, generator: $generator},
   status: $status,
   repo: ($repo + {dirty_worktree: $dirty}),
   outputs: [$outputs | split("\n")[] | select(. != "") | split("\t") | {file: .[0], sha256: (if .[1] == "MISSING" then null else .[1] end), bytes: (.[2] | tonumber), present: (.[1] != "MISSING")}],
   validation: {structural: $structural, semantic: $semantic,
                messages: [$vout | split("\n")[] | select(startswith("  ")) | ltrimstr("  ")]},
   confidence_summary: $art[0].confidence_summary,
   entity_counts: ($art[0].entities | map_values(length)) + {relations: ($art[0].relations // [] | length)},
   warnings: $norm.warnings,
   token_usage: null,
   token_usage_note: "Not observable from inside the session. Headless runs: read usage from `claude -p --output-format json`."}' > "$kb/manifest.json"

redact_values > "$tmpd/secrets"
while IFS= read -r v; do
  [ "${#v}" -ge 12 ] || continue
  for f in "$kb"/*.md "$kb"/ckb.json; do
    [ -f "$f" ] && grep -qF -- "$v" "$f" && { V="$v" perl -0pi -e 's/\Q$ENV{V}\E/[REDACTED]/g' "$f"; redacted=$((redacted+1)); }
  done
done < "$tmpd/secrets"
if [ "$redacted" -gt 0 ]; then
  jq --arg n "$redacted" '.warnings += ["redacted \($n) occurrence(s) of secret values copied from repo config into the KB"]' "$kb/manifest.json" > "$tmpd/m" && mv "$tmpd/m" "$kb/manifest.json"
  for f in 00-overview.md 01-technical-architecture.md 02-functional-workflows.md 03-business-rules.md 04-system-context-and-gaps.md ckb.json; do
    [ -f "$kb/$f" ] && jq --arg f "$f" --arg h "$(shasum -a 256 "$kb/$f" | cut -d' ' -f1)" --argjson b "$(wc -c < "$kb/$f" | tr -d ' ')" '(.outputs[] | select(.file == $f)) |= (.sha256 = $h | .bytes = $b)' "$kb/manifest.json" > "$tmpd/m" && mv "$tmpd/m" "$kb/manifest.json"
  done
fi

# Committed-KB hygiene: collapse generated files in PR diffs; deterministic human index (no timestamps).
printf '* linguist-generated=true\n' > "$kb/.gitattributes"
jq -r --arg status "$status" '
  "# Codebase knowledge base\n",
  "Generated by `\(.generator.name)` \(.generator.version) · CKB \(.ckb_version) · source commit `\(.repo.commit_sha[0:12])` (\(.repo.branch)) · status **\($status)**\n",
  "| Document | Contents |", "|---|---|",
  "| [00-overview.md](00-overview.md) | Summary, glossary, macro context |",
  "| [01-technical-architecture.md](01-technical-architecture.md) | Components, data model, interfaces, dependencies |",
  "| [02-functional-workflows.md](02-functional-workflows.md) | Capabilities and end-to-end workflows |",
  "| [03-business-rules.md](03-business-rules.md) | Rule catalog with enforcement sites |",
  "| [04-system-context-and-gaps.md](04-system-context-and-gaps.md) | System context, risks, unknowns |",
  "| [ckb.json](ckb.json) | Machine-readable CKB artifact |\n",
  "Claims: \(.confidence_summary.confirmed) confirmed · \(.confidence_summary.inferred) inferred · \(.confidence_summary.unknown) unknown.\n",
  "**Freshness:** this KB is current while nothing outside `.ckb/` has changed since the source commit (`git diff --quiet \(.repo.commit_sha[0:12]) HEAD -- . \u0027:(exclude).ckb\u0027`). Regenerate with `/kb`."
' "$kb/ckb.json" > "$kb/README.md"

printf '%s\n' "$vout"
if [ "$status" = complete ]; then rm -f "$draft"; fi
[ "$status" = complete ] && [ "$mode" = local ] && printf 'COMMIT_HINT=git add .ckb && git commit -m "docs(ckb): knowledge base for %s"\n' "$(printf '%s' "$sha" | cut -c1-7)"
printf 'STATUS=%s KB_DIR=%s JOB_ID=%s WARNINGS=%s%s\n' "$status" "$kb" "$job_id" "$(printf '%s' "$out" | jq '.warnings | length')" "${missing:+ MISSING=$(echo $missing | tr ' ' ',')}"
[ "$status" = complete ]
