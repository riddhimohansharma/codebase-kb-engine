#!/usr/bin/env bash
# agent-context.sh — propose an agent-context file (CLAUDE.md / AGENTS.md body) for a repo, from facts only.
# Usage: agent-context.sh <repo> [--out FILE]
#   no --out : print the proposal on stdout (read-only; used by tests)
#   --out FILE: write it; FILE must be <repo>/.ckb/agent-context.proposed.md inside a marked KB dir (plugin scripts are
#               pre-approved by the guard, so this must not become an arbitrary file write). Never touches CLAUDE.md or AGENTS.md.
# What it does: classify the repo (archetype.sh over inventory.sh), then emit the template for that archetype with only lines that
#   a manifest, lockfile, route/migration/IaC/CI bucket or directory listing proves. Everything a machine cannot know is a
#   `TODO(human)` line. No model is used; same repo state gives byte-identical output (no dates, sorted lists).
#   --seed   : first-run seeding of <repo>/CLAUDE.md, create-only (see the block below for every condition). Exclusive with --out.
#              Prints SEED=created|skipped:<reason>; a skip writes nothing. Off with CKB_AGENT_CONTEXT=off.
# With --out prints KEY=VALUE lines: ARCHETYPE, MODIFIERS, OUTPUT, WORDS, TODOS, CLAUDE_MD, AGENTS_MD, NEXT. Exit: 0 · 1 generator/lint failure · 2 usage.
# bash 3.2+, jq 1.6+.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd -P)"
die(){ echo "agent-context: $*" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || die "jq is required"
OUT=""; REPO=""; SEED=0
while [ $# -gt 0 ]; do
  case "$1" in --out) [ $# -ge 2 ] || die "--out needs a file"; OUT="$2"; shift ;; --seed) SEED=1 ;; -*) die "unknown option: $1" ;; *) REPO="$1" ;; esac; shift
done
[ -n "$REPO" ] && [ -d "$REPO" ] || die "usage: agent-context.sh <repo> [--out FILE]"
root="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git work tree: $REPO"
root="$(cd "$root" && pwd -P)"
[ "$SEED" = 1 ] && [ -n "$OUT" ] && die "--seed and --out are exclusive"

if [ -n "$OUT" ]; then
  case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
  odir="$(dirname "$OUT")"
  { [ "$(basename "$OUT")" = agent-context.proposed.md ] && [ -d "$odir" ] && [ ! -L "$odir" ] && [ ! -L "$OUT" ] \
    && [ -f "$odir/.ckb-output" ] && [ "$(cd "$odir" && pwd -P)" = "$root/.ckb" ]; } \
    || die "--out must be <repo>/.ckb/agent-context.proposed.md in a marked KB dir (REFUSED: $OUT)"
fi

inv="$("$HERE/inventory.sh" "$root")" || die "inventory failed for $root"
arch="$(printf '%s' "$inv" | "$HERE/archetype.sh" -)" || die "archetype classification failed"

# ---- commands a manifest proves ----
real_manifests="$(printf '%s' "$inv" | jq -r '.buckets.manifests[] | select(test("(^|/)(tests?|testdata|fixtures?|examples?)(/|$)") | not)')"
cmds=""
add_cmd(){ cmds="$cmds$1	$2	$3
"; }
pm_for(){ if [ -f "$root/$1/pnpm-lock.yaml" ]; then echo pnpm; elif [ -f "$root/$1/yarn.lock" ]; then echo yarn; elif [ -f "$root/$1/bun.lockb" ]; then echo bun; else echo npm; fi; }
pomdirs="$(printf '%s\n' "$real_manifests" | grep '/\?pom\.xml$' | sed -E 's#/?pom\.xml$##; s#^$#.#')"
while IFS= read -r p; do
  [ -n "$p" ] || continue
  d="$(dirname "$p")"; b="$(basename "$p")"
  case "$b" in
    package.json)
      t="$(jq -r '.scripts.test // empty' "$root/$p" 2>/dev/null)"
      case "$t" in ""|*"no test specified"*) ;; *) pm="$(pm_for "$d")"; if [ "$pm" = npm ]; then add_cmd "$d" "npm test" ""; else add_cmd "$d" "$pm run test" ""; fi ;; esac ;;
    pyproject.toml)
      if grep -qi pytest "$root/$p" 2>/dev/null; then
        if [ -f "$root/$d/uv.lock" ]; then add_cmd "$d" "uv run pytest" ""
        elif [ -f "$root/$d/poetry.lock" ]; then add_cmd "$d" "poetry run pytest" ""
        else add_cmd "$d" "pytest" ""; fi
      fi ;;
    go.mod) add_cmd "$d" "go test ./..." "" ;;
    Cargo.toml) add_cmd "$d" "cargo test" "" ;;
    pom.xml)
      # a module's parent builds it: only the topmost pom gets a command
      top=1; anc="$d"
      while [ "$anc" != "." ] && [ "$anc" != "/" ]; do anc="$(dirname "$anc")"; printf '%s\n' "$pomdirs" | grep -qxF "$anc" && top=0; done
      if [ "$top" = 1 ]; then if [ -f "$root/$d/mvnw" ] || [ -f "$root/mvnw" ]; then add_cmd "$d" "./mvnw test" ""; else add_cmd "$d" "mvn test" ""; fi; fi ;;
    build.gradle|build.gradle.kts)
      if [ -f "$root/$d/gradlew" ] || [ -f "$root/gradlew" ]; then add_cmd "$d" "./gradlew test" ""; else add_cmd "$d" "gradle test" ""; fi ;;
  esac
done <<EOF
$real_manifests
EOF
[ -f "$root/Makefile" ] && grep -qE '^test:' "$root/Makefile" 2>/dev/null && add_cmd "." "make test" ""
ls "$root"/tests/*.test.sh >/dev/null 2>&1 && add_cmd "." "tests/<suite>.test.sh" "one script per suite in tests/; run the ones you touched"
cmds_json="$(printf '%s' "$cmds" | awk 'NF && !seen[$0]++' | LC_ALL=C sort | jq -R -s -c 'split("\n") | map(select(length>0) | split("\t") | {dir: .[0], cmd: .[1], note: (.[2] // "")})')"

changelog=""; for c in CHANGELOG.md CHANGELOG CHANGES.md HISTORY.md; do [ -f "$root/$c" ] && { changelog="$c"; break; }; done
fixtures_json="$(cd "$root" && find . -maxdepth 4 -type d \( -name fixtures -o -name testdata \) -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.venv/*' 2>/dev/null | sed 's#^\./##' | LC_ALL=C sort | jq -R -s -c 'split("\n") | map(select(length>0))')"

vendored_json="$(cd "$root" && { find . -maxdepth 3 -type d \( -name vendor -o -name third_party -o -name generated -o -name dist \) -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.venv/*'
  find . -maxdepth 4 -type f \( -name SOURCE -o -name .vendored \) -not -path '*/.git/*' -not -path '*/node_modules/*' -exec dirname {} \; ; } 2>/dev/null | sed 's#^\./##' | LC_ALL=C sort -u | jq -R -s -c 'split("\n") | map(select(length>0))')"

read -r -d '' PROG <<'JQ' || true
def test_path: test("(^|/)(tests?|testdata|fixtures?|examples?)(/|$)");
def real($b): (($inv.buckets[$b] // []) | map(select(test_path | not)));
def bt: "`" + . + "`";
def bt_of($x): "`" + $x + "`";
def dirof: if test("/") then sub("/[^/]*$"; "") else "." end;
def base: sub("^.*/"; "");
def lst($a; $n): ($a | unique) as $u | ($u[0:$n] | map(bt) | join(", ")) + (if ($u | length) > $n then " and \(($u | length) - $n) more" else "" end);
def sec($t; $lines): "## " + $t + "\n" + ($lines | map("- " + .) | join("\n")) + "\n";
def pairs: {"package-lock.json":"package.json","yarn.lock":"package.json","pnpm-lock.yaml":"package.json","bun.lockb":"package.json",
            "uv.lock":"pyproject.toml","poetry.lock":"pyproject.toml","Pipfile.lock":"Pipfile","Cargo.lock":"Cargo.toml",
            "go.sum":"go.mod","Gemfile.lock":"Gemfile","composer.lock":"composer.json"};

$arch.archetype as $a | $arch.modifiers as $mods | real("manifests") as $mf
| (real("iac") | map(dirof) | unique) as $iacdirs
| ([real("lockfiles")[] as $l | (pairs[$l | base]) as $m | select($m != null)
    | ((($l | dirof) + "/" + $m) | ltrimstr("./")) as $mp | select($mf | index($mp) != null) | [$mp, $l]] | unique) as $lockpairs
| ($cmds | .[0:$ncmd]) as $cm
| ([$inv.languages[]? | select(.name | IN("JSON","YAML","XML","Markdown","TOML","Text") | not) | .name] | .[0:2]) as $langs
| (if ($langs | length) == 0 then "source" else ($langs | join(" and ")) end) as $langtxt
| ({A:"deployable service",B:"workspace monorepo",C:"library or CLI",D:"infrastructure repository",E:"contract-and-content repository"}[$a]) as $kind

| ( (if $a == "A" then ["Routes are defined in " + lst(real("routes"); $max) + ". A change to a path, method or payload is a breaking change for callers."]
    elif $a == "B" then ["Workspace roots: " + ([$inv.workspaces[]? | "`\(.root)` (\(.tool))"] | unique | .[0:4] | join(", ")) + ". Each ecosystem has its own tests; green in one proves nothing about the others."]
    elif $a == "C" then ["TODO(human): name the public surface (exported modules, console scripts, CLI flags). Renaming or re-typing anything exported is a breaking change."]
    elif $a == "D" then [(($iacdirs | map(bt) | .[0:$max] | join(", ")) + " is the source of truth. Edit it, never rendered output. Propose a diff; never apply. Never write a secret value into a variables or values file.")]
    else ["TODO(human): name the files that are the contract or artifact, and what a change to them obligates (fixtures, docs, schema)."] end)
  + (if ($mods | index("deploy")) != null then [(($iacdirs | map(bt) | .[0:$max] | join(", ")) + " governs deployment. Propose a diff; never apply.")] else [] end)
  ) as $nonneg

| ( (if ($vendored | length) > 0 then ["Vendored or generated, not yours to edit: " + lst($vendored; $max) + "."] else [] end)
    + (if $a == "B" then ["Members: " + lst([$inv.workspaces[]? | .members[]?] | map(select(test_path | not)); $max + 2) + "."] else [] end)
  ) as $shape0
| (if ($shape0 | length) == 0 then ["TODO(human): where an agent would put code in the wrong place, or what is generated."] else $shape0 end) as $shape

| (if ($cm | length) > 0 then ($cm | map("`" + .cmd + "`" + (if .dir != "." then " in `" + .dir + "`" else "" end) + (if .note != "" then " (" + .note + ")" else "" end)))
   else ["TODO(human): the build and test commands (none could be derived from the manifests)."] end) as $cmdlines

| ( (if (real("migrations") | length) > 0 then ["A model or schema change needs a new migration in " + lst(real("migrations") | map(dirof); $max) + "; never edit a committed migration."] else [] end)
  + (if (real("api_specs") | length) > 0 then ["A route or event change updates " + lst(real("api_specs"); $max) + " in the same change."] else [] end)
  + ($lockpairs[0:$max] | map("A dependency change in " + bt_of(.[0]) + " also updates " + bt_of(.[1]) + "."))
  + (if ($lockpairs | length) > $max then ["…and \(($lockpairs | length) - $max) more manifest and lockfile pairs."] else [] end)
  + (if (real("ci") | length) > 0 then ["A build or test command change also needs the CI definition: " + lst(real("ci"); $max) + "."] else [] end)
  + (if $a == "C" and $changelog != "" then ["A public signature change: update " + bt_of($changelog) + " and the version."] else [] end)
  ) as $obl0
| (if ($obl0 | length) == 0 then ["TODO(human): one edge of the form \"changing X obligates Y\", with paths."] else $obl0 end) as $obl

| ( (if ($fixtures | length) > 0 then [lst($fixtures; $max) + " hold fixtures; some are meant to fail. Do not \"fix\" them."] else [] end)
  + (if ($mods | index("events")) != null and ($a == "A" or $a == "B") then ["Candidate: publish and subscribe sites in " + lst(real("events"); $max) + ". A topic or payload rename is a cross-repo breaking change; verify each site."] else [] end)
  + ["TODO(human): a counter-intuitive fact about this repo that has already cost someone time."]
  ) as $traps

| ( (if ($cm | length) > 0 then ["The commands above pass for every area you touched."] else ["TODO(human): what \"done\" means here."] end)
  + (if ($mods | index("polyglot")) != null then ["Green in one ecosystem is not green: run each ecosystem you touched (" + (($inv.buckets.manifests // []) | length | tostring) + " manifests found)."] else [] end)
  ) as $done

| "<!-- Proposed by codebase-kb-engine from the repo inventory (no model used). Fill or delete every TODO(human) line, delete this comment, then copy this file to CLAUDE.md. -->\n"
  + "# Agent context — " + $name + "\n\n"
  + "A " + $langtxt + " " + $kind + ".\n\n"
  + sec("Non-negotiables"; $nonneg) + "\n"
  + sec("Shape"; $shape) + "\n"
  + sec("Commands"; $cmdlines) + "\n"
  + sec("Changing X obligates Y"; $obl) + "\n"
  + sec("Traps"; $traps) + "\n"
  + sec("Before you say you're done"; $done)
JQ

render(){ # <max> <ncmd>
  jq -nr --argjson inv "$inv" --argjson arch "$arch" --argjson cmds "$cmds_json" --argjson fixtures "$fixtures_json" --argjson vendored "$vendored_json" \
    --arg name "$(basename "$root")" --arg changelog "$changelog" --argjson max "$1" --argjson ncmd "$2" "$PROG"
}
text="$(render 3 6)" || { echo "agent-context: render failed" >&2; exit 1; }
words(){ printf '%s\n' "$1" | awk 'BEGIN{c=0} /^<!--/{next} /^```/{f=!f; next} !f{c+=NF} END{print c}'; }
if [ "$(words "$text")" -gt 400 ]; then text="$(render 1 3)" || exit 1; fi

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf '%s\n' "$text" > "$T/p.md"
lint="$("$HERE/lint-agent-context.sh" "$T/p.md" --proposal)" || { echo "agent-context: generated proposal failed its own lint:" >&2; printf '%s\n' "$lint" >&2; exit 1; }

# ---- first-run seed of <repo>/CLAUDE.md: create-only, every condition checked here (the guard stays strict) ----
if [ "$SEED" = 1 ]; then
  skip(){ echo "SEED=skipped:$1"; exit 0; }
  kb="$root/.ckb"
  [ "${CKB_AGENT_CONTEXT:-}" = off ] && skip opted-out
  [ -d "$kb" ] && [ ! -L "$kb" ] && [ -f "$kb/.ckb-output" ] || skip no-marked-kb-dir
  [ -e "$kb/manifest.json" ] && skip not-first-run
  [ -e "$kb/.agent-context-seeded" ] && skip already-seeded
  sup="$(git -C "$root" rev-parse --show-superproject-working-tree 2>/dev/null)" || skip git-failed
  [ -z "$sup" ] || skip submodule
  for f in CLAUDE.md AGENTS.md; do if [ -e "$root/$f" ] || [ -L "$root/$f" ]; then skip "exists:$f"; fi; done
  git -C "$root" check-ignore -q CLAUDE.md 2>/dev/null; rc=$?
  [ $rc -eq 0 ] && skip gitignored
  [ $rc -eq 1 ] || skip git-failed
  # the seed is the proposal minus every TODO(human) line: only what the repo proves
  { echo '<!-- Seeded once by codebase-kb-engine from the repo manifests and inventory. Edit freely: it is never regenerated or overwritten. /kb-agent-context lists what a person still has to add. -->'
    awk 'NR==1 && /^<!--/ {next} {print}' "$T/p.md" | grep -v 'TODO(human)'; } > "$T/seed.md"
  [ "$(grep -c '^- ' "$T/seed.md")" -ge 3 ] || skip too-few-proven-lines
  "$HERE/lint-agent-context.sh" "$T/seed.md" >/dev/null 2>&1 || skip lint-failed
  target="$root/CLAUDE.md"
  ( set -o noclobber; cat "$T/seed.md" > "$target" ) 2>/dev/null || skip "create-failed"   # O_EXCL: never overwrites, never follows a symlink
  sum="$( { shasum -a 256 "$target" 2>/dev/null || sha256sum "$target"; } | cut -d' ' -f1)"
  jq -n --arg sha "$sum" --arg b "$(wc -c < "$target" | tr -d ' ')" --arg a "$(printf '%s' "$arch" | jq -r .archetype)" \
    '{seeded: true, path: "CLAUDE.md", sha256: $sha, bytes: ($b | tonumber), archetype: $a}' > "$kb/.agent-context-seeded" 2>/dev/null
  printf 'SEED=created\nSEED_PATH=CLAUDE.md\nSEED_SHA256=%s\nARCHETYPE=%s\nNEXT=review CLAUDE.md, then commit it with the KB: git add .ckb CLAUDE.md\n' "$sum" "$(printf '%s' "$arch" | jq -r .archetype)"
  exit 0
fi

if [ -z "$OUT" ]; then cat "$T/p.md"; exit 0; fi

cp "$T/p.md" "$OUT.tmp.$$" && mv -f "$OUT.tmp.$$" "$OUT" || die "could not write $OUT"
gi="$odir/.gitignore"   # the proposal is a working file: keep it out of commits (finalize.sh writes the same line)
if [ ! -L "$gi" ]; then
  if [ ! -f "$gi" ]; then printf 'agent-context.proposed.md\n' > "$gi"
  elif ! grep -qxF agent-context.proposed.md "$gi"; then printf 'agent-context.proposed.md\n' >> "$gi"; fi
fi
have(){ [ -e "$root/$1" ] || [ -L "$root/$1" ] && echo exists || echo absent; }
cm="$(have CLAUDE.md)"
printf 'ARCHETYPE=%s\nMODIFIERS=%s\nOUTPUT=%s\n%s\nCLAUDE_MD=%s\nAGENTS_MD=%s\n' \
  "$(printf '%s' "$arch" | jq -r .archetype)" "$(printf '%s' "$arch" | jq -r '.modifiers | join(",")')" "$OUT" "$(printf '%s' "$lint" | tail -1 | tr ' ' '\n' | grep -E '^(WORDS|TODOS)=')" "$cm" "$(have AGENTS.md)"
if [ "$cm" = exists ]; then echo "NEXT=CLAUDE.md exists and is never overwritten: compare with  diff CLAUDE.md .ckb/agent-context.proposed.md  and merge by hand"
else echo "NEXT=fill every TODO(human) line, then  cp .ckb/agent-context.proposed.md CLAUDE.md"; fi
exit 0
