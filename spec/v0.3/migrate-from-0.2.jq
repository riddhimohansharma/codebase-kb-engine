# migrate-from-0.2.jq — turns a valid CKB v0.2 artifact into a valid v0.3 artifact. v0.3 is additive over v0.2, so migration only
# stamps the version and derives repo.key. Lock files: set ckb_lock_version and each entry's ckb_version to "0.3".
# Use: jq -L schema/v0.3 -f schema/v0.3/migrate-from-0.2.jq ckb.json
include "derive";
if .ckb_version != "0.2" then error("input is not a v0.2 artifact") else
  .ckb_version = "0.3" | .repo.key = (.repo | ckb_repo_key)
end
