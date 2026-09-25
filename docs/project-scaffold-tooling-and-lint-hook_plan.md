# TT-1: Project scaffold, tooling, and lint hook

<!-- Last edited: 2026-09-22 14:22 CDT -->

**TLDR:** The repo is almost empty, so this step builds the skeleton of the TickTick Mac app.
After this step, the app builds, its tests run, and a small `⏱` icon shows in the menu bar with a "Quit TickTick" menu.
It also adds the tools that block bad code: a lint check runs before every commit and rejects files that break the rules.

## Where to find it

This feature is not reachable through any UI yet, because the repo has no app.
After this step, the result is visible as a `⏱` icon in the macOS menu bar when you run `make install`.
Everything else in this step is developer tooling: `make` targets, a setup script, and a git pre-commit hook.

## Orientation

The repo is `JacquesAttinger/TODO_TIMER`, and it holds the TickTick menu bar timer app described in `docs/planning.md`.
Today the repo contains only `README.md` (one line) and `docs/planning.md` (the full project plan).
There is no Swift code, no project file, no Makefile, and no lint configuration.
This issue is step TT-1 of the plan: it creates the whole scaffold that steps TT-2 through TT-13 build on.
The relevant plan sections are "Technical approach" (XcodeGen, no committed `.xcodeproj`, AppKit `NSStatusItem`) and "Folder layout" (the target directory tree).

## What is wrong and why

Nothing is broken; this is a green-field feature.
The gap is that no build system, lint gate, or app shell exists, so no later issue can start.
The shape of the work is:

1. A setup script installs the three Homebrew tools (`xcodegen`, `swiftlint`, `swiftformat`) and points git at the committed hooks directory.
2. An XcodeGen `project.yml` describes the app and test targets, so the `.xcodeproj` is generated and never committed (this avoids `project.pbxproj` merge conflicts between parallel agents).
3. A minimal AppKit app shows `⏱` in the menu bar with a "Quit TickTick" item, and hides the Dock icon through `LSUIElement`.
4. A Makefile wraps generate, build, test, lint, format, and install.
5. SwiftLint and SwiftFormat configs plus a pre-commit hook enforce the code rules (500-line files, 75-line functions).

One environment fact matters: on this machine, `xcode-select -p` still points at `/Library/Developer/CommandLineTools`, and `xcodebuild` fails.
The brief says Jacques runs `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` by hand, because it needs sudo.
The implement agent must check `xcode-select -p` first; if it still points at CommandLineTools, it can write and commit all files but cannot verify the build, and it must say so on the issue instead of guessing.

## Likely touched files

- `scripts/setup.sh` — new; installs `xcodegen`, `swiftlint`, `swiftformat` via Homebrew and runs `git config core.hooksPath .githooks`.
- `project.yml` — new; XcodeGen spec for the `TickTick` app target and the `TickTickTests` test target.
- `Makefile` — new; targets `gen`, `build`, `test`, `lint`, `format`, `install`.
- `.swiftlint.yml` — new; `file_length` error at 500, `function_body_length` error at 75.
- `.swiftformat` — new; formatting rules, with the file header check off so the `// Last edited:` line survives.
- `.githooks/pre-commit` — new; runs SwiftFormat in lint mode and SwiftLint on staged Swift files.
- `.gitignore` — new; ignores `*.xcodeproj`, `build/`, `DerivedData/`, `.DS_Store`.
- `TickTick/App/TickTickApp.swift` — new; the `@main` entry point that attaches the app delegate.
- `TickTick/App/AppDelegate.swift` — new; creates the `NSStatusItem` with `⏱` and the "Quit TickTick" menu.
- `TickTick/Resources/Info.plist` — new; `LSUIElement = YES` plus the standard app keys.
- `TickTick/Resources/TickTick.entitlements` — new; `com.apple.developer.usernotifications.time-sensitive`.
- `TickTick/Resources/Assets.xcassets/` — new; empty asset catalog so the project has a place for the app icon later.
- `TickTickTests/ScaffoldTests.swift` — new; one trivial Swift Testing test so `make test` has something to run.
- `README.md` — rewritten; setup steps and the `make` targets.

## Plan

1. **Tooling and hook commit.**
   Write `scripts/setup.sh` (executable): `brew install xcodegen swiftlint swiftformat` (idempotent), then `git config core.hooksPath .githooks`.
   Write `.gitignore` with `*.xcodeproj`, `build/`, `DerivedData/`, `.DS_Store`.
   Write `.swiftlint.yml`: `file_length: { error: 500 }`, `function_body_length: { error: 75 }`, and exclude `build`.
   Write `.swiftformat`: `--swiftversion 6.0`, `--header ignore` (so SwiftFormat never rewrites the `// Last edited:` line), and otherwise defaults.
   Write `.githooks/pre-commit` (executable): collect staged `*.swift` files with `git diff --cached --name-only --diff-filter=ACM`, exit 0 if there are none, else run `swiftformat --lint` and `swiftlint lint --strict` on them and exit non-zero on any violation.
   Run `scripts/setup.sh` so the tools and the hook are active for the following commits.
   No Swift files are staged in this commit, so the hook passes trivially.
2. **Project spec commit.**
   Write `project.yml`: project name `TickTick`; deployment target macOS 26.0; base settings `SWIFT_VERSION: 6.0`, `SWIFT_STRICT_CONCURRENCY: complete`, `DEVELOPMENT_TEAM: UH88Q62C4G`, `CODE_SIGN_STYLE: Automatic`.
   App target `TickTick`: type `application`, bundle ID `com.jacquesattinger.TickTick`, sources by folder glob `TickTick/` (excluding `Resources/Info.plist` from compile sources), `INFOPLIST_FILE: TickTick/Resources/Info.plist`, `CODE_SIGN_ENTITLEMENTS: TickTick/Resources/TickTick.entitlements`, and the SPM package `KeyboardShortcuts` from `https://github.com/sindresorhus/KeyboardShortcuts` pinned `from: 2.0.0`.
   Test target `TickTickTests`: type `bundle.unit-test`, sources `TickTickTests/`, dependency on `TickTick`.
   A target-level `scheme` on `TickTick` with `testTargets: [TickTickTests]`, so `xcodebuild -scheme TickTick` and `xcodebuild test` both work.
   Write `TickTick/Resources/Info.plist` with `LSUIElement = YES` and the standard bundle keys, and `TickTick/Resources/TickTick.entitlements` with `com.apple.developer.usernotifications.time-sensitive = true`.
   Write the `Makefile`: `gen` = `xcodegen generate`; `build` = `xcodebuild -project TickTick.xcodeproj -scheme TickTick -configuration Debug -derivedDataPath build build`; `test` = the same with `test -destination 'platform=macOS'`; `lint` = `swiftlint lint --strict` plus `swiftformat --lint .`; `format` = `swiftformat .`; `install` = Release build into `build/`, `pkill -x TickTick || true`, `ditto` the app to `/Applications/TickTick.app`, then `open /Applications/TickTick.app`.
3. **Minimal app commit.**
   Write `TickTick/App/TickTickApp.swift`: a SwiftUI `@main App` with `@NSApplicationDelegateAdaptor(AppDelegate.self)` and an empty `Settings` scene as the only scene.
   Write `TickTick/App/AppDelegate.swift`: in `applicationDidFinishLaunching`, create an `NSStatusItem` with the title `⏱` and attach an `NSMenu` with one item, "Quit TickTick", wired to `NSApplication.terminate(_:)`.
   Write `TickTickTests/ScaffoldTests.swift`: `import Testing` and one trivial `@Test` (for example, assert the bundle identifier constant), so the test target compiles and passes.
   Every Swift file starts with `// Last edited: YYYY-MM-DD HH:MM PT`.
   Run `make gen build test lint` if the Xcode prerequisite is done; the pre-commit hook lints these files either way.
4. **README commit.**
   Rewrite `README.md`: what TickTick is (one paragraph), the one-time sudo `xcode-select` prerequisite, `scripts/setup.sh`, and a table of the `make` targets.
   Point to `docs/planning.md` for the full plan.
5. **End-to-end verification and the entitlement fallback.**
   Run the full acceptance sequence from the Verification section below.
   If code signing rejects the time-sensitive entitlement, remove the key from `TickTick.entitlements`, add the limitation to the README, and note it on TOD-5 so TT-6 uses the `.active` interruption level.
   If `xcode-select -p` still points at CommandLineTools, stop before the build steps and report the blocked prerequisite on the issue instead.

## Decisions made alone

- **App entry style:** a SwiftUI `@main App` with `NSApplicationDelegateAdaptor` and an empty `Settings` scene, not a pure AppKit `main`.
  Reason: the folder layout in `docs/planning.md` names both `TickTickApp.swift` and `AppDelegate.swift`, TT-11 later needs a `Settings` scene anyway, and the status item itself stays AppKit as "Technical approach" requires.
- **KeyboardShortcuts pin:** `from: 2.0.0` (latest major).
  Reason: the brief names the package but no version; a major-version pin is the normal SPM choice.
- **Derived data location:** `-derivedDataPath build` inside the repo, so `build/` in `.gitignore` covers all build output and `make install` can find `build/Build/Products/Release/TickTick.app` at a fixed path.
- **`.swiftformat` header rule:** `--header ignore`.
  Reason: the mandatory `// Last edited:` header changes on every edit, and SwiftFormat's header rule would either strip it or fight it.
- **Hook lints working-tree content of staged paths, not the staged blobs.**
  Reason: extracting staged blobs to a temp tree adds complexity for a solo repo; the simple form catches the required case (a staged lint violation blocks the commit).
- **`make lint` runs both SwiftLint and SwiftFormat in lint mode.**
  Reason: the acceptance command `make gen build test lint` should prove the same checks the hook enforces.
- **A trivial test file is part of this issue.**
  Reason: the acceptance criterion `make test` succeeds needs at least one test in `TickTickTests`, and TT-2 replaces it with real tests.
- **`make install` kills a running TickTick before copying.**
  Reason: the brief says install must "relaunch", and copying over a running app is unreliable.
- **Blocked-prerequisite handling:** commit all scaffold files even if `xcodebuild` is unavailable, and report the unverified steps.
  Reason: the sudo `xcode-select` step is explicitly Jacques's, and the file content does not depend on it.
- **Empty `Assets.xcassets` is included now.**
  Reason: the planning folder layout lists it under `Resources/`, and adding it later would touch `project.yml` review noise for no gain.

## Out of scope found

- **No CI workflow** — lint and tests run only locally and in the pre-commit hook; a GitHub Actions check would catch agents that bypass hooks.
- **Repo name vs app name mismatch** — the repo is `TODO_TIMER` but the app is TickTick; planning.md decision 19 accepts the TickTick name, so this is cosmetic only.
- **Root `README.md` has no license or screenshot** — TT-13 already owns the README polish pass (feature list and screenshot).

## Verification

Run on a machine where Jacques has already run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

1. `scripts/setup.sh && make gen build test lint` — every step exits 0; `TickTick.xcodeproj` exists but `git status` stays clean (it is ignored).
2. `make install` — the `⏱` icon appears in the menu bar, no Dock icon appears, and "Quit TickTick" in its menu quits the app.
3. Hook check: add a temporary Swift file with a function body over 75 lines, `git add` it, and run `git commit` — the commit is blocked with a SwiftLint error; then delete the temp file and reset the index.
4. Entitlement check: `codesign -d --entitlements - /Applications/TickTick.app` shows the time-sensitive key, or the README documents the fallback if signing rejected it.
5. Cleanup: quit TickTick and confirm with `pgrep -x TickTick` that no process is left.
