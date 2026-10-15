# Telemetry: what is sent, and how to turn it off

Telemetry is **on by default**: each `/kb` run shares one anonymous report with the maintainer to help improve the plugin. The first run shows a notice **before** anything is sent. This page shows the exact payload.

## The exact payload

One JSON object per run. This is a real report from a test run; every field is listed, and nothing else is sent. The `repo` value is a salted hash whose salt never leaves your machine.

```json
{
  "schema": 1,
  "day": "2026-10-15",
  "plugin_version": "0.10.0",
  "ckb_version": "0.2",
  "mode": "local",
  "status": "incomplete",
  "repo": "a2fb634f4959",
  "duration_s": 2,
  "os": "darwin",
  "jq": "jq-1.8.2",
  "uv": true,
  "size": "<100",
  "coverage": {
    "manifests": {
      "found": 12,
      "cited": 12
    },
    "lockfiles": {
      "found": 0,
      "cited": 0
    },
    "routes": {
      "found": 0,
      "cited": 0
    },
    "events": {
      "found": 0,
      "cited": 0
    },
    "datastores": {
      "found": 0,
      "cited": 0
    },
    "migrations": {
      "found": 0,
      "cited": 0
    },
    "iac": {
      "found": 1,
      "cited": 1
    },
    "ci": {
      "found": 1,
      "cited": 1
    },
    "config": {
      "found": 0,
      "cited": 0
    },
    "api_specs": {
      "found": 1,
      "cited": 1
    }
  },
  "entities": {
    "components": 1,
    "interfaces": 17,
    "dependencies": 14,
    "datastores": 2,
    "artifacts": 2,
    "services": 1,
    "config_keys": 2,
    "external_services": 1,
    "api_specs": 1,
    "relations": 10
  },
  "confidence": {
    "confirmed": 51,
    "inferred": 0,
    "unknown": 0,
    "overall": "confirmed"
  },
  "validation": {
    "structural": "pass",
    "semantic": "pass",
    "rules_failed": []
  },
  "docs_violations": {
    "parity": 11
  },
  "warnings": {
    "config_value_dropped": 1,
    "relation_not_allowed": 1
  },
  "audit": null
}
```

**Never sent:** repository or organization names, file paths, code, doc text, URLs, config or secret values, IP addresses, or your identity. Per-phase timings, fan-out, token counts, cost and run ids stay in a local file (`runs.jsonl`) and are stripped before sending: the report is built from an explicit allowlist of the fields above.

## Turn it off

| Scope | How |
|---|---|
| One machine | `codebase-kb-engine telemetry off` (saved), or `telemetry on` to re-enable |
| One shell or CI job | `CKB_TELEMETRY=off` or `DO_NOT_TRACK=1` |
| Nothing recorded at all, not even locally | `CKB_METRICS=off` |
| **Every developer in an organization** | Set `CKB_TELEMETRY` to `off` in the `env` block of Claude Code's managed settings (for example `/Library/Application Support/ClaudeCode/managed-settings.json` on macOS, `/etc/claude-code/managed-settings.json` on Linux): `{ "env": { "CKB_TELEMETRY": "off" } }`. Managed settings take precedence over user settings. |

`codebase-kb-engine telemetry status` shows the current state and the endpoint. Reports go over HTTPS to a relay that validates them against a strict allowlist and keeps no IP addresses.
