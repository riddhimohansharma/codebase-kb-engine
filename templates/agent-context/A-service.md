<!-- Archetype A: deployable service. [P] = project from ckb.json or the inventory; [H] = a human writes it. Delete this comment and the tags. -->
# Agent context — orders-api

Spring Boot service that owns the order lifecycle and is the only writer to `orders`. [P]

## Non-negotiables
- [P] Every route is registered in `src/main/java/com/acme/orders/OrderController.java`. A handler not registered there is dead code.
- [P] `POST /orders` and `POST /orders/{id}/cancel` are authenticated; `GET /healthz` is not. Do not add an unauthenticated write route.
- [P] Schema changes are new files in `src/main/resources/db/migration/`, named `V<n>__<desc>.sql`. Never edit a committed migration.
- [H] Money is integer minor units, never a float. There is no currency column; everything is USD.

## Shape
- [P] `src/main/java/com/acme/orders/`: controller, domain, repository.
- [P] `src/main/resources/application.yml`: config keys; values come from the environment.
- [P] `src/main/resources/db/migration/`: Flyway migrations.

## Commands
- [P] `docker compose up -d db`, then `mvn -q -B verify`. This is what CI runs, tests included.

## Changing X obligates Y
- [P] A new env var: `application.yml`, `.env.example`, and the configuration reference.
- [P] An `Order` field: a new migration. Editing `Order.java` alone migrates nothing.
- [P] A route path or method: `api/openapi.yaml`, because consumers generate from it.

## Traps
- [H] Transactions begin at the service layer, not the controller. A controller-level write autocommits per statement.

## Before you say you're done
- [P] `mvn -q -B verify` passes and every entity change has a migration.
