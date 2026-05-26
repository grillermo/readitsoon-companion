# ReadItSoon Companion

macOS menu bar companion app that polls ReadItSoon and writes completed articles to local Markdown files.

## Prerequisites

- macOS 12+
- Xcode 15+ command line tools
- Swift 5.9+
- Python 3 (only for the local E2E mock-backend test)

## Build

- `swift build`
- `swift build -c release`

## Test

Run full test suite:

- `swift test`

Run only unit tests:

- `swift test --filter ReadItSoonCoreUnitTests`

Run only integration tests:

- `swift test --filter ReadItSoonCoreIntegrationTests`

Run only E2E-style local backend test:

- `swift test --filter ReadItSoonCoreE2ETests`

## Coverage

Run all tests with coverage and print a summary report:

- `./script/test-with-coverage.sh`

Notes:

- Coverage is report-only; there is no failure threshold gate.
- The script uses `swift test --enable-code-coverage` and prints `llvm-cov report` output when it can resolve the package test binary.

## Environment Variables

The app bundle build script (`build.sh`) requires:

- `BASE_URL`

Example:

- `BASE_URL=https://readitsoon.com ./build.sh`

At runtime, the app asks the user to sign in with a `@kindle.com` email and OTP, then stores the resulting session token in local companion config.

## Test Safety Notes

- Tests do not call production ReadItSoon APIs.
- Integration tests use in-memory/mock transport.
- E2E test launches a local Python HTTP server process bound to `127.0.0.1`.
