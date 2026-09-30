#!/usr/bin/env bash
# sync-spec.sh — vendor a CKB spec version from a ckb-spec checkout into spec/v<ver>/ (maintainer tool, not used at runtime).
# Usage: tools/sync-spec.sh [path-to-ckb-spec] [version]      defaults: ../ckb-spec  0.1
#        tools/sync-spec.sh --check [path] [version]          exit 1 if the vendored copy differs from the checkout's HEAD
# The plugin must be self-contained (marketplace installs copy only the plugin dir), so the spec is vendored, never linked.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
check=0; [ "${1:-}" = --check ] && { check=1; shift; }
SRC="$(cd "${1:-$ROOT/../ckb-spec}" && pwd -P)"; VER="${2:-0.1}"
DST="$ROOT/spec/v$VER"
[ -f "$SRC/schema/v$VER/ckb.schema.json" ] || { echo "no schema v$VER in $SRC" >&2; exit 2; }
[ -z "$(git -C "$SRC" status --porcelain -- schema tests/semantic.jq)" ] || { echo "REFUSED: $SRC has uncommitted spec changes; commit them first so SOURCE is reproducible" >&2; exit 2; }
sha="$(git -C "$SRC" rev-parse HEAD)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
git -C "$SRC" show "HEAD:schema/v$VER/ckb.schema.json" > "$tmp/ckb.schema.json"
git -C "$SRC" show "HEAD:tests/semantic.jq" > "$tmp/semantic.jq"
if [ "$check" = 1 ]; then
  diff -q "$tmp/ckb.schema.json" "$DST/ckb.schema.json" >/dev/null && diff -q "$tmp/semantic.jq" "$DST/semantic.jq" >/dev/null \
    && { echo "IN SYNC with ckb-spec@${sha:0:7} (vendored from $(sed -n 's/^commit=//p' "$DST/SOURCE" | cut -c1-7))"; exit 0; } \
    || { echo "DRIFT: spec/v$VER differs from ckb-spec@${sha:0:7}; run tools/sync-spec.sh" >&2; exit 1; }
fi
mkdir -p "$DST" && cp "$tmp/ckb.schema.json" "$tmp/semantic.jq" "$DST/"
url="$(git -C "$SRC" remote get-url origin 2>/dev/null | sed -E 's#^([a-z]+://)[^/@]*@#\1#' || echo local)"
printf 'repository=%s\ncommit=%s\nversion=%s\nsynced_at=%s\nfiles=ckb.schema.json semantic.jq\n' "$url" "$sha" "$VER" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$DST/SOURCE"
echo "vendored ckb-spec@${sha:0:7} v$VER -> spec/v$VER"
