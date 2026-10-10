#!/usr/bin/env bash
# archetype.sh — classify a repo into one of five agent-context archetypes (+ modifiers) from inventory.sh output only.
# Usage: archetype.sh <repo_root | inventory.json | ->      prints ONE JSON object; read-only; exit 2 on bad input.
# Primaries (first match in this order): D infrastructure · B workspace monorepo · A deployable service · C library/CLI · E contract & content.
# Modifiers (additive): +events · +datastore · +deploy · +polyglot.
# Signal hygiene — each rule exists because the naive version misclassified a real repo:
#   · TESTPATH: manifests/workspaces/iac/ci under tests/, fixtures/, examples/, testdata/ are NOT the repo's own. (This engine ships a
#     six-ecosystem fixture; without the filter it classifies as a polyglot monorepo.)
#   · Shell hits (.sh/.bash) are content-sniffed with regexes that match their own pattern text, so they count for coverage but
#     never for classification (a script that quotes `kafkajs` is not an event consumer).
#   · A and C need exactly ONE real ecosystem: a "service" with no manifest is far more likely a docs/scripts repo (E).
# bash 3.2+, jq 1.6+. Never writes anything.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd -P)"
die(){ echo "archetype: $*" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || die "jq is required"
src="${1:-}"; [ -n "$src" ] || die "usage: archetype.sh <repo_root | inventory.json | ->"
if [ "$src" = - ]; then inv="$(cat)"
elif [ -d "$src" ]; then inv="$("$HERE/inventory.sh" "$src")" || die "inventory failed for $src"
elif [ -f "$src" ]; then inv="$(cat "$src")"
else die "not a directory, file or '-': $src"; fi
printf '%s' "$inv" | jq -e 'type == "object" and (.buckets | type == "object" and ([.[]] | all(type == "array"))) and has("files_total")' >/dev/null 2>&1 \
  || die "input is not a full inventory.sh JSON (a digest has no bucket lists)"
printf '%s' "$inv" | jq -c '
  def testpath: test("(^|/)(tests?|testdata|fixtures?|examples?)(/|$)");
  def weak: test("\\.(sh|bash)$");
  def real(b): (.buckets[b] // []) | map(select(testpath | not));
  def sig(b): real(b) | map(select(weak | not));
  def eco: (split("/") | last) as $b
    | if   ($b | test("^(package\\.json|deno\\.json)$")) then "js"
      elif ($b | test("^(pyproject\\.toml|setup\\.py|Pipfile|requirements.*\\.txt)$")) then "py"
      elif ($b | test("^(go\\.mod|go\\.work)$")) then "go"
      elif ($b | test("^(pom\\.xml|build\\.gradle.*|settings\\.gradle.*)$")) then "jvm"
      elif $b == "Cargo.toml" then "rust" elif $b == "Gemfile" then "ruby" elif $b == "composer.json" then "php"
      elif ($b | test("\\.(csproj|sln)$")) then "dotnet" elif $b == "Package.swift" then "swift"
      elif $b == "pubspec.yaml" then "dart" elif $b == "mix.exs" then "elixir"
      elif ($b | test("^(Dockerfile|Containerfile)")) then "container" elif ($b | test("\\.tf$")) then "terraform"
      elif $b == "Chart.yaml" then "helm" else null end;
  . as $i
  | ([real("manifests")[] | eco | select(. != null and . != "container" and . != "terraform" and . != "helm")] | unique) as $ecos
  | ([$i.workspaces[]? | .members[]? | select(testpath | not)] | unique | length) as $members
  | (sig("routes") | length) as $routes | (sig("events") | length) as $events
  | ((sig("datastores") | length) + (sig("migrations") | length)) as $stores
  | (real("iac") | length) as $iac | (real("ci") | length) as $ci
  | (real("manifests") | any(split("/") | last | test("^(Dockerfile|Containerfile)"))) as $dockerfile
  | (if   ($iac + $ci) >= (0.3 * $i.files_total) and ($ecos | length) == 0 then "D"
     elif $members >= 2 or ($ecos | length) >= 2 then "B"
     elif ($ecos | length) == 1 and $members == 0 and $routes > 0 and ($iac > 0 or $events > 0 or $dockerfile) then "A"
     elif ($ecos | length) == 1 and $members == 0 and $routes == 0 and $iac == 0 then "C"
     else "E" end) as $p
  | {archetype: $p,
     name: ({A: "deployable-service", B: "workspace-monorepo", C: "library-cli", D: "infrastructure", E: "contract-and-content"}[$p]),
     modifiers: ([ (if $events > 0 then "events" else empty end),
                   (if $stores > 0 then "datastore" else empty end),
                   (if $iac > 0 and $p != "D" then "deploy" else empty end),
                   (if ($ecos | length) >= 3 then "polyglot" else empty end) ]),
     evidence: {ecosystems: $ecos, workspace_members: $members, routes: $routes, events: $events, datastores_and_migrations: $stores,
                iac: $iac, ci: $ci, dockerfile: $dockerfile, files_total: $i.files_total}}'
