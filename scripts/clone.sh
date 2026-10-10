#!/usr/bin/env bash
# clone.sh — ephemeral, push-disabled shallow clone for repo-URL mode.
# Usage: clone.sh clone <url> [branch]   -> prints CLONE_DIR, JOB_DIR, NAME, BRANCH, COMMIT_SHA, REPO_URL
#        clone.sh fetch-commit <job_dir> <sha> -> fetches ONE commit (depth 1) into the job's clone, so freshness can diff trees
#        clone.sh destroy <job_dir>      -> deletes the sandbox job dir, verifies it is gone
# Contract: never pushes; retains no source after destroy; refuses URLs with embedded credentials.
# Sandbox base: $CKB_CLONE_BASE, else ${TMPDIR:-/tmp}/ckb-clones. Only dirs carrying a .ckb-clone marker are ever deleted.
set -uo pipefail
die(){ code="$1"; shift; printf '%s\n' "$@" >&2; exit "$code"; }
base="${CKB_CLONE_BASE:-${TMPDIR:-/tmp}/ckb-clones}"; base="${base%/}"
export GIT_TERMINAL_PROMPT=0 GIT_LFS_SKIP_SMUDGE=1

case "${1:-}" in
  clone)
    url="${2:-}"; branch="${3:-}"
    [ -n "$url" ] || die 2 "usage: clone.sh clone <url> [branch]"
    # reject userinfo in URL (https://user:token@host/...) — credentials must come from the git credential helper
    printf '%s' "$url" | grep -qE '^[a-zA-Z][a-zA-Z0-9+.-]*://[^/@]*:[^/@]*@' \
      && die 2 "REFUSED: URL embeds credentials. Use a credential helper or SSH, and pass a clean URL."
    schemes='^(https?|ssh|git)://|^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:'
    fileproto=never
    if [ "${CKB_ALLOW_FILE_URL:-}" = 1 ]; then schemes="$schemes|^file://"; fileproto=always; fi   # test fixtures only
    printf '%s' "$url" | grep -qE "$schemes" \
      || die 2 "REFUSED: unsupported URL scheme (use https://, ssh://, git://, or user@host:path): $url"
    name="$(basename "${url%/}")"; name="${name%.git}"
    case "$name" in ""|.|..) die 2 "cannot derive repo name from URL: $url" ;; esac
    mkdir -p "$base" && chmod 700 "$base" || die 3 "cannot create sandbox base: $base"
    job="$(mktemp -d "$base/job.XXXXXX")" || die 3 "mktemp failed under $base"
    printf 'ckb-clone\nurl=%s\n' "$url" > "$job/.ckb-clone"
    trap 'rm -rf "$job"' ERR
    args=(clone --quiet --depth 1 --single-branch --no-tags -c core.hooksPath=/dev/null -c protocol.file.allow=$fileproto)
    [ -n "$branch" ] && args+=(--branch "$branch")
    if ! git "${args[@]}" -- "$url" "$job/$name" >&2; then rm -rf "$job"; die 4 "clone failed: $url ${branch:+(branch $branch)}"; fi
    # disable push at the remote level (belt) — the guard also blocks `git push` (braces)
    git -C "$job/$name" remote set-url --push origin "PUSH-DISABLED-BY-CKB" || { rm -rf "$job"; die 4 "could not disable push"; }
    actual_branch="$(git -C "$job/$name" symbolic-ref --short -q HEAD || printf '%s' "${branch:-HEAD}")"
    sha="$(git -C "$job/$name" rev-parse HEAD)"
    printf 'JOB_DIR=%s\nCLONE_DIR=%s\nNAME=%s\nBRANCH=%s\nCOMMIT_SHA=%s\nREPO_URL=%s\n' \
      "$job" "$job/$name" "$name" "$actual_branch" "$sha" "$url" ;;
  fetch-commit)
    job="${2:-}"; sha="${3:-}"
    [ -n "$job" ] && [ -d "$job" ] && [ -n "$sha" ] || die 2 "usage: clone.sh fetch-commit <job_dir> <sha>"
    printf '%s' "$sha" | grep -qE '^[0-9a-f]{40}$' || die 2 "REFUSED: not a full 40-hex commit sha: $sha"
    rbase="$(cd "$base" 2>/dev/null && pwd -P)" || die 2 "sandbox base missing: $base"
    rjob="$(cd "$job" && pwd -P)"
    case "$rjob" in "$rbase"/job.*) ;; *) die 2 "REFUSED: '$job' is not a sandbox job dir under $rbase" ;; esac
    [ -f "$rjob/.ckb-clone" ] || die 2 "REFUSED: '$job' has no .ckb-clone marker"
    fileproto=never; [ "${CKB_ALLOW_FILE_URL:-}" = 1 ] && fileproto=always
    clone_dir="$(find "$rjob" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | head -1)"
    [ -d "$clone_dir/.git" ] || die 2 "no clone found in $rjob"
    # same hardening as the clone itself: no hooks, no tags, depth 1; never pushes
    git -C "$clone_dir" -c core.hooksPath=/dev/null -c protocol.file.allow=$fileproto fetch --quiet --depth 1 --no-tags origin "$sha" >&2 \
      || die 4 "could not fetch commit ${sha:0:12} (the remote may not allow fetching it by sha)"
    git -C "$clone_dir" cat-file -e "$sha^{commit}" 2>/dev/null || die 4 "fetched, but commit ${sha:0:12} is not present"
    printf 'FETCHED=%s\n' "$sha" ;;
  destroy)
    job="${2:-}"; [ -n "$job" ] && [ -d "$job" ] || die 2 "usage: clone.sh destroy <job_dir> (must exist)"
    rbase="$(cd "$base" 2>/dev/null && pwd -P)" || die 2 "sandbox base missing: $base"
    rjob="$(cd "$job" && pwd -P)"
    case "$rjob" in "$rbase"/job.*) ;; *) die 2 "REFUSED: '$job' is not a sandbox job dir under $rbase" ;; esac
    [ -f "$rjob/.ckb-clone" ] || die 2 "REFUSED: '$job' has no .ckb-clone marker"
    rm -rf "$rjob"
    [ -e "$rjob" ] && die 4 "DESTROY FAILED: $rjob still exists"
    printf 'DESTROYED=%s\n' "$rjob" ;;
  *) die 2 "usage: clone.sh clone <url> [branch] | clone.sh fetch-commit <job_dir> <sha> | clone.sh destroy <job_dir>" ;;
esac
