#!/usr/bin/env bash
# inventory.sh <repo_root> — deterministic, read-only file inventory for /kb recon (CKB v0.2 coverage buckets).
# Lists files with `git ls-files -co --exclude-standard` (plain `find` outside git), drops generated/vendored/
# third-party/submodule/ckb paths, buckets the rest (manifests, lockfiles, routes, events, datastores, migrations,
# iac, ci, config, api_specs) by name and by bounded content grep (text files < 1MB), detects workspaces, and
# splits the repo into areas for parallel scouts. Prints ONE JSON object on stdout; never writes to the repo.
# Temp files live in a private mktemp dir that is removed on exit. bash 3.2+, BSD/GNU userland, jq 1.6+.
set -euo pipefail
export LC_ALL=C
die(){ echo "inventory: $*" >&2; exit 2; }
[ $# -ge 1 ] || die "usage: inventory.sh <repo_root>"
command -v jq >/dev/null 2>&1 || die "jq is required"
ROOT="$(cd "$1" 2>/dev/null && pwd -P)" || die "not a directory: $1"
T="$(mktemp -d "${TMPDIR:-/tmp}/ckb-inv.XXXXXX")"; trap 'rm -rf "$T"' EXIT
cd "$ROOT"
MAXB=1024   # content sniffing cap in KiB (files larger than this are never read)
SPLIT=1500  # a non-workspace top-level area with more files than this is split one level deeper
onlist(){ # onlist <listfile> <cmd...>: run cmd with the list's paths as args (NUL-safe); no-op on an empty list
  local f="$1"; shift; [ -s "$f" ] || return 0
  tr '\n' '\0' < "$f" | xargs -0 "$@" 2>/dev/null || true
}
# ---------- 1. raw listing (repo-relative, unique, sorted) ----------
: > "$T/sub"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git ls-files -z -co --exclude-standard | tr '\0' '\n' | awk 'length && !/\/$/' | sort -u > "$T/raw"
  git ls-files -s -z | tr '\0' '\n' | awk -F'\t' '$1 ~ /^160000 / {print $2}' > "$T/sub" || true
  if [ -f .gitmodules ]; then git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{ $1=""; sub(/^ /,""); print }' >> "$T/sub" || true; fi
  sort -u -o "$T/sub" "$T/sub"
else
  find . -name .git -prune -o \( -type f -o -type l \) -print | awk '{ sub(/^\.\//,""); print }' | sort -u > "$T/raw"
fi
# keep only paths that exist as files/symlinks (ls-files -c also lists tracked files deleted from the worktree)
awk '{ print "./" $0 }' "$T/raw" > "$T/rawd"
onlist "$T/rawd" sh -c 'find "$@" -maxdepth 0 \( -type f -o -type l \) -print 2>/dev/null' sh | awk '{ sub(/^\.\//,""); print }' | sort -u > "$T/exist"
# ---------- 2. name-based exclusion + bucketing (one awk pass; file list read twice: chart dirs first) ----------
cat > "$T/classify.awk" <<'AWK'
function base(p,  n){ n = split(p, a, "/"); return a[n] }
function dirn(p){ if (p !~ /\//) return ""; sub(/\/[^\/]*$/, "", p); return p }
function ext(b,  n){ if (b !~ /\./) return ""; n = split(b, e, "."); return tolower(e[n]) }
function under(p, d){ return d == "" || index(p, d "/") == 1 }
function emit(bk, p){ print "B\t" bk "\t" p }
BEGIN {
  nd = split("node_modules vendor third_party Pods Carthage .dart_tool _build deps .venv venv site-packages target build dist out bin obj .gradle .terraform generated generated-sources __generated__ ckb .ckb", xd, " ")
  for (i = 1; i <= nd; i++) XD[xd[i]] = 1
  m = "package.json deno.json deno.jsonc pyproject.toml setup.py setup.cfg Pipfile environment.yml environment.yaml go.mod go.work Cargo.toml pom.xml build.gradle build.gradle.kts settings.gradle settings.gradle.kts libs.versions.toml build.sbt project.clj deps.edn Directory.Packages.props Directory.Build.props packages.config paket.dependencies Gemfile composer.json Podfile Package.swift pubspec.yaml mix.exs rebar.config conanfile.txt conanfile.py vcpkg.json CMakeLists.txt package.yaml stack.yaml cabal.project DESCRIPTION Project.toml MODULE.bazel WORKSPACE WORKSPACE.bazel Chart.yaml pnpm-workspace.yaml lerna.json nx.json turbo.json rush.json melos.yaml Cartfile pixi.toml flake.nix build.zig.zon Gopkg.toml shard.yml"
  n = split(m, a, " "); for (i = 1; i <= n; i++) MAN[a[i]] = 1
  m = "csproj fsproj vbproj gemspec podspec cabal rockspec sln tf"
  n = split(m, a, " "); for (i = 1; i <= n; i++) MANX[a[i]] = 1
  m = "package-lock.json npm-shrinkwrap.json yarn.lock pnpm-lock.yaml bun.lockb bun.lock deno.lock poetry.lock uv.lock pdm.lock pixi.lock Pipfile.lock go.sum Gopkg.lock Cargo.lock gradle.lockfile composer.lock Gemfile.lock Podfile.lock Package.resolved pubspec.lock mix.lock rebar.lock conan.lock packages.lock.json paket.lock Manifest.toml renv.lock flake.lock .terraform.lock.hcl cabal.project.freeze stack.yaml.lock Cartfile.resolved Chart.lock conda-lock.yml"
  n = split(m, a, " "); for (i = 1; i <= n; i++) LOCK[a[i]] = 1
  m = "proto graphql graphqls gql avsc avdl avpr wsdl thrift raml smithy"
  n = split(m, a, " "); for (i = 1; i <= n; i++) SPECX[a[i]] = 1
  m = "sql py rb ts js mjs cjs go cs java kt kts php ex exs xml yaml yml json rs scala groovy toml"
  n = split(m, a, " "); for (i = 1; i <= n; i++) MIGX[a[i]] = 1
}
FNR == 1 { pass++ }
pass == 1 { if (base($0) == "Chart.yaml") CH[++nch] = dirn($0); next }
{
  p = $0; b = base(p); lb = tolower(b); lp = tolower(p); x = ext(b); d = dirn(p)
  # --- exclusions ---
  ns = split(p, seg, "/"); why = ""
  for (i = 1; i < ns; i++) if (seg[i] in XD) { why = (seg[i] == "ckb" || seg[i] == ".ckb") ? "ckb" : "vendored_dir"; break }
  if (why == "" && (lb ~ /\.pb\.go$|\.pb\.gw\.go$|_pb2\.py$|_pb2\.pyi$|_pb2_grpc\.py$|\.pb\.h$|\.pb\.cc$|\.pb\.swift$|_pb\.js$|\.g\.dart$|\.freezed\.dart$|\.generated\.cs$|\.designer\.cs$|\.min\.js$|\.min\.css$|\.d\.ts$|\.d\.mts$|\.d\.cts$|\.map$/)) why = "generated_name"
  if (why != "") { print "X\t" why "\t" p; next }
  print "I\t" p
  # --- manifests ---
  if ((b in MAN) || (x in MANX) || b ~ /^requirements.*\.(txt|in)$/ || lp ~ /(^|\/)requirements\/[^\/]*\.(txt|in)$/ || b ~ /^(Dockerfile|Containerfile)/ || lb ~ /\.dockerfile$/) emit("manifests", p)
  # --- lockfiles ---
  if ((b in LOCK) || lb ~ /\.lockfile$/) emit("lockfiles", p)
  # --- api_specs ---
  if ((x in SPECX) || lb ~ /^(openapi|swagger|asyncapi)[^\/]*\.(ya?ml|json)$/ || lb ~ /\.(openapi|swagger|asyncapi)\.(ya?ml|json)$/) emit("api_specs", p)
  # --- migrations ---
  ism = 0
  if ((x in MIGX) && ("/" lp) ~ /\/(db\/migrate|migrations?|alembic\/versions|flyway|liquibase|changelogs?|db\/changelog|evolutions)\//) ism = 1
  if (b ~ /^[VUR][0-9]*[0-9._]*__.+\.sql$/ || lb ~ /^db\.changelog.*\.(xml|ya?ml|json|sql)$/) ism = 1
  if (ism) emit("migrations", p)
  # --- datastores (by name; content adds more) ---
  if (x == "prisma" || (x == "sql" && !ism) || x == "cql") emit("datastores", p)
  # --- routes (by name; content adds more) ---
  if (lp ~ /(^|\/)config\/routes(\.rb|\/[^\/]+\.rb)$/ || lp ~ /(^|\/)routes\/[^\/]+\.php$/ || lb ~ /urls\.py$/ || lp ~ /(^|\/)conf\/routes$/ || lp ~ /(^|\/)pages\/api\/.*\.(js|jsx|ts|tsx)$/ || lp ~ /(^|\/)app\/(.*\/)?route\.(js|jsx|ts|tsx)$/ || lb ~ /^\+server\.(js|ts)$/) emit("routes", p)
  # --- iac ---
  inchart = 0
  for (i = 1; i <= nch; i++) if (under(p, CH[i])) { inchart = 1; break }
  if (x == "tf" || x == "tfvars" || x == "hcl" || x == "bicep" || x == "nomad" || b == "Chart.yaml" || (inchart && (x == "yaml" || x == "yml" || x == "tpl")) \
      || lb ~ /^(docker-)?compose[^\/]*\.ya?ml$/ || b ~ /^(Dockerfile|Containerfile)/ || lb ~ /\.dockerfile$/ \
      || lb ~ /^serverless\.(ya?ml|json|ts|js)$/ || lb ~ /^template\.ya?ml$/ || lb == "samconfig.toml" || lb == "cdk.json" \
      || b ~ /^Pulumi(\.[^\/]+)?\.ya?ml$/ || lb ~ /^kustomization\.ya?ml$/ || (lb ~ /^nginx.*\.conf$/) || (x == "conf" && ("/" lp) ~ /\/(nginx|openresty|conf\.d|sites-available|sites-enabled)\//) \
      || lb ~ /^skaffold\.ya?ml$/ || lb ~ /^helmfile\.ya?ml$/ || lb == "fly.toml" || lb == "render.yaml" || lb == "vercel.json" || lb == "netlify.toml" || b == "Procfile" || b == "Vagrantfile" || b == "Tiltfile" \
      || lb ~ /\.cfn\.(ya?ml|json)$/ || lb ~ /task-?def[^\/]*\.json$/ || ("/" lp) ~ /\/(cloudformation|terraform|k8s|kubernetes|manifests|deploy|helm)\/.*\.(ya?ml|json)$/) emit("iac", p)
  # --- ci ---
  if (lp ~ /(^|\/)\.(github|gitea|forgejo)\/workflows\/[^\/]+\.ya?ml$/ || lp ~ /(^|\/)\.github\/actions\/.*action\.ya?ml$/ || lp ~ /^action\.ya?ml$/ \
      || b == ".gitlab-ci.yml" || lp ~ /(^|\/)\.gitlab\/ci\/.*\.ya?ml$/ || b ~ /^Jenkinsfile/ || lb ~ /^azure-pipelines.*\.ya?ml$/ || lp ~ /(^|\/)\.(azure-pipelines|azuredevops|pipelines)\/.*\.ya?ml$/ \
      || lp ~ /(^|\/)\.circleci\/config\.ya?ml$/ || b == "bitbucket-pipelines.yml" || lp ~ /(^|\/)\.buildkite\// || lb ~ /^buildkite.*\.ya?ml$/ \
      || b == ".travis.yml" || b == ".drone.yml" || lb ~ /^\.woodpecker(\.ya?ml)?$/ || lp ~ /(^|\/)\.woodpecker\/.*\.ya?ml$/ || lb ~ /^cloudbuild.*\.ya?ml$/ || lb ~ /^buildspec.*\.ya?ml$/ || lb == "appveyor.yml" || lb == "codemagic.yaml" || lb == "bitrise.yml") emit("ci", p)
  # --- config (by name; env-reading source added by content) ---
  if (b == ".env" || b ~ /^\.env\./ || lb ~ /\.env$/ || b == ".envrc" || lb ~ /^(application|bootstrap)([-._][^\/]*)?\.(ya?ml|properties)$/ || lb ~ /^appsettings[^\/]*\.json$/ || lb == "local.settings.json" || lb == "web.config" || lb == "app.config" \
      || (("/" lp) ~ /\/(config|configs|conf|settings)\// && x ~ /^(yml|yaml|json|php|exs|ex|toml|ini|properties)$/) || b == "settings.py" || lp ~ /(^|\/)settings\/[^\/]+\.py$/ \
      || x == "ini" || x == "properties" || (x == "cfg" ) || (x == "toml" && !(b in MAN) && !(b in LOCK)) || lb ~ /^config\.(ya?ml|json|toml)$/) emit("config", p)
}
AWK
awk -f "$T/classify.awk" "$T/exist" "$T/exist" > "$T/cls"
# submodule paths (and anything below them) are excluded
if [ -s "$T/sub" ]; then
  awk -F'\t' 'FILENAME==ARGV[1] { S[$0]=1; next }
    $1=="I" || $1=="X" || $1=="B" { p = ($1=="I") ? $2 : $3; q = p
      while (1) { if (q in S) { if ($1=="I") print "X\tsubmodule\t" p; next } if (q !~ /\//) break; sub(/\/[^\/]*$/, "", q) }
      print }' "$T/sub" "$T/cls" > "$T/cls2"; mv "$T/cls2" "$T/cls"
  submods="$(awk 'END{print NR}' "$T/sub")"
else submods=0; fi
awk -F'\t' '$1=="I"{print $2}' "$T/cls" > "$T/inc0"
# ---------- 3. content sniffing set: text-ish source/config under the size cap ----------
cat > "$T/textx.awk" <<'AWK'
BEGIN { n = split("java kt kts scala sc groovy gradle cs fs fsx vb js jsx mjs cjs ts tsx mts cts vue svelte astro py pyi rb rake erb php go rs ex exs erl hrl swift m mm h hpp hh hxx c cc cpp cxx dart lua pl pm r jl clj cljs cljc hs ml nim zig cr elm sol conf yml yaml xml toml ini properties tf hcl proto graphql gql sh bash zsh ps1 template tmpl", a, " "); for (i = 1; i <= n; i++) X[a[i]] = 1 }
{ n = split($0, s, "/"); b = s[n]; e = ""; if (b ~ /\./) { k = split(b, q, "."); e = tolower(q[k]) }
  if ((e in X) || b ~ /^(Dockerfile|Jenkinsfile|Gemfile|Rakefile|Podfile|Fastfile|Vagrantfile|Procfile)/) print }
AWK
awk -f "$T/textx.awk" "$T/inc0" > "$T/text0"
awk '{ print "./" $0 }' "$T/text0" > "$T/text0d"
onlist "$T/text0d" sh -c 'find "$@" -maxdepth 0 -type f -size +'"$MAXB"'k -print 2>/dev/null' sh | awk '{ sub(/^\.\//,""); print }' | sort -u > "$T/big"
awk 'FILENAME==ARGV[1] { B[$0]=1; next } !($0 in B)' "$T/big" "$T/text0" > "$T/text"
# ---------- 4. ONE bounded content pass (awk DFA; ~10x faster than BSD grep -E) over every text file < cap ----------
# Per file: generated-header sniff on lines 1-5 (manifests/lockfiles/api_specs/migrations/json exempt: e.g. Cargo.lock
# says "@generated"), then route/event/datastore/config regexes for source code, nginx/OpenResty for conf/lua,
# serverless http events, and k8s (top-level apiVersion + kind) for YAML. Emits "<bucket>\t<path>" / "G\t<path>".
awk -F'\t' '$1=="B" && ($2=="manifests" || $2=="lockfiles" || $2=="api_specs" || $2=="migrations") {print $3}' "$T/cls" | sort -u > "$T/exempt"
cat > "$T/content.awk" <<'AWK'
BEGIN {
  while ((getline l < EX) > 0) EXM[l] = 1
  n = split("java kt kts scala sc groovy cs fs fsx vb js jsx mjs cjs ts tsx mts cts vue svelte astro py rb rake php go rs ex exs erl swift m mm h hpp c cc cpp cxx dart lua pl pm r jl clj cljs cljc hs ml nim zig cr sol", a, " ")
  for (i = 1; i <= n; i++) SRC[a[i]] = 1
}
function hit(bk) { if (!(bk in H)) { H[bk] = 1; print bk "\t" f } }
FNR == 1 { f = FILENAME; split("", H); k8a = k8k = 0
  ns = split(f, s, "/"); b = s[ns]; lb = tolower(b); e = ""; if (b ~ /\./) { ne = split(b, q, "."); e = tolower(q[ne]) }
  sn = !(f in EXM) && e != "json"; src = (e in SRC); ngx = (e ~ /^(conf|lua|template|tmpl)$/ || lb ~ /nginx/)
  sls = (lb ~ /^serverless\.ya?ml$/); yml = (e == "yml" || e == "yaml") }
sn && FNR <= 5 && !("G" in H) { if ($0 ~ /Code generated .* DO NOT EDIT/ || $0 ~ /@generated/ || tolower($0) ~ /auto-generated/) hit("G") }
src {
  if (!("routes" in H) && ($0 ~ /@(Get|Post|Put|Delete|Patch|Request)Mapping|@Path\(|\[(Http(Get|Post|Put|Delete|Patch|Head|Options)|Route)(\(|\])|\.Map(Get|Post|Put|Delete|Patch|Methods|Group|Controllers|ControllerRoute|Hub)\(|@Controller\(|@(Get|Post|Put|Delete|Patch|All|Options|Head)\(|APIRouter\(|Blueprint\(|include_router\(|add_url_rule\(|add_api_route\(|urlpatterns|routes\.draw|Route::|HandleFunc\(|http\.Handle\(|\.(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|Any)\(|PathPrefix\(|Subrouter\(|Router::new\(|\.route\(|\.nest\(|web::(get|post|put|delete|patch|scope|resource)|#\[(get|post|put|delete|patch|route)\(|RouterFunctions|coRouter|routing[ \t]*\{|pipe_through|\.grouped\(/ \
      || $0 ~ /(^|[^A-Za-z0-9_])(app|router|server|fastify|api|routes|route|bp|blueprint|v1|v2|admin)\.(get|post|put|delete|patch|all|use|route|options|head)\(/ \
      || $0 ~ /(^|[^A-Za-z0-9_])(app|api|router)\.(Get|Post|Put|Delete|Patch|Group|Route|Mount|All)\(/ \
      || $0 ~ /(^|[^A-Za-z0-9_])(r|mux|sub|mr|rt|chi)\.(Get|Post|Put|Delete|Patch|Route|Mount|Method|Group|HandleFunc|Handle)\(/ \
      || $0 ~ /(^|[ \t])(scope[ \t]*\(?["']\/|resources?[ \t]+[:"']|(get|post|put|delete|patch|route)[ \t]*\(?[ \t]*["']\/)/)) hit("routes")
  if (!("events" in H) && ($0 ~ /KafkaListener|KafkaTemplate|KafkaHandler|@SqsListener|RabbitListener|RabbitTemplate|JmsListener|JmsTemplate|StreamListener|kafkajs|sarama|franz-go|twmb\/franz|segmentio\/kafka-go|rdkafka|confluent_kafka|confluent-kafka|Confluent\.Kafka|kafka-python|KafkaConsumer|KafkaProducer|ruby-kafka|karafka|Racecar|MassTransit|NServiceBus|amqplib|amqp:\/\/|Bunny::|[Cc]elery|@shared_task|@app\.task|[Ss]idekiq|queue_as|perform_later|ActiveJob|Oban|Broadway|client-(sqs|sns|kinesis|eventbridge)|SnsClient|SqsClient|AmazonSQS|AmazonSNS|KinesisClient|EventBridgeClient|["'](sqs|sns|kinesis)["']|ServiceBus|EventHub|EventGrid|[Pp]ub[Ss]ub|nats\.go|nats\.connect|BullModule|@nestjs\/bull|@Processor\(|@EventPattern|@MessagePattern|[Pp]ulsar|mqtt|MQTT|paho/ \
      || $0 ~ /(^|[^A-Za-z0-9_])(pika|nats|NATS|bull|Bull|bullmq|SNS|SQS|Kinesis|EventBridge)([^A-Za-z0-9_]|$)/)) hit("events")
  if (!("datastores" in H) && ($0 ~ /@Entity|@Table\(|@Document\(|JpaRepository|CrudRepository|EntityManager|[Hh]ibernate|ActiveRecord::|ApplicationRecord|has_many|belongs_to|models\.Model|db_table|__tablename__|declarative_base|DeclarativeBase|sqlalchemy|SQLAlchemy|@prisma\/client|PrismaClient|typeorm|TypeORM|@Column\(|getRepository\(|[Ss]equelize|mongoose|new Schema\(|MongoClient|pymongo|mongodb(\+srv)?:\/\/|Mongoid|gorm\.|gorm:"|TableName\(\)|sqlx|database\/sql|sql\.Open\(|jackc\/pgx|lib\/pq|go-sql-driver|DbContext|DbSet<|ToTable\(|UseSqlServer|UseNpgsql|Dapper|SqlConnection|Ecto\.Schema|Ecto\.Repo|table!|diesel::|sea_orm|rusqlite|tokio_postgres|extends Model|Eloquent|DB::table|Schema::create|[Rr]edis|Jedis|Lettuce|S3Client|AmazonS3|s3\.amazonaws|["']s3["']|BlobServiceClient|google-cloud-storage|cloud\.google\.com\/go\/storage|@google-cloud\/storage|minio|DynamoDB|dynamodb|DocumentClient|[Cc]assandra|[Ee]lasticsearch|opensearch|[Nn]eo4j|[Ff]irestore|CosmosClient|BigQuery|bigquery|snowflake|clickhouse|psycopg|asyncpg|pg\.Pool|knex|drizzle|kysely|mysql2|pymysql|sqlite3|JdbcTemplate|jdbc:|R2dbc|jOOQ|MyBatis/ \
      || $0 ~ /SELECT[ \t].*[ \t]FROM[ \t]|INSERT[ \t]+INTO[ \t]|UPDATE[ \t]+[A-Za-z_."`]+[ \t]+SET[ \t]|DELETE[ \t]+FROM[ \t]/)) hit("datastores")
  if (!("config" in H) && ($0 ~ /process\.env|import\.meta\.env|Deno\.env|Bun\.env|os\.environ|getenv\(|environ\.get|BaseSettings|pydantic_settings|environ\.Env|System\.getenv|@Value\(|@ConfigurationProperties|Environment\.getProperty|@ConfigProperty|os\.Getenv|os\.LookupEnv|viper\.|envconfig|caarlos0\/env|std::env::var|env::var\(|dotenvy|envy::|IConfiguration|GetEnvironmentVariable|IOptions<|GetConnectionString|ENV\[|ENV\.fetch|Rails\.application\.credentials|config\(["']|System\.get_env|Application\.get_env|Application\.fetch_env|String\.fromEnvironment|Platform\.environment/ \
      || $0 ~ /(^|[^A-Za-z0-9_.>])env\(/)) hit("config")
}
ngx && !("routes" in H) && $0 ~ /^[ \t]*location[ \t]|proxy_pass[ \t]|(content|access|rewrite)_by_lua|ngx\.location\.capture|resty\.http/ { hit("routes") }
sls && !("routes" in H) && $0 ~ /^[ \t]*-?[ \t]*(http|httpApi)[ \t]*:/ { hit("routes") }
yml && !("iac" in H) { if ($0 ~ /^apiVersion:/) k8a = 1; if ($0 ~ /^kind:/) k8k = 1; if (k8a && k8k) hit("iac") }
AWK
onlist "$T/text" awk -v EX="$T/exempt" -f "$T/content.awk" > "$T/cb"
awk -F'\t' '$1=="G" {print $2}' "$T/cb" | sort -u > "$T/gen"
awk 'FILENAME==ARGV[1] { G[$0]=1; next } !($0 in G)' "$T/gen" "$T/inc0" > "$T/inc"
# final bucket lines (name-based + content-based), minus generated files
awk -F'\t' 'FILENAME==ARGV[1] { G[$0]=1; next } $1=="B" && !($3 in G) { print $2 "\t" $3; next } FILENAME==ARGV[3] && $1!="G" && !($2 in G) { print $1 "\t" $2 }' "$T/gen" "$T/cls" "$T/cb" | sort -u > "$T/bk"
# ---------- 5. languages (extension -> linguist name) ----------
cat > "$T/lang.awk" <<'AWK'
BEGIN {
  m = "js:JavaScript mjs:JavaScript cjs:JavaScript jsx:JavaScript ts:TypeScript mts:TypeScript cts:TypeScript tsx:TSX py:Python pyi:Python java:Java kt:Kotlin kts:Kotlin scala:Scala sc:Scala sbt:Scala groovy:Groovy gradle:Groovy cs:C# fs:F# fsx:F# fsi:F# vb:Visual_Basic_.NET go:Go rs:Rust rb:Ruby rake:Ruby gemspec:Ruby php:PHP ex:Elixir exs:Elixir erl:Erlang hrl:Erlang swift:Swift m:Objective-C mm:Objective-C++ c:C h:C cc:C++ cpp:C++ cxx:C++ hpp:C++ hh:C++ hxx:C++ dart:Dart lua:Lua pl:Perl pm:Perl r:R jl:Julia clj:Clojure cljs:Clojure cljc:Clojure edn:edn hs:Haskell ml:OCaml mli:OCaml nim:Nim zig:Zig cr:Crystal elm:Elm sol:Solidity sh:Shell bash:Shell zsh:Shell ps1:PowerShell sql:SQL tf:HCL tfvars:HCL hcl:HCL bicep:Bicep proto:Protocol_Buffer graphql:GraphQL graphqls:GraphQL gql:GraphQL thrift:Thrift prisma:Prisma html:HTML htm:HTML css:CSS scss:SCSS sass:Sass less:Less vue:Vue svelte:Svelte astro:Astro erb:HTML+ERB ejs:EJS cshtml:HTML+Razor razor:HTML+Razor yml:YAML yaml:YAML json:JSON toml:TOML xml:XML md:Markdown mdx:MDX nix:Nix ipynb:Jupyter_Notebook cmake:CMake mk:Makefile bzl:Starlark"
  n = split(m, a, " "); for (i = 1; i <= n; i++) { split(a[i], kv, ":"); L[kv[1]] = kv[2] }
}
{ n = split($0, s, "/"); b = s[n]; name = ""
  if (b ~ /^(Dockerfile|Containerfile)/ || tolower(b) ~ /\.dockerfile$/) name = "Dockerfile"
  else if (b == "Makefile" || b == "GNUmakefile") name = "Makefile"
  else if (b == "CMakeLists.txt") name = "CMake"
  else if (b ~ /^Jenkinsfile/) name = "Groovy"
  else if (b ~ /^(Gemfile|Rakefile|Podfile|Fastfile|Vagrantfile|Guardfile)$/) name = "Ruby"
  else if (b ~ /^(BUILD|WORKSPACE|MODULE)(\.bazel)?$/) name = "Starlark"
  else if (b ~ /\./) { k = split(b, q, "."); e = q[k]; if (!(e in L)) e = tolower(e); if (e in L) name = L[e] }
  if (name != "") { gsub(/_/, " ", name); print name } }
AWK
awk -f "$T/lang.awk" "$T/inc" | sort | uniq -c | awk '{ c = $1; $1 = ""; sub(/^ /, ""); print c "\t" $0 }' > "$T/lang"
# ---------- 6. workspaces: emit "tool<TAB>base<TAB>marker<TAB>pattern" then resolve in jq ----------
pick(){ awk -v n="$1" '{ k = split($0, s, "/"); if (s[k] == n) print }' "$T/inc" > "$T/pick.$1"; printf '%s' "$T/pick.$1"; }
: > "$T/ws"
basef(){ case "$1" in */*) printf '%s' "${1%/*}";; *) printf '';; esac; }
onlist "$(pick package.json)" grep -l '"workspaces"' -- > "$T/pj"
while IFS= read -r f; do
  b="$(basef "$f")"; tool=npm
  if [ -f "${b:-.}/yarn.lock" ]; then tool=yarn; elif [ -f "${b:-.}/bun.lockb" ] || [ -f "${b:-.}/bun.lock" ]; then tool=bun; fi
  jq -r '(.workspaces | if type=="array" then . elif type=="object" then (.packages // []) else [] end) | .[] | strings' "$f" 2>/dev/null \
    | awk -v t="$tool" -v b="$b" '{ print t "\t" b "\tpackage.json\t" $0 }' >> "$T/ws" || true
done < "$T/pj"
while IFS= read -r f; do b="$(basef "$f")"
  jq -r '(.workspace // []) | if type=="array" then .[] else empty end | strings' "$f" 2>/dev/null | awk -v b="$b" '{ print "deno\t" b "\tdeno.json\t" $0 }' >> "$T/ws" || true; done < "$(pick deno.json)"
while IFS= read -r f; do b="$(basef "$f")"
  jq -r 'if (.packages|type)=="array" then .packages[] else "@pm" end' "$f" 2>/dev/null | awk -v b="$b" '{ print "lerna\t" b "\tpackage.json\t" $0 }' >> "$T/ws" || true; done < "$(pick lerna.json)"
while IFS= read -r f; do b="$(basef "$f")"; printf 'nx\t%s\tproject.json\t**\nnx\t%s\t-\t@pm\n' "$b" "$b" >> "$T/ws"; done < "$(pick nx.json)"
while IFS= read -r f; do b="$(basef "$f")"; printf 'turbo\t%s\t-\t@pm\n' "$b" >> "$T/ws"; done < "$(pick turbo.json)"
# YAML "packages:" lists (pnpm, melos) and TOML workspace member arrays (cargo, uv)
yamlpk='{ if (FNR==1) inl=0
  if ($0 ~ /^packages:/) { inl=1; next }
  if (inl && $0 ~ /^[ \t]*-[ \t]*/) { v=$0; sub(/^[ \t]*-[ \t]*/, "", v); sub(/[ \t]+#.*$/, "", v); gsub(/["\047]/, "", v); sub(/[ \t]+$/, "", v); if (v != "") print t "\t" bd(FILENAME) "\t" mk "\t" v; next }
  if (inl && $0 ~ /^[^[:space:]#]/) inl=0 }
  function bd(p){ if (p !~ /\//) return ""; sub(/\/[^\/]*$/, "", p); return p }'
onlist "$(pick pnpm-workspace.yaml)" awk -v t=pnpm -v mk=package.json "$yamlpk" >> "$T/ws"
onlist "$(pick melos.yaml)" awk -v t=melos -v mk=pubspec.yaml "$yamlpk" >> "$T/ws"
tomlws='function bd(p){ if (p !~ /\//) return ""; sub(/\/[^\/]*$/, "", p); return p }
  function take(s,  v){ while (match(s, /"[^"]*"|\047[^\047]*\047/)) { v = substr(s, RSTART+1, RLENGTH-2); print t "\t" bd(FILENAME) "\t" mk "\t" neg v; s = substr(s, RSTART+RLENGTH) } }
  { if (FNR==1) { sec=0; arr=0 }
    if ($0 ~ /^[ \t]*\[/) { sec = ($0 ~ "^[ \t]*\\[" sect "\\][ \t]*(#.*)?$"); arr=0 }
    if (!sec) next
    line=$0; sub(/#.*$/, "", line)
    if (!arr && line ~ /^[ \t]*(members|exclude)[ \t]*=/) { neg = (line ~ /^[ \t]*exclude/) ? "!" : ""; sub(/^[^=]*=/, "", line); arr=1 }
    if (arr) { take(line); if (line ~ /\]/) arr=0 } }'
onlist "$(pick Cargo.toml)" awk -v t=cargo -v mk=Cargo.toml -v sect='workspace' "$tomlws" >> "$T/ws"
onlist "$(pick pyproject.toml)" awk -v t=uv -v mk=pyproject.toml -v sect='tool\\.uv\\.workspace' "$tomlws" >> "$T/ws"
# literal-directory members: gradle include, maven <module>, go.work use, .sln projects, rush projectFolder, mix umbrella
bdf='function bd(p){ if (p !~ /\//) return ""; sub(/\/[^\/]*$/, "", p); return p }'
cat "$(pick settings.gradle)" "$(pick settings.gradle.kts)" > "$T/gradle"
onlist "$T/gradle" awk "$bdf"'
  { if (FNR==1) inc=0; l=$0; sub(/\/\/.*$/, "", l)
    if (l ~ /^[ \t]*include[ \t]*[("\047]/) { inc=1; paren = (l ~ /^[ \t]*include[ \t]*\(/) }
    if (inc) { s=l; while (match(s, /"[^"]*"|\047[^\047]*\047/)) { v=substr(s, RSTART+1, RLENGTH-2); s=substr(s, RSTART+RLENGTH); sub(/^:/, "", v); gsub(/:/, "/", v); if (v != "") print "gradle\t" bd(FILENAME) "\t-\t" v }
      if (paren) { if (l ~ /\)/) inc=0 } else if (l !~ /,[ \t]*$/) inc=0 } }' >> "$T/ws"
onlist "$(pick pom.xml)" awk "$bdf"'{ s=$0; while (match(s, /<module>[^<]*<\/module>/)) { v=substr(s, RSTART+8, RLENGTH-17); gsub(/^[ \t]+|[ \t]+$/, "", v); print "maven\t" bd(FILENAME) "\t-\t" v; s=substr(s, RSTART+RLENGTH) } }' >> "$T/ws"
onlist "$(pick go.work)" awk "$bdf"'
  { if (FNR==1) blk=0; l=$0; sub(/\/\/.*$/, "", l)
    if (l ~ /^[ \t]*use[ \t]*\(/) { blk=1; next }
    if (blk && l ~ /\)/) { blk=0; next }
    if (blk) { gsub(/^[ \t]+|[ \t]+$/, "", l); if (l != "") print "go\t" bd(FILENAME) "\t-\t" l; next }
    if (l ~ /^[ \t]*use[ \t]+/) { sub(/^[ \t]*use[ \t]+/, "", l); gsub(/[ \t]+$/, "", l); print "go\t" bd(FILENAME) "\t-\t" l } }' >> "$T/ws"
awk '/\.sln$/' "$T/inc" > "$T/sln"
onlist "$T/sln" awk "$bdf"'
  /^Project\(/ { s=$0; sub(/^[^=]*=/, "", s); n=0; while (match(s, /"[^"]*"/)) { n++; v=substr(s, RSTART+1, RLENGTH-2); s=substr(s, RSTART+RLENGTH); if (n==2) break }
    if (n==2 && v ~ /\.(cs|fs|vb)proj$/) { gsub(/\\/, "/", v); sub(/\/[^\/]*$/, "", v); if (v !~ /proj$/) print "dotnet-sln\t" bd(FILENAME) "\t-\t" v } }' >> "$T/ws"
onlist "$(pick rush.json)" awk "$bdf"'{ s=$0; while (match(s, /"projectFolder"[ \t]*:[ \t]*"[^"]*"/)) { v=substr(s, RSTART, RLENGTH); s=substr(s, RSTART+RLENGTH); sub(/^.*:[ \t]*"/, "", v); sub(/"$/, "", v); print "rush\t" bd(FILENAME) "\t-\t" v } }' >> "$T/ws"
onlist "$(pick mix.exs)" awk "$bdf"'{ if (match($0, /apps_path:[ \t]*"[^"]*"/)) { v=substr($0, RSTART, RLENGTH); sub(/^[^"]*"/, "", v); sub(/"$/, "", v); print "mix-umbrella\t" bd(FILENAME) "\tmix.exs\t" v "/*" } }' >> "$T/ws"
# directory index (every ancestor dir of an included file) and marker-file dirs, for resolving members
awk '{ p=$0; while (p ~ /\//) { sub(/\/[^\/]*$/, "", p); print p } }' "$T/inc" | sort -u > "$T/dirs"
awk '{ n = split($0, s, "/"); b = s[n]; if (b ~ /^(package\.json|deno\.json|Cargo\.toml|pyproject\.toml|pubspec\.yaml|mix\.exs|project\.json)$/) { d = $0; if (d ~ /\//) sub(/\/[^\/]*$/, "", d); else d = ""; print b "\t" d } }' "$T/inc" > "$T/markers"
jq -n --rawfile ws "$T/ws" --rawfile dirs "$T/dirs" --rawfile mk "$T/markers" '
  def lines($s): $s | split("\n") | map(select(length > 0));
  def normp: split("/") | reduce .[] as $s ([]; if $s == "" or $s == "." then . elif $s == ".." then (if length > 0 then .[:-1] else . end) else . + [$s] end) | join("/");
  def g2re: gsub("(?<c>[.+()\\[\\]{}^$|\\\\])"; "\\\(.c)") | gsub("\\*\\*/"; "\u0001") | gsub("\\*\\*"; "\u0002")
          | gsub("\\*"; "[^/]*") | gsub("\\?"; "[^/]") | gsub("\u0001"; "(.*/)?") | gsub("\u0002"; ".*") | ("^" + . + "$");
  (reduce lines($dirs)[] as $d ({}; .[$d] = true)) as $D
  | (lines($mk) | map(split("\t")) | group_by(.[0]) | map({key: .[0][0], value: map(.[1] // "")}) | from_entries) as $M
  | [lines($ws)[] | split("\t") | {tool: .[0], base: (.[1] // ""), marker: (.[2] // "-"), pat: (.[3] // "")}] as $rows
  | ($rows | map(select(.pat != "@pm")) | map(
      (.pat | startswith("!")) as $neg | (.pat | ltrimstr("!")) as $p
      | ((if .base == "" then $p else (.base + "/" + $p) end) | normp) as $full
      | . + {neg: $neg,
             hits: (if ($p | test("[*?]")) then ($full | g2re) as $re | [($M[.marker] // [])[] | select(test($re))]
                    elif ($D[$full] // false) then [$full] else [] end)}
      | . as $r | .hits |= map(select(. != $r.base and . != "")))
    | group_by([.tool, .base]) | map({tool: .[0].tool, base: .[0].base,
        members: ((map(select(.neg | not) | .hits[]) | unique) - (map(select(.neg) | .hits[]) | unique))})) as $direct
  | ($rows | map(select(.pat == "@pm")) | unique_by([.tool, .base]) | map(. as $r |
      {tool: .tool, base: .base, members: ([$direct[] | select(.base == $r.base and ((.tool == "npm") or (.tool == "yarn") or (.tool == "pnpm") or (.tool == "bun"))) | .members[]] | unique)})) as $pm
  | ($direct + $pm) | group_by([.tool, .base]) | map({tool: .[0].tool, root: (if .[0].base == "" then "." else .[0].base end), members: (map(.members[]) | unique)})
  | map(select(.members | length > 0)) | sort_by(.tool, .root)' > "$T/ws.json"
jq -r '.[].members[]' "$T/ws.json" | sort -u > "$T/members"
# ---------- 7. areas: workspace member (longest prefix) else top-level dir; oversized top-level dirs split once ----------
awk -v lim="$SPLIT" 'FILENAME==ARGV[1] { M[$0]=1; t = $0; if (t ~ /\//) { sub(/\/.*$/, "", t); HM[t] = 1 } next }
  { p = $0; key = ""; q = p
    while (q ~ /\//) { sub(/\/[^\/]*$/, "", q); if (q in M) { key = q; break } }
    if (key != "") { K[FNR] = key; ISM[key] = 1 }
    else if (p ~ /\//) { t = p; sub(/\/.*$/, "", t); K[FNR] = t; TOP[t]++ ; F[FNR] = p }
    else K[FNR] = "."
    N = FNR }
  END {
    for (i = 1; i <= N; i++) { k = K[i]
      if ((k in TOP) && !(k in ISM) && (TOP[k] > lim || (k in HM))) { p = F[i]; r = substr(p, length(k) + 2); if (r ~ /\//) { sub(/\/.*$/, "", r); k = k "/" r } }
      C[k]++; if (K[i] in ISM) MEM[k] = 1 }
    for (k in C) print C[k] "\t" k "\t" ((k in MEM) ? 1 : 0) }' "$T/members" "$T/inc" | sort -t "$(printf '\t')" -k1,1nr -k2,2 > "$T/areas"
# ---------- 8. assemble ----------
cnt(){ awk -F'\t' -v w="$1" '$1=="X" && $2==w {n++} END {print n+0}' "$T/cls"; }
jq -n --rawfile inc "$T/inc" --rawfile bk "$T/bk" --rawfile lang "$T/lang" --rawfile areas "$T/areas" --slurpfile ws "$T/ws.json" \
  --argjson ex_dir "$(cnt vendored_dir)" --argjson ex_name "$(cnt generated_name)" --argjson ex_ckb "$(cnt ckb)" \
  --argjson ex_sub "$(cnt submodule)" --argjson ex_hdr "$(awk 'END{print NR}' "$T/gen")" --argjson submods "$submods" '
  def lines($s): $s | split("\n") | map(select(length > 0));
  def slug: ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("^-+|-+$"; "") | (if . == "" then "root" else . end);
  ["manifests","lockfiles","routes","events","datastores","migrations","iac","ci","config","api_specs"] as $B
  | (lines($bk) | map(split("\t")) | group_by(.[0]) | map({key: .[0][0], value: (map(.[1]) | unique)}) | from_entries) as $bm
  | {
      files_total: (lines($inc) | length),
      excluded_total: ($ex_dir + $ex_name + $ex_ckb + $ex_sub + $ex_hdr),
      excluded_by: {vendored_dir: $ex_dir, generated_name: $ex_name, generated_header: $ex_hdr, ckb: $ex_ckb, submodule: $ex_sub},
      submodules: $submods,
      languages: (lines($lang) | map(split("\t") | {name: .[1], files: (.[0] | tonumber)}) | sort_by((0 - .files), .name)),
      workspaces: [$ws[0][] | {tool, root, members}],
      buckets: (reduce $B[] as $b ({}; .[$b] = ($bm[$b] // []))),
      areas: (lines($areas) | map(split("\t") | {path: .[1], files: (.[0] | tonumber), workspace_member: (.[2] == "1")})
              | reduce .[] as $a ({used: {}, out: []}; ($a.path | slug) as $s
                  | (if .used[$s] then ([range(2; 10000) | ($s + "-" + tostring)] as $c | first($c[] as $x | select(.used[$x] | not) | $x)) else $s end) as $u
                  | .used[$u] = true | .out += [{area: $u, path: $a.path, files: $a.files, workspace_member: $a.workspace_member}]) | .out)
    }'
