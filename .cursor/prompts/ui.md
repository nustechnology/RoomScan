# UI Implementation

Implement the provided UI design for the existing feature.

## Context

- This task is UI-only.
- Business logic will be implemented in a later task.
- Existing ViewModels, Services, Models, navigation, and business logic should remain unchanged unless absolutely required for the UI.
- Use placeholder actions where necessary.

## Before coding

Read:

- docs/architecture.md
- docs/coding-guidelines.md
- docs/product-requirements.md

Review the existing feature before making changes.

## Requirements

### Design

- Match the provided design as closely as possible.
- Build reusable UI components whenever appropriate.
- Avoid duplicated UI code.

### Design System

If the project does not already have one, create a shared design system that can be reused by future screens.

Extract reusable design tokens instead of hardcoding values.

Create shared definitions for:

- Typography
- Colors
- Spacing
- Corner radius
- Shadows (if needed)

Place them in a shared location (for example `Core/UI`).

### Typography

Do not hardcode font sizes in Views.

Create a centralized typography system, for example:

- Large Title
- Title
- Headline
- Body
- Caption

Support Dynamic Type whenever appropriate.

### Colors

Do not hardcode colors directly inside Views.

Create reusable color definitions.

### Spacing

Avoid magic numbers.

Create shared spacing constants.

Example categories:

- xs
- sm
- md
- lg
- xl

### Components

If reusable components appear in the design, extract them.

Examples:

- PrimaryButton
- SecondaryButton
- AppTextField
- AppCard
- LoadingView

### Accessibility

Support:

- Dynamic Type
- VoiceOver
- Appropriate accessibility labels

### Architecture

Do NOT:

- Change business logic.
- Change services.
- Change Firebase implementation.
- Change ViewModel behavior.
- Introduce unnecessary architecture.

The purpose of this task is to prepare a scalable UI foundation.

### Validation

- Project builds successfully.
- No SwiftLint warnings.
- No duplicated design tokens.

## Deliverables

Before implementing:

- Brief implementation plan.

After implementing:

- Summary of changed files.
- Newly created shared UI components.
- Newly created design system files.
- Any assumptions due to missing design details.