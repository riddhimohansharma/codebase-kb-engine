# project.jq — ACC v0.1 normative projection: CKB v0.3 artifact (+ optional human lines) -> agent-context body (CLAUDE.md / AGENTS.md).
# Use:  jq -r -L agent-context/v0.1 --rawfile human .ckb/agent-context.human.md -f agent-context/v0.1/project.jq .ckb/ckb.json
#       (pass --arg human "" when there is no human file). The output is byte-identical on every conforming implementation.
include "acc";
acc_project($human)
