# Architecture

This document describes the architecture implemented in the current source tree. Product behavior and future requirements belong in [product-requirements.md](product-requirements.md); implementation status belongs in [app-overview.md](app-overview.md).

## Current Structure

RoomScan uses a shallow, feature-oriented MVVM structure:

```text
roomscan/
├── App/
│   ├── RoomScanApp.swift
│   ├── AppView.swift
│   ├── AppState.swift
│   └── AppRoute.swift
├── Features/
│   ├── Authentication/
│   │   ├── Views/
│   │   ├── ViewModels/
│   │   ├── Services/
│   │   └── Models/
│   └── Home/
│       └── Views/
├── Core/
│   └── UI/                 # Shared design tokens, typography
├── Resources/
│   └── Fonts/
├── Localizable.xcstrings
└── Assets.xcassets/
```

`Core/` holds shared code used by multiple features (currently design-system UI). Expand it only when there are real consumers; do not add empty scaffolding.

## Architecture Principles

- Prefer simplicity over abstraction.
- Optimize for readability and onboarding.
- Keep the folder structure shallow.
- Keep feature-specific code inside its feature.
- Introduce shared layers and protocols only when they solve a demonstrated reuse, integration, or testing need.
- Do not add repositories, use cases, dependency containers, or service locators without a concrete requirement.
- Prefer consistency with the existing codebase over introducing new patterns.

## Layer Responsibilities

- **App:** owns the application entry point, dependency composition, root navigation, and app-wide state. `RoomScanApp` creates the authentication service and `AppState`; `AppView` selects the root UI from `AppState.Phase`.
- **Features:** contain user-facing functionality. A feature owns its presentation, state management, service boundaries, and feature-specific data types.
- **Core:** contains shared code with multiple real feature consumers (for example `Core/UI` design tokens and typography). Feature-specific code must not be moved here preemptively.
- **Resources:** contains bundled assets that are not managed by asset catalogs, such as custom fonts.

Views render state and forward user actions. ViewModels own screen state and coordinate asynchronous work. Services isolate external or replaceable behavior. Models represent the data and errors used by the feature.

## Creating a New Feature

When implementing a new feature:

1. Create a new folder under `Features/`.
2. Follow the feature-based MVVM structure.
3. Start with the minimum number of files.
4. Introduce new abstractions only when justified.
5. Keep the feature self-contained whenever practical.

## Feature Organization

Every new feature should be self-contained under `Features/<FeatureName>/` and follow feature-based MVVM:

```text
Features/<FeatureName>/
├── Views/
├── ViewModels/
├── Services/
├── Models/
└── Components/       # Optional reusable views within the feature
```

Create only the folders required by working code. Start with the smallest structure that supports the feature. Expand incrementally as responsibilities grow. Add a ViewModel when a screen has state or behavior that should not live in its View, and add a service or protocol only when the feature has an external, replaceable, or testable boundary.

## Dependency Direction

Dependencies flow from presentation toward behavior and are supplied through initializers:

```text
App composition → AppState → feature service protocol
View → ViewModel → feature service protocol
View → Models
```

Concrete services conform to feature-owned protocols. Views and ViewModels should not select concrete service implementations or depend directly on backend, persistence, or platform-vendor types. The current project has no repository or use-case layer.

## Authentication Reference Implementation

Authentication is the first feature and the reference implementation for future modules.

- `RoomScanApp` creates `MockAuthenticationService` and injects it into `AppState`.
- `AppState` restores the session at launch and owns the app-wide authentication phase.
- `AppView` switches between restoration, authentication, home, and retry UI.
- `AuthenticationView` creates `AuthenticationViewModel` with the service received through `AppState`.
- `AuthenticationViewModel` owns screen state: idle, signing in, or failed.
- `AuthenticationService` defines the provider-neutral boundary used by both `AppState` and `AuthenticationViewModel`.
- `MockAuthenticationService` is the current implementation. It stores an in-memory session and provides deterministic outcomes for development, previews, and tests.

Root flow:

```text
Launch → restore session
  ├── authenticated → Home
  ├── no session → Authentication
  └── restore failure → Retry
```

## Concurrency

- Keep UI-observed state on the main actor.
- Prefer async/await for asynchronous work.
- Allow cancellation to propagate naturally.

When in doubt, prefer consistency with the existing project over introducing a new architectural pattern.
