# Business rules

## Rule catalog
Rules are ordered by the path and line of their enforcement site. Each rule is stated once, with its trigger, outcome, and the place in code where it is enforced, so that a reader can verify it in under a minute.

<a id="business-rule-refunds-require-admin"></a>
### Refunds require admin
`ckb:business_rule:refunds-require-admin`

- **ID:** BR-refunds-require-admin
- **Statement:** Only users holding the admin role may trigger a refund of a charged order.
- **Rationale:** Refunds move money out of the business, so they need a privileged actor. [I]
- **Trigger:** A refund request reaching the API or the worker.
- **Outcome:** Non-admin requests are rejected with 403 and no refund is created.
- **Exceptions:** None observed; automated refunds for failed shipments may exist elsewhere. [?]
- **Enforced at:** src/api/auth.ts:30 [I]
- **Confidence:** [I]

<a id="business-rule-order-total-positive"></a>
### Order total must be positive
`ckb:business_rule:order-total-positive`

- **ID:** BR-order-total-positive
- **Statement:** An order is rejected unless its total in cents is strictly greater than zero.
- **Rationale:** Prevents zero-value or negative charges being sent to the payment provider. [I]
- **Trigger:** Every POST to the order endpoint, before any charge is attempted.
- **Outcome:** The request fails with 422 and nothing is written to the orders table.
- **Exceptions:** None observed in the validation module. [C]
- **Enforced at:** src/api/validate.ts:21 [C]
- **Confidence:** [C]

## Traceability
| Rule | Enforced at | Tests | Confidence |
|---|---|---|---|
| BR-refunds-require-admin | src/api/auth.ts:30 [I] | none found | [I] |
| BR-order-total-positive | src/api/validate.ts:21 [C] | test/validate.test.ts:5 [C] | [C] |

Both rules are enforced in the API process. The worker trusts that refund requests were authorized upstream, which means the admin rule is only as strong as the path that creates refund requests. That path is not visible in this repository and is listed as an open question in the system context document. The positive-total rule has a unit test; the admin rule has none, so a regression in the role check would not be caught by the test suite.
