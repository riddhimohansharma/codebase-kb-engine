# Overview

## Elevator pitch
Shop is a small order-taking service. It accepts orders over HTTP, validates them against a handful of business rules, charges the customer through Stripe, stores the order in Postgres, and announces each new order on a Kafka topic so that downstream fulfilment systems can react. A separate worker process handles refunds asynchronously. The HTTP entrypoint lives in src/api/server.ts:3 [C].

## Executive summary
- The service is a single TypeScript codebase with two runtime roles: an API and a background worker. [C]
- Orders are the only persistent aggregate; they live in one Postgres table created by migrations/001_orders.sql:1 [C].
- Payment is delegated entirely to Stripe; the service never stores card data. [I]
- Refund authorization is enforced in code but the admin role source is not visible in this repository. [?]
- The deployable unit is a container image named shop-api, built from Dockerfile:1 [C].

## Stakeholders and users
| Stakeholder | Interest | Confidence |
|---|---|---|
| Customers | Place orders and receive confirmations | [I] |
| Support admins | Issue refunds for failed or disputed orders | [I] |
| Fulfilment team | Consume order.created events to ship goods | [I] |
| Platform team | Operate the Kubernetes deployment | [?] |

## Quality goals
1. Correctness of money movement: no order is stored without a successful charge decision. [I]
2. Availability of order intake during business hours, since every lost request is a lost sale. [?]
3. Simple operations: one image, one database, one topic, so that a small team can run it. [I]

## Glossary
| Term | Meaning | Source |
|---|---|---|
| Order | A customer purchase with a positive total | src/api/validate.ts:21 [C] |
| Charge | A Stripe payment attempt for an order | src/api/pay.ts:8 [C] |
| Refund | Reversal of a charge, run by the worker | src/worker/refund.ts:4 [I] |

## Macro context
Shop is one piece of a larger commerce platform. It needs an identity provider for admin roles, a fulfilment consumer for order events, and Stripe for payments to be complete. None of those systems live in this repository, so their behaviour is described here only from the contracts this service exposes and consumes. [I]

## How to read this KB
Confidence legend: [C] confirmed in code, [I] inferred, [?] unknown and worth verifying. Start with the technical architecture, then the workflows and business rules. System context and gaps lists risks and open questions. Operations explains how to build and run the service. Security and data covers trust boundaries and secrets. Decisions records the architectural choices that can be observed. The generated reference file holds complete tables of interfaces, dependencies, and configuration keys.
