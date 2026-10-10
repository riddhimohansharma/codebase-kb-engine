# Modifiers

Append the matching block to the primary archetype. Each is two or three lines and is projected from `ckb.json`, never guessed from the inventory alone.

## +events
- [P] Publish and subscribe sites by path. A topic rename is a cross-repo breaking change.
- [P] Delivery is at-least-once: handlers must be idempotent.

## +datastore
- [P] Migrations live in `<migration dir>`, named `<convention>`. Never edit a committed migration.
- [P] A model change needs a migration; the model file alone changes nothing.

## +deploy
- [P] `<iac file>` governs this unit. Propose a diff; never apply.

## +polyglot
- [P] One row per ecosystem: its test command and its manifest. Green in one ecosystem is not green.
