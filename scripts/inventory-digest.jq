# inventory-digest.jq — compact views over a FULL inventory.sh JSON; shared by inventory.sh --out and kbq.sh inventory.
# Usage: jq -c --arg mode digest|scopes|slice --arg scope <name|inventory> --argjson maxscopes 7 -f inventory-digest.jq <inventory.json>
# digest : ~1-2 KB orchestrator view (counts, languages, workspaces, tier mix, scopes). scopes: the scope list only.
# slice  : what ONE scout needs. `inventory` = name-matched mechanical buckets; any other name = an area scope.
# Never changes the full file: coverage.sh keeps reading the complete buckets, so `found` counts are unaffected.
def tier_w: if . == "source" then 1 else 0.25 end;
def make_scopes($max):
  reduce ((.areas | map(. + {w: (.files * (.tier | tier_w))})) | sort_by(-.w, .area))[] as $a ([];
    if length < $max then . + [{areas: [$a], w: $a.w}]
    else (to_entries | min_by(.value.w) | .key) as $i | .[$i].areas += [$a] | .[$i].w += $a.w end)
  | map({scope: .areas[0].area, areas: (.areas | map(.area)), paths: (.areas | map(.path)), files: (.areas | map(.files) | add),
         tiers: (.areas | group_by(.tier) | map({key: .[0].tier, value: (map(.files) | add)}) | from_entries)});
def area_of($areas): . as $p
  | ([$areas[] | select(.path != "." and (.path as $q | $p | startswith($q + "/")))] | max_by(.path | length)) // ([$areas[] | select(.path == ".")] | first);
def shallow: sort_by([(split("/") | length), .]);
def digest:
  . as $i
  | {files_total, excluded_total,
     languages: (.languages | .[0:8]),
     workspaces: (.workspaces | map({tool, root, members: (.members | length)})),
     buckets: (.buckets | to_entries | map({key, value: {found: (.value | length), sniffed: (($i.sniffed[.key] // []) | length)}}) | from_entries),
     areas: {count: (.areas | length), by_tier: (.areas | group_by(.tier) | map({key: .[0].tier, value: (map(.files) | add)}) | from_entries)},
     scopes: (make_scopes($maxscopes) | map({scope, files, tiers, paths: .paths[0:6], more_paths: ((.paths | length) - 6 | if . > 0 then . else 0 end)}))};
def slice($scope):
  . as $i
  | if $scope == "inventory" then
      {scope: "inventory",
       buckets: (["manifests","lockfiles","iac","ci","api_specs","migrations","config"]
                 | map(. as $b | {key: $b, value: ((($i.buckets[$b] // []) - ($i.sniffed[$b] // [])))}) | from_entries),
       note: "name-matched files only; source files that merely read env/config belong to the area scouts"}
    else
      (make_scopes($maxscopes) | map(select(.scope == $scope)) | first) as $sc
      | if $sc == null then error("unknown scope: " + $scope) else
        $i.areas as $A | $sc.areas as $mine
        | def mine: map(. as $p | select((($p | area_of($A)).area) as $x | ($mine | index($x)) != null));
          (["routes","events","datastores"] | map(. as $b | {key: $b, value: (($i.buckets[$b] // []) | mine)}) | from_entries) as $core
        | (($i.sniffed.config // []) | mine | shallow) as $sn
        | ((($i.buckets.config // []) | mine) - $sn) as $named
        | {scope: $sc.scope, paths: $sc.paths, files: $sc.files, tiers: $sc.tiers,
           areas: ($A | map(select(.area as $x | ($mine | index($x)) != null) | {path, tier, files})),
           buckets: ($core + {config: ($named + $sn[0:25])}),
           config_sniffed_more: (($sn | length) - 25 | if . > 0 then . else 0 end),
           note: "path \".\" means root-level files only; config lists name-matched files in full plus a sample of env readers"}
      end
    end;
if $mode == "digest" then digest elif $mode == "scopes" then make_scopes($maxscopes) elif $mode == "slice" then slice($scope) else error("mode must be digest|scopes|slice") end
