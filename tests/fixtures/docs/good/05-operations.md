# Operations

## Build
Install dependencies with npm and compile TypeScript, as declared in the scripts block of package.json:5 [C]. The container image is built from Dockerfile:1 [C], which copies the compiled output and runs the API entrypoint. No multi-stage build is used, so the image also contains development tooling. [I]

## Run locally
Set PORT and DATABASE_URL in the environment, start a local Postgres, apply migrations/001_orders.sql:1 [C], then run the start script. A Stripe test key must be provided through STRIPE_KEY for the charge call to succeed; without it the API starts but every order fails at the payment step. [I]

```sh
npm ci
npm run build
npm start
```

## Test
Unit tests run with jest, declared at package.json:14 [C]. The only observed test file covers order validation at test/validate.test.ts:5 [C]. There are no integration tests against Postgres or Stripe, and no contract tests for the event topic. [I]

## Deploy and environments
The Kubernetes deployment at deploy/k8s/deployment.yaml:4 [C] runs the shop-api image on port 8080. Two environments, staging and prod, are referenced. The promotion mechanism between them, such as a pipeline or a manual apply, is not visible in this repository. [?]

## Observability
Logs go to standard output via console calls in src/api/server.ts:3 [I]. No metrics, tracing, or structured logging library is declared in the manifest. Health endpoints were not found, so the platform probably relies on TCP checks only. [?]

## Alerts and failure modes
- Stripe outage: every order fails with a gateway error; no queueing or degradation path exists. [I]
- Postgres outage: orders fail after the customer has been charged, because the charge precedes the insert. [I]
- Kafka outage: orders succeed but no event is emitted, and nothing retries later. [I]
- No alert definitions exist in this repository. [?]

## Rollback
Roll back by redeploying the previous image tag through the Kubernetes deployment. Database migrations are forward only and have no down scripts, so a schema change cannot be reverted automatically; see migrations/001_orders.sql:1 [C]. Coordinate any rollback that crosses a migration with the database owner. [I]
