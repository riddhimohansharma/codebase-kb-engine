# cyclonedx.jq — CKB v0.3 normative projection to a CycloneDX 1.6 SBOM (JSON). The KB is the source for an org SBOM, not a parallel truth.
# Use:  jq -f schema/v0.3/cyclonedx.jq ckb.json      Deterministic: no timestamp or serial number (the caller may add them).
# components = unique dependencies by purl (versioned with resolved_version when known); metadata.component = this repo;
# dependencies = the repo -> each direct dependency edge.
def purlv: if .resolved_version then .purl + "@" + .resolved_version else .purl end;
. as $a
| ($a.repo.key // ($a.repo.url | sub("^https://"; "") | ascii_downcase)) as $key
| ([$a.entities.dependencies[]? | select((.direct // true))] | unique_by(purlv) | sort_by(purlv)) as $deps
| {bomFormat: "CycloneDX", specVersion: "1.6", version: 1,
   metadata: {component: ({type: "application", "bom-ref": $key, name: ($key | split("/") | last), group: ($key | split("/")[:-1] | join("/")), version: $a.repo.commit_sha[0:12]}
               + (if $a.repo_profile.license then {licenses: [{expression: $a.repo_profile.license}]} else {} end)),
              tools: {components: [{type: "application", name: ($a.generator.product_name // $a.generator.name), version: $a.generator.version}]}},
   components: ($deps | map({type: "library", "bom-ref": purlv, name: (.name // (.purl | split("/") | last)), purl: purlv}
                        + (if .version_constraint then {properties: [{name: "ckb:version_constraint", value: .version_constraint}]} else {} end)
                        + (if .license then {licenses: [{expression: .license}]} else {} end))),
   dependencies: [{ref: $key, dependsOn: ($deps | map(purlv))}]}
