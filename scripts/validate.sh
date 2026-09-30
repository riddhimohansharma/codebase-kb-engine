#!/usr/bin/env bash
# validate.sh — check a ckb.json against the vendored CKB spec: JSON Schema (structural) + semantic rules R1–R6.
# Usage: validate.sh <ckb.json>
# Last stdout line: RESULT=PASS|FAIL STRUCTURAL=pass|fail|skipped SEMANTIC=pass|fail
# Exit: 0 PASS · 1 FAIL · 2 usage/unreadable. Structural check needs `uvx` (uv); if absent it is reported as skipped, never as pass.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
f="${1:-}"; [ -n "$f" ] && [ -r "$f" ] || { echo "usage: validate.sh <ckb.json>" >&2; exit 2; }
jq -e . "$f" >/dev/null 2>&1 || { echo "not valid JSON: $f"; echo "RESULT=FAIL STRUCTURAL=fail SEMANTIC=fail"; exit 1; }
ver="$(jq -r '.ckb_version // empty' "$f")"
SPEC="$ROOT/spec/v${ver:-0.1}"
[ -d "$SPEC" ] || { echo "unsupported ckb_version: '${ver}' (this producer vendors: $(ls "$ROOT/spec" | tr '\n' ' '))"; echo "RESULT=FAIL STRUCTURAL=fail SEMANTIC=fail"; exit 1; }

structural=skipped
if command -v uvx >/dev/null 2>&1; then
  if out="$(uvx --quiet check-jsonschema --schemafile "$SPEC/ckb.schema.json" "$f" 2>&1)"; then structural=pass
  else structural=fail; printf '%s\n' "$out" | grep -E '::\$' | sed -E 's#^[^:]*::#  schema: #' | head -50; fi
else
  echo "  note: uvx not found — structural (JSON Schema) check skipped. Install uv: https://docs.astral.sh/uv/"
fi

viol="$(jq -r -f "$SPEC/semantic.jq" "$f" | jq -r '.[]')"
if [ -z "$viol" ]; then semantic=pass; else semantic=fail; printf '%s\n' "$viol" | sed 's/^/  semantic: /'; fi

result=PASS; { [ "$structural" = fail ] || [ "$semantic" = fail ]; } && result=FAIL
echo "RESULT=$result STRUCTURAL=$structural SEMANTIC=$semantic"
[ "$result" = PASS ]
