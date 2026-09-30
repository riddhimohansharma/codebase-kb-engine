---
description: Read-only. Produce a five-step plan and a proposed patch as text for a chosen initiative. Never writes or applies.
argument-hint: "<initiative>"
---
Produce a change plan for "$ARGUMENTS" on THIS repo. READ-ONLY: never create, edit, or delete files; never run mutating commands; never apply the patch. Output only.

Reason through the five steps in order, showing your work:
1. QUESTION — is the requirement real? If not, say so and stop.
2. DELETE — what existing code/steps to remove.
3. SIMPLIFY — reduce the remainder to its core data model.
4. ACCELERATE — performance/clarity improvements.
5. AUTOMATE — the tests and automation to add last.

Then emit the concrete change as a single unified diff inside one ```diff block, followed by the exact commands the human would run to apply and verify it. You never apply anything — the user applies the patch.
