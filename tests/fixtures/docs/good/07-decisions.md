# Decisions

## Decision log
Decisions are listed in order of their first evidence path. None of them is documented as a formal ADR in the repository, so all are inferred from code and configuration.

### ADR-kubernetes-single-image: One image serves both runtime roles
- **Status:** inferred
- **Context:** The API and the refund worker share models, validation code, and the Stripe client, and the team is small.
- **Decision:** A single container image is built and deployed to Kubernetes, with the role selected by the start command rather than by separate builds.
- **Consequences:** One build pipeline and one dependency set to patch; the worker carries the HTTP stack it does not need; scaling the two roles independently requires separate deployments of the same image.
- **Evidence:** Dockerfile:1 [C], deploy/k8s/deployment.yaml:4 [I]
- **Confidence:** [I]

### ADR-single-postgres-table: Orders live in one Postgres table
- **Status:** inferred
- **Context:** Orders are the only aggregate the service owns and they need transactional writes.
- **Decision:** A single orders table holds the full order, including status, with no separate line-item table.
- **Consequences:** Simple queries and migrations; line-item reporting must parse the stored payload; schema changes are forward only.
- **Evidence:** migrations/001_orders.sql:1 [C]
- **Confidence:** [I]

### ADR-events-without-outbox: Publish events directly after insert
- **Status:** inferred
- **Context:** Fulfilment needs to learn about new orders quickly.
- **Decision:** The API publishes order.created directly to Kafka after the insert, without an outbox table.
- **Consequences:** Low latency and little code, but events can be lost if the broker is down, and nothing replays them.
- **Evidence:** src/api/events.ts:5 [I]
- **Confidence:** [I]

### ADR-stripe-as-payment-authority: Stripe is the payment authority
- **Status:** inferred
- **Context:** The service must take payments without holding card data or a payments licence.
- **Decision:** All charges and refunds are delegated to Stripe through its HTTP API.
- **Consequences:** Card data stays out of scope; availability of order intake is bounded by Stripe availability; there is no fallback provider.
- **Evidence:** src/api/pay.ts:8 [C], src/worker/refund.ts:4 [I]
- **Confidence:** [I]

## Existing ADRs
Not applicable — no docs/adr directory or other decision records exist in the repository [?]
