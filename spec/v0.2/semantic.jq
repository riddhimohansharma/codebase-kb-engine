# CKB v0.2 semantic rules that JSON Schema cannot express.
# Run with: jq -L schema/v0.2 -f schema/v0.2/semantic.jq ckb.json
# Output: array of violation strings (empty = pass). Each string starts with its rule code (R1..R12).
include "derive";
def coll_prefix: {components:"component", interfaces:"interface", dependencies:"dependency", datastores:"datastore", business_rules:"business_rule", workflows:"workflow", artifacts:"artifact", services:"service", config_keys:"config", external_services:"external", api_specs:"api_spec"};
def ids: [.entities[]?[]?.id];
def claims: [.entities[]?[]?, .relations[]?];
def in_kb: . == "ckb" or startswith("ckb/");
. as $a
| (ids) as $ids
| ([$a.entities.interfaces[]? | {key: .id, value: .}] | from_entries) as $ifaces
| [
    # R1: entity ids unique across the artifact
    ($ids | group_by(.) | map(select(length > 1) | "R1 duplicate id: \(.[0])") | .[]),
    # R2: id prefix matches its collection
    (($a.entities // {}) | to_entries[] | .key as $k | .value[] | select((.id | ckb_prefix) != coll_prefix[$k]) | "R2 id \(.id) not prefixed \(coll_prefix[$k]):"),
    # R3: every reference resolves to an entity in this artifact
    ([$a.relations[]? | .from, .to] + [$a.entities.business_rules[]?.applies_to[]?] + [$a.entities.workflows[]?.steps[]?.entity_id // empty]
      | map(select(. as $r | $ids | index($r) | not)) | unique | map("R3 dangling reference: \(.)") | .[]),
    # R4: confidence_summary counts equal actual claim counts (entities + relations)
    (claims as $c | ["confirmed", "inferred", "unknown"][] as $lvl
      | ($c | map(select(.confidence == $lvl)) | length) as $n
      | select($a.confidence_summary[$lvl] != $n)
      | "R4 confidence_summary.\($lvl)=\($a.confidence_summary[$lvl]) but counted \($n)"),
    # R5: workflow step order is 1..n without gaps or duplicates
    ($a.entities.workflows[]? | select(([.steps[].order] | sort) != [range(1; (.steps | length) + 1)]) | "R5 workflow \(.id) step order not 1..n"),
    # R6: end_line >= line
    (claims[] | .provenance[]? | select(.end_line != null and .end_line < .line) | "R6 end_line < line at \(.path)"),
    # R7: nothing cites or describes the KB directory itself (no self-contamination)
    (claims[] | .provenance[]? | select(.path | in_kb) | "R7 provenance cites the KB directory: \(.path)"),
    ($a.entities.components[]? | select(.module_id | in_kb) | "R7 component inside the KB directory: \(.id)"),
    (($a.entities.dependencies[]?, $a.entities.artifacts[]?) | select(.manifest_path | in_kb) | "R7 manifest_path inside the KB directory: \(.id)"),
    ($a.entities.api_specs[]? | select(.path | in_kb) | "R7 api_spec inside the KB directory: \(.id)"),
    # R8: id equals the normative derivation (derive.jq) for every collection except business_rules/workflows
    (($a.entities // {}) | to_entries[] | select(.key != "business_rules" and .key != "workflows") | .key as $k
      | .value[] | ckb_derive_id($k) as $want | select(.id != $want) | "R8 \($k) id \(.id) != derived \($want)"),
    # R10: (from-type, kind, to-type) is an allowed triple; provides/consumes/calls match interface.role;
    #      publishes/subscribes target an event or websocket interface
    ($a.relations[]? | . as $r
      | ckb_relation_rules[$r.kind] as $rule
      | ($r.from | ckb_prefix) as $fp | ($r.to | ckb_prefix) as $tp
      | if $rule == null then "R10 unknown relation kind: \($r.kind)"
        elif (($rule.from | index($fp)) == null) or (($rule.to | index($tp)) == null)
          then "R10 relation (\($fp), \($r.kind), \($tp)) not allowed: \($r.from) -> \($r.to)"
        else ($ifaces[$r.to]) as $t
          | if $t == null then empty
            elif ($r.kind == "provides") and ($t.role != "provides")
              then "R10 provides edge to interface with role \($t.role): \($r.from) -> \($r.to)"
            elif (($r.kind == "consumes") or ($r.kind == "calls")) and ($t.role != "consumes")
              then "R10 \($r.kind) edge to interface with role \($t.role): \($r.from) -> \($r.to)"
            elif (($r.kind == "publishes") or ($r.kind == "subscribes")) and ((["event", "websocket"] | index($t.kind)) == null)
              then "R10 \($r.kind) edge to \($t.kind) interface (needs event or websocket): \($r.from) -> \($r.to)"
            else empty end
        end),
    # R11: relations unique by (from, kind, to)
    (($a.relations // []) | group_by([.from, .kind, .to]) | map(select(length > 1) | "R11 duplicate relation: \(.[0].from) -\(.[0].kind)-> \(.[0].to)") | .[]),
    # R12: coverage counts are consistent per bucket
    (($a.coverage.buckets // {}) | to_entries[] | .key as $b | .value
      | (select(.cited > .found) | "R12 coverage.\($b): cited=\(.cited) > found=\(.found)"),
        (select((.uncited | length) > .found) | "R12 coverage.\($b): \(.uncited | length) uncited > found=\(.found)"))
  ]
