#!/usr/bin/env bash
# sync-spec.sh — vendor CKB spec versions from a codebase-kb-spec checkout into spec/v<ver>/ (maintainer tool, not used at runtime).
# Usage: tools/sync-spec.sh [--check] [path-to-codebase-kb-spec] [version...]   defaults: ../codebase-kb-spec, every schema/v* present
#   --check: exit 1 if any vendored copy differs from the checkout's HEAD
# The plugin must be self-contained (marketplace installs copy only the plugin dir), so the spec is vendored, never linked.
# Layout: v0.1 = schema/v0.1/ckb.schema.json + tests/semantic.jq ; v0.2+ = schema/vX/{ckb.schema.json,semantic.jq,derive.jq}
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
check=0; [ "${1:-}" = --check ] && { check=1; shift; }
SRC="$(cd "${1:-$ROOT/../codebase-kb-spec}" && pwd -P)"; [ $# -gt 0 ] && shift
vers=("$@"); [ ${#vers[@]} -gt 0 ] || vers=($(cd "$SRC/schema" && ls -d v* | sed 's/^v//' | sort -V))
[ -z "$(git -C "$SRC" status --porcelain -- schema tests)" ] || { echo "REFUSED: $SRC has uncommitted spec changes; commit them first so SOURCE is reproducible" >&2; exit 2; }
sha="$(git -C "$SRC" rev-parse HEAD)"
url="$(git -C "$SRC" remote get-url origin 2>/dev/null | sed -E 's#^([a-z]+://)[^/@]*@#\1#' || echo local)"
rc=0
for VER in "${vers[@]}"; do
  DST="$ROOT/spec/v$VER"; tmp="$(mktemp -d)"
  if git -C "$SRC" cat-file -e "HEAD:schema/v$VER/semantic.jq" 2>/dev/null; then files="ckb.schema.json semantic.jq derive.jq"
    for f in $files; do git -C "$SRC" show "HEAD:schema/v$VER/$f" > "$tmp/$f"; done
  else files="ckb.schema.json semantic.jq"
    git -C "$SRC" show "HEAD:schema/v$VER/ckb.schema.json" > "$tmp/ckb.schema.json"; git -C "$SRC" show "HEAD:tests/semantic.jq" > "$tmp/semantic.jq"
  fi
  if [ "$check" = 1 ]; then
    same=1; for f in $files; do diff -q "$tmp/$f" "$DST/$f" >/dev/null 2>&1 || same=0; done
    if [ $same = 1 ]; then echo "IN SYNC v$VER with codebase-kb-spec@${sha:0:7} (vendored from $(sed -n 's/^commit=//p' "$DST/SOURCE" 2>/dev/null | cut -c1-7))"
    else echo "DRIFT: spec/v$VER differs from codebase-kb-spec@${sha:0:7}; run tools/sync-spec.sh" >&2; rc=1; fi
  else
    mkdir -p "$DST"; for f in $files; do cp "$tmp/$f" "$DST/$f"; done
    printf 'repository=%s\ncommit=%s\nversion=%s\nsynced_at=%s\nfiles=%s\n' "$url" "$sha" "$VER" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$files" > "$DST/SOURCE"
    echo "vendored codebase-kb-spec@${sha:0:7} v$VER -> spec/v$VER"
  fi
  rm -rf "$tmp"
done
exit $rc
