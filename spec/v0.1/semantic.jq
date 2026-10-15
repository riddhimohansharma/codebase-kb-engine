# CKB v0.1 semantic rules that JSON Schema cannot express.
# Output: array of violation strings (empty = pass).
def ids: [.entities[]?[]?.id];
def prefix_for: {components:"component:",interfaces:"interface:",dependencies:"dependency:",datastores:"datastore:",business_rules:"business_rule:",workflows:"workflow:"};
def claims: [.entities[]?[]?, .relations[]?];
. as $a
| (ids) as $ids
| [
    # R1: entity ids unique across the artifact
    ($ids | group_by(.) | map(select(length > 1) | "R1 duplicate id: \(.[0])") | .[]),
    # R2: id prefix matches its collection
    ($a.entities | to_entries[] | .key as $k | .value[] | select(.id | startswith(prefix_for[$k]) | not) | "R2 id \(.id) not prefixed \(prefix_for[$k])"),
    # R3: every reference resolves to an entity in this artifact
    ([$a.relations[]? | .from, .to] + [$a.entities.business_rules[]?.applies_to[]?] + [$a.entities.workflows[]?.steps[]?.entity_id // empty]
      | map(select(. as $r | $ids | index($r) | not)) | unique | map("R3 dangling reference: \(.)") | .[]),
    # R4: confidence_summary counts equal actual claim counts
    (claims as $c | ["confirmed","inferred","unknown"][] as $lvl
      | ($c | map(select(.confidence == $lvl)) | length) as $n
      | select($a.confidence_summary[$lvl] != $n)
      | "R4 confidence_summary.\($lvl)=\($a.confidence_summary[$lvl]) but counted \($n)"),
    # R5: workflow step order is 1..n without gaps or duplicates
    ($a.entities.workflows[]? | select(([.steps[].order] | sort) != [range(1; (.steps | length) + 1)]) | "R5 workflow \(.id) step order not 1..n"),
    # R6: end_line >= line
    (claims[] | .provenance[]? | select(.end_line != null and .end_line < .line) | "R6 end_line < line at \(.path)"),
    # R7: no claim cites the KB itself (no self-contamination)
    (claims[] | .provenance[]? | select(.path == ".ckb" or (.path | startswith(".ckb/"))) | "R7 provenance cites the KB directory: \(.path)"),
    ([$a.entities.components[]? | select(.module_id == ".ckb" or (.module_id | startswith(".ckb/")))] | .[] | "R7 component inside the KB directory: \(.id)")
  ]
