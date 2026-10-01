# normalize.jq — turn a model-written CKB draft into a deterministic CKB v0.1 artifact.
# Input: {entities:{...}, relations:[...]} where entity `id`s are local reference keys.
# Args:  $repo (object), $generator (object),
#        $roots (array of absolute repo-root spellings, stripped from absolute citations),
#        $lines (object: repo-relative path -> line count, for every cited file that exists and is not in ckb/)
# Does:  verify citations against real files · drop anything citing/describing ckb/ (R7) · coerce enums ·
#        normalize join keys · derive IDs per spec · merge duplicates · remap/prune references · sort · summarize.
# Output: {artifact, warnings}

# ---------- helpers ----------
def slug: ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("^-+|-+$"; "")
        | if . == "" then null else . end;
def slug_or($s): (slug) // ("u-" + ($s | explode | .[0:8] | map(tostring) | join("-")));
def snake: gsub("(?<a>[a-z0-9])(?<b>[A-Z])"; "\(.a)_\(.b)") | ascii_downcase | gsub("[^a-z0-9_]+"; "_") | gsub("^_+|_+$"; "")
         | if . == "" then "param" elif test("^[a-z_]") then . else "p_" + . end;
def rank: {"confirmed": 0, "inferred": 1, "unknown": 2}[.] // 2;
def nonempty: select(. != null and . != "");
def in_kb: (. // "" | tostring | sub("^\\./"; "")) as $q | ($q == "ckb" or ($q | startswith("ckb/")));
def key: tostring | ascii_downcase | gsub("[ _]+"; "-");
# coerce a free-text enum value: exact → alias → default
def coerce($allowed; $aliases; $default): (. // "" | key) as $v
  | if ($allowed | index([$v])) then $v elif $aliases[$v] then $aliases[$v] else $default end;
def enum_ok($allowed; $aliases): (. // "" | key) as $v | ($allowed | index([$v])) or ($aliases[$v] != null);

def E_COMP:  ["service","library","module","cli","ui","job","other"];
def A_COMP:  {"app":"service","application":"service","api":"service","server":"service","microservice":"service","backend":"service","web-service":"service","package":"library","lib":"library","sdk":"library","frontend":"ui","web":"ui","client":"ui","worker":"job","cron":"job","batch":"job","scheduler":"job","lambda":"job","command":"cli","tool":"cli","script":"cli","config":"other","infra":"other","infrastructure":"other","test":"other","tests":"other"};
def E_IKIND: ["http","event","rpc","cli","library"];
def A_IKIND: {"rest":"http","api":"http","route":"http","endpoint":"http","https":"http","webhook":"http","graphql":"rpc","grpc":"rpc","thrift":"rpc","json-rpc":"rpc","jsonrpc":"rpc","message":"event","queue":"event","topic":"event","kafka":"event","pubsub":"event","stream":"event","command":"cli","sdk":"library","function":"library","export":"library","module":"library"};
def E_ROLE:  ["provides","consumes"];
def A_ROLE:  {"serves":"provides","exposes":"provides","publishes":"provides","produces":"provides","server":"provides","provider":"provides","implements":"provides","calls":"consumes","uses":"consumes","subscribes":"consumes","client":"consumes","consumer":"consumes","invokes":"consumes","reads":"consumes"};
def E_METH:  ["GET","POST","PUT","PATCH","DELETE","HEAD","OPTIONS","ANY"];
def E_TRANS: ["kafka","sqs","sns","rabbitmq","pubsub","eventbridge","nats","redis","webhook","other"];
def A_TRANS: {"amazon-sqs":"sqs","aws-sqs":"sqs","amazon-sns":"sns","aws-sns":"sns","google-pubsub":"pubsub","gcp-pubsub":"pubsub","pub/sub":"pubsub","rabbit":"rabbitmq","amqp":"rabbitmq","redis-streams":"redis","redis-pubsub":"redis","event-bridge":"eventbridge","http":"webhook","https":"webhook","msk":"kafka","confluent":"kafka"};
def E_RPC:   ["grpc","thrift","jsonrpc","graphql","other"];
def A_RPC:   {"json-rpc":"jsonrpc","gql":"graphql","protobuf":"grpc"};
def E_SCOPE: ["runtime","dev","build","test","peer","optional"];
def A_SCOPE: {"dependencies":"runtime","prod":"runtime","production":"runtime","compile":"runtime","main":"runtime","implementation":"runtime","api":"runtime","require":"runtime","install-requires":"runtime","devdependencies":"dev","development":"dev","dev-dependencies":"dev","testimplementation":"test","testing":"test","test-dependencies":"test","peerdependencies":"peer","optionaldependencies":"optional","extras":"optional","provided":"build","plugin":"build","build-dependencies":"build","tooling":"build"};
def E_ENG:   ["postgres","mysql","sqlite","mssql","oracle","mongodb","dynamodb","redis","elasticsearch","s3","gcs","filesystem","other"];
def A_ENG:   {"postgresql":"postgres","pg":"postgres","psql":"postgres","aurora-postgres":"postgres","mariadb":"mysql","aurora-mysql":"mysql","mongo":"mongodb","documentdb":"mongodb","dynamo":"dynamodb","elastic":"elasticsearch","opensearch":"elasticsearch","sql-server":"mssql","sqlserver":"mssql","file":"filesystem","fs":"filesystem","local":"filesystem","disk":"filesystem","cloud-storage":"gcs","google-cloud-storage":"gcs","minio":"s3","aws-s3":"s3","memcached":"other","cassandra":"other"};
def E_ACC:   ["read","write","readwrite"];
def A_ACC:   {"rw":"readwrite","read-write":"readwrite","read/write":"readwrite","both":"readwrite","all":"readwrite","crud":"readwrite","r":"read","select":"read","query":"read","read-only":"read","w":"write","insert":"write","update":"write","delete":"write","write-only":"write"};
def E_REL:   ["contains","calls","provides","consumes","depends_on","reads","writes","publishes","subscribes","enforces"];
def A_REL:   {"depends-on":"depends_on","uses":"depends_on","requires":"depends_on","imports":"depends_on","invokes":"calls","call":"calls","requests":"calls","implements":"provides","exposes":"provides","serves":"provides","emits":"publishes","produces":"publishes","sends":"publishes","listens":"subscribes","receives":"subscribes","queries":"reads","selects":"reads","loads":"reads","persists":"writes","stores":"writes","inserts":"writes","updates":"writes","saves":"writes","has":"contains","includes":"contains","owns":"contains","validates":"enforces","guards":"enforces","checks":"enforces"};
def SQL_ENGINES: ["postgres","mysql","sqlite","mssql","oracle"];

# ---------- paths & provenance ----------
def rel_path: (. // "" | tostring) as $p
  | ([$roots[] | select(. != "" and ($p | startswith(. + "/")))] | first) as $r
  | (if $r then $p[($r | length) + 1:] else $p end) | sub("^(\\./)+"; "");
def valid_prov: [.provenance[]? | select(type == "object") | (.path | rel_path) as $rp
                   | select(($rp | startswith("/") | not) and ($rp | test("(^|/)\\.\\.(/|$)") | not) and ($rp | in_kb | not))
                   | select($lines[$rp] != null)                                          # file must exist in the repo
                   | select((.line | type) == "number" and .line >= 1 and .line <= ($lines[$rp] + 1))   # line must exist
                   | {path: $rp, line: (.line | floor)} + (if (.end_line|type) == "number" and .end_line >= .line then {end_line: ([(.end_line|floor), ($lines[$rp] + 1)] | min)} else {} end)]
                | unique_by([.path, .line, .end_line]) | sort_by([.path, .line, (.end_line // 0)]);
# claims without verifiable provenance are downgraded to `unknown` (spec: provenance mandatory unless unknown)
def claim_fields: valid_prov as $p
  | ((.confidence // "unknown") | tostring | ascii_downcase | if IN("confirmed","inferred","unknown") then . else "unknown" end) as $c
  | {confidence: (if $p == [] then "unknown" else $c end), provenance: $p};
def downgraded: ((.confidence // "") | tostring | ascii_downcase | IN("confirmed","inferred")) and (valid_prov == []);

# ---------- join keys ----------
def norm_path:
  (. // "/" | tostring | gsub("^\\s+|\\s+$"; ""))
  | sub("^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]*"; "")                  # absolute URL: drop scheme+host (host kept separately)
  | sub("^(\\$\\{[^}]*\\}|\\{\\{[^}]*\\}\\}|%s|<[^>]*>)(?=/|$)"; "") # leading host placeholder: ${BASE_URL}/x, {{host}}/x
  | (split("?")[0] | split("#")[0])
  | split("/") | map(select(. != ""))
  | map(
      if   test("^\\[\\[?\\.\\.\\.(?<p>[^\\]]+)\\]\\]?$") then "{" + (capture("\\.\\.\\.(?<p>[^\\]]+)").p | snake) + "}"   # Next.js [...slug]
      elif test("^\\[(?<p>[^\\]]+)\\]$")                  then "{" + (capture("^\\[(?<p>[^\\]]+)\\]$").p | snake) + "}" # Next.js [id]
      elif test("^:(?<p>[A-Za-z0-9_]+)(\\(.*\\))?\\??$")   then "{" + (capture("^:(?<p>[A-Za-z0-9_]+)").p | snake) + "}"  # express :id / :id(\\d+)
      elif test("^<([^:>]+:)?(?<p>[A-Za-z0-9_]+)>$")      then "{" + (capture("^<([^:>]+:)?(?<p>[A-Za-z0-9_]+)>$").p | snake) + "}" # flask <int:id>
      elif test("^\\{(?<p>[A-Za-z0-9_]+)(:[^}]*)?\\}$")   then "{" + (capture("^\\{(?<p>[A-Za-z0-9_]+)").p | snake) + "}" # {id} / {id:int}
      elif test("^\\$\\{(?<p>[^}]+)\\}$")                  then "{" + (capture("^\\$\\{(?<p>[^}]+)\\}$").p | split(".") | last | snake) + "}" # ${req.params.id}
      elif test("^\\$(?<p>[A-Za-z0-9_]+)$")               then "{" + (capture("^\\$(?<p>[A-Za-z0-9_]+)$").p | snake) + "}"  # $id
      elif test("^(\\*+|\\(\\.\\*\\)|\\.\\*)$")            then "{wildcard}"
      elif test("^[0-9]+$") or test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$") then "{id}"   # literal ids
      else gsub("[^A-Za-z0-9._~-]"; "-") end)
  | "/" + join("/");
def url_host: (. // "" | tostring) as $u
  | if ($u | test("^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]+")) then ($u | capture("^[a-zA-Z][a-zA-Z0-9+.-]*://(?<h>[^/]+)").h)
    elif ($u | test("^\\$\\{[^}]+\\}(/|$)")) then ($u | capture("^\\$\\{(?<h>[^}]+)\\}").h | split(".") | last)
    elif ($u | test("^\\{\\{[^}]+\\}\\}(/|$)")) then ($u | capture("^\\{\\{\\s*(?<h>[^} ]+)").h)
    else null end;

def PKG_RE: "^(npm:(@[a-z0-9._~-]+/)?[a-z0-9._~-]+|pypi:[a-z0-9]+([._-][a-z0-9]+)*|maven:[A-Za-z0-9._-]+:[A-Za-z0-9._-]+|go:[^\\s]+|cargo:[a-z0-9_-]+|nuget:[A-Za-z0-9._-]+|gem:[A-Za-z0-9._-]+|other:[^\\s]+)$";
def eco_from_manifest: (. // "" | split("/") | last) as $b
  | if   $b == "package.json" then "npm"
    elif ($b | test("^(requirements.*\\.txt|pyproject\\.toml|setup\\.py|setup\\.cfg|Pipfile)$")) then "pypi"
    elif $b == "go.mod" then "go" elif $b == "Cargo.toml" then "cargo" elif ($b | test("^Gemfile")) then "gem"
    elif ($b | test("\\.csproj$|^packages\\.config$|\\.fsproj$")) then "nuget"
    elif ($b | test("^pom\\.xml$|^build\\.gradle(\\.kts)?$|^ivy\\.xml$")) then "maven"
    else null end;
def strip_ver($eco):
  if $eco == "npm" then (if startswith("@") then "@" + (.[1:] | sub("@.*$"; "")) else sub("@.*$"; "") end)
  elif $eco == "pypi" then sub("\\[.*$"; "") | sub("[<>=!~;\\s].*$"; "")
  elif $eco == "maven" then split(":") | .[0:2] | join(":")
  elif $eco == "go" then sub("@.*$"; "") | sub("\\s.*$"; "")
  else sub("[@\\s].*$"; "") end;
def norm_pkg($name; $manifest):
  (. // "" | tostring | gsub("^\\s+|\\s+$"; "")) as $raw
  | (if ($raw | test("^[a-z]+:")) then ($raw | capture("^(?<e>[a-z]+):(?<n>.*)$")) else {e: ($manifest | eco_from_manifest), n: (if $raw == "" then ($name // "") else $raw end)} end) as $k
  | ($k.n | strip_ver($k.e)) as $n
  | (if   $k.e == "npm"   then "npm:" + ($n | ascii_downcase)
     elif $k.e == "pypi"  then "pypi:" + ($n | ascii_downcase | gsub("[-_.]+"; "-"))
     elif $k.e == "cargo" then "cargo:" + ($n | ascii_downcase)
     elif $k.e == null or $k.e == "" then "other:" + ($n | ascii_downcase | gsub("\\s+"; "-"))
     else "\($k.e):\($n)" end) as $key
  | if ($key | test(PKG_RE)) then $key else "other:" + ((($n | slug) // "unknown")) end;

# ---------- shaping ----------
def base_fields: {name: ((.name // .id // "unnamed") | tostring)} + (if (.description|type) == "string" then {description} else {} end) + claim_fields;
def pick(keys): . as $o | reduce keys[] as $k ({}; if ($o[$k] | . != null and . != "") then .[$k] = ($o[$k] | tostring) else . end);

def shape($coll):
  if $coll == "components" then base_fields
     + {module_id: ((.module_id // "") | rel_path | sub("/+$"; "") | if . == "" then "." else . end), kind: (.kind | coerce(E_COMP; A_COMP; "other"))} + pick(["language"])
  elif $coll == "interfaces" then
    (.kind // "" | key) as $rk
    | (if ($rk | IN("graphql","grpc","thrift","jsonrpc","json-rpc")) then ($rk | coerce(E_RPC; A_RPC; "other")) else null end) as $proto
    | (.kind | coerce(E_IKIND; A_IKIND; "library")) as $k
    | base_fields + {kind: $k, role: (.role | coerce(E_ROLE; A_ROLE; "provides"))}
    + (if $k == "http" then
         ((.http // {}) | . as $h | ($h.normalized_path // $h.path // $h.url // "/")) as $p
         | {http: ({method: ((.http.method // "ANY") | tostring | ascii_upcase | . as $m | if IN("ALL","*","USE","") then "ANY" elif (E_METH | index([$m])) then $m else "ANY" end),
                    normalized_path: ($p | norm_path)}
                   + (((.http.host // ($p | url_host)) | nonempty | {host: tostring}) // {}))}
       elif $k == "event" then {event: {transport: ((.event.transport // "other") | coerce(E_TRANS; A_TRANS; "other")),
                                        topic: ((.event.topic // .name // "unknown") | tostring)}}
       elif $k == "rpc" then {rpc: {protocol: ((.rpc.protocol // $proto // "other") | coerce(E_RPC; A_RPC; "other")),
                                    service: ((.rpc.service // .name // "unknown") | tostring), method: ((.rpc.method // "unknown") | tostring)}}
       else {symbol: ((.symbol // .name // "unknown") | tostring)} end)
  elif $coll == "dependencies" then
    (.name // null) as $nm | ((.provenance // [])[0].path? // null) as $mf
    | base_fields + {package_key: (.package_key | norm_pkg($nm; $mf)), scope: (.scope | coerce(E_SCOPE; A_SCOPE; "runtime"))} + pick(["version_constraint"])
  elif $coll == "datastores" then
    ((.engine | coerce(E_ENG; A_ENG; "other"))) as $e
    | base_fields + {engine: $e, access: (.access | coerce(E_ACC; A_ACC; "readwrite"))}
      + (pick(["schema","table"]) | if (SQL_ENGINES | index([$e])) then map_values(ascii_downcase) else . end)
  elif $coll == "business_rules" then base_fields + {statement: ((.statement // .name // "unspecified") | tostring)} + (if (.applies_to|type) == "array" then {applies_to: [.applies_to[] | tostring]} else {} end)
  elif $coll == "workflows" then base_fields + pick(["trigger"])
       + {steps: ([.steps[]? | select(type == "object") | {description: ((.description // .name // "step") | tostring)} + pick(["entity_id"]) + {o: (.order // 1e9)}]
                  | sort_by(.o) | to_entries | map(.value | del(.o)) | to_entries | map(.value + {order: (.key + 1)})
                  | if length == 0 then [{order: 1, description: "unspecified"}] else . end)}
  else base_fields end;

def derive_id($coll):
  if   $coll == "components"   then "component:" + .module_id
  elif $coll == "dependencies" then "dependency:" + .package_key
  elif $coll == "datastores"   then "datastore:" + .engine
       + ([.schema, .table | nonempty] | if length > 0 then ":" + join(".") else ":" + ((.name | slug) // "unnamed") end)
  elif $coll == "interfaces" then
    if   .kind == "http"  then "interface:http:\(.role):\(.http.method):\(.http.normalized_path)"
    elif .kind == "event" then "interface:event:\(.role):\(.event.transport):\(.event.topic)"
    elif .kind == "rpc"   then "interface:rpc:\(.role):\(.rpc.service)/\(.rpc.method)"
    else "interface:\(.kind):\(.role):\(.symbol)" end
  else null end;   # business_rules / workflows: slug + collision suffix, assigned below

def merge_group: (sort_by(.confidence | rank) | .[0]) as $best
  | $best + {provenance: ([.[].provenance[]] | unique_by([.path, .line, .end_line]) | sort_by([.path, .line, (.end_line // 0)]))};

# ---------- pipeline ----------
. as $draft
| ["components","interfaces","dependencies","datastores","business_rules","workflows"] as $colls
# 1) shape + derive IDs, keeping the draft's local id for reference remapping
| [ $colls[] as $c | ($draft.entities[$c] // [])[] | select(type == "object")
    | select($c != "components" or (.module_id | rel_path | in_kb | not))
    | {coll: $c, local: ((.id // null) | if . == null then null else tostring end), ent: shape($c)} | .ent.id = (.ent | derive_id($c)) ] as $shaped
# 2) slug IDs for rules/workflows; collisions suffixed in (slug, name, first provenance, statement) order — independent of draft order
| ( [ $shaped[] | select(.ent.id == null) ]
    | group_by(.coll) | map(
        (.[0].coll | if . == "business_rules" then "business_rule" else "workflow" end) as $t
        | map(.ent.name as $n | .s = ($n | slug_or($n)))
        | sort_by([.s, .ent.name, (.ent.provenance[0].path // ""), (.ent.provenance[0].line // 0), (.ent.statement // "")])
        | group_by(.s)
        | map(to_entries | map(.key as $k | .value | .ent.id = "\($t):\(.s)" + (if $k > 0 then "-\($k + 1)" else "" end) | del(.s))) | add)
    | add // [] ) as $slugged
| ([ $shaped[] | select(.ent.id != null) ] + $slugged) as $all
| ([ $all[].ent.id ] | unique) as $final_ids
# 3) local-id -> final-id map; a local id used for different final entities is ambiguous and never mapped
| ([ $all[] | select(.local != null) ] | group_by(.local)
   | map({key: .[0].local, value: ([.[].ent.id] | unique)})) as $locals
| ([ $locals[] | select(.value | length > 1) | .key ]) as $ambiguous
| ((reduce ($locals[] | select(.value | length == 1)) as $l ({}; .[$l.key] = $l.value[0]))
   + reduce $final_ids[] as $f ({}; .[$f] = $f)) as $idmap
| def remap: . as $r | $idmap[$r];      # null when unresolved
# 4) merge duplicates, remap + prune refs, sort
  ( $colls | map(. as $c | {key: $c, value: (
      [ $all[] | select(.coll == $c) | .ent ] | group_by(.id) | map(merge_group)
      | map(if $c == "business_rules" and has("applies_to") then .applies_to |= ([.[] | remap | nonempty] | unique) | (if .applies_to == [] then del(.applies_to) else . end) else . end)
      | map(if $c == "workflows" then .steps |= map(if has("entity_id") then (.entity_id | remap) as $m | (if $m then .entity_id = $m else del(.entity_id) end) else . end) else . end)
      | sort_by(.id)) }) | from_entries | with_entries(select(.value | length > 0)) ) as $entities
| ( [ ($draft.relations // [])[] | select(type == "object" and .from and .to and .kind)
      | select(.kind | enum_ok(E_REL; A_REL))
      | {from: (.from | tostring | remap), to: (.to | tostring | remap), kind: (.kind | coerce(E_REL; A_REL; "depends_on"))} + claim_fields
      | select(.from != null and .to != null) ]
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
   warnings: ([ $colls[] as $c | ($draft.entities[$c] // [])[] | select(type == "object") | select(downgraded) | "downgraded to unknown (no verifiable provenance): \($c)/\(.id // .name)" ]
              + [ ($draft.relations // [])[] | select(type == "object") | select(downgraded) | "downgraded to unknown (no verifiable provenance): relation \(.from) -> \(.to)" ]
              + [ ($draft.relations // [])[] | select(type != "object" or ((.from and .to and .kind) | not)) | "dropped malformed relation" ]
              + [ ($draft.relations // [])[] | select(type == "object" and .kind and (.kind | enum_ok(E_REL; A_REL) | not)) | "dropped relation with unknown kind '\(.kind)': \(.from) -> \(.to)" ]
              + [ ($draft.relations // [])[] | select(type == "object" and .from and .to) | select(((.from|tostring|remap) == null) or ((.to|tostring|remap) == null)) | "dropped relation with unresolved endpoint: \(.from) -> \(.to)" ]
              + [ ($draft.entities.business_rules // [])[] | .applies_to[]? | tostring | select(remap == null) | "dropped unresolved applies_to reference: \(.)" ]
              + [ ($draft.entities.workflows // [])[] | .steps[]? | .entity_id? // empty | tostring | select(remap == null) | "dropped unresolved workflow step reference: \(.)" ]
              + [ $ambiguous[] | "local id '\(.)' names more than one entity; references to it were dropped" ]
              + [ $colls[] as $c | ($draft.entities[$c] // [])[] | select(type == "object")
                  | (if $c == "components" then [["kind", .kind, E_COMP, A_COMP]] elif $c == "interfaces" then [["kind", .kind, E_IKIND, A_IKIND], ["role", .role, E_ROLE, A_ROLE]]
                     elif $c == "dependencies" then [["scope", .scope, E_SCOPE, A_SCOPE]] elif $c == "datastores" then [["engine", .engine, E_ENG, A_ENG], ["access", .access, E_ACC, A_ACC]] else [] end)[]
                  | . as $t | select($t[1] != null and ($t[1] | enum_ok($t[2]; $t[3]) | not)) | "unrecognised \($c) \(.[0]) '\(.[1])' coerced to default" ]
              + [ $entities.datastores[]? | select(.id | test(":[^:]*$")) | . as $d | select(([$all[] | select(.ent.id == $d.id) | .ent.name] | unique | length) > 1) | "merged differently-named datastores into \(.id)" ]
              | unique)}
