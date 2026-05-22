# ReadItSoon Companion Product Overview

## Purpose

ReadItSoon Companion is a native macOS menu bar utility that continuously syncs completed ReadItSoon articles from the backend API to a local folder as Markdown files. It is designed to be lightweight, always-on, and minimally interactive.

At a product level, it solves one job: keep a user’s downloaded article library on disk automatically.

## User-Facing Features

## 1. Menu Bar Presence with Quick Status Panel

- The app lives in the macOS menu bar (`NSStatusItem`) and runs with accessory activation policy (no persistent Dock app UI).
- Clicking the menu bar icon opens a custom floating panel (not a standard dropdown menu).
- The panel shows:
  - Logged-in account email.
  - Current sync state (monitoring, downloading, complete, error).
  - Polling cadence (every 60 seconds).
  - Selected local save folder.
  - Pending downloads list (article titles waiting to be written locally).
  - Last downloaded title when the queue is empty.
  - Quick actions: change save folder and quit.

Implementation entry points:
- `Sources/AppDelegate.swift`
- `Sources/StatusPanelController.swift`

## 2. First-Run Setup and Folder Selection

- On first launch, if no config exists, the app prompts the user to choose a destination folder.
- If the user cancels initial setup, the app exits.
- The chosen path is stored in a local JSON config file in the user home directory.

Implementation entry points:
- `Sources/AppDelegate.swift` (`promptFirstRun`, `pickSaveFolder`)
- `Sources/Config.swift`

## 3. Continuous Polling for Pending Articles

- The app polls the backend every 60 seconds.
- It fetches all delivered-but-not-yet-downloaded articles for the configured user.
- If no items are pending, state remains idle/monitoring.
- If items exist, the app enters downloading state and processes the queue.

Implementation entry points:
- `Sources/Poller.swift` (`start`, `poll`)
- `Sources/APIClient.swift` (`fetchArticles`)

## 4. Concurrent Download and Local File Write

- Pending items are downloaded concurrently with a max concurrency of 3.
- For each article:
  - Fetch markdown content from API.
  - Ensure target directory exists.
  - Generate a sanitized filename from title.
  - Resolve collisions with numeric suffixes (`-2`, `-3`, ...).
  - Write the `.md` file atomically.
  - Notify backend that this article was downloaded.

Implementation entry points:
- `Sources/Poller.swift` (`downloadAll`, `downloadArticle`, `sanitize`, `uniquePath`)
- `Sources/APIClient.swift` (`fetchMarkdown`, `markDownloaded`)
- `Sources/AsyncSemaphore.swift` (concurrency cap)

## 5. Live Queue and Progress Reporting in UI

- Poller emits structured updates containing:
  - Sync state.
  - Current pending titles.
  - Last downloaded title.
- `AppDelegate` consumes these updates and refreshes the panel so the pending list changes in near real-time while downloads complete.

Implementation entry points:
- `Sources/Poller.swift` (`PollerUpdate`, `PollerProgress` actor)
- `Sources/AppDelegate.swift` (`applyPollerUpdate`, `refreshPanel`)
- `Sources/StatusPanelController.swift` (`setContent`)

## 6. Basic Reliability Behaviors

- API requests include bearer auth token.
- Request path includes user email query param.
- 429 rate-limit responses are retried with exponential backoff.
- Poller surfaces error state to the UI.

Implementation entry points:
- `Sources/APIClient.swift` (`perform`)
- `Sources/Poller.swift`

## High-Level Architecture

## Components

- `AppDelegate`
- Application lifecycle, status item wiring, setup flow, panel toggling, and bridging poller updates to UI.
- `StatusPanelController`
- All panel UI layout and interactions (folder change, quit, pending list rendering, click-outside dismissal).
- `Poller`
- Periodic synchronization orchestration and concurrent download execution.
- `PollerProgress` actor
- Thread-safe in-memory queue/progress snapshot model for UI updates.
- `APIClient`
- Network boundary for companion endpoints.
- `Config`
- Persistent local configuration (`~/.readitsoon-companion.json`).

## Runtime Data Flow

1. App launches and loads icon + status item.
2. App loads config:
   - If missing: prompt for folder, persist config.
   - If present: start poller immediately.
3. Poller fetches pending article metadata from API.
4. Poller updates UI state with pending titles.
5. Poller downloads markdown, writes local files, marks backend records as downloaded.
6. Poller emits completion/error/idle updates.
7. Status panel renders current state whenever user opens it (and during active updates).

## External Contracts

The companion app depends on these backend endpoints:

- `GET /api/companion/articles?email=...`
  - Returns pending article metadata (`id`, `title`, `domain`).
- `GET /api/companion/articles/:id/markdown?email=...`
  - Returns raw markdown body.
- `POST /api/companion/articles/:id/downloaded?email=...`
  - Marks article as downloaded.

Auth model:

- Bearer token in `Authorization` header for every request.

## Local Storage and Artifacts

- Config file:
  - `~/.readitsoon-companion.json`
- Contains:
  - `save_path` (destination folder selected by the user)
- Downloaded files:
  - `{savePath}/{sanitized-title}.md`
- If duplicate filename:
  - `{savePath}/{sanitized-title}-N.md`

## Operational Notes for Engineers

- The app is AppKit-based (not SwiftUI), built with Swift Package Manager, targeting macOS 12+.
- The panel UI is intentionally transient and non-activating to behave like a menu bar utility.
- Polling is timer-based, not push-based; end-to-end sync latency is up to the polling interval.
- Current state is in-memory only; queue/progress is not persisted across app restarts.

## Related Docs

- End-to-end backend + companion flow: `docs/flow.md`
