<!-- Archetype B: workspace monorepo. [P] = project from ckb.json or the inventory; [H] = a human writes it. Delete this comment and the tags. -->
# Agent context — shop

Several independently built units under one root: a web app, a shared UI package, a Go gateway, a Java orders service. [P]

## Non-negotiables
- [P] Dependencies go in the member's own manifest. The root `package.json` declares workspaces only.
- [P] Green in one ecosystem is not green. `npx turbo run test` does not run the Maven or Go members.
- [P] `packages/ui/src/index.ts` is a published surface. Changing an exported symbol means updating every consumer in `apps/web`.
- [H] Never import across members through relative paths; use the package name.

## Shape
- [P] `apps/web` (npm), `packages/ui` (npm), `services/gateway` (go), `services/orders/orders-api` (maven).
- [P] `services/catalog` (pip) and `services/storefront` (bundler) are not workspace members; build them separately.

## Commands
- [P] npm members: `npx turbo run test`.
- [P] Maven: `mvn -q -B -f services/orders/pom.xml verify`.
- [P] Go: `go test ./services/gateway/...`.

## Changing X obligates Y
- [P] A cross-member contract in `api/openapi.yaml` or `proto/`: change the spec before the implementation, then every consumer.
- [P] A shared type: find every consumer with the member's own tooling; one grep is not enough.

## Traps
- [H] `services/catalog` and `services/storefront` share the same database as `orders-api`. A schema change touches all three.

## Before you say you're done
- [P] The test command for every ecosystem you touched passes.
