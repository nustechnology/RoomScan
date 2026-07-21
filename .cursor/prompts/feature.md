# Implement a Feature

Implement the following feature:

**[Describe the feature, related requirement IDs, and acceptance criteria]**

## Context

Before doing anything, read the relevant project documentation:

- `docs/app-overview.md`
- `docs/product-requirements.md`
- `docs/architecture.md`
- `docs/coding-guidelines.md`
- `docs/tech-stack.md`

Then inspect the existing source code and tests to identify:

- Existing implementation patterns
- Reusable views and components
- Relevant models and services
- Existing test conventions
- Files that may be affected

## Requirements

- Follow the documented SwiftUI and feature-based MVVM architecture.
- Keep business logic out of Views.
- Use constructor dependency injection.
- Use Swift concurrency (`async`/`await`) for asynchronous work.
- Prefer native Apple frameworks and the technologies already used by the project.
- Reuse existing components and patterns before creating new ones.
- Do not introduce unnecessary abstractions, dependencies, or architectural layers.
- Keep the change focused on the requested feature.
- Add or update tests for important behavior where practical.
- Do not treat a product requirement as implemented until corresponding code and tests exist.

## Before Coding

First provide:

1. Your understanding of the feature
2. The related requirement IDs and acceptance criteria
3. The proposed implementation approach
4. Files to create or modify
5. Testing strategy
6. Assumptions or limitations

Make reasonable decisions by following existing project conventions.

Ask a focused question only when missing or ambiguous information would materially change product behavior, architecture, or a difficult-to-reverse technical decision.

Do not begin implementation until the plan is accepted when the change introduces a new architecture pattern or significant dependency.

## Implementation

Implement incrementally and keep each file focused.

Do not introduce repositories, use cases, dependency containers, service locators, or generic abstractions unless a demonstrated requirement justifies them.

## Validation

After implementation:

- Build the affected targets.
- Run relevant unit tests.
- Run relevant UI tests when the user flow changes.
- Run lint checks if linting is configured.
- Review the implementation for unnecessary complexity and duplication.
- Confirm that no unrelated behavior was changed.
- Run SwiftLint.
- Fix all SwiftLint violations.
- Report any remaining warnings or errors.

## Final Summary

Summarize:

- Files created or modified
- Behavior implemented
- Requirement IDs covered
- Tests added or updated
- Test and build results
- Assumptions and remaining limitations