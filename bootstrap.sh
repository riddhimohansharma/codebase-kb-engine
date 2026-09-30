#!/usr/bin/env bash
# bootstrap.sh — run once after unzip. Fixes permissions, auto-corrects accidental
# double-nesting, verifies the layout, and installs `repokb` onto your PATH.
# Usage:  bash ./bootstrap.sh            (installs to ~/.local/bin)
#         bash ./bootstrap.sh /usr/local/bin
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"

# if unzipped one level too deep, drop into the real engine folder automatically
if [ ! -e "$DIR/.claude-plugin/plugin.json" ] && [ -e "$DIR/repository-kb-engine/.claude-plugin/plugin.json" ]; then
  DIR="$DIR/repository-kb-engine"
fi

chmod +x "$DIR/repokb" "$DIR/run.sh" "$DIR/hooks/guard.sh" 2>/dev/null || true
echo "engine : $DIR"
echo
"$DIR/repokb" doctor || true
echo
"$DIR/repokb" install "${1:-$HOME/.local/bin}"
