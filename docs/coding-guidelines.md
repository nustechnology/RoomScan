# Coding Guidelines

These conventions apply to all new code and refactoring.

This document describes **how code should be written**, not product requirements or future architecture.

---

## Design

- Follow the architecture described in `architecture.md`.
- Prefer simplicity over abstraction.
- Keep changes small and focused.
- Organize code by feature.
- Avoid introducing new architectural patterns without a concrete need.
- Use constructor injection for dependencies.
- Avoid global mutable state, service locators, and dependency containers.
- Introduce protocols only when they improve testability, isolate an external dependency, or provide demonstrated reuse.

---

## Swift

- Prefer Swift Concurrency (`async`/`await`) for asynchronous work.
- Bridge callback-based APIs at the service boundary when necessary.
- Keep UI-observed mutable state on `@MainActor`.
- Handle cancellation explicitly.
- Avoid force unwraps (`!`) and forced casts (`as!`).
- Propagate meaningful errors instead of silently ignoring failures.
- Follow Apple's Swift API Design Guidelines.

---

## SwiftUI

- Keep Views lightweight.
- Views should render state and forward user actions.
- Do not place business logic inside Views.
- Move presentation state into ViewModels.
- Prefer composition over deeply nested View hierarchies.
- Extract reusable Components only when duplication appears.

---

## Code Style

- Prefer explicit, readable code over clever solutions.
- Write small, focused types and functions.
- Use descriptive names.
- Prefer composition over inheritance.
- Avoid magic numbers and duplicated logic.
- Remove unused code.
- Minimize comments by writing self-explanatory code.

---

## Services

- Keep networking, persistence, platform APIs, and third-party SDKs inside Services.
- Do not expose framework-specific types directly to Views.
- Keep Services focused on a single responsibility.
- Prefer dependency injection over creating dependencies internally.

---

## Testing

- Add or update unit tests for business logic whenever practical.
- Test observable behavior rather than implementation details.
- Use deterministic mocks or fakes through constructor injection.
- Avoid real networking, storage, or platform services in unit tests.
- Keep tests independent and easy to understand.

---

## Accessibility

- Localize all user-facing strings.
- Support Dynamic Type.
- Support VoiceOver where applicable.
- Do not rely on color alone to communicate important information.

---

## Security

- Store credentials and tokens using secure platform storage.
- Never log credentials, tokens, or sensitive user data.
- Always use secure network communication for backend requests.
- Minimize the collection and storage of sensitive data.

---

## Validation

Before completing a change:

- Build the affected targets.
- Run relevant unit tests.
- Run UI tests when user flows change.
- Ensure no new build warnings are introduced.
- Verify the implementation follows the documented architecture and project conventions.

---

## General Principles

When multiple valid solutions exist:

- Prefer the simpler solution.
- Prefer consistency with the existing codebase.
- Avoid premature optimization.
- Avoid over-engineering.
- Write code that a new team member can understand quickly.