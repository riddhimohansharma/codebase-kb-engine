#!/usr/bin/env bash
# checkpoint.sh — resumable /kb runs. State is DERIVED FROM DISK (fragments, docs, inventory), never trusted from memory,
# so a crash, timeout, closed terminal or compacted context loses nothing: run `status` and continue from PENDING.
# Usage:
#   checkpoint.sh begin  <kb_dir> <repo_root> [--force] [--focus TEXT]   -> RESUME=yes|fresh  KEY=<sha>  (+ REASON=... on fresh)
#   checkpoint.sh status <kb_dir>                                       -> one JSON line, then PENDING=<comma list>
#   checkpoint.sh mark   <kb_dir> audit <supported>/<total>             -> records the claim-audit result
#   checkpoint.sh mark   <kb_dir> finalize                               -> counts one finalize attempt
# (bash 3.2 compares times to the second, so "newer or same second as the start marker" counts as this run's work.)
# Run key = HEAD commit + hash of uncommitted source changes (outside .ckb, CLAUDE.md, AGENTS.md) + plugin version + focus.
# Any difference => resume is refused and the stale draft is cleared (fragments from different source states never mix).
# Writes ONLY <marked KB dir>/ckb.draft.d/.checkpoint.json and .checkpoint-begin (and clears ckb.draft.d on a fresh start).
# Plugin scripts are pre-approved by the guard, so every path is checked: marked dir, no symlinks, fixed file names.
# bash 3.2+, jq 1.6+.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd -P)"; ROOT="$(cd "$HERE/.." && pwd -P)"
die(){ echo "checkpoint: $*" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || die "jq is required"
verb="${1:-}"; kb="${2:-}"; [ -n "$verb" ] && [ -n "$kb" ] || die "usage: checkpoint.sh begin|status|mark <kb_dir> ..."
[ -d "$kb" ] && [ ! -L "$kb" ] && [ -f "$kb/.ckb-output" ] || die "not a marked KB dir (REFUSED): $kb"
kb="$(cd "$kb" && pwd -P)"; dd="$kb/ckb.draft.d"; cp="$dd/.checkpoint.json"; begin="$dd/.checkpoint-begin"
[ ! -L "$dd" ] && [ ! -L "$cp" ] && [ ! -L "$begin" ] || die "symlink in checkpoint paths (REFUSED)"
sha(){ { shasum -a 256 2>/dev/null || sha256sum; } | cut -d' ' -f1; }
atomic(){ cat > "$cp.tmp.$$" && mv -f "$cp.tmp.$$" "$cp"; }   # stdin -> checkpoint file

case "$verb" in
  begin)
    repo="${3:-}"; [ -d "$repo" ] || die "usage: checkpoint.sh begin <kb_dir> <repo_root> [--force] [--focus TEXT]"; shift 3
    force=0; focus=""
    while [ $# -gt 0 ]; do case "$1" in --force) force=1 ;; --focus) focus="${2:-}"; shift ;; *) die "unknown option: $1" ;; esac; shift; done
    head="$(git -C "$repo" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)" || die "no commit in $repo"
    EX=(':(exclude).ckb' ':(exclude)CLAUDE.md' ':(exclude)AGENTS.md')
    dirty="$( { git -C "$repo" status --porcelain -- . "${EX[@]}" 2>/dev/null; git -C "$repo" diff HEAD -- . "${EX[@]}" 2>/dev/null; } | sha)"
    ver="$(jq -r .version "$ROOT/.claude-plugin/plugin.json" 2>/dev/null)"
    key="$(printf '%s\n%s\n%s\n%s\n' "$head" "$dirty" "$ver" "$focus" | sha)"
    reason=""
    if [ "$force" = 1 ]; then reason="forced"
    elif [ ! -f "$cp" ]; then reason="no-checkpoint"
    elif [ "$(jq -r '.key // ""' "$cp" 2>/dev/null)" != "$key" ]; then reason="source-or-plugin-or-focus-changed"; fi
    if [ -n "$reason" ]; then
      rm -rf "$dd"; mkdir -p "$dd" || die "could not create $dd"
      : > "$begin"
      jq -nc --arg key "$key" --arg head "$head" --arg ver "$ver" '{key:$key, head:$head, plugin_version:$ver, audit:null, finalize_attempts:0}' | atomic
      echo "RESUME=fresh REASON=$reason KEY=$key"
    else
      [ -f "$begin" ] || : > "$begin"
      echo "RESUME=yes KEY=$key"
    fi ;;

  status)
    [ -f "$cp" ] || { echo '{"checkpoint":false}'; echo "PENDING=all"; exit 0; }
    inv="$dd/.inventory.json"; inv_ok=false; scopes='[]'
    if [ -f "$inv" ] && [ ! "$begin" -nt "$inv" ] && jq -e '(.areas | type == "array") and ((.buckets | type) == "object") and has("files_total")' "$inv" >/dev/null 2>&1; then
      inv_ok=true
      scopes="$(jq -c --arg mode scopes --arg scope "" --argjson maxscopes 7 -f "$HERE/inventory-digest.jq" "$inv" 2>/dev/null | jq -c '[.[].scope]' 2>/dev/null || echo '[]')"
      [ -n "$scopes" ] || scopes='[]'
    fi
    # a fragment is done when it is non-empty valid JSON; anything else is pending (a half-written file is never trusted)
    done_list=""; for f in "$dd"/*.json; do
      [ -f "$f" ] || continue; b="$(basename "$f")"; [ "$b" = .inventory.json ] && continue
      [ -s "$f" ] && jq -e 'type == "object"' "$f" >/dev/null 2>&1 && done_list="$done_list ${b%.json}"
    done
    done_json="$(printf '%s\n' $done_list | jq -R . | jq -sc 'map(select(length>0)) | sort')"
    docs_json="$(for f in "$kb"/0[0-7]-*.md; do [ -s "$f" ] && [ ! "$begin" -nt "$f" ] && basename "$f"; done 2>/dev/null | jq -R . | jq -sc 'map(select(length>0)) | sort')"
    jq -nc --argjson inv "$inv_ok" --argjson scopes "$scopes" --argjson done "$done_json" --argjson docs "$docs_json" --slurpfile cp "$cp" '
      ($scopes + (if $inv then ["inventory"] else [] end) | unique) as $want
      | ($want - $done) as $pend_scouts
      | (["00-overview.md","01-technical-architecture.md","02-functional-workflows.md","03-business-rules.md","04-system-context-and-gaps.md","05-operations.md","06-security-and-data.md","07-decisions.md"] - $docs) as $pend_docs
      | {checkpoint: true, key: $cp[0].key, inventory: $inv, scopes: {expected: $scopes, done: $done, pending: $pend_scouts}, docs: {done: $docs, pending: $pend_docs},
         audit: $cp[0].audit, finalize_attempts: $cp[0].finalize_attempts}' > "$dd/.status.tmp.$$" 2>/dev/null || die "could not compute status"
    cat "$dd/.status.tmp.$$"; pend="$(jq -r '[(if .inventory then empty else "inventory" end), (.scopes.pending[] | "scout:" + .), (.docs.pending[] | "doc:" + .), (if .audit == null then "audit" else empty end)] | join(",")' "$dd/.status.tmp.$$")"; rm -f "$dd/.status.tmp.$$"
    echo "PENDING=${pend:-none}" ;;

  mark)
    [ -f "$cp" ] || die "no checkpoint (run begin first)"
    what="${3:-}"
    case "$what" in
      audit) val="${4:-}"; printf '%s' "$val" | grep -qE '^[0-9]+/[0-9]+$' || die "audit value must be <supported>/<total>"
             jq -c --arg v "$val" '.audit = $v' "$cp" | atomic; echo "MARKED=audit $val" ;;
      finalize) jq -c '.finalize_attempts += 1' "$cp" | atomic; echo "MARKED=finalize attempts=$(jq -r .finalize_attempts "$cp")" ;;
      *) die "mark what? audit <s>/<t> | finalize" ;;
    esac ;;
  *) die "usage: checkpoint.sh begin|status|mark <kb_dir> ..." ;;
esac
exit 0
