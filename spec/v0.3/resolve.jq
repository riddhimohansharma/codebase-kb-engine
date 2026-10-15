# resolve.jq — CKB v0.3 normative cross-repo link resolution. Reference semantics for any consumer: N artifacts in, link records out.
# Use:  jq -s -L schema/v0.3 -f schema/v0.3/resolve.jq a/.ckb/ckb.json b/.ckb/ckb.json ...     (input: a JSON array of artifacts)
# Output: {links: [...], unresolved: [...]} sorted deterministically. A conformant consumer produces the same set (compare after sorting).
# Link record: {kind, src, dst, key, confidence, status}; src/dst are global IRIs (ckb://<repo.key>/<entity_id>).
#   status: "resolved" (exactly one provider repo) | "ambiguous" (several provider repos: one record per candidate).
#   confidence = the weaker of the two claims (unknown < inferred < confirmed).
# Join keys (README "Provider side"): purl · host==service_key + METHOD + normalized_path (path params match any param) · event transport+topic ·
#   rpc protocol+service+method · datastore engine+instance_key+name · external domain. Links never connect a repo to itself.
include "derive";
def rank: {unknown: 0, inferred: 1, confirmed: 2}[.] // 0;
def minconf($a; $b): if ($a | rank) <= ($b | rank) then $a else $b end;
def segs: split("/") | map(select(. != ""));
def is_param: test("^\\{.*\\}$") or test("^:") ;
def path_eq($a; $b): ($a | segs) as $x | ($b | segs) as $y
  | ($x | length) == ($y | length) and ([range(0; $x | length)] | all(. as $i | ($x[$i] == $y[$i]) or ($x[$i] | is_param) or ($y[$i] | is_param)));
def ifc_key: if .kind == "http" then "\(.http.method | ascii_upcase) \(.http.normalized_path)"
  elif .kind == "websocket" then .websocket.normalized_path
  elif .kind == "event" then "\(.event.transport):\(.event.topic)"
  elif .kind == "rpc" then "\(.rpc.protocol):\(.rpc.service)/\(.rpc.method)" else null end;

. as $arts
| [ $arts | to_entries[] | .key as $n | .value as $a | ($a.repo | ckb_repo_key) as $rk
    | {n: $n, rk: $rk, a: $a} ] as $repos
| ([ $repos[] | . as $r | ($r.a.entities.interfaces[]? | select(.role == "provides") | {rk: $r.rk, e: .})]) as $providers
| ([ $repos[] | . as $r | ($r.a.entities.interfaces[]? | select(.role == "consumes") | {rk: $r.rk, e: .})]) as $consumers
| ([ $repos[] | . as $r | ($r.a.entities.artifacts[]? | {rk: $r.rk, e: .})]) as $artifacts
| def emit($kind; $c; $p; $key): {drk: $p.rk, kind: $kind, src: ckb_iri($c.rk; $c.e.id), dst: ckb_iri($p.rk; $p.e.id), key: $key, confidence: minconf($c.e.confidence; $p.e.confidence)};
  def group_status($cands): ($cands | map(.drk) | unique | length) as $nrepos | $cands | map(. + {status: (if $nrepos == 1 then "resolved" else "ambiguous" end)});

  # dependency -> artifact (equal versionless purl)
  ( [ $repos[] | . as $r | $r.a.entities.dependencies[]? | {rk: $r.rk, e: .} ] | map(. as $d
      | [ $artifacts[] | select(.e.purl == $d.e.purl and .rk != $d.rk) | emit("depends_on_artifact"; $d; .; $d.e.purl) ] | group_status(.)) | add // [] ) as $dep_links
| # http / websocket: host == service_key, then method + path
  ( [ $consumers[] | select(.e.kind == "http") | . as $c
      | [ $providers[] | select(.e.kind == "http" and .rk != $c.rk and .e.service_key == $c.e.http.host
            and (.e.http.method | ascii_upcase) == ($c.e.http.method | ascii_upcase) and path_eq(.e.http.normalized_path; $c.e.http.normalized_path)) | emit("calls_http"; $c; .; ($c.e | ifc_key)) ]
      | {cands: ., c: $c} ] ) as $http
| ( [ $consumers[] | select(.e.kind == "websocket") | . as $c
      | [ $providers[] | select(.e.kind == "websocket" and .rk != $c.rk and .e.service_key == $c.e.websocket.host and path_eq(.e.websocket.normalized_path; $c.e.websocket.normalized_path)) | emit("calls_websocket"; $c; .; ($c.e | ifc_key)) ]
      | {cands: ., c: $c} ] ) as $ws
| ( [ $consumers[] | select(.e.kind == "rpc") | . as $c
      | [ $providers[] | select(.e.kind == "rpc" and .rk != $c.rk and .e.rpc.protocol == $c.e.rpc.protocol and .e.rpc.service == $c.e.rpc.service and .e.rpc.method == $c.e.rpc.method) | emit("calls_rpc"; $c; .; ($c.e | ifc_key)) ]
      | {cands: ., c: $c} ] ) as $rpc
| ( [ $consumers[] | select(.e.kind == "event") | . as $c
      | [ $providers[] | select(.e.kind == "event" and .rk != $c.rk and .e.event.transport == $c.e.event.transport and .e.event.topic == $c.e.event.topic) | emit("subscribes_event"; $c; .; ($c.e | ifc_key)) ]
      | {cands: ., c: $c} ] ) as $ev
| ( $http + $ws + $rpc + $ev ) as $calls
| ( $calls | map(select(.cands | length > 0) | group_status(.cands)) | add // [] ) as $call_links
| ( $calls | map(select(.cands | length == 0) | {kind: (.c.e.kind | if . == "event" then "subscribes_event" elif . == "rpc" then "calls_rpc" elif . == "websocket" then "calls_websocket" else "calls_http" end), src: ckb_iri(.c.rk; .c.e.id), key: (.c.e | ifc_key), reason: "no provider among the given artifacts"})) as $unresolved
| # shared datastores / externals: same key in >1 repo (membership edges between every pair, ordered by IRI)
  ( [ $repos[] | . as $r | $r.a.entities.datastores[]? | {rk: $r.rk, e: ., key: "\(.engine):\(.instance_key // "_"):\(.schema // "")\(if .schema and .table then "." else "" end)\(.table // .name // "")"} ]
    | group_by(.key) | map(select((map(.rk) | unique | length) > 1) | . as $g | [range(0; length)] as $ix
        | [ $ix[] as $i | $ix[] as $j | select($i < $j and $g[$i].rk != $g[$j].rk)
            | ([ckb_iri($g[$i].rk; $g[$i].e.id), ckb_iri($g[$j].rk; $g[$j].e.id)] | sort) as $pr | {kind: "shares_datastore", src: $pr[0], dst: $pr[1], key: $g[$i].key, confidence: minconf($g[$i].e.confidence; $g[$j].e.confidence), status: "resolved"} ]) | add // [] ) as $store_links
| ( [ $repos[] | . as $r | $r.a.entities.external_services[]? | {rk: $r.rk, e: ., key: .domain} ]
    | group_by(.key) | map(select((map(.rk) | unique | length) > 1) | . as $g | [range(0; length)] as $ix
        | [ $ix[] as $i | $ix[] as $j | select($i < $j and $g[$i].rk != $g[$j].rk)
            | ([ckb_iri($g[$i].rk; $g[$i].e.id), ckb_iri($g[$j].rk; $g[$j].e.id)] | sort) as $pr | {kind: "shares_external", src: $pr[0], dst: $pr[1], key: $g[$i].key, confidence: minconf($g[$i].e.confidence; $g[$j].e.confidence), status: "resolved"} ]) | add // [] ) as $ext_links
| {links: (($dep_links + $call_links + $store_links + $ext_links) | map(del(.drk)) | unique_by([.kind, .src, .dst]) | sort_by([.kind, .src, .dst])),
   unresolved: ($unresolved | sort_by([.kind, .src]))}
