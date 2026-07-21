# Refactor Code

Refactor:

**[Describe the target files, component, or concern]**

---

## Context

Before making changes:

Read:

- `docs/architecture.md`
- `docs/coding-guidelines.md`

Inspect the surrounding implementation, callers, and tests to understand the current behavior and public interfaces.

---

## Goal

Improve the internal structure of the code without changing its observable behavior.

The goal is to improve readability and maintainability, not redesign the feature.

---

## Requirements

- Preserve existing behavior unless explicitly requested otherwise.
- Keep public APIs unchanged whenever practical.
- Keep the refactor focused on the requested scope.
- Prefer incremental improvements over large rewrites.
- Follow the documented architecture.
- Reuse existing project patterns.
- Remove duplication where appropriate.
- Simplify unnecessary complexity.
- Improve naming and code organization where helpful.
- Do not introduce new architecture, dependencies, or unrelated cleanup.

---

## Before Refactoring

First provide:

1. Current issues
2. Proposed refactoring approach
3. Files to modify
4. Potential risks

---

## Validation

After refactoring:

- Build affected targets.
- Run relevant unit tests.
- Run UI tests if affected.
- Ensure behavior remains unchanged.
- Review the result for unnecessary complexity.
- Run SwiftLint.
- Fix all SwiftLint violations.
- Report any remaining warnings or errors.

---

## Final Summary

Summarize:

- Files modified
- Improvements made
- Any behavior intentionally changed
- Tests executed
- Remaining technical debt

When in doubt, prefer the smallest refactoring that improves the code.