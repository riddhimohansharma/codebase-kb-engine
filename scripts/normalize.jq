# normalize.jq — turn a model-written CKB draft into a deterministic CKB v0.1 artifact.
# Input: {entities:{...}, relations:[...]} where entity `id`s are local reference keys.
# Args:  $repo (object), $generator (object)
# Does:  whitelist fields · normalize join keys · derive IDs per spec · merge duplicates ·
#        remap references · sort everything · compute confidence_summary.
# Output: {artifact, warnings}

def slug: ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("^-+|-+$"; "") | if . == "" then "unnamed" else . end;
def snake: gsub("(?<a>[a-z0-9])(?<b>[A-Z])"; "\(.a)_\(.b)") | ascii_downcase | gsub("[^a-z0-9_]+"; "_") | gsub("^_+|_+$"; "")
         | if test("^[a-z_]") then . else "p_" + . end;
def rank: {"confirmed": 0, "inferred": 1, "unknown": 2}[.] // 2;
def nonempty: select(. != null and . != "");

def norm_path:
  (split("?")[0] | split("#")[0])
  | split("/") | map(select(. != ""))
  | map(
      if   test("^\\[\\[?\\.\\.\\.(?<p>[^\\]]+)\\]\\]?$") then "{" + (capture("\\.\\.\\.(?<p>[^\\]]+)").p | snake) + "}"   # Next.js [...slug]
      elif test("^\\[(?<p>[^\\]]+)\\]$")                  then "{" + (capture("^\\[(?<p>[^\\]]+)\\]$").p | snake) + "}" # Next.js [id]
      elif test("^:(?<p>[A-Za-z0-9_]+)\\??$")               then "{" + (capture("^:(?<p>[A-Za-z0-9_]+)").p | snake) + "}"  # express :id
      elif test("^<([^:>]+:)?(?<p>[A-Za-z0-9_]+)>$")      then "{" + (capture("^<([^:>]+:)?(?<p>[A-Za-z0-9_]+)>$").p | snake) + "}" # flask <int:id>
      elif test("^\\{(?<p>[A-Za-z0-9_]+)(:[^}]*)?\\}$")   then "{" + (capture("^\\{(?<p>[A-Za-z0-9_]+)").p | snake) + "}" # {id} / {id:int}
      elif test("^\\$\\{?(?<p>[A-Za-z0-9_]+)\\}?$")       then "{" + (capture("^\\$\\{?(?<p>[A-Za-z0-9_]+)").p | snake) + "}" # template ${id}
      else gsub("[^A-Za-z0-9._~-]"; "-") end)
  | "/" + join("/");

def norm_pkg:
  if   startswith("npm:")  then "npm:"  + (.[4:] | ascii_downcase)
  elif startswith("pypi:") then "pypi:" + (.[5:] | ascii_downcase | gsub("[-_.]+"; "-"))
  elif startswith("cargo:") then "cargo:" + (.[6:] | ascii_downcase)
  else . end;

def valid_prov: [.provenance[]? | select(type == "object" and (.path|type) == "string" and (.path|startswith("/")|not) and (.path|test("(^|/)\\.\\.(/|$)")|not) and (.line|type) == "number" and .line >= 1)
                   | {path: (.path | sub("^\\./"; "")), line: (.line | floor)} + (if (.end_line|type) == "number" and .end_line >= .line then {end_line: (.end_line|floor)} else {} end)]
                  | unique_by([.path, .line, .end_line]) | sort_by([.path, .line, (.end_line // 0)]);
# claims asserted without citable provenance are downgraded to `unknown` (spec: provenance mandatory unless unknown)
def claim_fields: valid_prov as $p
  | ((.confidence // "unknown") | if IN("confirmed","inferred","unknown") then . else "unknown" end) as $c
  | {confidence: (if $p == [] then "unknown" else $c end), provenance: $p};
def downgraded: (.confidence | IN("confirmed","inferred")) and (valid_prov == []);

def base_fields: {name: ((.name // .id // "unnamed") | tostring)} + (if (.description|type) == "string" then {description} else {} end) + claim_fields;
def pick(keys): . as $o | reduce keys[] as $k ({}; if ($o[$k] | . != null and . != "") then .[$k] = $o[$k] else . end);

def shape($coll):
  if $coll == "components" then base_fields + {module_id: ((.module_id // "") | sub("^\\./"; "") | sub("/+$"; "") | if . == "" then "." else . end), kind: (.kind // "other")} + pick(["language"])
  elif $coll == "interfaces" then
    base_fields + {kind, role: (.role // "provides")}
    + (if .kind == "http"  then {http: ({method: ((.http.method // "ANY") | ascii_upcase), normalized_path: ((.http.normalized_path // .http.path // "/") | norm_path)} + (.http | pick(["host"])))}
       elif .kind == "event" then {event: {transport: ((.event.transport // "other") | ascii_downcase), topic: .event.topic}}
       elif .kind == "rpc"   then {rpc: (.rpc | pick(["protocol","service","method"]))}
       else pick(["symbol"]) end)
  elif $coll == "dependencies" then base_fields + {package_key: (.package_key | norm_pkg), scope: (.scope // "runtime")} + pick(["version_constraint"])
  elif $coll == "datastores" then base_fields + {engine: ((.engine // "other") | ascii_downcase), access: (.access // "readwrite")} + pick(["schema","table"])
  elif $coll == "business_rules" then base_fields + {statement: (.statement // .name)} + (if (.applies_to|type) == "array" then {applies_to} else {} end)
  elif $coll == "workflows" then base_fields + pick(["trigger"])
       + {steps: ([.steps[]? | {description: (.description // "step")} + pick(["entity_id","order"])] | sort_by(.order // 1e9) | to_entries | map(.value + {order: (.key + 1)}))}
  else base_fields end;

def derive_id($coll):
  if   $coll == "components"   then "component:" + .module_id
  elif $coll == "dependencies" then "dependency:" + .package_key
  elif $coll == "datastores"   then "datastore:" + .engine + ([.schema, .table | nonempty] | if length > 0 then ":" + join(".") else "" end)
  elif $coll == "interfaces" then
    if   .kind == "http"  then "interface:http:\(.role):\(.http.method):\(.http.normalized_path)"
    elif .kind == "event" then "interface:event:\(.role):\(.event.transport):\(.event.topic)"
    elif .kind == "rpc"   then "interface:rpc:\(.role):\(.rpc.service)/\(.rpc.method)"
    else "interface:\(.kind):\(.role):\(.symbol)" end
  else null end;   # business_rules / workflows: slug + collision suffix, assigned below

def merge_group: (sort_by(.confidence | rank) | .[0]) as $best
  | $best + {provenance: ([.[].provenance[]] | unique_by([.path, .line, .end_line]) | sort_by([.path, .line, (.end_line // 0)]))};

. as $draft
| ["components","interfaces","dependencies","datastores","business_rules","workflows"] as $colls
# 1) shape + derive IDs, keeping the draft's local id for reference remapping
| [ $colls[] as $c | ($draft.entities[$c] // [])[] | {coll: $c, local: (.id // null), ent: shape($c)} | .ent.id = (.ent | derive_id($c)) ] as $shaped
# 2) slug IDs for rules/workflows, collisions suffixed in deterministic order
| ( [ $shaped[] | select(.ent.id == null) ]
    | group_by(.coll) | map(
        (.[0].coll | if . == "business_rules" then "business_rule" else "workflow" end) as $t
        | sort_by([(.ent.name | slug), .ent.name, (.ent.provenance[0].path // ""), (.ent.provenance[0].line // 0), (.ent.statement // "")])
        | group_by(.ent.name | slug)
        | map(to_entries | map(.key as $k | .value | .ent.id = "\($t):\(.ent.name | slug)" + (if $k > 0 then "-\($k + 1)" else "" end))) | add)
    | add // [] ) as $slugged
| ([ $shaped[] | select(.ent.id != null) ] + $slugged) as $all
# 3) local-id -> final-id map (draft may reference by local id or by already-correct final id)
| (reduce $all[] as $e ({}; if $e.local != null then .[$e.local] = $e.ent.id else . end)
   + reduce $all[] as $e ({}; .[$e.ent.id] = $e.ent.id)) as $idmap
| def remap: . as $r | ($idmap[$r] // $r);
# 4) merge duplicates, remap refs, sort
  ( $colls | map(. as $c | {key: $c, value: (
      [ $all[] | select(.coll == $c) | .ent ] | group_by(.id) | map(merge_group)
      | map(if $c == "business_rules" and has("applies_to") then .applies_to |= (map(remap) | unique) else . end)
      | map(if $c == "workflows" then .steps |= map(if has("entity_id") then .entity_id |= remap else . end) else . end)
      | sort_by(.id)) }) | from_entries | with_entries(select(.value | length > 0)) ) as $entities
| ( [ ($draft.relations // [])[] | select(.from and .to and .kind)
      | {from: (.from | remap), to: (.to | remap), kind} + claim_fields ]
    | group_by([.from, .to, .kind]) | map(merge_group) | sort_by([.from, .kind, .to]) ) as $relations
| ([ $entities[][], $relations[] ]) as $claims
| {confirmed: ([$claims[] | select(.confidence == "confirmed")] | length),
   inferred:  ([$claims[] | select(.confidence == "inferred")]  | length),
   unknown:   ([$claims[] | select(.confidence == "unknown")]   | length)} as $n
| ($n + {overall: (if ($claims | length) == 0 then "unknown"
                   elif $n.inferred == 0 and $n.unknown == 0 then "confirmed"
                   elif $n.unknown > ($n.confirmed + $n.inferred) then "unknown"
                   else "inferred" end)}) as $summary
| {artifact: ({ckb_version: "0.1", repo: $repo, generator: $generator, confidence_summary: $summary, entities: $entities}
              + (if ($relations | length) > 0 then {relations: $relations} else {} end)),
   warnings: ([ $colls[] as $c | ($draft.entities[$c] // [])[] | select(downgraded) | "downgraded to unknown (no valid provenance): \($c)/\(.id // .name)" ]
              + [ ($draft.relations // [])[] | select(downgraded) | "downgraded to unknown (no valid provenance): relation \(.from) -> \(.to)" ]
              + [ ($draft.relations // [])[] | select((.from and .to and .kind) | not) | "dropped malformed relation" ])}
