#!/usr/bin/env bash
# resolve-kb.sh — resolve, vet, and initialise the KB output directory.
# Usage: resolve-kb.sh <target-dir> [--url-mode] [--name NAME] [--check]
#   --check: resolve and vet only; create nothing (dry runs, /kb-validate)
#   local mode: KB = $KB_DIR, else <target-root-parent>/<name>-kb
#   url mode:   KB = $KB_DIR, else <cwd-root-parent or cwd>/<name>-kb  (target is an ephemeral clone)
# Prints KEY=VALUE lines. Exit: 0 ok · 2 usage · 3 not writable · 4 KB inside target repo/sandbox · 5 dir exists, not a CKB dir
# Creates the KB dir and its `.ckb-output` marker; the read-only guard only permits writes under a marked dir.
# The dir is created up front deliberately: Claude Code ignores `--add-dir` for a path that does not exist at launch.
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
[ -n "$target" ] && [ -d "$target" ] || die 2 "usage: resolve-kb.sh <target-dir> [--url-mode] [--name NAME]"

toplevel(){ git -C "$1" rev-parse --show-toplevel 2>/dev/null || (cd "$1" && pwd -P); }
# canonical path for a possibly-nonexistent path: resolve the nearest existing ancestor
canon(){
  local p="$1" rest=""
  case "$p" in /*) ;; *) p="$PWD/$p" ;; esac
  while [ ! -d "$p" ]; do rest="/$(basename "$p")$rest"; p="$(dirname "$p")"; done
  printf '%s%s\n' "$(cd "$p" && pwd -P)" "$rest"
}
inside(){ case "$1/" in "$2"/*) return 0 ;; *) return 1 ;; esac; }   # $1 is $2 or below it

root="$(cd "$(toplevel "$target")" && pwd -P)"
[ -n "$name" ] || name="$(basename "$root")"
case "$name" in */*|.|..|"") die 2 "invalid name: $name" ;; esac

if [ -n "${KB_DIR:-}" ]; then
  kb="$(canon "$KB_DIR")"
elif [ "$url_mode" = 1 ]; then
  if cwdroot="$(git rev-parse --show-toplevel 2>/dev/null)"; then base="$(dirname "$cwdroot")"; else base="$PWD"; fi
  kb="$(canon "$base/$name-kb")"
else
  kb="$(canon "$(dirname "$root")/$name-kb")"
fi

inside "$kb" "$root" && die 4 "REFUSED: KB dir '$kb' is inside the target repo '$root'. Set KB_DIR to a path outside it."
clone_base="$(canon "${CKB_CLONE_BASE:-${TMPDIR:-/tmp}/ckb-clones}")"
inside "$kb" "$clone_base" && die 4 "REFUSED: KB dir '$kb' is inside the ephemeral clone sandbox '$clone_base'."

# writability: the dir itself if it exists, else its nearest existing ancestor
probe="$kb"; while [ ! -d "$probe" ]; do probe="$(dirname "$probe")"; done
if [ ! -w "$probe" ]; then
  printf 'KB_DIR=%s\nSTATUS=NOT_WRITABLE\n' "$kb"
  die 3 "KB dir '$kb' is not writable (checked '$probe'). Re-run with a writable location, e.g.:" \
        "  mkdir -p \$HOME/ckb/$name-kb && KB_DIR=\$HOME/ckb/$name-kb claude --add-dir \$HOME/ckb/$name-kb"
fi

if [ -d "$kb" ] && [ ! -e "$kb/.ckb-output" ] && [ -n "$(ls -A "$kb" 2>/dev/null)" ]; then
  die 5 "REFUSED: '$kb' exists, is non-empty, and is not a CKB output dir." \
        "Point KB_DIR elsewhere, or adopt it with: touch '$kb/.ckb-output'"
fi

if [ "$check" = 1 ]; then
  printf 'REPO_ROOT=%s\nKB_DIR=%s\nNAME=%s\nADD_DIR_HINT=mkdir -p "%s" && claude --add-dir "%s"\nSTATUS=CHECK_OK\n' "$root" "$kb" "$name" "$kb" "$kb"; exit 0
fi
mkdir -p "$kb" || die 3 "could not create '$kb'"
[ -e "$kb/.ckb-output" ] || printf 'ckb-output\ntarget_root=%s\ncreated_at=%s\n' "$root" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$kb/.ckb-output"

printf 'REPO_ROOT=%s\nKB_DIR=%s\nNAME=%s\nADD_DIR_HINT=mkdir -p "%s" && claude --add-dir "%s"\nSTATUS=OK\n' "$root" "$kb" "$name" "$kb" "$kb"
