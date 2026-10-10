<!-- Archetype D: infrastructure. [P] = project from ckb.json or the inventory; [H] = a human writes it. Delete this comment and the tags. -->
# Agent context — platform-infra

Terraform and Kubernetes manifests for the production platform. [P]

## Non-negotiables
- [P] The source of truth is `infra/terraform/*.tf`. Never edit state, plan output or rendered manifests.
- [P] Propose a diff and stop. Never run `terraform apply`, `terraform destroy`, `helm upgrade` or `kubectl apply`.
- [P] Secrets are names only. `.env.example` lists names; values live in the secret manager named in the security doc.
- [H] `prod` is the account whose id starts with `9`. Treat any change that mentions it as needing a second reviewer.

## Shape
- [P] `infra/terraform/`: modules and environments. `k8s/`: manifests. `.github/workflows/`: the pipeline that applies them.

## Commands
- [P] `terraform fmt -check` and `terraform validate` in each environment directory. These are read-only.

## Changing X obligates Y
- [P] A module's input variable: every environment that calls it, and its `README.md`.
- [P] An image tag in `k8s/`: the pipeline's tag variable, or the deploy ignores it.

## Traps
- [H] `staging` and `prod` share one state bucket with different keys. A wrong `-chdir` points at the wrong environment.

## Before you say you're done
- [P] `terraform validate` passes for every environment you touched, and your diff names the environment it affects.
