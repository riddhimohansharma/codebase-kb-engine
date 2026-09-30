#!/usr/bin/env bash
# Point the read-only kb engine at any repo. SELF-LOCATING: resolves its own
# folder (even through symlinks / from PATH), so there are no hardcoded paths.
# Usage: /path/to/repository-kb-engine/run.sh <repo-path> [extra claude args...]
#   Override KB output location: KB_DIR=/some/path run.sh <repo-path>
set -euo pipefail

# resolve this script's real directory, following symlinks (BSD/macOS safe)
src="${BASH_SOURCE[0]}"
while [ -h "$src" ]; do
  d="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
  src="$(readlink "$src")"; case "$src" in /*) ;; *) src="$d/$src" ;; esac
done
ENGINE="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"

REPO="${1:?usage: run.sh <repo-path> [claude args...]}"; shift || true
[ -d "$REPO" ] || { echo "not a directory: $REPO" >&2; exit 1; }
REPO="$(cd "$REPO" && pwd)"
command -v claude >/dev/null 2>&1 || { echo "claude not found in PATH" >&2; exit 1; }

# KB output defaults to a sibling of the target repo; fully derived, never hardcoded
KB_DIR="${KB_DIR:-$(dirname "$REPO")/$(basename "$REPO")-kb}"
mkdir -p "$KB_DIR"; KB_DIR="$(cd "$KB_DIR" && pwd)"; export KB_DIR
{ echo "engine : $ENGINE"
  echo "repo   : $REPO   (read-only)"
  echo "KB_DIR : $KB_DIR   (writable — KB output only)"; } >&2
cd "$REPO"
exec claude --plugin-dir "$ENGINE" --add-dir "$KB_DIR" "$@"
