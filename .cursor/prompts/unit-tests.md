# Add Unit Tests

Create or improve unit tests for:

**[Describe the type, feature, behavior, or related requirement IDs]**

## Context

Before writing tests, read:

- `docs/architecture.md`
- `docs/coding-guidelines.md`

Also read when relevant:

- `docs/product-requirements.md` for expected behavior, validation rules, acceptance criteria, and edge cases
- `docs/tech-stack.md` for current testing tools and platform constraints
- `docs/app-overview.md` only when implementation status affects the requested scope

Inspect the production code, existing test targets, project structure, test helpers, and current testing conventions before making changes.

## Test Framework

- Follow the testing framework and conventions already used by the target.
- Prefer Apple’s Swift Testing framework for unit tests when consistent with the existing target.
- Do not migrate existing XCTest-based tests solely for consistency unless explicitly requested.
- Keep UI tests in the UI test target; do not mix them with unit tests.

## Test Philosophy

- Test observable behavior rather than implementation details.
- Prefer black-box testing whenever practical.
- Keep tests deterministic, readable, independent, and focused.
- Each test should verify one meaningful behavior.
- Use descriptive test names following the existing project convention.
- Avoid asserting private implementation details or exact internal call sequences unless they are part of the contract.

## Scope

Focus unit tests on:

- ViewModels
- Services
- App and feature state transitions
- Core business logic
- Utilities
- Storage components
- Regression fixes

Do not create unit tests for:

- SwiftUI Views
- Simple models or DTOs without behavior
- Generated code
- Assets or localization resources

unless explicitly requested or meaningful behavior exists.

## Test Organization

Mirror the production source structure inside `roomscanTests`.

Example:

```text
roomscan/
└── Features/
    └── Authentication/
        ├── ViewModels/
        └── Services/

roomscanTests/
└── Features/
    └── Authentication/
        ├── ViewModels/
        └── Services/
```

Rules:

- Place each test file under the corresponding feature hierarchy.
- Keep production and test file naming aligned where practical.
- Do not create unnecessary or empty folders.
- Follow existing project organization and target membership.

## Dependencies

Use deterministic fakes, stubs, or mocks through constructor injection.

Do not use real:

- Networking
- RoomPlan
- ARKit
- Camera
- Keychain
- File transfers
- Connectivity monitoring
- Timers
- Current date/time
- Random values
- Other nondeterministic platform dependencies

Introduce controllable abstractions only when they provide meaningful testability.

## Production Code

Do not modify production behavior solely to satisfy a test.

Small testability improvements may be made when justified, such as:

- Constructor injection
- Protocol extraction around an external or replaceable boundary
- Narrow access-level adjustments
- Injecting a clock, identifier generator, or similar nondeterministic dependency

Do not expose private implementation details only for testing.

If meaningful testing requires a larger architectural change, stop and explain:

1. Why the current design prevents testing
2. The smallest proposed production change
3. The affected files and risks

Do not make that larger change without approval.

## Coverage

When applicable, cover:

- Success cases
- Failure and cancellation cases
- Boundary and validation conditions
- State transitions
- Async and actor-isolation behavior
- Relaunch or persistence behavior through deterministic fakes
- Relevant acceptance criteria and regression scenarios

Avoid redundant tests that verify the same behavior through different implementation details.

## Validation

After adding or updating tests:

1. Build the affected test target.
2. Run the smallest relevant test scope first.
3. Run the broader unit test suite when practical.
4. Confirm tests compile and execute successfully.
5. Report failures with their root cause.
6. Run SwiftLint.
7. Fix all SwiftLint violations.
8. Report any remaining warnings or errors.

Do not automatically modify production code merely to make a failing test pass. Determine whether the failure indicates:

- A production defect
- An incorrect test expectation
- A nondeterministic test
- A test-environment or configuration problem

Explain the conclusion before proposing changes.

## Final Summary

Provide a concise summary including:

- Test files added, moved, or updated
- Behaviors and requirement IDs covered
- Remaining scenarios intentionally not covered
- Production changes made for testability, if any
- Test commands or suites executed
- Final pass/fail results