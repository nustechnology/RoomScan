# Review Unit Tests

Review the existing unit tests for:

**[Feature, type, component, or test target]**

Do not modify production code.

## Context

Before reviewing:

Read:

- `docs/architecture.md`
- `docs/coding-guidelines.md`

Read when relevant:

- `docs/product-requirements.md` to verify business behavior and acceptance criteria
- `docs/tech-stack.md` for testing framework and platform constraints

Inspect the related production code, existing test helpers, mocks, and test organization.

---

## Review Checklist

### Test Quality

Check for:

- Missing scenarios
- Missing edge cases
- Missing regression coverage
- Duplicate tests
- Flaky or nondeterministic tests
- Weak assertions
- Overspecified assertions
- Testing implementation details instead of observable behavior

### Test Design

Verify:

- Tests are focused and independent.
- Each test verifies one meaningful behavior.
- Naming is descriptive and consistent.
- Async and actor-isolation behavior is handled correctly.
- Mocks, fakes, and stubs are appropriate.
- Real platform dependencies are avoided.

### Organization

Verify:

- Tests mirror the production folder structure.
- Test files follow existing naming conventions.
- Production and test hierarchy remain consistent.
- No unnecessary View tests exist unless explicitly required.

### Coverage

Check whether important behavior is covered:

- Success cases
- Failure cases
- Boundary conditions
- State transitions
- Cancellation
- Async behavior
- Regression scenarios

Point out missing coverage when appropriate.

---

## Review Rules

Do not rewrite tests unless explicitly requested.

Prefer consistency with the existing testing style.

Do not recommend additional tests unless they provide meaningful value.

---

## Final Summary

Provide:

### Overall Quality

Rate the test suite:

- Excellent
- Good
- Fair
- Needs Improvement

### Findings

List findings ordered by priority.

For each finding include:

- Severity
- File
- Issue
- Why it matters
- Suggested improvement

If no meaningful issues are found:

- State that explicitly.
- Mention any remaining testing risks or intentionally uncovered scenarios.