#!/usr/bin/env bash
# Last edited: 2026-09-22 12:20 PT
# One-time developer setup: installs the build and lint tools, then activates the committed git hooks.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v brew >/dev/null 2>&1; then
  echo "error: Homebrew is required. Install it from https://brew.sh and run this script again." >&2
  exit 1
fi

for tool in xcodegen swiftlint swiftformat; do
  if brew list --formula "$tool" >/dev/null 2>&1; then
    echo "$tool is already installed."
  else
    brew install "$tool"
  fi
done

git -C "$repo_root" config core.hooksPath .githooks
echo "Git hooks are active (core.hooksPath = .githooks)."

if [[ "$(xcode-select -p)" != *Xcode*.app* ]]; then
  echo "warning: xcode-select points at $(xcode-select -p), so xcodebuild will fail." >&2
  echo "Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
fi
