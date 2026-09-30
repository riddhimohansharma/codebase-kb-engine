---
description: CKB v0.1 output contract for the machine artifact. Load when writing ckb.draft.json during /kb. Defines the draft format, entity granularity, join-key fields, confidence, and provenance rules.
---
# CKB output contract (v0.1)

You write `ckb.draft.json`; `scripts/finalize.sh` turns it into the conforming `ckb.json`. The spec is vendored at `${CLAUDE_PLUGIN_ROOT}/spec/v0.1/ckb.schema.json`.

## The script does this for you. Do not spend effort on it.
- `ckb_version`, `repo` identity (url, branch, commit_sha, generated_at), `generator`, `confidence_summary`.
- Final entity IDs. Put any **local** `id` on each entity (e.g. `"c1"`, `"users-route"`) and reference entities by that local id. The script derives spec IDs and rewrites every reference.
- Normalization of join keys: HTTP method casing; path params (`:id`, `[id]`, `<int:id>`, `${id}`, and `{id}` all become `{id}` in snake_case); trailing slashes; query strings; npm/pypi casing; PEP 503.
- Merging duplicates (same derived ID). Provenance is unioned and the strongest confidence is kept.
- Sorting, and renumbering workflow steps to 1..n.
- Dropping unknown fields, and **downgrading to `unknown`** any claim whose provenance is missing or invalid.

## Draft shape
```json
{
  "entities": {
    "components":     [{"id","name","module_id","kind","language?","description?","confidence","provenance"}],
    "interfaces":     [{"id","name","kind","role","http|event|rpc|symbol","confidence","provenance"}],
    "dependencies":   [{"id","name","package_key","scope","version_constraint?","confidence","provenance"}],
    "datastores":     [{"id","name","engine","schema?","table?","access","confidence","provenance"}],
    "business_rules": [{"id","name","statement","applies_to?":[local ids],"confidence","provenance"}],
    "workflows":      [{"id","name","trigger?","steps":[{"order","description","entity_id?"}],"confidence","provenance"}]
  },
  "relations": [{"from","to","kind","confidence","provenance"}]
}
```
`provenance` = `[{"path": "<repo-relative>", "line": N, "end_line?": M}]`. Paths are relative to the repo root, with no leading `/` and no `..`.

## Enums (anything else fails validation)
- component.kind: `service library module cli ui job other`
- interface.kind: `http event rpc cli library`. role: `provides` (this repo serves or publishes it) or `consumes` (this repo calls or subscribes to it).
  - http: `{"method": "GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|ANY", "normalized_path": "/users/{id}", "host?": "<logical service>"}`
  - event: `{"transport": "kafka|sqs|sns|rabbitmq|pubsub|eventbridge|nats|redis|webhook|other", "topic": "..."}`
  - rpc: `{"protocol": "grpc|thrift|jsonrpc|graphql|other", "service": "pkg.Service", "method": "Get"}`
  - cli / library: `"symbol": "<command or exported name>"`
- dependency.package_key: `npm:@scope/name` · `pypi:name` · `maven:group:artifact` · `go:module/path` · `cargo:name` · `nuget:Name` · `gem:name` · `other:<id>`. scope: `runtime dev build test peer optional`
- datastore.engine: `postgres mysql sqlite mssql oracle mongodb dynamodb redis elasticsearch s3 gcs filesystem other`. access: `read write readwrite`
- relation.kind: `contains calls provides consumes depends_on reads writes publishes subscribes enforces`

## Granularity: what earns an entity
- **components**: deployable units and top-level modules (roughly 3–30 per repo), not every file. `module_id` = repo-relative directory or file.
- **interfaces**: every HTTP route served; every outbound HTTP call to another service (`consumes`, with `host` when known); every event topic published or subscribed; every public CLI command. These carry the cross-repo join keys, so completeness here matters most.
- **dependencies**: direct dependencies declared in manifests only (not the lockfile's transitive closure). Cite the manifest line.
- **datastores**: tables, collections, buckets and caches that the code actually reads or writes (migrations, ORM models, queries).
- **business_rules**: the same rules as `03-business-rules.md`, using the same names. The statement is one sentence and the provenance is the enforcement site.
- **workflows**: the same workflows as `02-functional-workflows.md`. Steps point at entities where possible.
- **relations**: within-repo edges only. Cross-repo links are never written as IDs; consumers resolve them through join keys.

## Confidence (per claim)
- `confirmed`: the cited line states it directly (a route decorator, a manifest entry, a CREATE TABLE statement).
- `inferred`: derived from naming or structure. It is plausible but not stated.
- `unknown`: you looked and could not determine it. Keep the entity so the gap is visible. Provenance may be `[]`.

Never upgrade confidence to look complete. The artifact exists so a consumer can trust it.
