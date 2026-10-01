#!/usr/bin/env bash
# reference.sh — deterministic reference tables generated from ckb.json (never model-written).
# Usage: reference.sh <ckb.json> > <kb_dir>/09-reference.md
# Sections: Interfaces, Dependencies, Artifacts, Services, Datastores, Config keys, External services, API specs, Relations.
# Rows sorted by id (relations by from,kind,to); absent/empty collections render "_None recorded._".
# Config keys carry names and is_secret only; ckb.json never holds values. Front-matter: ckb_doc "reference",
# confidence = global confidence_summary (confidence_scope: global). No timestamps.
# Exit: 0 ok · 2 usage/precondition (missing or non-JSON artifact).
set -uo pipefail
art="${1:-}"
[ -n "$art" ] || { echo "usage: reference.sh <ckb.json>" >&2; exit 2; }
jq -e 'type == "object"' "$art" >/dev/null 2>&1 || { echo "artifact missing or not a JSON object: $art" >&2; exit 2; }
jq -r --arg ex "':(exclude)ckb'" '
  def esc: if . == null then "-" elif type == "array" then (if length == 0 then "-" else map(tostring) | join(", ") end)
           else tostring end | gsub("[\r\n]+"; " ") | gsub("\\|"; "\\|") | (if . == "" then "-" else . end);
  def tag: if .confidence == "confirmed" then "[C]" elif .confidence == "inferred" then "[I]" else "[?]" end;
  def src: (.provenance // []) as $p
           | if ($p | length) == 0 then "-" else ("\($p[0].path):\($p[0].line)" + (if ($p | length) > 1 then " (+\(($p | length) - 1))" else "" end)) end;
  def cell: if . == null or . == "" then null else "`" + tostring + "`" end;
  def table($title; $rows; $hdr; f):
    "## \($title)", "",
    (if ($rows | length) == 0 then "_None recorded._", ""
     else ("| " + ($hdr | join(" | ")) + " |"), ("|" + ($hdr | map("---") | join("|")) + "|"),
          ($rows[] | "| " + ([f] | map(esc) | join(" | ")) + " |"), ""
     end);
  def coll($c): ((.entities // {})[$c] // []) | map(objects) | sort_by(.id // "");
  def detail: if .kind == "http" then ("\(.http.method // "") \(.http.normalized_path // "")" + (if .http.host then " @\(.http.host)" else "" end))
              elif .kind == "event" then "\(.event.transport // ""):\(.event.topic // "")"
              elif .kind == "rpc" then "\(.rpc.protocol // "") \(.rpc.service // "")/\(.rpc.method // "")"
              elif .kind == "websocket" then "ws \(.websocket.normalized_path // "")"
              else (.symbol // "") end;
  (.confidence_summary // {}) as $cs
  | "---",
    "ckb_doc: \"reference\"",
    "title: \"Generated reference\"",
    "audience: \"engineers, tooling\"",
    "diataxis: \"reference\"",
    "source_commit: \((.repo.commit_sha // "") | tojson)",
    "branch: \((.repo.branch // "") | tojson)",
    "generator: \(("\(.generator.name // "codebase-kb-engine") \(.generator.version // "")" | sub(" $"; "")) | tojson)",
    "ckb_version: \((.ckb_version // "") | tojson)",
    "confidence_scope: \"global\"",
    "confidence:",
    "  confirmed: \($cs.confirmed // 0)",
    "  inferred: \($cs.inferred // 0)",
    "  unknown: \($cs.unknown // 0)",
    "freshness_cmd: \(("git diff --quiet " + (.repo.commit_sha // "<sha>") + " HEAD -- . " + $ex) | tojson)",
    "---",
    "# Generated reference", "",
    "Generated from `ckb.json` by `scripts/reference.sh`. Do not edit by hand. Tags: [C] confirmed, [I] inferred, [?] unknown.", "",
    table("Interfaces"; coll("interfaces"); ["ID", "Kind", "Role", "Detail", "Service", "Name", "Conf", "Source"];
          (.id | cell), .kind, .role, detail, .service_key, .name, tag, src),
    table("Dependencies"; coll("dependencies"); ["purl", "manifest_path", "scope", "version_constraint", "resolved_version", "source", "Conf", "Cited at"];
          (.purl | cell), .manifest_path, .scope, .version_constraint, .resolved_version, .source, tag, src),
    table("Artifacts"; coll("artifacts"); ["purl", "Kind", "Version", "manifest_path", "Name", "Conf", "Source"];
          (.purl | cell), .kind, .version, .manifest_path, .name, tag, src),
    table("Services"; coll("services"); ["service_key", "Runtime", "Ports", "Environments", "Name", "Conf", "Source"];
          (.service_key | cell), .runtime, .ports, .environments, .name, tag, src),
    table("Datastores"; coll("datastores"); ["ID", "Engine", "Instance key", "Schema", "Table", "Access", "Conf", "Source"];
          (.id | cell), .engine, .instance_key, .schema, .table, .access, tag, src),
    table("Config keys"; coll("config_keys"); ["Name", "Source", "is_secret", "Conf", "Referenced at"];
          (.name | cell), .source, .is_secret, tag, src),
    table("External services"; coll("external_services"); ["Domain", "Vendor", "Category", "Conf", "Source"];
          (.domain | cell), .vendor, .category, tag, src),
    table("API specs"; coll("api_specs"); ["Path", "Format", "Version", "Conf", "Source"];
          (.path | cell), .format, .version, tag, src),
    table("Relations"; ((.relations // []) | map(objects) | sort_by([.from // "", .kind // "", .to // ""])); ["From", "Kind", "To", "Conf", "Source"];
          (.from | cell), .kind, (.to | cell), tag, src)
' "$art"
