# TT-3: Duration parser and time formatting

<!-- Last edited: 2026-09-24 15:00 PT -->

**TLDR:** We add two small Swift files with pure functions and no UI.
One file reads a typed duration such as `25`, `1h30`, or `1:30` and turns it into a number of seconds, or refuses bad input.
The other file turns seconds and dates into display text such as `24:13`, `+2:13`, `1 h 30 min`, and `3:42 PM`.
Table-driven tests prove every rule.

## Where to find it

Not UI-reachable.
This issue adds a pure-logic layer: two Swift files under `TickTick/Time/` and their unit tests.
Later issues use them: TT-5 (menu bar label and popover), TT-7 (quick-add duration field with live preview), and TT-10 (time badges).

## Orientation

The area is the TickTick macOS app described in `docs/planning.md`.
TT-1 (TOD-5) has merged, so `master` has the project scaffold: `project.yml`, `Makefile`, SwiftLint, SwiftFormat, the pre-commit hook, and the `TickTickTests` target.
The part this issue owns is the `TickTick/Time/` folder from the planned folder layout, which holds all duration and time text logic.
The exact sections are two new files: `DurationParser.swift` with `parse(_:) -> TimeInterval?`, and `TimeFormatting.swift` with the countdown, overtime, human, clock, preview, and menu-bar-name-cut formatters.
Product decisions 7 (duration input formats and live preview), 9 (menu bar text and the 24-character name cut), 10 (popover fields), and 12 (overtime `+2:13`) define the required output shapes.

## What is wrong and why

Nothing is broken; this is a gap.
No code exists yet that converts typed durations to seconds or seconds to display text, and four later issues need exactly that.
The shape of the fix is two stateless namespaces (`enum DurationParser` and `enum TimeFormatting` with static functions), so callers never construct anything and tests need no setup.
The parser normalizes the input (trim, lowercase, collapse inner whitespace), then tries three regex grammars in order: colon form `h:mm`, hour compound (`1h`, `1.5h`, `1h30`, `1h 30m`), and minutes (`25`, `25m`, `90 min`).
It then rejects any result that is zero, negative, or over 24 hours.
The formatters are pure functions of their inputs; the clock and preview formatters take an explicit `Date`, `Locale`, and `TimeZone` so tests are deterministic.

## Likely touched files

- `TickTick/Time/DurationParser.swift` — new; `parse(_:) -> TimeInterval?` and its private grammar helpers.
- `TickTick/Time/TimeFormatting.swift` — new; countdown, overtime, human, clock, preview, and `menuBarName(_:)` cut.
- `TickTickTests/DurationParserTests.swift` — new; table-driven Swift Testing cases for valid, invalid, and edge inputs.
- `TickTickTests/TimeFormattingTests.swift` — new; formatter cases with a fixed locale, time zone, and `now`.
- `docs/duration-parser-and-time-formatting_plan.md` — this plan.

## Plan

0. Sync the branch: `git fetch` and merge `origin/master` so the TT-1 scaffold (`project.yml`, `Makefile`, `.swiftlint.yml`, `.githooks/pre-commit`, `TickTickTests` target) is present.
1. Add `TickTick/Time/DurationParser.swift` with `enum DurationParser` and `static func parse(_ input: String) -> TimeInterval?`.
   Grammar, applied to the normalized input in this order:
   - Colon form: `^(\d{1,2}):([0-5]\d)$` read as hours:minutes, so `1:30` is 90 minutes and `1:75` and `:30` fail.
   - Hour compound: hours number (integer or decimal) plus an hour unit (`h`, `hr`, `hrs`, `hour`, `hours`), then an optional minutes number with an optional minute unit, so `1h`, `1.5h`, `1h30`, and `1h 30m` all pass.
   - Minutes: an integer with an optional minute unit (`m`, `min`, `mins`, `minute`, `minutes`), so `25`, `25m`, and `90 min` pass.
   Sum the components, round to whole seconds, and return `nil` unless `0 < total <= 24 * 3600`.
   Commit with the parser tests from step 2 (one commit-sized unit: parser plus its tests).
2. Add `TickTickTests/DurationParserTests.swift` using Swift Testing `@Test(arguments:)` tables:
   - Valid: `25`, `25m`, `90 min`, `1h`, `1h30`, `1h 30m`, `1:30`, `1.5h`, `24h`, ` 25 M `, `1H30`, `0.5h`, each with its expected seconds.
   - Invalid: empty string, whitespace only, `0`, `0m`, `0:00`, `-5`, `25h`, `24h 1m`, `:30`, `1:75`, `abc`, `1h abc`, `30s`, `1.5`, `1.5m`, `1,5h`, `25 h 30`.
3. Add `TickTick/Time/TimeFormatting.swift` with `enum TimeFormatting`:
   - `countdown(_ seconds: TimeInterval) -> String`: `m:ss` under one hour (`24:13`, `0:59`), `h:mm:ss` from one hour (`1:02:03`). A part of a second rounds up, and negative input shows `0:00`.
   - `overtime(_ seconds: TimeInterval) -> String`: `+` plus the countdown form (`+2:13`, `+1:02:03`). A part of a second rounds down.
   - `human(_ seconds: TimeInterval) -> String`: whole minutes as `45 min`, `1 h 30 min`, and bare `2 h` when minutes are zero; values round to the nearest minute with a floor of `1 min`.
   - `clock(_ date: Date, locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> String`: locale-aware short time (`3:42 PM`) via `Date.FormatStyle` with hour and minute.
   - `preview(seconds: TimeInterval, now: Date, locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> String`: `= 1 h 30 min · ends 3:42 PM`, where the end is `now + seconds`.
   - `menuBarName(_ name: String) -> String`: unchanged at 24 `Character`s or fewer; else the first 24 characters, trailing whitespace trimmed, plus `…`.
   Commit with the formatting tests from step 4.
4. Add `TickTickTests/TimeFormattingTests.swift` with `Locale(identifier: "en_US")`, `TimeZone(identifier: "America/Los_Angeles")`, and a fixed `now`:
   - Countdown: `0`, `59`, `1453` → `24:13`, `3600` → `1:00:00`, `3723` → `1:02:03`.
   - Overtime: `133` → `+2:13`, and a value over one hour.
   - Human: `2700` → `45 min`, `5400` → `1 h 30 min`, `7200` → `2 h`, `36` → `1 min`, `5429` → `1 h 30 min` (rounding).
   - Clock and preview: a fixed `now` that renders `3:42 PM`, and one preview string checked end to end.
   - Menu bar cut: 24-character name unchanged, 25-character name cut with `…`, an emoji-containing name (Character count, not UTF-16), and a cut point that lands on a space.
5. Run `make gen test lint`, fix any SwiftLint or SwiftFormat findings, and make sure every new Swift file starts with `// Last edited: YYYY-MM-DD HH:MM PT` and stays under the 500-line and 75-line limits.

## Decisions made alone

- **Namespace shape:** caseless `enum`s with static functions (`DurationParser`, `TimeFormatting`), because the functions are pure and the planning doc's folder layout names exactly these two files. Reason: no state, no init, trivial test setup.
- **Bare numbers are minutes and must be integers:** `25` parses, `1.5` and `1.5m` do not. Reason: decision 7 only shows decimals with an explicit hour unit (`1.5h`), and decimal minutes would force sub-minute text in the `human` preview.
- **Unit spellings accepted:** `m`, `min`, `mins`, `minute`, `minutes` and `h`, `hr`, `hrs`, `hour`, `hours`, case-insensitive. Reason: the issue demands whitespace and case tolerance; these are the common spellings, and anything else is garbage to reject.
- **Colon input is hours:minutes:** `1:30` is 90 minutes, minutes limited to `00`–`59`. Reason: decision 7 lists `1:30` next to `1h30` as a duration input; the acceptance criteria mark `1:75` and `:30` invalid.
- **Exactly 24 h is valid, over 24 h is not:** the issue says reject "values over 24 h", so `24h` passes and `25h` and `24h 1m` fail.
- **Compound components sum without a per-part cap:** `1h 90m` is 150 minutes and valid. Reason: only the colon grammar carries a 0–59 rule; rejecting `1h 90m` would need an arbitrary extra rule the issue does not state.
- **No seconds unit:** `30s` is rejected. Reason: decision 7 lists no seconds form, and every consumer works in whole minutes.
- **`human` rounds to whole minutes with a floor of 1 min:** a decimal-hour input such as `0.01h` (36 s) displays as `1 min`. Reason: the shown formats (`45 min`, `1 h 30 min`) are minute-granular, and `0 min` next to a valid timer would look broken.
- **Overtime over one hour is `+h:mm:ss`:** decision 12 only shows `+2:13`, so the long form reuses the countdown shape for consistency.
- **`clock` and `preview` take `Locale` and `TimeZone` parameters** that default to `.autoupdatingCurrent`, so production callers can leave them out. Reason: the acceptance criteria demand a fixed locale and fixed `now` in tests, and parameter injection is the smallest way to get it.
- **`clock` keeps the ICU output as it is:** en_US puts a narrow no-break space (U+202F), not a normal space, before `AM` or `PM`. Tests that compare clock or preview text must expect `"3:42\u{202F}PM"`. Reason: it is the system's locale-correct output, and it keeps `3:42` and `PM` on one line.
- **`countdown` rounds a part of a second up, and `overtime` rounds it down:** the countdown shows `0:00` only when the time is up, and overtime starts at `+0:00`. Negative input shows `0:00` or `+0:00`. Reason: the timer engine (TT-4) gives fractional seconds from `endDate - now`, and this is how a countdown and a count-up clock normally read.
- **Name cut counts Swift `Character`s** (grapheme clusters), and trailing whitespace before `…` is trimmed. Reason: cutting UTF-16 units could split an emoji in the menu bar, and `Some name …` with a space reads worse than `Some name…`.
- **Step 0 merges `origin/master` for the TT-1 scaffold:** this branch was cut before TT-1 merged, so it had no `Makefile`, `project.yml`, or test target. The implementation merges master first to get them.
- **SwiftLint now requires trailing commas in multi-line collection literals** (`trailing_comma: mandatory_comma: true` in `.swiftlint.yml`). Reason: SwiftFormat adds that comma, and SwiftLint's default forbids it, so the pre-commit hook blocked every multi-line array, such as the test tables in this issue.

## Out of scope found

- **Seconds-granular input (`30s`, `1m30s`)** — not in decision 7; a possible later parser extension.
- **Localized duration words** — `human` and `preview` hard-code `h`, `min`, `ends`, and `·`; only the clock time is locale-aware. Fine for a single-user English app, a follow-up if that changes.

## Verification

- `make gen test lint` — exits 0; the new `DurationParserTests` and `TimeFormattingTests` suites run and pass.
- `git log --oneline origin/master..HEAD` — shows this plan commit, the merge of `origin/master`, the lint config commit, and the implementation commits, nothing else.
- Manual check: none; this issue is pure logic with no UI. The live preview and menu bar label are verified by hand in TT-5 and TT-7.
