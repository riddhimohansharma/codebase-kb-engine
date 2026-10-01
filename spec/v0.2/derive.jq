# derive.jq — CKB v0.2 normative entity-ID derivation. Single source of truth:
# used by the spec's semantic rule R8 and by producers. Include with: include "derive"; (jq -L <dir>)
# ckb_derive_id($coll): input = one entity object of collection $coll; output = its id (null for business_rules/workflows,
# whose ids are content slugs assigned by the producer and only prefix-checked).

def ckb_slug: ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("^-+|-+$"; "");

def ckb_derive_id($coll):
  . as $e
  | if   $coll == "components"        then "component:" + $e.module_id
    elif $coll == "dependencies"      then "dependency:" + $e.purl + "@" + $e.manifest_path
    elif $coll == "artifacts"         then "artifact:" + $e.purl
    elif $coll == "services"          then "service:" + $e.service_key
    elif $coll == "config_keys"       then "config:" + $e.source + ":" + $e.name
    elif $coll == "external_services" then "external:" + $e.domain
    elif $coll == "api_specs"         then "api_spec:" + $e.path
    elif $coll == "datastores" then
      "datastore:" + $e.engine + ":" + (($e.instance_key // "") | if . == "" then "_" else . end) + ":"
      + ([$e.schema, $e.table] | map(select(. != null and . != "")) | if length > 0 then join(".") else (($e.name // "") | ckb_slug | if . == "" then "unnamed" else . end) end)
    elif $coll == "interfaces" then
      ( if $e.role == "provides" then ($e.service_key // "") else ($e.http.host // $e.websocket.host // "") end
        | if . == "" then "_" else . end ) as $p
      | if   $e.kind == "http"      then "interface:http:\($e.role):\($p):\($e.http.method):\($e.http.normalized_path)"
        elif $e.kind == "websocket" then "interface:websocket:\($e.role):\($p):\($e.websocket.normalized_path)"
        elif $e.kind == "event"     then "interface:event:\($e.role):\($e.event.transport):\($e.event.topic)"
        elif $e.kind == "rpc"       then "interface:rpc:\($e.role):\($e.rpc.protocol):\($e.rpc.service)/\($e.rpc.method)"
        else "interface:\($e.kind):\($e.role):\($e.symbol)" end
    else null end;

# Allowed relation triples (R10): kind -> {from: [prefixes], to: [prefixes]}
def ckb_relation_rules: {
  "contains":      {from: ["component"], to: ["component"]},
  "imports":       {from: ["component"], to: ["component"]},
  "depends_on":    {from: ["component"], to: ["dependency", "component"]},
  "provides":      {from: ["component"], to: ["interface"]},
  "consumes":      {from: ["component"], to: ["interface"]},
  "calls":         {from: ["component"], to: ["interface"]},
  "reads":         {from: ["component", "interface"], to: ["datastore"]},
  "writes":        {from: ["component", "interface"], to: ["datastore"]},
  "publishes":     {from: ["component"], to: ["interface"]},
  "subscribes":    {from: ["component"], to: ["interface"]},
  "enforces":      {from: ["component", "interface"], to: ["business_rule"]},
  "builds":        {from: ["component"], to: ["artifact"]},
  "deploys_as":    {from: ["component"], to: ["service"]},
  "exposes":       {from: ["service"], to: ["interface"]},
  "configured_by": {from: ["component", "service", "interface", "datastore"], to: ["config"]},
  "uses_external": {from: ["component", "interface"], to: ["external"]},
  "specified_by":  {from: ["interface"], to: ["api_spec"]}
};
def ckb_prefix: split(":")[0];
