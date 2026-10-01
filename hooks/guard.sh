#!/usr/bin/env bash
# Read-only enforcement gate for codebase-kb-engine (PreToolUse, all tools).
# Contract: exit 2 = BLOCK (reason -> stderr, returned to Claude); exit 0 = ALLOW.
#
# SCOPE: enforces only in sessions that are ARMED (an engine command was typed, or a plugin
# script was invoked — see arm.sh), or when CKB_ENFORCE=always (set by the codebase-kb-engine/run.sh wrappers).
# Unarmed sessions pass through untouched, so installing the plugin never locks normal work.
#
# POLICY when enforcing — fails CLOSED:
#   · Write/Edit only inside a dir marked `.ckb-output` (created by scripts/resolve-kb.sh); inside a git work tree
#     only at exactly <work-tree>/ckb — the rest of the repo stays read-only. Symlinks resolved before checking.
#   · Bash: plugin's own scripts, plus a read-only command allowlist; every segment head is checked.
#   · Any tool not on the known non-mutating list is blocked (MCP tools included).
set -uo pipefail
payload="$(cat)"
GUARD_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PLUGIN_ROOT="$(cd "$GUARD_DIR/.." && pwd -P)"
STATE="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}/ckb-guard}/armed"
block(){ echo "BLOCKED by codebase-kb-engine read-only mode: $*" >&2; exit 2; }
jqget(){ command -v jq >/dev/null 2>&1 && printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null; }
rawget(){ printf '%s' "$payload" | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed -E 's/.*"([^"]*)"$/\1/'; }

# one jq pass for all fields (latency: this hook runs on every tool call); raw-grep fallback when jq is absent
sid=""; tool=""; cwd=""; c0=""
if command -v jq >/dev/null 2>&1; then
  eval "$(printf '%s' "$payload" | jq -r '@sh "sid=\(.session_id // "") tool=\(.tool_name // "") cwd=\(.cwd // "") c0=\(.tool_input.command // "")"' 2>/dev/null)"
fi
[ -z "$sid" ] && sid="$(rawget session_id)"; [ -z "$tool" ] && tool="$(rawget tool_name)"; [ -z "$cwd" ] && cwd="$(rawget cwd)"
sid="$(printf '%s' "${sid:-}" | tr -cd 'A-Za-z0-9_-')"; [ -z "${cwd:-}" ] && cwd="$PWD"

SCRIPTS='resolve-kb.sh|clone.sh|finalize.sh|validate.sh|freshness.sh|inventory.sh|coverage.sh|lint-docs.sh|reference.sh|docmeta.sh|kbq.sh|stats.sh|telemetry.sh'
is_plugin_script(){ # $1 = command head; true only for this plugin's own scripts, by real path
  local d b
  case "$1" in */scripts/*) ;; *) return 1 ;; esac
  b="$(basename "$1")"; printf '%s' "$b" | grep -qxE "$SCRIPTS" || return 1
  d="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" || return 1
  [ "$d" = "$PLUGIN_ROOT/scripts" ]
}

armed(){
  [ "${CKB_ENFORCE:-}" = always ] && return 0
  [ -n "$sid" ] && [ -f "$STATE/$sid" ] && [ -z "$(find "$STATE/$sid" -mmin +1440 2>/dev/null)" ] && return 0
  return 1
}
arm(){ [ -n "$sid" ] && mkdir -p "$STATE" 2>/dev/null && chmod 700 "$STATE" 2>/dev/null && : > "$STATE/$sid"; }

# Invoking a plugin script arms the session (arming only ever adds restriction, so the model may trigger it).
if [ "${tool:-}" = Bash ]; then
  [ -z "$c0" ] && c0="$(jqget '.tool_input.command')"
  first="$(printf '%s' "${c0:-}" | sed -E 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//' | awk '{print $1}' | tr -d "\"'")"
  is_plugin_script "${first:-}" && arm
fi
armed || exit 0
case "${tool:-}" in Read|Grep|Glob|LS|Task|Agent|Skill|ToolSearch|TodoWrite|TodoRead|TaskCreate|TaskUpdate|TaskList|TaskGet|TaskOutput|BashOutput) exit 0 ;; esac

canon(){ # canonical absolute path for a possibly-nonexistent path (symlinks in existing part resolved)
  local p="$1" rest=""
  case "$p" in /*) ;; *) p="$cwd/$p" ;; esac
  while [ ! -d "$p" ]; do rest="/$(basename "$p")$rest"; p="$(dirname "$p")"; done
  printf '%s%s\n' "$(cd "$p" && pwd -P)" "$rest"
}
inside(){ case "$1/" in "$2"/*) return 0 ;; *) return 1 ;; esac; }
kb_root_of(){ # nearest ancestor dir carrying .ckb-output
  local d; d="$(dirname "$1")"
  while [ "$d" != "/" ] && [ -n "$d" ]; do [ -f "$d/.ckb-output" ] && { printf '%s\n' "$d"; return 0; }; d="$(dirname "$d")"; done
  return 1
}
write_allowed(){ # $1 = raw file path
  local fp kb wt
  case "$1" in *..*) block "write path contains '..': $1" ;; "") block "write with no path (fail-closed)" ;; esac
  fp="$(canon "$1")"
  kb="$(kb_root_of "$fp")" || block "writes are allowed only inside the KB dir (<repo>/ckb, marked .ckb-output); denied: $fp"
  # inside a git work tree the ONLY writable place is exactly <work-tree>/ckb (a forged marker elsewhere is useless)
  if wt="$(git -C "$(dirname "$kb")" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$wt" ]; then
    wt="$(cd "$wt" && pwd -P)"
    [ "$kb" = "$wt/ckb" ] || block "inside a git work tree only '$wt/ckb' is writable; denied: $fp"
  fi
  return 0
}

case "${tool:-}" in
  Bash) ;;                                                # inspect the command below
  Write|Edit|MultiEdit)
    fp="$(jqget '.tool_input.file_path')"; [ -z "${fp:-}" ] && fp="$(jqget '.tool_input.path')"
    write_allowed "${fp:-}"; exit 0 ;;
  NotebookEdit) block "tool '$tool' modifies files." ;;
  "") block "could not determine tool name (fail-closed)." ;;
  Read|Grep|Glob|LS|WebFetch|WebSearch|Task|Agent|Skill|ToolSearch|TodoWrite|TodoRead|TaskCreate|TaskUpdate|TaskList|TaskGet|TaskOutput|BashOutput|KillShell|KillBash|TaskStop|AskUserQuestion|EnterPlanMode|ExitPlanMode|SendMessage|ListMcpResourcesTool|ReadMcpResourceTool)
    exit 0 ;;
  *) block "tool '$tool' is not on the read-only allowlist (type /kb-unlock to leave read-only mode)." ;;
esac

cmd="$c0"; [ -z "${cmd:-}" ] && cmd="$(jqget '.tool_input.command')"
[ -z "${cmd:-}" ] && cmd="$payload"                      # fail-closed: scan raw payload if unparseable

# 1) file-writing redirection: strip only safe sinks (/dev + fd dup); any '>' left => write
redscrub="$(printf '%s' "$cmd" \
  | sed -E 's#&>[[:space:]]*/dev/(null|stdout|stderr)##g' \
  | sed -E 's#[0-9]*>>?[[:space:]]*/dev/(null|stdout|stderr)##g' \
  | sed -E 's#[0-9]*>&[0-9]*##g')"
printf '%s' "$redscrub" | grep -q '>' && block "output redirection would write a file: $cmd"

# 2) in-place stream edits
printf '%s' "$cmd" | grep -qiE '(^|[^[:alpha:]])(sed|perl|gawk|awk)([[:space:]]).*(-i([[:space:]=]|$)|--in-place)' \
  && block "in-place edit: $cmd"

# 3) broad nets for destructive verbs / installers / pipe-to-shell (catches $(...) and loop bodies)
printf '%s' "$cmd" | grep -qiE '(^|[^[:alnum:]_./-])(rm|rmdir|unlink|shred|mkfs[.a-z]*|truncate|tee|dd|chmod|chown|chgrp|mv|cp|ln|mkdir|touch|patch|rsync)([[:space:]]|$)' \
  && block "destructive/write command: $cmd"
printf '%s' "$cmd" | grep -qiE '(^|[^[:alnum:]_./-])(npm|pnpm|yarn|pip[0-9]*|pipx|poetry|cargo|go|apt|apt-get|dpkg|brew|gem|composer|make|cmake|gradle|mvn|docker|podman|kubectl|terraform|helm|ansible|systemctl|service)([[:space:]]|$)' \
  && block "build/install/deploy command (blocked in read-only engine): $cmd"
printf '%s' "$cmd" | grep -qiE '(curl|wget|fetch)[[:space:]].*\|[[:space:]]*(ba|z|k)?sh([[:space:]]|$)' \
  && block "pipe-to-shell: $cmd"
printf '%s' "$cmd" | grep -qE ':\(\)[[:space:]]*\{[[:space:]]*:' && block "fork bomb: $cmd"

# 3b) environment overrides that make read-only tools execute code (git pagers/diff drivers, loader injection, shells)
printf '%s' "$cmd" | grep -qE '(^|[[:space:];&|(])(GIT_[A-Z_]*|LD_[A-Z_]*|DYLD_[A-Z_]*|PAGER|MANPAGER|LESS[A-Z_]*|EDITOR|VISUAL|BASH_ENV|ENV|PATH|SHELL|PS4|PROMPT_COMMAND|PERL5OPT|PERL5LIB|PYTHON[A-Z_]*|RUBYOPT|NODE_OPTIONS|JQ_LIB)=' \
  && block "environment override that can execute code: $cmd"
# 3c) read-only tools with write/exec modes
printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_./-])find[[:space:]].*[[:space:]]-(delete|exec|execdir|ok|okdir|fprint|fprint0|fprintf|fls)([[:space:]]|$)' && block "find with a write/exec action: $cmd"
printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_./-])sort[[:space:]].*(-o|--output)([[:space:]=]|$)' && block "sort writing a file: $cmd"
printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_./-])tree[[:space:]].*-o([[:space:]]|$)' && block "tree writing a file: $cmd"
printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_./-])yq[[:space:]].*(-i|--inplace)([[:space:]=]|$)' && block "yq in-place edit: $cmd"
printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_./-])(cloc|tokei)[[:space:]].*(--out|--report-file|-o)([[:space:]=]|$)' && block "report writing a file: $cmd"
printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_./-])awk[[:space:]].*system[[:space:]]*\(' && block "awk system(): $cmd"
if printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_./-])sed[[:space:]]'; then
  printf '%s' "$cmd" | grep -qE "(^|[;{}'\"[:space:]])[0-9,\$]*[wWe]([[:space:]]|$|['\";}])|/[gpiImM0-9]*[we]([[:space:]'\";}]|$)" && block "sed w/e command (writes or executes): $cmd"
fi

# 4) default-deny allowlist: every command segment head must be a read-only command
sc="$(printf '%s' "$cmd" \
  | sed -E 's#[0-9]*>&[0-9]*##g' \
  | sed -E 's#&>[[:space:]]*[^[:space:];|&]*##g' \
  | sed -E 's#[0-9]*>>?[[:space:]]*[^[:space:];|&]*##g')"
# normalize all shell separators to ';' (portable), then split on newlines via tr
sc="$(printf '%s' "$sc" | sed -E 's/\|\|/;/g; s/&&/;/g; s/\|/;/g; s/&/;/g')"
segs="$(printf '%s' "$sc" | tr ';' '\n')"
all_plugin=1
READ='^(ls|cat|head|tail|bat|less|more|grep|egrep|fgrep|rg|ag|find|fd|tree|wc|stat|file|du|df|pwd|echo|printf|true|:|test|\[|which|type|whoami|id|uname|hostname|date|sort|uniq|cut|tr|column|nl|tac|comm|diff|jq|yq|awk|sed|od|hexdump|strings|md5sum|sha256sum|shasum|cksum|basename|dirname|realpath|readlink|expr|seq|env|printenv|cd|pushd|popd|dirs|man|cloc|tokei|wait|sleep|for|while|if|case|read)$'
while IFS= read -r seg; do
  seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  [ -z "$seg" ] && continue
  # strip transparent prefixes and VAR=val assignments
  while :; do
    h="$(printf '%s' "$seg" | awk '{print $1}')"
    case "$h" in
      sudo|env|time|nohup|command|builtin|exec|do|then|else|elif|"{"|"("|"!")
        seg="$(printf '%s' "$seg" | sed -E 's/^[^[:space:]]+[[:space:]]+//')" ;;
      *)
        if printf '%s' "$h" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*='; then
          seg="$(printf '%s' "$seg" | sed -E 's/^[^[:space:]]+[[:space:]]+//')"
        else break; fi ;;
    esac
    [ -z "$seg" ] && break
  done
  h="$(printf '%s' "$seg" | awk '{print $1}' | tr -d "\"'")"
  [ -z "$h" ] && continue
  if is_plugin_script "$h"; then continue; fi
  all_plugin=0
  if [ "$h" = "git" ]; then
    # strip global options so `git -C x commit` is judged as `commit`; config/exec overrides are never allowed
    gs="$(printf '%s' "$seg" | sed -E 's/^git([[:space:]]+|$)//')"
    while :; do
      tok="$(printf '%s' "$gs" | awk '{print $1}')"
      case "$tok" in
        -c|-c*|--config-env|--config-env=*|--exec-path|--exec-path=*) block "git config/exec override not allowed: $cmd" ;;
        -C|--git-dir|--work-tree|--namespace|--super-prefix) gs="$(printf '%s' "$gs" | sed -E 's/^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]*//')" ;;
        --git-dir=*|--work-tree=*|--namespace=*|--no-pager|-P|--paginate|-p|--bare|--no-replace-objects|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--no-optional-locks|--no-advice)
          gs="$(printf '%s' "$gs" | sed -E 's/^[^[:space:]]+[[:space:]]*//')" ;;
        *) break ;;
      esac
    done
    sub="$(printf '%s' "$gs" | awk '{print $1}')"
    case "$sub" in
      status|log|diff|show|rev-parse|ls-files|ls-tree|blame|shortlog|describe|cat-file|for-each-ref|reflog|whatchanged|grep|count-objects|symbolic-ref|rev-list|name-rev|var|help|version|show-ref|merge-base|""|--version|--help) : ;;
      branch) printf '%s' "$gs" | grep -qE '(^|[[:space:]])(-[dDmMcCfu]|--delete|--move|--copy|--force|--set-upstream-to|--unset-upstream|--edit-description)([[:space:]=]|$)' && block "git branch write: $cmd"
              printf '%s' "$gs" | grep -qE '^branch[[:space:]]+[^-[:space:]]' && block "git branch create: $cmd" ;;
      tag)    printf '%s' "$gs" | grep -qE '^tag[[:space:]]+(-l|--list|-n[0-9]*|--contains|--points-at|--sort[= ]|--format[= ]|--merged|--no-merged)?([[:space:]]|$)' || block "git tag write: $cmd"
              printf '%s' "$gs" | grep -qE '^tag[[:space:]]+[^-[:space:]]' && block "git tag create: $cmd" ;;
      remote) printf '%s' "$gs" | grep -qE '^remote([[:space:]]+(-v|--verbose|show|get-url))*([[:space:]]+[^[:space:]]+)?[[:space:]]*$' || block "git remote write: $cmd"
              printf '%s' "$gs" | grep -qE '^remote[[:space:]]+(add|remove|rm|rename|set-url|set-head|set-branches|prune|update)' && block "git remote write: $cmd" ;;
      config) printf '%s' "$gs" | grep -qE '^config[[:space:]]+(--get|--get-all|--get-regexp|--list|-l|--name-only|-z|--show-origin)([[:space:]]|$)' || block "git config write: $cmd" ;;
      *) block "git subcommand '$sub' not in read allowlist: $cmd" ;;
    esac
    # read subcommands that can still write files or run external programs
    printf '%s' "$gs" | grep -qE '(^|[[:space:]])(--output|--ext-diff|-O|--open-files-in-pager)([[:space:]=]|$)' && block "git option writes a file or runs a program: $cmd"
    continue
  fi
  printf '%s' "$h" | grep -qE "$READ" || block "command '$h' not in read-only allowlist: $cmd"
done <<SEG
$segs
SEG
# A command made only of this plugin's own scripts is pre-approved: without this, marketplace installs
# hit an approval prompt (the scripts live outside the project dir) that headless runs cannot answer.
if [ "$all_plugin" = 1 ]; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"codebase-kb-engine: plugin-owned script, verified by real path"}}'
fi
exit 0
