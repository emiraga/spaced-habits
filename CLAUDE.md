# CLAUDE.md

Spaced Habits is a native iOS + watchOS habit tracker with an adaptive, spaced-repetition-style
check-in scheduler. **`DESIGN.md` is the source of truth** for scope, architecture, and the
milestone plan. Read the relevant section before starting any task.

## Workflow

- Work directly on `main`. **No branches, no pull requests.** Commit and push when a task is done.
- Small, atomic commits. Message format: `M<n>: <what changed>` (e.g. `M1: add QuestionPlanner due rules`).
- Before every commit: `make format && make lint && make test`. Never commit red.
- Finish each milestone by verifying its checkpoint in `DESIGN.md` §13. Put the evidence
  (test output, simulation table, screenshot paths) in the commit message. Don't start the next
  milestone until the checkpoint passes.
- If a decision changes or an Apple API doesn't behave as `DESIGN.md` assumes, update
  the section of `DESIGN.md` it governs in the same commit as the code. There is no separate
  decisions log; §16 holds open questions only.

## Commands

```
make setup         # brew bundle + pre-commit install (once)
make gen           # regenerate SpacedHabits.xcodeproj from project.yml (after any target/file-structure change)
make build         # iOS simulator build via xcodebuild + xcbeautify
make test          # HabitCore via `swift test`, app targets via xcodebuild
make lint          # swiftlint --strict
make format        # swiftformat . (run this, don't hand-format)
make format-check  # what `make ci` runs
make ci            # gen + format-check + lint + test — must pass before push
```

Fast inner loop for engine work: `xcrun swift test --package-path Packages/HabitCore`.
Always use `xcrun swift`, not bare `swift`: a swiftly toolchain on `PATH` fails to build the
packages (`unknown argument: '-target-arch-variant'`). The Makefile already uses `xcrun`.

## Code rules

- `Packages/HabitCore` is pure Swift: no SwiftUI, UIKit, SwiftData, HealthKit, or WidgetKit
  imports. Inject `Clock` and `RandomSource`; never call `Date()` or `.random()` directly.
- All dates in domain logic are `DayKey` (local calendar day), never raw `Date`.
- Swift 6 language mode, strict concurrency, warnings are errors. Value types are `Sendable`;
  view models are `@MainActor`. No `@unchecked Sendable` without a justifying comment.
- No force unwraps or `try!` outside tests. No `print`; use `os.Logger`.
- New tests use Swift Testing (`import Testing`, `@Test`, `#expect`). Every `HabitCore` change
  ships with tests; the §4.8 simulations must keep passing.
- SwiftData models that sync via CloudKit: no `@Attribute(.unique)`, every property has a
  default or is optional, relationships are optional.
- `*.xcodeproj` is generated and git-ignored. Edit `project.yml`, then `make gen`.
- Don't add third-party dependencies without a one-line rationale in `DESIGN.md` §2.
- Prefer editing existing files over creating new ones; keep files under ~300 lines.

## Don't

- Don't skip or weaken a failing test to get green.
- Don't leave TODOs without a matching open question in `DESIGN.md` §16.
- Don't touch milestone N+1 features while milestone N's checkpoint is unverified.
