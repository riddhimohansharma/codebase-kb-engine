#!/usr/bin/env bash
# Read-only enforcement gate for repository-kb-engine.
# Contract: exit 2 = BLOCK (reason -> stderr, returned to Claude); exit 0 = ALLOW.
# Policy: allow read/inspect tools and a read-only Bash allowlist; block every
# tool or command that can write, delete, install, build, or deploy.
# Fails CLOSED: unparseable input, unknown tools that aren't clearly reads, and
# any command whose segment head is not on the allowlist are all blocked.
set -uo pipefail
payload="$(cat)"
block(){ echo "BLOCKED by read-only engine: $*" >&2; exit 2; }
under_kb(){ # $1 = path; true only if KB_DIR set and path is inside it
  [ -n "${KB_DIR:-}" ] || return 1
  case "$1" in "$KB_DIR"|"$KB_DIR"/*) return 0 ;; *) return 1 ;; esac
}
jqget(){ command -v jq >/dev/null 2>&1 && printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null; }

tool="$(jqget '.tool_name')"
[ -z "${tool:-}" ] && tool="$(printf '%s' "$payload" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')"

case "${tool:-}" in
  Bash) ;;                                              # inspect the command below
  Write|Edit|MultiEdit)
    fp="$(jqget '.tool_input.file_path')"; [ -z "${fp:-}" ] && fp="$(jqget '.tool_input.path')"
    case "${fp:-}" in *..*) block "write path contains '..': ${fp:-}";; esac
    under_kb "${fp:-}" && exit 0
    block "'$tool' may only write under KB_DIR (${KB_DIR:-unset}); denied: ${fp:-<none>}." ;;
  NotebookEdit)
    block "tool '$tool' modifies files; this engine is read-only." ;;
  "")
    block "could not determine tool name (fail-closed)." ;;
  *)
    exit 0 ;;                                            # Read/Grep/Glob/WebFetch/WebSearch/Task/TodoWrite/...
esac

cmd="$(jqget '.tool_input.command')"
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
printf '%s' "$cmd" | grep -qiE '(curl|wget|fetch)[[:space:]].*\|[[:space:]]*(ba|z|k|)?sh([[:space:]]|$)' \
  && block "pipe-to-shell: $cmd"
printf '%s' "$cmd" | grep -qE ':\(\)[[:space:]]*\{[[:space:]]*:' && block "fork bomb: $cmd"

# 4) default-deny allowlist: every command segment head must be a read-only command
sc="$(printf '%s' "$cmd" \
  | sed -E 's#[0-9]*>&[0-9]*##g' \
  | sed -E 's#&>[[:space:]]*[^[:space:];|&]*##g' \
  | sed -E 's#[0-9]*>>?[[:space:]]*[^[:space:];|&]*##g')"
# normalize all shell separators to ';' (portable), then split on newlines via tr
sc="$(printf '%s' "$sc" | sed -E 's/\|\|/;/g; s/&&/;/g; s/\|/;/g; s/&/;/g')"
segs="$(printf '%s' "$sc" | tr ';' '\n')"
READ='^(ls|cat|head|tail|bat|less|more|grep|egrep|fgrep|rg|ag|find|fd|tree|wc|stat|file|du|df|pwd|echo|printf|true|:|test|\[|which|type|whoami|id|uname|hostname|date|sort|uniq|cut|tr|column|nl|tac|comm|diff|jq|yq|awk|sed|xxd|od|hexdump|strings|md5sum|sha256sum|shasum|cksum|basename|dirname|realpath|readlink|expr|seq|env|printenv|cd|pushd|popd|dirs|man|cloc|tokei|wait|sleep|for|while|if|case|read)$'
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
  h="$(printf '%s' "$seg" | awk '{print $1}')"
  [ -z "$h" ] && continue
  if [ "$h" = "git" ]; then
    printf '%s' "$seg" | grep -qiE 'git[[:space:]]+(add|commit|push|pull|fetch|clone|init|reset|checkout|switch|restore|merge|rebase|stash|rm|mv|clean|apply|am|cherry-pick|revert|format-patch|update-ref|update-index|write-tree|commit-tree|gc|prune|repack|worktree|submodule|notes|filter-branch|fast-import|replace|mktag|mktree)([[:space:]]|$)' \
      && block "git write op: $cmd"
    printf '%s' "$seg" | grep -qiE 'git[[:space:]]+remote[[:space:]]+(add|remove|rename|set-url|prune)' && block "git remote write: $cmd"
    printf '%s' "$seg" | grep -qiE 'git[[:space:]]+branch[[:space:]]+(-[dDmM]|--delete|--move|--force)' && block "git branch write: $cmd"
    printf '%s' "$seg" | grep -qiE 'git[[:space:]]+tag[[:space:]]+([^-]|-[adfsm])' && block "git tag write: $cmd"
    if printf '%s' "$seg" | grep -qiE 'git[[:space:]]+config'; then
      printf '%s' "$seg" | grep -qiE 'git[[:space:]]+config[[:space:]]+(--get|--get-all|--get-regexp|--list|-l|--name-only|-z)([[:space:]]|$)' \
        || block "git config write: $cmd"
    fi
    sub="$(printf '%s' "$seg" | awk '{print $2}')"
    case "$sub" in
      status|log|diff|show|branch|remote|rev-parse|ls-files|ls-tree|blame|shortlog|describe|cat-file|for-each-ref|reflog|tag|config|whatchanged|grep|count-objects|symbolic-ref|rev-list|name-rev|var|help|version|show-ref|""|-*) : ;;
      *) block "git subcommand '$sub' not in read allowlist: $cmd" ;;
    esac
    continue
  fi
  printf '%s' "$h" | grep -qE "$READ" || block "command '$h' not in read-only allowlist: $cmd"
done <<SEG
$segs
SEG
exit 0
