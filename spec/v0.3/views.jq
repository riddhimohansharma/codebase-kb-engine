# views.jq — CKB v0.3 normative views. Pure functions of one artifact (input = ckb.json); same input => same output on every conforming
# implementation. Each view is BOUNDED and returns compact records with citations ("path:line[-end]") so an agent answers a question in a few
# hundred tokens instead of loading the artifact. Use:  jq -L schema/v0.3 'include "views"; ckb_view_impact("src/orders/routes.ts")' ckb.json
def cite: (.provenance // []) | map("\(.path):\(.line)\(if .end_line then "-\(.end_line)" else "" end)");
def brief: {id, name, confidence} + (if (cite | length) > 0 then {at: (cite | .[0:3])} else {} end);
def glob_match($path): . as $g
  | if $g == $path then true
    elif ($g | endswith("/**")) then ($path | startswith($g | sub("/\\*\\*$"; "/")))
    elif ($g | test("^\\*\\*/")) then ($path | endswith($g | sub("^\\*\\*/"; "")))
    elif ($g | endswith("/*")) then (($path | startswith($g | sub("\\*$"; ""))) and (($path | sub($g | sub("\\*$"; ""); "")) | contains("/") | not))
    else false end;
def ckb_cap: if length > 50 then .[0:50] + [{truncated: (length - 50)}] else . end;

# summary: what this repo is and how to run it, in one small object
def ckb_view_summary:
  {repo: (.repo | {key: (.key // (.url | sub("^https://"; "") | ascii_downcase)), branch, commit_sha: .commit_sha[0:12]}),
   taxonomy: (.repo_profile.taxonomy // {}), languages: ([.repo_profile.languages[]? | .name] | .[0:5]),
   counts: ((.entities // {}) | with_entries(.value |= length)), relations: ((.relations // []) | length),
   commands: ([.entities.commands[]? | {kind, command}] | ckb_cap),
   do_not_edit: ((.repo_profile.generated_globs // []) + (.repo_profile.vendored_globs // []) | unique | ckb_cap)};

def ckb_view_commands($kind): [.entities.commands[]? | select($kind == null or $kind == "" or .kind == $kind) | {id, kind, command, cwd: (.cwd // "."), at: (cite | .[0:1])}] | sort_by(.id) | ckb_cap;

def ckb_view_entity($id): (.relations // []) as $r
  | ([.entities[][]? | select(.id == $id)] | first) as $e
  | if $e == null then null else
    {entity: ($e | del(.provenance) + {at: ($e | cite)}),
     out: ([$r[] | select(.from == $id) | {kind, to, confidence}] | sort_by([.kind, .to]) | ckb_cap),
     in:  ([$r[] | select(.to == $id) | {kind, from, confidence}] | sort_by([.kind, .from]) | ckb_cap)} end;

def ckb_view_interfaces($service_key): [.entities.interfaces[]? | select($service_key == null or $service_key == "" or .service_key == $service_key)
  | {id, role, kind, at: (cite | .[0:1])}] | sort_by(.id) | ckb_cap;

# impact: everything this artifact says touches a path: entities cited at it, components containing it, the relations of those,
# and the invariants (constraints, traps, obligations) that govern it.
def ckb_view_impact($path): . as $a
  | ([$a.entities[][]? | select(any((.provenance // [])[]; .path == $path))] | map(.id)) as $cited
  | ([$a.entities.components[]? | select(.module_id as $m | $m == "." or $path == $m or ($path | startswith($m + "/"))) | .id]) as $comps
  | (($cited + $comps) | unique) as $ids
  | {path: $path,
     components: $comps,
     cited_by: ($cited | ckb_cap),
     relations: ([($a.relations // [])[] | select((.from as $f | $ids | index($f)) or (.to as $t | $ids | index($t))) | {from, kind, to}] | sort_by([.from, .kind, .to]) | ckb_cap),
     invariants: ([$a.entities.invariants[]? | select(any((.applies_to // [])[]; glob_match($path)) or any((.obligates // [])[]; . == $path))
                   | {id, kind, statement, obligates: (.obligates // [])}] | sort_by(.id) | ckb_cap)};
