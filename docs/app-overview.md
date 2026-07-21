# App Overview

RoomScan is a native iOS showcase application for capturing indoor spaces, annotating them with spatial notes, and sharing projects with read-only viewers.

## Current State

The project currently provides:

- Application skeleton
- Mock authentication flow
- Root navigation
- Reference MVVM implementation
- Unit and UI tests for the authentication flow

Real authentication, RoomPlan integration, cloud synchronization, and sharing will be implemented in future milestones.

## Target State

The completed application will allow users to:

- Capture rooms
- Organize multiple scans into projects
- View models in 3D and top-down modes
- Annotate rooms with spatial notes
- Share projects with read-only viewers
- Synchronize data across devices

## Product Constraints

- Authentication is required for synchronization and sharing.
- Capturing a room requires a device supported by the eventual capture implementation and camera permission; unsupported devices must retain viewing capability.
- Locally saved data must survive connectivity, upload, and authentication failures.
- Backend authorization—not UI visibility alone—must enforce Owner and Viewer permissions.
- User-facing content is planned for English
