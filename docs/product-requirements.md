## Reading Guide

This document is the single source of truth for product requirements.

It defines:

- Functional requirements
- Business rules
- Validation rules
- Acceptance criteria

It does not describe the current implementation or architecture.

See:

- app-overview.md for implementation status
- architecture.md for technical architecture
- coding-guidelines.md for coding conventions

# Product Requirements

This document is the English, implementation-oriented version of the RoomScan PRD. It describes the **target showcase demo**, not the current source code. See [app-overview.md](app-overview.md) for implementation status.

Requirement IDs are stable references for implementation plans, tests, and pull requests. A feature must not be treated as implemented until code and tests exist.

## Product Scope

RoomScan allows users to:

- Create projects containing multiple 3D room scans.
- Capture, review, name, and save scans.
- Place colored text notes at model-relative 3D positions.
- Share a project through a revocable, expiring invitation link.
- View projects shared by other users without editing them.
- Work from local data while uploads and synchronization continue asynchronously.

## Roles and Permissions

### Owner

The user who creates a project may:

- Create, edit, and delete the project.
- Create, rename, and delete room scans.
- Create, edit, move, and delete notes.
- Share the project and manage or revoke access.

### Viewer

A user who accepts a shared project may:

- View project metadata, 3D scans, and notes.
- Remove the project from their own **Shared With Me** list.

A Viewer must not edit the project, scans, or notes; manage access; or reshare the project.

Authorization must be enforced by the backend. Hiding UI controls is not sufficient.

## MVP Scope

The MVP includes:

- Authentication
- Projects
- Room Capture
- 3D Viewer
- Notes
- Sharing

Everything else is considered future enhancement unless explicitly added to this document.

## Functional Requirements

### Authentication

- **FR-AUTH-001 — Sign in:** Authentication is required to synchronize data, share projects, and receive shared projects. Sign in with Apple is an acceptable MVP mechanism.
- **FR-AUTH-002 — Session:** Persist the session across launches. Refresh an expired session when possible or require sign-in again. Never delete unsynchronized local data because a session expires.
- **FR-AUTH-003 — Sign out:** Remove credentials from the device. Warn when projects or scans are not synchronized, and preserve local data that has not been uploaded.

### Project Management

- **FR-PROJ-001 — Create:** Project name is required, trimmed, 1–100 characters, Unicode-compatible, and does not need to be unique. Description is optional and limited to 1,000 characters.
- **FR-PROJ-002 — List:** Show name, scan count, last-updated date, optional thumbnail, and sync status. Sort by most recently updated by default.
- **FR-PROJ-003 — Search:** Search by project name in both **My Projects** and **Shared With Me**.
- **FR-PROJ-004 — Detail:** Show name, description, Owner, created/updated dates, scans, recipient count, and actions allowed by the current role.
- **FR-PROJ-005 — Edit:** The Owner may edit name and description. Save locally first, then synchronize.
- **FR-PROJ-006 — Delete:** Only the Owner may delete. Confirm that scans, notes, and recipient access will also be removed.

### 3D Room Capture

- **FR-SCAN-001 — Capability check:** Before capture, check device support, camera permission, available storage, and camera availability. Unsupported devices may still view shared models.
- **FR-SCAN-002 — Camera permission:** Explain why camera access is needed before requesting it. If denied, block capture and provide a path to Settings.
- **FR-SCAN-003 — Scan metadata:** Scan name is required, trimmed, 1–100 characters, and does not need to be unique. Description is optional and limited to 500 characters.
- **FR-SCAN-004 — Guidance:** Before capture, instruct the user to move slowly, cover walls/corners/doors/furniture, keep the camera unobstructed, and ensure adequate lighting.
- **FR-SCAN-005 — Capture:** Show camera preview, recognized areas, real-time guidance, Cancel, and Finish. Prevent automatic screen locking during active capture and restore the previous behavior afterward.
- **FR-SCAN-006 — Cancel:** If partial data exists, let the user continue or discard the current capture.
- **FR-SCAN-007 — Finish:** Stop capture, process the 3D model, generate a thumbnail, and open scan review.
- **FR-SCAN-008 — Review:** Allow rotate, zoom, inspect, rename, save, rescan, or discard.
- **FR-SCAN-009 — Save:** Save locally and associate with the current project before upload. Upload must not block continued app use.
- **FR-SCAN-010 — Upload:** Show progress, support automatic and manual retry, resume after connectivity returns, and present actionable errors.

### Saved Scan Management

- **FR-ROOM-001 — List:** Show thumbnail, name, creation date, note count, and sync status.
- **FR-ROOM-002 — Detail:** Show name, description, thumbnail, creator, created/updated dates, note count, and an Open 3D View action. Owners also receive rename, delete, and add-note actions.
- **FR-ROOM-003 — Rename:** Only the Owner may rename; apply the creation validation rules.
- **FR-ROOM-004 — Delete:** Confirm that related notes will be deleted. Remove the scan from its project and make it inaccessible to Viewers.

### 3D Viewer

- **FR-VIEW-001 — Open:** Open a local model immediately; otherwise download it with progress and retry states.
- **FR-VIEW-002 — Controls:** Support rotate, pan, zoom, focus, reset view, and fit-room-to-screen.
- **FR-VIEW-003 — Modes:** Support 3D and top-down views in the MVP.
- **FR-VIEW-004 — Note markers:** Render notes as readable colored bubbles anchored to their saved model positions. Support selected/unselected states, short previews, and tap interaction.
- **FR-VIEW-005 — Note detail:** Show full content, color, creator, and created/updated dates. Owners also receive Edit, Move, and Delete actions.
- **FR-VIEW-006 — Note list:** Show all notes with truncated content, color, and updated date. Selecting a row focuses the camera and highlights the corresponding bubble.

### Text Notes

- **FR-NOTE-001 — Create:** Only the Owner may create a note by selecting Add Note, choosing a model position, entering content, choosing a color, and saving.
- **FR-NOTE-002 — Fields:** Content is required, trimmed, and 1–2,000 characters. Color is required and selected from the supported palette. A valid model position is required.
- **FR-NOTE-003 — Position:** Persist at least model-relative X/Y/Z coordinates, optional orientation, and the related model version. Position must not depend on the current camera.
- **FR-NOTE-004 — Color:** Provide a predefined accessible palette. Proposed colors are yellow, red, blue, green, orange, and purple; do not rely on color alone to convey meaning.
- **FR-NOTE-005 — Edit:** Only the Owner may edit content and color. Save locally first, then synchronize.
- **FR-NOTE-006 — Move:** Only the Owner may choose a new model position and confirm or cancel the change.
- **FR-NOTE-007 — Delete:** Only the Owner may delete, confirmation is required, and the bubble and list entry must disappear together.

### Sharing

- **FR-SHARE-001 — Manage sharing:** Only the Owner may share. Show project name, recipients, invitation status, Invite People, and a clear read-only notice.
- **FR-SHARE-002 — Create invitation:** Generate a project-specific, expiring, revocable Viewer invitation and present the iOS share sheet.
- **FR-SHARE-003 — Open invitation:** If installed, deep-link into the app, authenticate if needed, show project information, and allow Accept or Decline. If not installed, open installation guidance and preserve a way to continue acceptance afterward.
- **FR-SHARE-004 — Accept:** Add the project to **Shared With Me**, download metadata, and fetch scans on demand or through the cache policy.
- **FR-SHARE-005 — Invalid invitation:** Handle malformed, expired, revoked, deleted-project, and already-authorized cases.
- **FR-SHARE-006 — Recipients:** Show recipient name or email, Pending/Accepted status, sent date, and accepted date.
- **FR-SHARE-007 — Revoke:** Stop further downloads, prevent access after the next authorization check, and remove or invalidate cached data according to the app policy.
- **FR-SHARE-008 — Leave:** A Viewer may remove a project from **Shared With Me** without affecting the Owner or other Viewers.

### Shared With Me

- **FR-SHARED-001 — List:** Show project name, Owner, scan count, updated date, and thumbnail.
- **FR-SHARED-002 — State:** Represent Active, Downloading, Download Failed, Access Revoked, Project Deleted, and Temporarily Unavailable.
- **FR-SHARED-003 — Refresh:** Fetch Owner changes at app launch, pull-to-refresh, project open, and supported background synchronization opportunities.

### Offline and Synchronization

- **FR-SYNC-001 — Local first:** Persist project create/edit, scan save, note create/edit, and note/scan deletion locally before synchronization.
- **FR-SYNC-002 — Status:** Data may be Pending, Syncing, Synced, Failed, or Conflict.
- **FR-SYNC-003 — Upload queue:** Persist the queue across app termination, retry when online, prevent duplicate uploads, limit concurrency, and prioritize metadata before large model files.
- **FR-SYNC-004 — Conflict:** Only Owners edit. For edits from multiple Owner devices, prefer the latest server update; deletion takes precedence over older edits. Completed scans are immutable.
- **FR-SYNC-005 — Share readiness:** Do not create an invitation until required project data is uploaded. Explain the state and allow wait or retry.

## Domain Rules

1. A project has exactly one Owner and may contain many scans.
2. A scan belongs to exactly one project and must have a name.
3. A note belongs to exactly one scan and cannot exist independently.
4. Deleting a project deletes or invalidates its scans, notes, and access grants.
5. Deleting a scan deletes its notes.
6. A Viewer is read-only and cannot reshare.
7. A user has at most one active access grant per project.
8. An expired invitation must be recreated.
9. A note position belongs to a specific model version.
10. Rescanning creates a new scan; notes are not migrated automatically.
11. A project is fully synchronized only after all required metadata and files upload successfully.

## Required Screens

1. Authentication: introduction, Sign in with Apple, Privacy Policy, Terms of Service.
2. My Projects: list, search, create, sync status, empty state.
3. Create/Edit Project: fields, validation, Save, Cancel.
4. Project Detail: metadata, scans, Add Room Scan, Share, role-appropriate edit/delete actions.
5. Pre-scan Check: capability, permission, guidance, Start Scan.
6. Scan Capture: camera, recognized areas, guidance, Cancel, Finish.
7. Scan Review: model, rename, Save, Scan Again, Discard.
8. Scan Detail: metadata, thumbnail, note count, Open 3D View, role-appropriate actions.
9. 3D Viewer: model, reset, top view, note list, Owner-only Add Note, loading/error states.
10. Note Editor: content, color, Save, Cancel, and Owner-only move/delete actions.
11. Share Management: invitations, Viewers, Invite People, Revoke Access.
12. Invitation: project and Owner summary, scan count, permission, Accept, Decline.
13. Shared With Me: shared list, Owner, updated date, Remove from Shared With Me.

## UI States

Every applicable screen must define:

- **Empty:** no projects, no scans, no notes, no shared projects, or no recipients.
- **Loading:** scan processing, model download, upload, synchronization, or invitation acceptance.
- **Error:** unsupported device, denied camera, insufficient storage, scan-processing failure, corrupt model, transfer failure, offline state, deleted project, revoked access, expired invitation, or unavailable server.
- **Recovery:** provide the applicable Retry, Open Settings, Continue Offline, or Return to Project action.

## Non-Functional Requirements

### Performance

- Render project lists quickly from cached metadata.
- Show immediate feedback when model loading begins.
- Keep rotate, pan, and zoom responsive on supported devices.
- Load thumbnails—not full models—in lists.
- Bound the number of large models retained in memory.

### Reliability

- Never lose a locally saved scan because upload fails.
- Persist the upload queue across termination.
- Retry transient failures with exponential backoff.
- Verify model-file integrity.
- Viewer failures must not corrupt projects or notes.

### Security and Privacy

- Use HTTPS for all network traffic.
- Store credentials in secure platform storage.
- Authorize every backend request.
- Use expiring invitations and time-limited model URLs.
- Prevent access after revocation.
- Never log tokens or sensitive note content.
- Explain camera use, uploaded data, project visibility, and account/data deletion.
- Do not upload raw camera imagery unless it is required and disclosed.

### Accessibility and Localization

- Support Dynamic Type and VoiceOver.
- Give interactive controls accessibility labels.
- Do not distinguish notes by color alone.
- Provide the note list as an alternative to spatial bubble discovery.
- Localize user-facing strings. Proposed MVP languages are English and Vietnamese.

## Acceptance Criteria

- **AC-01 — Project:** Reject empty names; persist and display created projects across relaunch.
- **AC-02 — Scan:** Supported devices can scan; unsupported devices receive a clear message; saved scans have a project, name, and thumbnail; offline state does not lose local data.
- **AC-03 — 3D Viewer:** Reopen persisted models; rotate, pan, zoom, and reset work; loading and error states are visible.
- **AC-04 — Note:** Owner can place a non-empty note; its model-relative position survives reload; it appears in the note list.
- **AC-05 — Edit note:** Owner can edit, move, and delete; Viewer cannot.
- **AC-06 — Share:** Owner can create an invitation; recipient can inspect and accept it; synchronized scans and notes are viewable; Viewer cannot edit or reshare.
- **AC-07 — Revoke:** Owner can revoke; Viewer cannot download more data and loses access after authorization is rechecked.

## Required Edge-Case Tests

- App termination during scan processing.
- Storage exhaustion during save.
- Connectivity loss during upload.
- Suspension or termination during background upload.
- Project deletion while a Viewer is viewing.
- Access revocation while a Viewer is offline.
- Invitation opened with another account or used multiple times.
- Overlapping or nearby notes.
- Memory pressure from a large model.
- Corrupt downloaded model.
- Concurrent Owner edits from multiple devices.
- Sign-out with unsynchronized data.
- Scan deletion during upload.
- Camera permission denied and later granted.
- Phone call or system interruption during capture.

## Architecture Decisions Pending

The PRD does not select:

- Backend, API protocol, database, or object storage.
- Local persistence technology.
- 3D model file format and model-version strategy.
- Cache limits and revocation behavior for offline Viewer data.
- Invitation web fallback and deferred deep-link provider.
- Background transfer implementation.
- Exact note palette and contrast treatment.

Resolve these through explicit architecture decisions before implementing the dependent feature. Do not infer a vendor or framework from this document.
