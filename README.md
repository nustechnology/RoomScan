# RoomScan

A native iOS application for scanning 3D rooms, attaching spatial notes, and sharing multi-scan projects. RoomPlan is the planned room-capture technology but has not yet been integrated.

The repository currently includes a minimal `App` / `Features` architecture and a mock Authentication reference implementation. Real Sign in with Apple, Room scanning, and backend sync are not implemented yet.

## Documentation

- [App overview](docs/app-overview.md) — product scope and implementation status
- [Product requirements](docs/product-requirements.md) — target behavior, acceptance criteria, and edge cases
- [Architecture](docs/architecture.md) — current and planned project structure
- [Coding guidelines](docs/coding-guidelines.md) — development conventions
- [Tech stack](docs/tech-stack.md) — configured and planned technologies

Read the relevant documents before contributing or implementing new features. AI development guidance is provided in `.cursor/rules.md`, with reusable task prompts under `.cursor/prompts/`.

## Getting Started

1. Open `roomscan.xcodeproj`
2. Use an Xcode version that supports the configured iOS 26.2 deployment target.
3. Build and run the `roomscan` scheme.

A LiDAR-capable device will be required once RoomPlan-based room scanning is implemented.