# Fix a Bug

Investigate and fix:

**[Describe the bug, reproduction steps, expected behavior, and any relevant logs or screenshots]**

---

## Context

Before investigating:

Read:

- `docs/architecture.md`
- `docs/coding-guidelines.md`

Read when relevant:

- `docs/app-overview.md`
- `docs/product-requirements.md`

Inspect the related implementation, callers, state flow, and existing tests.

---

## Investigation

When possible:

1. Reproduce the issue.
2. Trace the execution flow.
3. Identify the root cause.
4. Explain why the bug occurs.

Do not implement a fix until a plausible root cause has been identified.

If the issue cannot be reproduced, explain why and continue with a reasoned investigation based on the available evidence.

---

## Requirements

- Fix the root cause, not only the visible symptom.
- Keep the patch minimal and focused.
- Preserve existing behavior outside the affected area.
- Follow the documented architecture and project conventions.
- Consider Swift concurrency, actor isolation, lifecycle, state management, async flows, and error handling where relevant.
- Avoid unrelated refactoring or cleanup.

Add or update a regression test whenever practical, unless the issue cannot reasonably be tested.

---

## Validation

After implementing the fix:

- Verify the original reproduction steps.
- Build the affected targets.
- Run relevant unit tests.
- Run relevant UI tests if the user flow changed.
- Confirm no obvious regressions were introduced.

---

## Final Summary

Provide:

- Root cause
- Files modified
- Fix implemented
- Tests added or updated
- Verification performed
- Remaining risks or limitations