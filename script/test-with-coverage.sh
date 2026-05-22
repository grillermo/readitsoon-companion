#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "Running all tests with coverage enabled..."
swift test --enable-code-coverage "$@"

PROFILE_PATH="$(swift test --show-codecov-path)"
PROFILE_DIR="$(cd "$(dirname "$PROFILE_PATH")" && pwd)"

if [[ "$PROFILE_PATH" != *.profdata ]]; then
  if [[ -f "$PROFILE_DIR/default.profdata" ]]; then
    PROFILE_PATH="$PROFILE_DIR/default.profdata"
  fi
fi

echo ""
echo "Coverage profile: $PROFILE_PATH"

TEST_BINARY="$(find .build -type f -path "*.xctest/Contents/MacOS/*PackageTests" | head -n 1 || true)"

if [[ -n "$TEST_BINARY" && -f "$TEST_BINARY" ]]; then
  echo ""
  echo "=== llvm-cov summary (project files) ==="
  if ! xcrun llvm-cov report \
    "$TEST_BINARY" \
    -instr-profile "$PROFILE_PATH" \
    -ignore-filename-regex=".build/checkouts|Tests/"; then
    echo "llvm-cov summary failed for profile $PROFILE_PATH"
    echo "Fallback: raw JSON coverage export is at $PROFILE_DIR"
  fi
else
  echo ""
  echo "Could not find XCTest bundle binary for llvm-cov summary."
  echo "Fallback: open the profile at $PROFILE_PATH with your preferred coverage tooling."
fi
