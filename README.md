# RoomScan

A native iOS application for scanning 3D rooms, attaching spatial notes, and sharing multi-scan projects. RoomPlan is the planned room-capture technology but has not yet been integrated.

The repository currently includes a minimal `App` / `Features` architecture and a mock Authentication reference implementation. Real Sign in with Apple, Room scanning, and backend sync are not implemented yet.

## Documentation

- [App overview](docs/app-overview.md) — product scope and implementation status
- [Product requirements](docs/product-requirements.md) — target behavior, acceptance criteria, and edge cases
- [Architecture](docs/architecture.md) — current and planned project structure
- [Coding guidelines](docs/coding-guidelines.md) — development conventions
- [Tech stack](docs/tech-stack.md) — configured and planned technologies

Read the relevant documents before contributing or implementing new features. AI development guidance is provided in `.cursor/rules.md` and `CLAUDE.md`, with reusable task prompts under `.cursor/prompts/`.

## Getting Started

1. Open `roomscan.xcodeproj`
2. Install the shared Git hooks:

   ```sh
   ./scripts/install-git-hooks.sh
   ```

3. Use an Xcode version that supports the configured iOS 26.2 deployment target.
4. Build and run the `roomscan` scheme.

## Pre-Commit Checks

The shared pre-commit hook runs:

```sh
git diff --check
xcodebuild test -project roomscan.xcodeproj -scheme roomscan -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' -only-testing:roomscanTests -derivedDataPath .derivedData CODE_SIGNING_ALLOWED=NO
```

Run `./scripts/install-git-hooks.sh` once after cloning the repository to enable the hook locally.

A LiDAR-capable device will be required once RoomPlan-based room scanning is implemented.
