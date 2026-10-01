# Security Policy

## What this plugin promises
Codebase KB Engine analyses repositories **read-only**. While a session is armed (see the README's *Safety model*), a `PreToolUse` hook blocks every write outside a `.ckb-output` directory, every git write or push, and every tool that isn't on a known read-only list. In repo-URL mode, clones are shallow, push-disabled, and deleted when the job ends.

## Honest limits
- The gate inspects shell command **text**. It is a strong guardrail, not an OS sandbox. For untrusted code, also enable Claude Code's sandbox mode.
- Hooks run with your user privileges, as all Claude Code plugin hooks do. Read `hooks/` before installing.
- Deleting a clone removes it with `rm -rf`. On SSDs, that doesn't guarantee physical erasure.

## Anonymous usage reports
The plugin sends one anonymous report per run (on by default; see README). Reports contain counts and category IDs only, never names, paths, code or values. Disable with `codebase-kb-engine telemetry off`, `CKB_TELEMETRY=off` or `DO_NOT_TRACK=1`.

## Reporting a vulnerability
Please **do not open a public issue** for a bypass of the read-only gate or the clone sandbox. Report it privately through GitHub: **Security → Report a vulnerability** on this repository. Include the hook payload or command that got through, and the Claude Code and OS versions.

You'll get an acknowledgement within 7 days. Confirmed bypasses are fixed with a regression test in `tests/guard.test.sh` and credited in `CHANGELOG.md` unless you ask otherwise.

## Supported versions
Only the latest release receives fixes during `0.x`.
