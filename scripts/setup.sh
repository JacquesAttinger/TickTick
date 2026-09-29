#!/usr/bin/env bash
# Last edited: 2026-09-29 19:40 CDT
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
  if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    echo "note: xcode-select points at $(xcode-select -p)." >&2
    echo "The make targets and the git hook use /Applications/Xcode.app instead, but a bare xcodebuild or swiftlint fails." >&2
  else
    echo "warning: xcode-select points at $(xcode-select -p), and /Applications/Xcode.app is missing." >&2
    echo "xcodebuild and SwiftLint will fail. Install Xcode, then run the command below." >&2
  fi
  echo "To fix it everywhere, run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
fi
