# Repository Guidelines

## Project Structure & Module Organization
This repository is a macOS menu bar companion app built with Swift Package Manager.

- `Sources/`: app source code (entry point, AppKit lifecycle, polling, API client, config, icons).
- `assets/`: icon source files and bundled app icon assets.
- `docs/`: product and flow documentation (`product.md`, `flow.md`).
- `script/`: helper scripts (for example icon generation).
- `build.sh`, `build-dev.sh`: local build and run scripts.

## Build, Test, and Development Commands
- `swift build`: compile the app target in debug mode.
- `swift build -c release`: compile optimized binary used by packaging.
- `./build.sh`: inject runtime base URL config from env vars and assemble `ReadItSoonCompanion.app`.
- `./build-dev.sh`: local convenience flow (kills running app, builds, opens app).
- `swift run ReadItSoonCompanion`: run directly from SwiftPM during development.

Required env vars for `build.sh`: `BASE_URL`.

## Coding Style & Naming Conventions
- Language: Swift 5.9+, AppKit-first architecture.
- Indentation: 4 spaces; keep methods small and focused.
- Types/protocols: `UpperCamelCase` (`StatusPanelController`).
- Methods/properties/locals: `lowerCamelCase` (`startPolling`, `savePath`).
- Prefer explicit access control (`private`) and `// MARK:` sections for organization.
- Keep filenames aligned with primary type (`Poller.swift`, `APIClient.swift`).

No formatter/linter config is currently committed; match existing style in touched files.

## Testing Guidelines
Automated tests are not yet present (`Tests/` directory is currently absent). For now:

- Run `swift build` before opening a PR.
- Smoke test via `./build-dev.sh` and verify:
  - menu bar icon renders,
  - status panel opens,
  - polling/download flow updates status text.

When adding tests, use SwiftPM XCTest under `Tests/ReadItSoonCompanionTests/` and name files as `*Tests.swift`.

## Commit & Pull Request Guidelines
- Use concise, imperative commit messages (`Add retry for 429 responses`).
- Optional conventional prefixes are acceptable (`chore: ...`) when appropriate.
- Keep commits scoped to one logical change.

PRs should include:
- what changed and why,
- manual verification steps run locally,
- screenshots/GIFs for panel or menu bar UI changes,
- linked issue/spec/doc when relevant.
