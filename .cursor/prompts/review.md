# Review Code

Review:

**[Current changes / commit / branch / pull request / specified files]**

---

## Context

Before reviewing:

Read the relevant documentation under `docs/`.

At minimum:

- `docs/architecture.md`
- `docs/coding-guidelines.md`

Read when relevant:

- `docs/app-overview.md`
- `docs/product-requirements.md`
- `docs/tech-stack.md`

Inspect the surrounding implementation and existing tests so the review reflects the current project rather than isolated files.

---

## Review Checklist

Check for:

### Correctness

- Functional bugs
- Regressions
- Incorrect business logic
- Missing edge cases

### Architecture

- Violations of the documented architecture
- Inconsistent project patterns
- Unnecessary abstractions
- Over-engineering

### Swift

- Swift 6 concurrency issues
- Actor isolation
- Thread safety
- Memory leaks
- Retain cycles
- Error handling
- Unsafe optionals
- Force unwraps / casts

### Code Quality

- Naming
- Readability
- Duplication
- Dead code
- API consistency
- Reusability

### Testing

- Missing unit tests
- Weak assertions
- Untested edge cases

### UI

- Accessibility
- Performance
- Localization
- SwiftUI best practices

---

## Review Rules

Do not modify code.

Report only actionable findings.

Do not suggest architectural rewrites unless they solve a significant issue.

Prefer consistency with the existing project.

---

## Output Format

Order findings by severity:

- Critical
- High
- Medium
- Low
- Nit

For each finding include:

- Severity
- File (and line if available)
- Issue
- Impact
- Suggested fix

If no issues are found:

- State that explicitly.
- Mention any remaining testing risks or areas that deserve additional verification.