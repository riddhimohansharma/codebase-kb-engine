# Security and data

## Trust boundaries
There are three boundaries. The public internet meets the API at the order endpoint declared in src/api/routes.ts:12 [C]. The API meets Stripe over HTTPS at src/api/pay.ts:8 [C]. The API and worker meet Postgres inside the cluster network, addressed through the connection string variable read at src/db.ts:2 [C]. Everything that crosses the first boundary is untrusted input.

## AuthN/AuthZ model
Customers are not authenticated by this service; it trusts the storefront to forward valid sessions, which is an inference from the absence of any auth middleware on the order route. [I] Admin authorization for refunds checks a role claim at src/api/auth.ts:30 [I]. Who signs that claim, and how it is verified, is not visible. [?]

## Data classification
| Data | Class | Where | Confidence |
|---|---|---|---|
| Order totals and status | internal business data | migrations/001_orders.sql:1 [C] | [C] |
| Customer identifiers | personal data | migrations/001_orders.sql:1 [I] | [I] |
| Card data | never handled; tokenised by Stripe | src/api/pay.ts:8 [I] | [I] |

## Secrets inventory
| Name | Kind | Source | Referenced at |
|---|---|---|---|
| DATABASE_URL | connection string | env | src/db.ts:2 [C] |
| STRIPE_KEY | API credential | env | src/api/pay.ts:3 [C] |

No secret values appear in tracked files. Both secrets are injected by the platform at runtime. [I]

## Security findings
- Medium: no rate limiting on the order endpoint, which allows card-testing abuse through the charge call at src/api/pay.ts:8 [I].
- Medium: the admin role check has no tests, so a regression could expose refunds to any caller; see src/api/auth.ts:30 [I].
- Low: the container image includes development dependencies, which widens the attack surface; see Dockerfile:1 [I].

## Compliance notes
Card data never reaches the service, which keeps it out of the strictest payment card scope, assuming the storefront uses Stripe client-side tokenisation. [I] Personal data in the orders table falls under the platform's privacy policy; retention and deletion procedures are not defined in this repository. [?]
