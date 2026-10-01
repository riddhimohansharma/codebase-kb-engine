# normalize.jq — turn a model-written CKB draft into a deterministic CKB v0.2 artifact.
# Run with: jq -L <plugin>/spec/v0.2 -f normalize.jq   (IDs come from the spec's own derive.jq — single source of truth)
# Input: {entities:{...}, relations:[...], repo_profile?} where entity `id`s are local reference keys.
# Args:  $repo, $generator (objects); $roots (array of absolute repo-root spellings); $lines (object path -> line count,
#        for every cited file that exists in the repo outside ckb/).
# Output: {artifact, idmap, warnings}
include "derive";

# ---------- helpers ----------
def slug: ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("^-+|-+$"; "") | if . == "" then null else . end;
def slug_or($s): (slug) // ("u-" + ($s | explode | .[0:8] | map(tostring) | join("-")));
def snake: gsub("(?<a>[a-z0-9])(?<b>[A-Z])"; "\(.a)_\(.b)") | ascii_downcase | gsub("[^a-z0-9_]+"; "_") | gsub("^_+|_+$"; "")
         | if . == "" then "param" elif test("^[a-z_]") then . else "p_" + . end;
def rank: {"confirmed": 0, "inferred": 1, "unknown": 2}[.] // 2;
def nonempty: select(. != null and . != "");
def in_kb: (. // "" | tostring | sub("^\\./"; "")) as $q | ($q == "ckb" or ($q | startswith("ckb/")));
def key: tostring | ascii_downcase | gsub("[ _]+"; "-");
def coerce($allowed; $aliases; $default): (. // "" | key) as $v
  | if ($allowed | index([$v])) then $v elif $aliases[$v] then $aliases[$v] else $default end;
def enum_ok($allowed; $aliases): (. // "" | key) as $v | ($allowed | index([$v])) or ($aliases[$v] != null);
def strs: if type == "array" then [.[] | select(. != null) | tostring] else [] end;

def E_COMP:  ["service","library","module","cli","ui","job","other"];
def A_COMP:  {"app":"service","application":"service","api":"service","server":"service","microservice":"service","backend":"service","web-service":"service","gateway":"service","proxy":"service","package":"library","lib":"library","sdk":"library","frontend":"ui","web":"ui","client":"ui","spa":"ui","mobile":"ui","worker":"job","cron":"job","batch":"job","scheduler":"job","lambda":"job","consumer":"job","command":"cli","tool":"cli","script":"cli","config":"other","infra":"other","infrastructure":"other","test":"other","tests":"other"};
def E_IKIND: ["http","event","rpc","cli","library","websocket"];
def A_IKIND: {"rest":"http","api":"http","route":"http","endpoint":"http","https":"http","webhook":"http","graphql":"rpc","grpc":"rpc","thrift":"rpc","json-rpc":"rpc","jsonrpc":"rpc","twirp":"rpc","connect":"rpc","message":"event","queue":"event","topic":"event","kafka":"event","pubsub":"event","stream":"event","command":"cli","sdk":"library","function":"library","export":"library","module":"library","ws":"websocket","sse":"websocket","signalr":"websocket","channel":"websocket","socket":"websocket","socket.io":"websocket"};
def E_ROLE:  ["provides","consumes"];
def A_ROLE:  {"serves":"provides","exposes":"provides","publishes":"provides","produces":"provides","server":"provides","provider":"provides","implements":"provides","calls":"consumes","uses":"consumes","subscribes":"consumes","client":"consumes","consumer":"consumes","invokes":"consumes","reads":"consumes"};
def E_METH:  ["GET","POST","PUT","PATCH","DELETE","HEAD","OPTIONS","ANY"];
def E_TRANS: ["kafka","sqs","sns","rabbitmq","pubsub","eventbridge","nats","redis","kinesis","servicebus","pulsar","mqtt","webhook","other"];
def A_TRANS: {"amazon-sqs":"sqs","aws-sqs":"sqs","amazon-sns":"sns","aws-sns":"sns","google-pubsub":"pubsub","gcp-pubsub":"pubsub","pub/sub":"pubsub","rabbit":"rabbitmq","amqp":"rabbitmq","redis-streams":"redis","redis-pubsub":"redis","sidekiq":"redis","bull":"redis","bullmq":"redis","resque":"redis","event-bridge":"eventbridge","http":"webhook","https":"webhook","msk":"kafka","confluent":"kafka","redpanda":"kafka","azure-service-bus":"servicebus","service-bus":"servicebus","event-hubs":"kafka","eventhubs":"kafka","jms":"other","activemq":"other","artemis":"other","celery":"other","nsq":"other","aws-kinesis":"kinesis","spring-cloud-stream":"other"};
def E_RPC:   ["grpc","thrift","jsonrpc","graphql","other"];
def A_RPC:   {"json-rpc":"jsonrpc","gql":"graphql","protobuf":"grpc","connect":"grpc","twirp":"grpc"};
def E_SCOPE: ["runtime","dev","build","test","peer","optional"];
def A_SCOPE: {"dependencies":"runtime","prod":"runtime","production":"runtime","compile":"runtime","main":"runtime","implementation":"runtime","api":"runtime","require":"runtime","install-requires":"runtime","runtimeonly":"runtime","devdependencies":"dev","development":"dev","dev-dependencies":"dev","require-dev":"dev","testimplementation":"test","testing":"test","test-dependencies":"test","testcompile":"test","peerdependencies":"peer","optionaldependencies":"optional","extras":"optional","provided":"build","compileonly":"build","annotationprocessor":"build","kapt":"build","plugin":"build","build-dependencies":"build","tooling":"build","ci":"build","base-image":"build"};
def E_SRC:   ["registry","workspace","git","path","vendored","unknown"];
def A_SRC:   {"npm":"registry","pypi":"registry","maven":"registry","local":"path","file":"path","link":"path","monorepo":"workspace","internal":"workspace","github":"git","vcs":"git","vendor":"vendored"};
def E_ENG:   ["postgres","mysql","sqlite","mssql","oracle","mongodb","dynamodb","redis","elasticsearch","s3","gcs","azure-blob","cassandra","bigquery","snowflake","clickhouse","neo4j","cosmosdb","firestore","filesystem","other"];
def A_ENG:   {"postgresql":"postgres","pg":"postgres","psql":"postgres","aurora-postgres":"postgres","cockroachdb":"postgres","yugabyte":"postgres","timescale":"postgres","timescaledb":"postgres","mariadb":"mysql","aurora-mysql":"mysql","aurora":"mysql","tidb":"mysql","planetscale":"mysql","mongo":"mongodb","documentdb":"mongodb","dynamo":"dynamodb","elastic":"elasticsearch","opensearch":"elasticsearch","sql-server":"mssql","sqlserver":"mssql","azure-sql":"mssql","file":"filesystem","fs":"filesystem","local":"filesystem","disk":"filesystem","cloud-storage":"gcs","google-cloud-storage":"gcs","minio":"s3","aws-s3":"s3","r2":"s3","azure-storage":"azure-blob","blob":"azure-blob","valkey":"redis","keydb":"redis","dragonfly":"redis","elasticache":"redis","memcache":"other","memcached":"other","scylla":"cassandra","scylladb":"cassandra","h2":"other","hsqldb":"other","cosmos":"cosmosdb","big-query":"bigquery"};
def E_ACC:   ["read","write","readwrite"];
def A_ACC:   {"rw":"readwrite","read-write":"readwrite","read/write":"readwrite","both":"readwrite","all":"readwrite","crud":"readwrite","r":"read","select":"read","query":"read","read-only":"read","w":"write","insert":"write","update":"write","delete":"write","write-only":"write"};
def E_AKIND: ["package","container_image","helm_chart","binary","terraform_module","function","static_site","other"];
def A_AKIND: {"library":"package","npm":"package","jar":"package","wheel":"package","gem":"package","crate":"package","nuget":"package","image":"container_image","docker":"container_image","docker-image":"container_image","container":"container_image","container-image":"container_image","oci":"container_image","chart":"helm_chart","helm":"helm_chart","helm-chart":"helm_chart","exe":"binary","executable":"binary","cli":"binary","module":"terraform_module","terraform-module":"terraform_module","lambda":"function","cloud-function":"function","site":"static_site","static-site":"static_site","spa":"static_site"};
def E_RUNTIME: ["k8s","ecs","lambda","cloudrun","vm","container","serverless","other"];
def A_RUNTIME: {"kubernetes":"k8s","helm":"k8s","eks":"k8s","gke":"k8s","aks":"k8s","openshift":"k8s","fargate":"ecs","aws-ecs":"ecs","aws-lambda":"lambda","cloud-run":"cloudrun","docker":"container","compose":"container","docker-compose":"container","ec2":"vm","bare-metal":"vm","systemd":"vm","heroku":"other","app-engine":"serverless","azure-functions":"serverless","cloud-functions":"serverless","vercel":"serverless","netlify":"serverless"};
def E_CSRC:  ["env","file","vault","aws_ssm","aws_secrets_manager","k8s_secret","k8s_configmap","other"];
def A_CSRC:  {"environment":"env","env-var":"env","dotenv":"env","process.env":"env","config":"file","yaml":"file","properties":"file","json":"file","appsettings":"file","hashicorp-vault":"vault","ssm":"aws_ssm","parameter-store":"aws_ssm","aws-ssm":"aws_ssm","secrets-manager":"aws_secrets_manager","aws-secrets-manager":"aws_secrets_manager","secret":"k8s_secret","k8s-secret":"k8s_secret","configmap":"k8s_configmap","k8s-configmap":"k8s_configmap"};
def E_XCAT:  ["observability","auth","payments","email","messaging","llm","cdn","analytics","storage","search","maps","other"];
def A_XCAT:  {"monitoring":"observability","apm":"observability","logging":"observability","tracing":"observability","identity":"auth","oauth":"auth","sso":"auth","billing":"payments","sms":"messaging","push":"messaging","chat":"messaging","ai":"llm","ml":"llm","cms":"storage","database":"storage"};
def E_SPEC:  ["openapi","swagger","proto","graphql_sdl","asyncapi","avro","jsonschema","wsdl","other"];
def A_SPEC:  {"oas":"openapi","oas3":"openapi","protobuf":"proto","grpc":"proto","graphql":"graphql_sdl","gql":"graphql_sdl","sdl":"graphql_sdl","graphql-sdl":"graphql_sdl","json-schema":"jsonschema","avsc":"avro"};
def E_REL:   ["contains","imports","depends_on","provides","consumes","calls","reads","writes","publishes","subscribes","enforces","builds","deploys_as","exposes","configured_by","uses_external","specified_by"];
def A_REL:   {"depends-on":"depends_on","uses":"depends_on","requires":"depends_on","import":"imports","invokes":"calls","call":"calls","requests":"calls","implements":"provides","serves":"provides","emits":"publishes","produces":"publishes","sends":"publishes","listens":"subscribes","receives":"subscribes","queries":"reads","selects":"reads","loads":"reads","persists":"writes","stores":"writes","inserts":"writes","updates":"writes","saves":"writes","has":"contains","includes":"contains","owns":"contains","validates":"enforces","guards":"enforces","checks":"enforces","publishes-artifact":"builds","produces-artifact":"builds","build":"builds","deploys":"deploys_as","deploys-as":"deploys_as","deployed-as":"deploys_as","configured-by":"configured_by","reads-config":"configured_by","uses-external":"uses_external","specified-by":"specified_by","documented-by":"specified_by"};
def SQL_ENGINES: ["postgres","mysql","sqlite","mssql","oracle"];
def GENERATED_RE: "(^|/)(node_modules|vendor|third_party|Pods|\\.venv|site-packages|generated|__generated__|dist)/|\\.pb\\.go$|_pb2(_grpc)?\\.py$|\\.pb\\.(h|cc)$|\\.g\\.dart$|\\.freezed\\.dart$|\\.generated\\.cs$|\\.Designer\\.cs$|\\.min\\.js$";

# ---------- paths & provenance ----------
def rel_path: (. // "" | tostring) as $p
  | ([$roots[] | select(. != "" and ($p | startswith(. + "/")))] | first) as $r
  | (if $r then $p[($r | length) + 1:] else $p end) | sub("^(\\./)+"; "");
def valid_prov: [.provenance[]? | select(type == "object") | (.path | rel_path) as $rp
                   | select(($rp | startswith("/") | not) and ($rp | test("(^|/)\\.\\.(/|$)") | not) and ($rp | in_kb | not))
                   | select($lines[$rp] != null)
                   | select((.line | type) == "number" and .line >= 1 and .line <= ($lines[$rp] + 1))
                   | {path: $rp, line: (.line | floor)} + (if (.end_line|type) == "number" and .end_line >= .line then {end_line: ([(.end_line|floor), ($lines[$rp] + 1)] | min)} else {} end)]
                | unique_by([.path, .line, .end_line]) | sort_by([.path, .line, (.end_line // 0)]);
def claim_fields: valid_prov as $p
  | ((.confidence // "unknown") | tostring | ascii_downcase | if IN("confirmed","inferred","unknown") then . else "unknown" end) as $c
  | {confidence: (if $p == [] then "unknown" else $c end), provenance: $p};
def downgraded: ((.confidence // "") | tostring | ascii_downcase | IN("confirmed","inferred")) and (valid_prov == []);

# ---------- HTTP paths & hosts ----------
def norm_path:
  (. // "/" | tostring | gsub("^\\s+|\\s+$"; ""))
  | sub("^(=|~\\*?|\\^~)\\s+"; "")                                   # nginx location modifiers
  | gsub("#\\{(?<p>[^}]*)\\}"; "{\(.p)}")                              # Ruby "#{id}"
  | gsub("\\\\\\((?<p>[^)]*)\\)"; "{\(.p)}")                           # Swift "\(id)"
  | gsub("\\{\\$(?<p>[A-Za-z_][A-Za-z0-9_]*)\\}"; "{\(.p)}")           # PHP "{$id}"
  | gsub("\\(\\?P?<(?<p>[A-Za-z_][A-Za-z0-9_]*)>[^)]*\\)"; "{\(.p)}")   # Python/regex named groups
  | gsub("\\([^)]*\\)"; "{param}")                                     # other regex groups, e.g. nginx (\d+)
  | sub("^\\^"; "") | sub("\\$$"; "") | gsub("\\\\"; "")
  | sub("^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]*"; "")                        # absolute URL: host handled by norm_host
  | sub("^(\\$\\{[^}]*\\}|\\{\\{[^}]*\\}\\}|%s|<[^>]*>|\\$[A-Za-z_][A-Za-z0-9_]*|\\{[A-Za-z_][A-Za-z0-9_]*(Url|URL|Host|HOST|Base|BASE)[A-Za-z0-9_]*\\})(?=/|$)"; "")
  | (if test("^[^{(]*\\?") then split("?")[0] else . end) | split("#")[0]
  | split("/") | map(select(. != ""))
  | map(
      if   test("^\\[\\[?\\.\\.\\.[^\\]]+\\]\\]?$")      then "{wildcard}"                                       # Next.js [...slug]
      elif test("^\\[(?<p>[^\\]]+)\\]$")                  then "{" + (capture("^\\[(?<p>[^\\]]+)\\]$").p | snake) + "}"
      elif test("^:(?<p>[A-Za-z0-9_]+)(\\{.*\\})?\\??$")   then "{" + (capture("^:(?<p>[A-Za-z0-9_]+)").p | snake) + "}"
      elif test("^<([^:>]+:)?(?<p>[A-Za-z0-9_]+)>$")      then "{" + (capture("^<([^:>]+:)?(?<p>[A-Za-z0-9_]+)>$").p | snake) + "}"
      elif test("^\\{\\*\\*?[A-Za-z0-9_]*\\}$")           then "{wildcard}"                                       # {*rest} {**slug}
      elif test("^\\*\\*?[A-Za-z0-9_]*$")                  then "{wildcard}"                                       # *filepath, *, **
      elif test("^\\{\\s*(?<p>[A-Za-z0-9_.]+)\\s*(:[^}]*)?\\??\\s*\\}$") then "{" + (capture("^\\{\\s*(?<p>[A-Za-z0-9_.]+)").p | split(".") | last | snake) + "}"
      elif test("^\\$\\{(?<p>[^}]+)\\}$")                  then "{" + (capture("^\\$\\{(?<p>[^}]+)\\}$").p | split(".") | last | snake) + "}"
      elif test("^\\$(?<p>[A-Za-z0-9_]+)$")               then "{" + (capture("^\\$(?<p>[A-Za-z0-9_]+)$").p | snake) + "}"
      elif test("^%[sdvqxf]$")                             then "{param}"
      elif test("^(\\(\\.\\*\\)|\\.\\*)$")                 then "{wildcard}"
      elif test("^[0-9]+$") or test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$") then "{id}"
      else gsub("[^A-Za-z0-9._~-]"; "-") end)
  | "/" + join("/");
def norm_host:
  (. // "" | tostring | gsub("^\\s+|\\s+$"; "")) as $h
  | if $h == "" then null else
      ($h
       | sub("^process\\.env\\."; "") | sub("^\\$\\{(?<v>[^}]+)\\}.*$"; "\(.v)") | sub("^\\{\\{\\s*(?<v>[^} ]+).*$"; "\(.v)") | sub("^\\$"; "")
       | sub("^[a-zA-Z][a-zA-Z0-9+.-]*://"; "") | sub("^[^@/]*@"; "") | split("/")[0] | sub(":[0-9]+$"; "")
       | (split(".") | last) as $l | (if (split(".") | length) > 1 and ($l | test("^[A-Z0-9_]+$")) then $l else . end)
       | if test("^[A-Z][A-Z0-9_]*$") then (sub("_(BASE_URL|SERVICE_URL|API_URL|URL|URI|HOST|HOSTNAME|ENDPOINT|ADDR|ADDRESS|BASE)$"; "") | ascii_downcase | gsub("_"; "-"))
         elif test("^[a-z][A-Za-z0-9]*(Url|URL|Host|HOST|Base|BASE|Endpoint)$") then (sub("(Url|URL|Host|HOST|Base|BASE|Endpoint)$"; "") | snake | gsub("_"; "-"))
         else ascii_downcase | sub("\\.[a-z0-9-]+\\.svc(\\.cluster\\.local)?$"; "") | sub("\\.svc(\\.cluster\\.local)?$"; "") end
       | gsub("[^a-z0-9.-]"; "-") | gsub("^-+|-+$"; ""))
      | if . == "" then null else . end
    end;
def url_host: (. // "" | tostring) as $u
  | if ($u | test("^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]+")) then ($u | capture("^[a-zA-Z][a-zA-Z0-9+.-]*://(?<h>[^/]+)").h)
    elif ($u | test("^(\\$\\{[^}]+\\}|\\{\\{[^}]+\\}\\}|\\$[A-Za-z_][A-Za-z0-9_]*|\\{[A-Za-z_][A-Za-z0-9_]*(Url|URL|Host|HOST|Base|BASE)[A-Za-z0-9_]*\\})(/|$)")) then ($u | split("/")[0])
    else null end;

# ---------- package identity (purl, versionless) ----------
def eco_from_manifest: (. // "" | tostring) as $full | ($full | split("/") | last) as $b
  | if   ($b | test("^(package\\.json|deno\\.jsonc?|package-lock\\.json|yarn\\.lock|pnpm-lock\\.yaml)$")) then "npm"
    elif ($b | test("^(requirements.*\\.(txt|in)|pyproject\\.toml|setup\\.py|setup\\.cfg|Pipfile(\\.lock)?|poetry\\.lock|uv\\.lock)$")) then "pypi"
    elif ($b | test("^environment\\.ya?ml$")) then "conda"
    elif ($b | test("^go\\.(mod|work|sum)$")) then "golang"
    elif ($b | test("^Cargo\\.(toml|lock)$")) then "cargo"
    elif ($b | test("^(Gemfile(\\.lock)?|.*\\.gemspec)$")) then "gem"
    elif ($b | test("\\.(csproj|fsproj|vbproj)$|^(packages\\.config|Directory\\.(Packages|Build)\\.props|paket\\.dependencies|packages\\.lock\\.json)$")) then "nuget"
    elif ($b | test("^(pom\\.xml|.*\\.gradle(\\.kts)?|libs\\.versions\\.toml|build\\.sbt|ivy\\.xml|project\\.clj|deps\\.edn|gradle\\.lockfile)$")) then "maven"
    elif ($b | test("^composer\\.(json|lock)$")) then "composer"
    elif ($b | test("^(Podfile(\\.lock)?|.*\\.podspec)$")) then "cocoapods"
    elif ($b | test("^Package\\.(swift|resolved)$")) then "swift"
    elif ($b | test("^pubspec\\.(yaml|lock)$")) then "pub"
    elif ($b | test("^(mix\\.(exs|lock)|rebar\\.config)$")) then "hex"
    elif ($b | test("^(conanfile\\.(txt|py)|conan\\.lock)$")) then "conan"
    elif ($b | test("^vcpkg\\.json$")) then "generic"
    elif ($b | test("\\.cabal$|^(package\\.yaml|stack\\.yaml)$")) then "hackage"
    elif ($b | test("^(DESCRIPTION|renv\\.lock)$")) then "cran"
    elif ($b | test("^(Project|Manifest)\\.toml$")) then "julia"
    elif ($b | test("\\.rockspec$")) then "luarocks"
    elif ($b | test("^Dockerfile|\\.dockerfile$|^(docker-compose|compose).*\\.ya?ml$")) then "docker"
    elif ($b | test("\\.ya?ml$")) and ($full | test("(^|/)\\.github/workflows/")) then "github"
    elif ($b | test("\\.tf$")) then "terraform"
    elif ($b | test("^Chart\\.ya?ml$")) then "helm"
    elif ($b | test("^(MODULE\\.bazel|WORKSPACE(\\.bazel)?)$")) then "bazel"
    else null end;
def ECO_ALIASES: {"npm":"npm","node":"npm","yarn":"npm","pnpm":"npm","pypi":"pypi","pip":"pypi","python":"pypi","maven":"maven","gradle":"maven","sbt":"maven","go":"golang","golang":"golang","cargo":"cargo","crates":"cargo","rust":"cargo","nuget":"nuget","dotnet":"nuget","gem":"gem","rubygems":"gem","composer":"composer","packagist":"composer","php":"composer","pub":"pub","dart":"pub","hex":"hex","elixir":"hex","cocoapods":"cocoapods","pod":"cocoapods","swift":"swift","spm":"swift","conan":"conan","hackage":"hackage","cabal":"hackage","cran":"cran","julia":"julia","luarocks":"luarocks","conda":"conda","docker":"docker","oci":"docker","github":"github","github-action":"github","actions":"github","terraform":"terraform","helm":"helm","bazel":"bazel","generic":"generic","other":"generic","vcpkg":"generic"};
def strip_ver($eco):
  gsub("^\\s+|\\s+$"; "")
  | if $eco == "npm" then (if startswith("@") then "@" + (.[1:] | sub("@.*$"; "")) else sub("@.*$"; "") end)
    elif $eco == "pypi" or $eco == "conda" then sub("\\[.*$"; "") | sub("[<>=!~;\\s].*$"; "")
    elif $eco == "maven" then split(":") | .[0:2] | join(":")
    elif $eco == "golang" then sub("\\s*//.*$"; "") | sub("@.*$"; "") | sub("\\s.*$"; "")
    elif $eco == "docker" then sub("@sha256:.*$"; "") | (if test(":[^/:]+$") then sub(":[^/:]+$"; "") else . end)
    elif $eco == "github" then sub("@.*$"; "")
    else sub("[@\\s].*$"; "") end;
def purl_of($eco; $n0):
  ($n0 | tostring | strip_ver($eco)) as $n
  | if   $eco == "npm"       then ($n | ascii_downcase) as $m | (if ($m | startswith("@")) then "pkg:npm/%40" + ($m[1:]) else "pkg:npm/" + $m end)
    elif $eco == "pypi"      then "pkg:pypi/" + ($n | ascii_downcase | gsub("[-_.]+"; "-"))
    elif $eco == "maven"     then (if ($n | test(":")) then "pkg:maven/" + ($n | split(":") | .[0] + "/" + .[1]) else "pkg:maven/" + $n end)
    elif $eco == "golang"    then "pkg:golang/" + $n
    elif $eco == "cargo"     then "pkg:cargo/" + ($n | ascii_downcase | gsub("_"; "-"))
    elif $eco == "nuget"     then "pkg:nuget/" + ($n | ascii_downcase)
    elif $eco == "gem"       then "pkg:gem/" + $n
    elif $eco == "composer"  then "pkg:composer/" + ($n | ascii_downcase)
    elif $eco == "pub"       then "pkg:pub/" + ($n | ascii_downcase)
    elif $eco == "hex"       then "pkg:hex/" + ($n | ascii_downcase)
    elif $eco == "cocoapods" then "pkg:cocoapods/" + $n
    elif $eco == "swift"     then "pkg:swift/" + ($n | sub("^[a-z]+://"; "") | sub("\\.git$"; "") | ascii_downcase)
    elif $eco == "conda"     then "pkg:conda/" + ($n | ascii_downcase)
    elif $eco == "docker"    then ($n | ascii_downcase) as $m | "pkg:docker/" + (if ($m | test("/")) then $m else "library/" + $m end)
    elif $eco == "github"    then "pkg:github/" + ($n | ascii_downcase | split("/") | .[0:2] | join("/"))
    elif ($eco | IN("conan","hackage","cran","julia","luarocks","terraform","helm","bazel")) then "pkg:" + $eco + "/" + $n
    else "pkg:generic/" + ($n | ascii_downcase | gsub("\\s+"; "-")) end
  | gsub("[\\s?#]"; "-");
def canon_purl:
  (. // "" | tostring | gsub("^\\s+|\\s+$"; "")) as $p
  | ($p | capture("^pkg:(?<t>[A-Za-z][A-Za-z0-9.+-]*)/(?<rest>[^?#]*)") // null) as $m
  | if $m == null then null
    else ($m.t | ascii_downcase) as $t
      | ($m.rest | sub("@[^/]*$"; "")) as $r
      | (ECO_ALIASES[$t] // $t) as $eco
      | if $eco == "npm" then purl_of("npm"; ($r | sub("^%40"; "@")))
        elif $eco == "maven" then purl_of("maven"; ($r | sub("/"; ":")))
        elif ($eco | IN("pypi","cargo","nuget","composer","pub","hex","conda","github","docker","swift")) then purl_of($eco; $r)
        else "pkg:" + $t + "/" + $r end
    end;
def PURL_RE: "^pkg:[a-z][a-z0-9.+-]*/[^@?#\\s]+$";
def dep_purl($e):
  ([$e.manifest_path, ($e.provenance // [] | .[]?.path)] | map(select(. != null) | eco_from_manifest) | map(select(. != null)) | first) as $mfeco
  | (if ($e.purl | type) == "string" and ($e.purl | startswith("pkg:")) then ($e.purl | canon_purl)
     else (($e.package_key // $e.purl // "") | tostring) as $raw
       | (if ($mfeco | IN("docker","github")) then {e: $mfeco, n: (if $raw == "" then ($e.name // "unknown") else $raw end | tostring)}   # image:tag / owner/repo@ref look like prefixes
          elif ($raw | test("^[a-z][a-z-]*:")) and ((ECO_ALIASES[($raw | split(":")[0])]) != null)
            then {e: ECO_ALIASES[($raw | split(":")[0])], n: ($raw | sub("^[a-z-]+:"; ""))}
            else {e: ($mfeco // "generic"), n: (if $raw == "" then ($e.name // "unknown") else $raw end | tostring)} end) as $k
       | (if $k.e == "generic" and ($k.n | test("^[a-z]+/")) and (ECO_ALIASES[($k.n | split("/")[0])] != null)
            then purl_of(ECO_ALIASES[($k.n | split("/")[0])]; ($k.n | sub("^[a-z]+/"; ""))) else purl_of($k.e; $k.n) end)
     end)
  | if . != null and test(PURL_RE) then . else "pkg:generic/" + ((($e.name // "unknown") | tostring | slug) // "unknown") end;
def norm_topic:
  (. // "unknown" | tostring | gsub("^\\s+|\\s+$"; ""))
  | if test("^arn:aws:[a-z]+:[^:]*:[^:]*:") then sub("^arn:aws:[a-z]+:[^:]*:[^:]*:"; "")
    elif test("^https://sqs\\.[^/]+/[0-9]+/") then sub("^https://sqs\\.[^/]+/[0-9]+/"; "")
    elif test("^projects/[^/]+/(topics|subscriptions)/") then sub("^projects/[^/]+/(topics|subscriptions)/"; "")
    else . end
  | if . == "" then "unknown" else . end;
def ident: tostring | gsub("[`\"\\[\\]]"; "") | gsub("^\\s+|\\s+$"; "");

# ---------- shaping ----------
def base_fields: {name: ((.name // .id // "unnamed") | tostring)} + (if (.description|type) == "string" then {description} else {} end) + claim_fields;
def pick(keys): . as $o | reduce keys[] as $k ({}; if ($o[$k] | . != null and . != "") then .[$k] = ($o[$k] | tostring) else . end);
def xfields: with_entries(select(.key | startswith("x-")));

def shape($coll):
  . as $e
  | (if $coll == "components" then base_fields
       + {module_id: ((.module_id // "") | rel_path | sub("/+$"; "") | if . == "" then "." else . end), kind: (.kind | coerce(E_COMP; A_COMP; "other"))} + pick(["language"])
    elif $coll == "interfaces" then
      (.kind // "" | key) as $rk
      | (if ($rk | IN("graphql","grpc","thrift","jsonrpc","json-rpc","twirp","connect")) then ($rk | coerce(E_RPC; A_RPC; "other")) else null end) as $proto
      | (.kind | coerce(E_IKIND; A_IKIND; "library")) as $k
      | (.role | coerce(E_ROLE; A_ROLE; "provides")) as $role
      | base_fields + {kind: $k, role: $role}
      + (if $role == "provides" and ((.service_key // "") != "") then {service_key: ((.service_key | tostring | slug) // "unknown")} else {} end)
      + (if $k == "http" then
           ((.http // {}) | (.normalized_path // .path // .url // "/")) as $p
           | {http: ({method: ((.http.method // "ANY") | tostring | ascii_upcase | . as $m | if IN("ALL","*","USE","") then "ANY" elif (E_METH | index([$m])) then $m else "ANY" end),
                      normalized_path: ($p | norm_path)}
                     + (if $role == "consumes" then (((.http.host // .host // ($p | url_host)) | norm_host) | if . then {host: .} else {} end) else {} end))}
         elif $k == "websocket" then
           ((.websocket // .http // {}) | (.normalized_path // .path // .url // "/")) as $p
           | {websocket: ({normalized_path: ($p | norm_path)} + (if $role == "consumes" then (((.websocket.host // .host // ($p | url_host)) | norm_host) | if . then {host: .} else {} end) else {} end))}
         elif $k == "event" then {event: {transport: ((.event.transport // "other") | coerce(E_TRANS; A_TRANS; "other")), topic: ((.event.topic // .name) | norm_topic)}}
         elif $k == "rpc" then {rpc: {protocol: ((.rpc.protocol // $proto // "other") | coerce(E_RPC; A_RPC; "other")),
                                      service: ((.rpc.service // .name // "unknown") | tostring), method: ((.rpc.method // "unknown") | tostring)}}
         else {symbol: ((.symbol // .name // "unknown") | tostring)} end)
    elif $coll == "dependencies" then
      ((.version_constraint // "") | tostring) as $vc
      | ((.manifest_path // ((.provenance // [])[0].path?) // "unknown") | rel_path) as $mp
      | base_fields
      + {purl: dep_purl($e), manifest_path: $mp, scope: (.scope | coerce(E_SCOPE; A_SCOPE; "runtime")),
         source: (if ($vc | test("^(workspace|portal):")) then "workspace" elif ($vc | test("^(file|link|path):")) then "path"
                  elif ($vc | test("^(git\\+|git:|github:|https?://.*\\.git)")) then "git" else (.source | coerce(E_SRC; A_SRC; "registry")) end)}
      + pick(["version_constraint","resolved_version"])
    elif $coll == "datastores" then
      ((.engine | coerce(E_ENG; A_ENG; "other"))) as $eng
      | ((.schema // "") | ident | if (SQL_ENGINES | index([$eng])) then ascii_downcase else . end
         | if ($eng == "postgres" and . == "public") or ($eng == "mssql" and . == "dbo") then "" else . end) as $sch
      | ((.table // "") | ident | if (SQL_ENGINES | index([$eng])) then ascii_downcase else . end) as $tbl
      | base_fields + {engine: $eng, access: (.access | coerce(E_ACC; A_ACC; "readwrite"))}
        + (if $sch != "" then {schema: $sch} else {} end) + (if $tbl != "" then {table: $tbl} else {} end)
        + (((.instance_key // "") | tostring | gsub("\\s+"; "-")) as $ik | if $ik != "" and ($ik | test("[:/@]") | not) then {instance_key: $ik} else {} end)
    elif $coll == "business_rules" then base_fields + {statement: ((.statement // .name // "unspecified") | tostring)} + (if (.applies_to|type) == "array" then {applies_to: (.applies_to | strs)} else {} end)
    elif $coll == "workflows" then base_fields + pick(["trigger"])
         + {steps: ([.steps[]? | select(type == "object") | {description: ((.description // .name // "step") | tostring)} + pick(["entity_id"]) + {o: (.order // 1e9)}]
                    | sort_by(.o) | to_entries | map(.value | del(.o)) | to_entries | map(.value + {order: (.key + 1)})
                    | if length == 0 then [{order: 1, description: "unspecified"}] else . end)}
    elif $coll == "artifacts" then
      (.kind | coerce(E_AKIND; A_AKIND; "other")) as $ak
      | base_fields + {kind: $ak,
          purl: (if $ak == "container_image" and ((.purl // "") | tostring | startswith("pkg:") | not) then purl_of("docker"; (.image // .name // "unknown"))
                 else dep_purl($e) end),
          manifest_path: ((.manifest_path // ((.provenance // [])[0].path?) // "unknown") | rel_path)} + pick(["version"])
    elif $coll == "services" then
      base_fields + {service_key: ((((.service_key // .name) | tostring) | slug) // "unknown"), runtime: (.runtime | coerce(E_RUNTIME; A_RUNTIME; "other"))}
      + (if (.ports | type) == "array" then {ports: ([.ports[] | (tonumber? // empty) | floor | select(. > 0 and . < 65536)] | unique)} else {} end)
      + (if (.environments | type) == "array" then {environments: (.environments | strs | map(ascii_downcase) | unique)} else {} end)
    elif $coll == "config_keys" then
      ((.name // "unknown") | tostring | gsub("\\s+"; "")) as $n
      | base_fields + {name: $n, source: (.source | coerce(E_CSRC; A_CSRC; "env")),
                       is_secret: (if (.is_secret | type) == "boolean" then .is_secret
                                   else ($n | test("(secret|passw|pwd|token|api[_-]?key|private|credential|dsn|conn(ection)?[_-]?str|license[_-]?key|access[_-]?key|signing|(database|db|redis|mongo|mongodb|amqp|rabbit|broker|postgres|mysql|sql)[_-]?(url|uri))"; "i")) end)}
    elif $coll == "external_services" then
      ((.domain // .url // .name // "unknown") | tostring | sub("^[a-zA-Z]+://"; "") | sub("^[^@/]*@"; "") | split("/")[0] | sub(":[0-9]+$"; "") | ascii_downcase | gsub("[^a-z0-9.-]"; "")) as $d
      | base_fields + {domain: $d, category: (.category | coerce(E_XCAT; A_XCAT; "other"))} + pick(["vendor"])
    elif $coll == "api_specs" then
      ((.path // ((.provenance // [])[0].path?) // "unknown") | rel_path) as $sp
      | base_fields + {path: $sp,
          format: (if .format then (.format | coerce(E_SPEC; A_SPEC; "other"))
                   elif ($sp | test("\\.proto$")) then "proto" elif ($sp | test("\\.(graphqls?|gql)$")) then "graphql_sdl"
                   elif ($sp | test("asyncapi"; "i")) then "asyncapi" elif ($sp | test("swagger"; "i")) then "swagger"
                   elif ($sp | test("openapi"; "i")) then "openapi" elif ($sp | test("\\.avsc$")) then "avro" elif ($sp | test("\\.wsdl$")) then "wsdl" else "other" end)}
      + pick(["version"])
    else base_fields end)
  | . + ($e | xfields);

# expand multi-method HTTP routes into one entity per method; remember the base local id
def expand_methods:
  if ((.kind // "") | key | IN("http","rest","route","endpoint","api")) then
    ((.http.method // "ANY") | if type == "array" then [.[] | tostring] else (tostring | [splits("[,|/ ]+")] | map(select(. != ""))) end) as $ms
    | if ($ms | length) > 1 then (.id // null) as $base | $ms[] as $m | (.http.method = $m) | (if $base then .id = ($base + "#" + ($m | ascii_downcase)) else . end) | .x_local_base = $base
      else . end
  else . end;

def merge_group: (sort_by(.confidence | rank) | .[0]) as $best
  | $best + {provenance: ([.[].provenance[]] | unique_by([.path, .line, .end_line]) | sort_by([.path, .line, (.end_line // 0)]))};

# ---------- pipeline ----------
. as $draft
| ["components","interfaces","dependencies","datastores","business_rules","workflows","artifacts","services","config_keys","external_services","api_specs"] as $colls
| def ext_domain_ok: ((.domain // .url // .name // "") | tostring | sub("^[a-zA-Z]+://"; "") | sub("^[^@/]*@"; "") | split("/")[0] | sub(":[0-9]+$"; "") | ascii_downcase | gsub("[^a-z0-9.-]"; "")) | test("^[a-z0-9-]+(\\.[a-z0-9-]+)+$");
  [ $colls[] as $c | ($draft.entities[$c] // [])[] | select(type == "object")
    | select($c != "components" or (.module_id | rel_path | in_kb | not))
    | select($c != "external_services" or ext_domain_ok)
    | if $c == "interfaces" then expand_methods else . end
    | {coll: $c, local: ((.id // null) | if . == null then null else tostring end), lbase: (.x_local_base // null), ent: (del(.x_local_base) | shape($c))}
    | .ent.id = (.ent | ckb_derive_id($c)) ] as $shaped
| ( [ $shaped[] | select(.ent.id == null) ]
    | group_by(.coll) | map(
        (.[0].coll | if . == "business_rules" then "business_rule" else "workflow" end) as $t
        | map(.ent.name as $n | .s = ($n | slug_or($n)))
        | sort_by([.s, .ent.name, (.ent.provenance[0].path // ""), (.ent.provenance[0].line // 0), (.ent.statement // "")])
        | group_by(.s)
        | map(to_entries | map(.key as $k | .value | .ent.id = "\($t):\(.s)" + (if $k > 0 then "-\($k + 1)" else "" end) | del(.s))) | add)
    | add // [] ) as $slugged
| ([ $shaped[] | select(.ent.id != null) ] + $slugged) as $all
| ([ $all[].ent.id ] | unique) as $final_ids
| ([ $all[] | select(.local != null) ] | group_by(.local) | map({key: .[0].local, value: ([.[].ent.id] | unique)})) as $locals
| ([ $all[] | select(.lbase != null) ] | group_by(.lbase) | map({key: .[0].lbase, value: ([.[].ent.id] | unique)})) as $bases
| ([ $locals[] | select(.value | length > 1) | .key ]) as $ambiguous
| ((reduce ($locals[] | select(.value | length == 1)) as $l ({}; .[$l.key] = $l.value[0]))
   + reduce $final_ids[] as $f ({}; .[$f] = $f)) as $idmap
| (reduce $bases[] as $b ({}; .[$b.key] = $b.value)) as $basemap
| def remap: . as $r | $idmap[$r];
  def remap_all: . as $r | if $idmap[$r] then [$idmap[$r]] else ($basemap[$r] // []) end;
  ( $colls | map(. as $c | {key: $c, value: (
      [ $all[] | select(.coll == $c) | .ent ] | group_by(.id) | map(merge_group)
      | map(if $c == "business_rules" and has("applies_to") then .applies_to |= ([.[] | remap_all[]] | unique) | (if .applies_to == [] then del(.applies_to) else . end) else . end)
      | map(if $c == "workflows" then .steps |= map(if has("entity_id") then (.entity_id | remap) as $m | (if $m then .entity_id = $m else del(.entity_id) end) else . end) else . end)
      | sort_by(.id)) }) | from_entries | with_entries(select(.value | length > 0)) ) as $entities
| (reduce ($entities.interfaces // [])[] as $i ({}; .[$i.id] = $i.role)) as $role_of
| def rel_ok: . as $r | (ckb_relation_rules[$r.kind]) as $rule | ($r.from | ckb_prefix) as $fp | ($r.to | ckb_prefix) as $tp
    | ($rule != null) and (($rule.from | index([$fp])) != null) and (($rule.to | index([$tp])) != null);
  ( [ ($draft.relations // [])[] | select(type == "object" and .from and .to and .kind)
      | select(.kind | enum_ok(E_REL; A_REL))
      | (.kind | coerce(E_REL; A_REL; "depends_on")) as $kind | claim_fields as $cf
      | (.from | tostring | remap_all[]) as $f | (.to | tostring | remap_all[]) as $t
      | {from: $f, to: $t, kind: (if ($kind | IN("provides","consumes")) and $role_of[$t] and $role_of[$t] != $kind then $role_of[$t] else $kind end)} + $cf
      | select(rel_ok) ]
    | group_by([.from, .to, .kind]) | map(merge_group) | sort_by([.from, .kind, .to]) ) as $relations
| ([ $entities[][], $relations[] ]) as $claims
| {confirmed: ([$claims[] | select(.confidence == "confirmed")] | length),
   inferred:  ([$claims[] | select(.confidence == "inferred")]  | length),
   unknown:   ([$claims[] | select(.confidence == "unknown")]   | length)} as $n
| ($n + {overall: (if ($claims | length) == 0 then "unknown"
                   elif $n.inferred == 0 and $n.unknown == 0 then "confirmed"
                   elif $n.unknown > ($n.confirmed + $n.inferred) then "unknown"
                   else "inferred" end)}) as $summary
| (($draft.repo_profile // {}) | if type == "object" then
     ({} + (if (.languages | type) == "array" then {languages: ([.languages[] | if type == "string" then {name: ., files: 0} else {name: (.name | tostring), files: ((.files // 0) | (tonumber? // 0) | floor)} end] | unique_by(.name) | sort_by([-.files, .name]))} else {} end)
         + (if (.frameworks | type) == "array" then {frameworks: (.frameworks | strs | unique)} else {} end)
         + (if (.build_tools | type) == "array" then {build_tools: (.build_tools | strs | unique)} else {} end)
         + (if (.license | type) == "string" and .license != "" then {license} else {} end)
         + (if (.owners | type) == "array" then {owners: ([.owners[] | if type == "string" then {name: ., source: "other"} else {name: (.name | tostring), source: ((.source // "other") | tostring | if IN("codeowners","catalog-info","manifest","other") then . else "other" end)} end] | unique_by(.name))} else {} end))
   else {} end) as $profile0
| (if ($profile0 | length) > 0 then ({languages: [], frameworks: [], build_tools: [], owners: []} + $profile0) else {} end) as $profile
| {artifact: ({ckb_version: "0.2", repo: $repo, generator: $generator}
              + (if ($profile | length) > 0 then {repo_profile: $profile} else {} end)
              + {confidence_summary: $summary, entities: $entities}
              + (if ($relations | length) > 0 then {relations: $relations} else {} end)),
   idmap: (reduce ($locals[] | select(.value | length == 1)) as $l ({}; .[$l.key] = $l.value[0])),
   warnings: ([ $colls[] as $c | ($draft.entities[$c] // [])[] | select(type == "object") | select(downgraded) | "downgraded to unknown (no verifiable provenance): \($c)/\(.id // .name)" ]
              + [ ($draft.relations // [])[] | select(type == "object") | select(downgraded) | "downgraded to unknown (no verifiable provenance): relation \(.from) -> \(.to)" ]
              + [ ($draft.relations // [])[] | select(type != "object" or ((.from and .to and .kind) | not)) | "dropped malformed relation" ]
              + [ ($draft.relations // [])[] | select(type == "object" and .kind and (.kind | enum_ok(E_REL; A_REL) | not)) | "dropped relation with unknown kind '\(.kind)': \(.from) -> \(.to)" ]
              + [ ($draft.relations // [])[] | select(type == "object" and .from and .to) | select(((.from|tostring|remap_all) == []) or ((.to|tostring|remap_all) == [])) | "dropped relation with unresolved endpoint: \(.from) -> \(.to)" ]
              + [ ($draft.relations // [])[] | select(type == "object" and .from and .to and .kind and (.kind | enum_ok(E_REL; A_REL)))
                  | (.kind | coerce(E_REL; A_REL; "depends_on")) as $k | ((.from|tostring|remap_all) + (.to|tostring|remap_all)) as $ft
                  | select(($ft | length) == 2) | select(({from: $ft[0], to: $ft[1], kind: $k} | rel_ok) | not)
                  | "dropped relation not allowed by the spec (\($ft[0] | ckb_prefix) -\($k)-> \($ft[1] | ckb_prefix)): \(.from) -> \(.to)" ]
              + [ ($draft.entities.business_rules // [])[] | .applies_to[]? | tostring | select(remap_all == []) | "dropped unresolved applies_to reference: \(.)" ]
              + [ ($draft.entities.workflows // [])[] | .steps[]? | .entity_id? // empty | tostring | select(remap == null) | "dropped unresolved workflow step reference: \(.)" ]
              + [ $ambiguous[] | "local id '\(.)' names more than one entity; references to it were dropped" ]
              + [ ($draft.entities.config_keys // [])[] | select(type == "object" and (has("value") or has("default"))) | "config key '\(.name)': value/default dropped (CKB stores names only)" ]
              + [ ($draft.entities.external_services // [])[] | select(type == "object") | select(ext_domain_ok | not) | "dropped external service without a hostname: \(.name // .id)" ]
              + [ ($draft.entities.datastores // [])[] | select(type == "object") | select(((.instance_key // "") | tostring | test("[:/@]"))) | "datastore '\(.name)': instance_key looked like a connection string and was dropped (store the env var NAME)" ]
              + [ $colls[] as $c | ($draft.entities[$c] // [])[] | select(type == "object") | .provenance[]? | .path? // empty | rel_path | select(test(GENERATED_RE)) | "citation in generated/vendored code: \(.)" ]
              + [ $colls[] as $c | ($draft.entities[$c] // [])[] | select(type == "object")
                  | (if $c == "components" then [["kind", .kind, E_COMP, A_COMP]] elif $c == "interfaces" then [["kind", .kind, E_IKIND, A_IKIND], ["role", .role, E_ROLE, A_ROLE]]
                     elif $c == "dependencies" then [["scope", .scope, E_SCOPE, A_SCOPE]] elif $c == "datastores" then [["engine", .engine, E_ENG, A_ENG], ["access", .access, E_ACC, A_ACC]]
                     elif $c == "artifacts" then [["kind", .kind, E_AKIND, A_AKIND]] elif $c == "services" then [["runtime", .runtime, E_RUNTIME, A_RUNTIME]]
                     elif $c == "external_services" then [["category", .category, E_XCAT, A_XCAT]] else [] end)[]
                  | . as $t | select($t[1] != null and ($t[1] | enum_ok($t[2]; $t[3]) | not)) | "unrecognised \($c) \($t[0]) '\($t[1])' coerced to default" ]
              + [ ($entities.dependencies // [])[] | select(.purl | startswith("pkg:generic/")) | "dependency without a known ecosystem (pkg:generic): \(.name) at \(.manifest_path)" ]
              | unique)}
