#!/usr/bin/env bash
# resolve-kb.sh — resolve, vet, and initialise the KB output directory.
# Usage: resolve-kb.sh <target-dir> [--url-mode] [--name NAME] [--check]
#   local mode (standard): KB = <repo-root>/ckb   — committed with the code (CKB spec: canonical location)
#   url mode:              KB = $KB_DIR, else <cwd-root-parent or cwd>/<name>-ckb  (target is an ephemeral clone, never committed)
#   --check: resolve and vet only; create nothing (dry runs, /kb-validate)
# Prints KEY=VALUE lines. Exit: 0 ok · 2 usage · 3 not writable · 4 refused location · 5 dir exists, not a CKB dir
# Creates the KB dir and its static `.ckb-output` marker; the read-only guard permits writes only inside a marked dir,
# and inside a git work tree only at exactly <work-tree>/ckb.
set -uo pipefail
die(){ code="$1"; shift; printf '%s\n' "$@" >&2; exit "$code"; }

target=""; url_mode=0; name=""; check=0
while [ $# -gt 0 ]; do
  case "$1" in
    --url-mode) url_mode=1 ;;
    --check) check=1 ;;
    --name) name="${2:?--name needs a value}"; shift ;;
    -*) die 2 "unknown option: $1" ;;
    *) target="$1" ;;
  esac; shift
done
[ -n "$target" ] && [ -d "$target" ] || die 2 "usage: resolve-kb.sh <target-dir> [--url-mode] [--name NAME] [--check]"

# canonical path for a possibly-nonexistent path: resolve the nearest existing ancestor
canon(){
  local p="$1" rest=""
  case "$p" in /*) ;; *) p="$PWD/$p" ;; esac
  while [ ! -d "$p" ]; do rest="/$(basename "$p")$rest"; p="$(dirname "$p")"; done
  printf '%s%s\n' "$(cd "$p" && pwd -P)" "$rest"
}
inside(){ case "$1/" in "$2"/*) return 0 ;; *) return 1 ;; esac; }   # $1 is $2 or below it

root="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)" || root=""
[ -n "$root" ] && root="$(cd "$root" && pwd -P)"
clone_base="$(canon "${CKB_CLONE_BASE:-${TMPDIR:-/tmp}/ckb-clones}")"

if [ "$url_mode" = 1 ]; then
  [ -n "$root" ] || root="$(cd "$target" && pwd -P)"
  [ -n "$name" ] || name="$(basename "$root")"
  case "$name" in */*|.|..|"") die 2 "invalid name: $name" ;; esac
  if [ -n "${KB_DIR:-}" ]; then kb="$(canon "$KB_DIR")"
  else
    if cwdroot="$(git rev-parse --show-toplevel 2>/dev/null)"; then base="$(dirname "$cwdroot")"; else base="$PWD"; fi
    kb="$(canon "$base/$name-ckb")"
  fi
  inside "$kb" "$root" && die 4 "REFUSED: KB dir '$kb' is inside the ephemeral clone; it would be destroyed."
  inside "$kb" "$clone_base" && die 4 "REFUSED: KB dir '$kb' is inside the clone sandbox '$clone_base'."
  wt="$(git -C "$(dirname "$kb")" rev-parse --show-toplevel 2>/dev/null)" && \
    die 4 "REFUSED: '$kb' is inside the git work tree '$wt'. Set KB_DIR outside any repo for URL mode."
else
  [ -n "$root" ] || die 2 "REFUSED: '$target' is not inside a git work tree. The KB is committed at <repo-root>/ckb, so a git repo is required."
  [ -n "$name" ] || name="$(basename "$root")"
  [ -n "${KB_DIR:-}" ] && echo "note: KB_DIR is ignored in local mode; the standard location is <repo-root>/ckb" >&2
  # migrate a legacy hidden .ckb/ (plugin <= 0.6.x) to the visible ckb/ — only our own marked dir, never a symlink
  if [ "$check" != 1 ] && [ -d "$root/.ckb" ] && [ ! -L "$root/.ckb" ] && [ -f "$root/.ckb/.ckb-output" ] && [ ! -e "$root/ckb" ]; then
    mv "$root/.ckb" "$root/ckb" || die 3 "could not migrate '$root/.ckb' to '$root/ckb'"
    echo "MIGRATED=.ckb->ckb (legacy hidden KB folder renamed; if .ckb was committed, commit the rename: git add -A .ckb ckb)" 
  fi
  [ -L "$root/ckb" ] && die 4 "REFUSED: '$root/ckb' is a symlink. The KB must be a real directory in the repo."
  [ -e "$root/ckb" ] && [ ! -d "$root/ckb" ] && die 4 "REFUSED: '$root/ckb' exists and is not a directory."
  kb="$root/ckb"
fi

# writability: the dir itself if it exists, else its nearest existing ancestor
probe="$kb"; while [ ! -d "$probe" ]; do probe="$(dirname "$probe")"; done
if [ ! -w "$probe" ]; then
  printf 'KB_DIR=%s\nSTATUS=NOT_WRITABLE\n' "$kb"
  if [ "$url_mode" = 1 ]; then
    die 3 "KB dir '$kb' is not writable (checked '$probe'). Re-run with a writable location, e.g.:" \
          "  mkdir -p \$HOME/ckb/$name-ckb && KB_DIR=\$HOME/ckb/$name-ckb claude --add-dir \$HOME/ckb/$name-ckb"
  fi
  die 3 "'$probe' is not writable, so '$kb' cannot be created. Fix permissions on the repo, or analyse a clone: /kb <repo-url>"
fi

if [ -d "$kb" ] && [ ! -e "$kb/.ckb-output" ] && [ -n "$(ls -A "$kb" 2>/dev/null)" ]; then
  die 5 "REFUSED: '$kb' exists, is non-empty, and is not a CKB output dir." \
        "If it is yours to replace, adopt it with: touch '$kb/.ckb-output'"
fi

hint="mkdir -p \"$kb\" && claude --add-dir \"$kb\""
if [ "$check" = 1 ]; then
  printf 'REPO_ROOT=%s\nKB_DIR=%s\nNAME=%s\nADD_DIR_HINT=%s\nSTATUS=CHECK_OK\n' "$root" "$kb" "$name" "$hint"; exit 0
fi
# The dir is created up front deliberately: Claude Code ignores `--add-dir` for a path that does not exist at launch.
mkdir -p "$kb" || die 3 "could not create '$kb'"
[ -e "$kb/.ckb-output" ] || printf 'ckb-output v1 — written by a CKB producer; safe to commit.\n' > "$kb/.ckb-output"
printf 'REPO_ROOT=%s\nKB_DIR=%s\nNAME=%s\nADD_DIR_HINT=%s\nSTATUS=OK\n' "$root" "$kb" "$name" "$hint"
