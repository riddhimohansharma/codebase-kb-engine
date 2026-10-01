#!/usr/bin/env bash
# bootstrap.sh — run once after unzip. Fixes permissions, auto-corrects accidental
# double-nesting, verifies the layout, and installs `codebase-kb-engine` onto your PATH.
# Usage:  bash ./bootstrap.sh            (installs to ~/.local/bin)
#         bash ./bootstrap.sh /usr/local/bin
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"

# if unzipped one level too deep, drop into the real engine folder automatically
for sub in codebase-kb-engine repository-kb-engine; do
  if [ ! -e "$DIR/.claude-plugin/plugin.json" ] && [ -e "$DIR/$sub/.claude-plugin/plugin.json" ]; then DIR="$DIR/$sub"; fi
done

chmod +x "$DIR/codebase-kb-engine" "$DIR/run.sh" "$DIR"/hooks/*.sh "$DIR"/scripts/*.sh 2>/dev/null || true
echo "engine : $DIR"
echo
"$DIR/codebase-kb-engine" doctor || true
echo
"$DIR/codebase-kb-engine" install "${1:-$HOME/.local/bin}"
