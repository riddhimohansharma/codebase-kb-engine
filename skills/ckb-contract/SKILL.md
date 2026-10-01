---
name: ckb-contract
description: CKB v0.2 machine-artifact contract (ckb.draft.json shape, purl dependencies, entity granularity, join keys, confidence, provenance). Load only during codebase-kb-engine /kb.
---
# CKB output contract (v0.2)

You (and the scouts) write the **draft**; `scripts/finalize.sh` turns it into the conforming `ckb/ckb.json`. The spec is vendored at `${CLAUDE_PLUGIN_ROOT}/spec/v0.2/` (`ckb.schema.json`, `semantic.jq`, `derive.jq`). The KB serves one goal: a consumer ingesting many repos must be able to build a **complete cross-repo graph and dependency map**. Completeness of join keys matters more than prose.

## Where the draft goes
- Small repo: one file `ckb/ckb.draft.json`.
- Large repo (more than ~300 entities): **one file per area or collection** in `ckb/ckb.draft.d/*.json`, each in the same shape. Finalize merges them. Never put more than ~300 entities in one Write.

## The script does this for you. Don't spend effort on it.
- `ckb_version`, `repo` identity, `generator`, `confidence_summary`, `coverage`.
- **Final IDs.** Give every entity any short **local** `id` (prefix it with the area slug in multi-scout runs, e.g. `api.users-get`) and reference entities by local id. Finalize derives the spec ID and rewrites every reference, in the JSON and in the docs.
- **Join-key normalization:**
  - Route params from every framework become `{param}`: `:id`, `[id]`, `<int:id>`, `{id?}`, `#{id}`, `(?P<id>…)`, `${x.id}`, `$id`, `*rest` and `{*rest}`.
  - Literal ids and UUIDs become `{id}`. Absolute URLs and host placeholders are removed from paths.
  - Outbound hosts are normalized: `.svc.cluster.local` and ports are dropped, and `USER_SERVICE_URL` becomes `user-service`.
  - Topic ARN and SQS-URL forms are reduced to the topic name. SQL identifiers are unquoted and lowercased, and default schemas (`public`, `dbo`) are dropped.
- **purl canonicalization:** versions and extras are stripped, the ecosystem is inferred from the manifest file name, and names are canonicalized per ecosystem (npm/nuget/composer lowercase, PEP 503, cargo `_`→`-`).
- **Cleanup:**
  - Multi-method routes split into one entity per method.
  - Duplicates merge. Enum synonyms are coerced.
  - Relations not allowed by the spec are dropped. Uncited claims are **downgraded to `unknown`**.
  - Secret values are redacted.

## Draft shape
```json
{ "repo_profile": {"languages":[{"name","files"}], "frameworks":[], "build_tools":[], "license":"SPDX", "owners":[{"name","source"}]},
  "entities": {
    "components":        [{"id","name","module_id","kind","language?"}],
    "interfaces":        [{"id","name","kind","role","service_key?","http|event|rpc|websocket|symbol"}],
    "dependencies":      [{"id","name","purl","manifest_path","scope","version_constraint?","resolved_version?","source?"}],
    "datastores":        [{"id","name","engine","instance_key?","schema?","table?","access"}],
    "business_rules":    [{"id","name","statement","applies_to?":[local ids]}],
    "workflows":         [{"id","name","trigger?","steps":[{"order","description","entity_id?"}]}],
    "artifacts":         [{"id","name","kind","purl","version?","manifest_path"}],
    "services":          [{"id","name","service_key","runtime","ports?","environments?"}],
    "config_keys":       [{"id","name","source","is_secret"}],
    "external_services": [{"id","name","domain","vendor?","category"}],
    "api_specs":         [{"id","name","path","format","version?"}] },
  "relations": [{"from","to","kind"}] }
```
Every entity and relation also carries `"confidence"` and `"provenance": [{"path":"<repo-relative>","line":N,"end_line?":M}]`. Paths are repo-relative, with no leading `/` and no `..`. **Never cite `ckb/`, generated or vendored code.** Extra vendor data goes in `x-…` fields.

## Join keys: what makes the graph connect
| Collection | Key fields | Rules |
|---|---|---|
| interfaces (http) | `role`, `http.method`, `http.normalized_path`, **`http.host`** (consumes), **`service_key`** (provides) | Compose the **full** path, including mount prefixes, class-level mappings and context paths. Use one entity per method. For outbound calls, always give the target as `host`: a service name, a hostname, or the env var name that holds the base URL |
| interfaces (event) | `event.transport`, `event.topic` | Resolve `${…}` placeholders from config. For RabbitMQ, the topic is `exchange/routing_key` |
| interfaces (rpc) | `rpc.protocol`, `rpc.service`, `rpc.method` | gRPC: `service` is proto `package.Service`. GraphQL: `service` is `Query`/`Mutation`/`Subscription` and `method` is the field name |
| dependencies | **`purl`** (versionless), `manifest_path`, `scope` | One entity per declaration (per manifest). Use `source: workspace\|path` for internal monorepo packages, and add a `depends_on` relation component→component. Skip go.mod `// indirect`. Resolve Gradle catalog aliases, sbt `%%` and `${property}` |
| artifacts | **`purl`** | What this repo **publishes**: its package name from the manifest, container images it builds, charts, binaries. This is how a consumer resolves "repo A depends on X" to "repo B builds X" |
| services | `service_key` (kebab) | Deployable runtime units: k8s Deployment, Helm release, compose service, Lambda function |
| datastores | `engine`, `instance_key`, `schema`, `table` | The physical table name follows ORM conventions (see the scout checklist). `instance_key` is the **name of the env var** holding the DSN, never the DSN |
| config_keys | `source`, `name` | **Names only, never values.** Set `is_secret` for credentials, tokens, keys and DSNs |
| external_services | `domain` | Third-party SaaS, such as `api.stripe.com` or `collector.newrelic.com` |
| api_specs | `path`, `format` | OpenAPI, proto, GraphQL SDL and AsyncAPI files. These are **authoritative** over code annotations |

## Enums (values outside these are coerced, with a warning)
- component.kind: `service library module cli ui job other`
- interface.kind: `http event rpc cli library websocket`. interface.role: `provides consumes`
- event.transport: `kafka sqs sns rabbitmq pubsub eventbridge nats redis kinesis servicebus pulsar mqtt webhook other`
- rpc.protocol: `grpc thrift jsonrpc graphql other`
- dependency.scope: `runtime dev build test peer optional`. dependency.source: `registry workspace git path vendored unknown`
- datastore.engine: `postgres mysql sqlite mssql oracle mongodb dynamodb redis elasticsearch s3 gcs azure-blob cassandra bigquery snowflake clickhouse neo4j cosmosdb firestore filesystem other`. datastore.access: `read write readwrite`
- artifact.kind: `package container_image helm_chart binary terraform_module function static_site other`
- service.runtime: `k8s ecs lambda cloudrun vm container serverless other`
- config_key.source: `env file vault aws_ssm aws_secrets_manager k8s_secret k8s_configmap other`
- external_service.category: `observability auth payments email messaging llm cdn analytics storage search maps other`
- api_spec.format: `openapi swagger proto graphql_sdl asyncapi avro jsonschema wsdl other`

## Relations (only these are allowed; anything else is dropped)
| kind | from | to |
|---|---|---|
| `contains`, `imports` | component | component |
| `depends_on` | component | dependency, component |
| `provides` / `consumes` | component | interface (role must match) |
| `publishes` / `subscribes` | component | interface (event, websocket) |
| `reads` / `writes` | component, interface | datastore |
| `enforces` | component, interface | business_rule |
| `builds` | component | artifact |
| `deploys_as` | component | service |
| `exposes` | service | interface |
| `configured_by` | component, service, interface, datastore | config_key |
| `uses_external` | component, interface | external_service |
| `specified_by` | interface | api_spec |

**Every interface needs at least one `provides` or `consumes` edge from its component.** Every dependency needs a `depends_on` edge from the component whose manifest declares it.

## Confidence (per claim)
- `confirmed`: the cited line states it directly.
- `inferred`: derived from naming or structure.
- `unknown`: you looked but could not determine it. Keep the entity so the gap is visible.

## Secrets
**Never copy secret values** (passwords, tokens, keys, license keys, connection strings) into the KB. Name the secret as a `config_key` with `is_secret: true` and cite where it is defined, for example "New Relic license key hardcoded at `newrelic.js:16`". Finalize also redacts any value it recognises.

Never upgrade confidence to make the KB look complete.
