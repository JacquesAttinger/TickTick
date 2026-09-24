<!-- Last edited: 2026-09-22 12:28 PT -->

# TickTick

TickTick is a macOS menu bar timer for tasks.
You type a task, give it a time, and the menu bar counts down.
When the time is up, the screen flashes, a sound plays, and a notification shows.
The full product and build plan is in [`docs/planning.md`](docs/planning.md).

## Prerequisites

- macOS 26 or later, with Xcode installed at `/Applications/Xcode.app`.
- [Homebrew](https://brew.sh).
- Point the command-line tools at Xcode one time (this needs `sudo`):

  ```sh
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  ```

  If `xcode-select -p` shows `/Library/Developer/CommandLineTools`, `xcodebuild` fails and SwiftLint crashes.

## Setup

Run this one time after you clone the repo:

```sh
scripts/setup.sh
```

The script installs `xcodegen`, `swiftlint`, and `swiftformat` with Homebrew.
It also sets `core.hooksPath` to `.githooks`, so the pre-commit hook runs on every commit.
The hook runs SwiftFormat (lint mode) and SwiftLint (strict) on the staged Swift files, and it blocks the commit if one of them fails.

## Make targets

| Target | What it does |
|---|---|
| `make gen` | Generates `TickTick.xcodeproj` from `project.yml` with XcodeGen. The project file is not committed. |
| `make build` | Generates the project, then builds the Debug app into `build/`. |
| `make test` | Generates the project, then runs the `TickTickTests` unit tests. |
| `make lint` | Runs `swiftlint lint --strict` and `swiftformat --lint .`. |
| `make format` | Runs `swiftformat .` to fix formatting in place. |
| `make install` | Builds Release, quits a running TickTick, copies the app to `/Applications`, and opens it. |

`build`, `test`, and `install` run `make gen` first, so new files under `TickTick/` or `TickTickTests/` are always part of the build.

## Code rules

- Every Swift file starts with `// Last edited: YYYY-MM-DD HH:MM PT`.
- No file has more than 500 lines, and no function body has more than 75 lines. SwiftLint enforces both.
- Never skip the hook with `git commit --no-verify`.

## Known limits

- **No Time Sensitive notifications.**
  The app is signed with a personal (free) development team, and personal teams cannot sign the `com.apple.developer.usernotifications.time-sensitive` entitlement.
  So `TickTick.entitlements` leaves that key out, and the timer notifications use the `.active` interruption level.
  A Focus mode can hide these notifications, but the flash and the sound still work.
  To get Time Sensitive notifications, sign with a paid Apple Developer team and add the key back.
