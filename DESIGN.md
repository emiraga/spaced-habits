# Spaced Habits — Design Document

> Working name: **Spaced Habits**. Xcode targets and identifiers use `SpacedHabits` (no space);
> user-facing strings use "Spaced Habits".
>
> Audience: the implementing engineer/agent. This document is the source of truth for scope,
> architecture, and the milestone plan. Keep it updated when decisions change.

---

## 1. Vision

Most habit trackers make you check off every habit every day, forever. That is measurement
overhead that never goes away, and it creates dependence on the app instead of on the habit.

Spaced Habits inverts this. It treats each habit check-in as a **measurement**, not a ritual, and uses an
adaptive scheduler (in the spirit of spaced-repetition software) to ask about a habit **only as
often as needed to stay confident about it**:

- A habit you keep consistently gets asked about less and less often (every week or two).
- A habit you struggle with gets asked about daily.
- When a question does arrive after a gap, it covers the whole gap ("how many of the last 5 days?"),
  and the app fills in the intervening days from that answer.
- Habits that depend on other habits (protein shake after gym) are only asked about when the
  parent habit is actually happening.
- Pauses ("delay 10 days") and vacation mode let life happen without corrupting the data.

The user-facing promise: **the better you do, the less the app bothers you.** The fading ask
interval is itself the progress metric.

### 1.1 Principles

1. **Honest data.** Every habit-day records *how* we know its value (observed, aggregated,
   inferred, from Health, paused, blocked). Charts and exports never hide this.
2. **Minimum questions.** A hard per-session budget. If the app asks more than ~3 things when
   opened, something is wrong.
3. **Native and fast.** SwiftUI, SwiftData, WidgetKit, Swift Charts. No web views, no cross-platform
   runtime. Cold launch to first question in well under a second.
4. **Offline-first, sync second.** Everything works with no network. CloudKit reconciles later.
5. **Logic is pure and tested.** The scheduler, interpolation, dependency gating, and pause logic
   live in a platform-agnostic Swift package with an injectable clock and RNG, and are
   exhaustively unit-tested and simulation-tested before any UI touches them.
6. **User owns the data.** Full CSV and JSON export at any time; JSON re-import round-trips.

### 1.2 Non-goals (v1)

- Android, web, macOS (Catalyst/Designed-for-iPad is fine if it comes free).
- Social features, sharing, leaderboards, gamification/XP.
- Quantity habits ("drink 2L water") — the model is built to allow this later, but v1 habits are
  boolean per day.
- Multiple check-ins per day for one habit.
- AI/LLM features.
- Server backend of our own. CloudKit only.
- HealthKit integration (§9). Deferred as optional post-v1 work because it needs the Health
  entitlement and user permission; see O7.

---

## 2. Platforms and tech stack

| Concern | Choice | Notes |
|---|---|---|
| Language | Swift, **Swift 6 language mode**, strict concurrency | Warnings as errors |
| Min deployment | iOS 17 / watchOS 10 | Raise if a required API needs it; document why |
| Xcode | 27.0 | Pinned in `.xcode-version`; `make` calls `xcrun swift` so SwiftPM uses this toolchain, not whatever `swift` is first on `PATH` |
| UI | SwiftUI everywhere | UIKit only for wrapped edge cases |
| Persistence | SwiftData in an App Group container | Shared by app + widget extension |
| Sync | SwiftData + CloudKit private database | Plus WatchConnectivity for low-latency phone↔watch |
| Widgets | WidgetKit + App Intents (interactive) | Home, Lock Screen, StandBy, watch Smart Stack |
| Notifications | UserNotifications with action categories | Answer from the notification |
| Health | HealthKit (read-only) | Auto-answer physical habits. **Deferred, optional post-v1** (§9, O7) |
| Charts | Swift Charts | |
| Tests | **Swift Testing** (`import Testing`) for new code; XCTest only where required (UI tests) | |
| Project generation | **XcodeGen** (`project.yml`) | `.xcodeproj` is generated and git-ignored |
| Formatting | **SwiftFormat** (`.swiftformat`) | Run on save + pre-commit + `make ci` check |
| Linting | **SwiftLint** (`.swiftlint.yml`) | `--strict` |
| Build output | **xcbeautify** | |
| Editor LSP | **xcode-build-server** | `make gen` writes a git-ignored `buildServer.json` for the `SpacedHabits` scheme (must re-run after every `xcodegen generate`); run `make build` once, then reload the editor |
| Tool pinning | `Brewfile` (+ optional `mise`) | Everyone builds with the same tool versions |
| Task runner | `Makefile` | `make gen / build / test / lint / format / ci` |
| CI | None hosted; `make ci` locally | Run before every push. GitHub's macOS runners lacked Xcode 27 at M0 |
| Git hooks | `pre-commit` (or `lefthook`) | format + lint on staged files |
| Privacy | `PrivacyInfo.xcprivacy` in each of the four bundles | No tracking, no collected data types (habits stay on device and in the user's own iCloud). Required-reason APIs: `UserDefaults` only — `CA92.1` (app's own defaults, iPhone app) and `1C8F.1` (App Group suite, every bundle). `LaunchMetrics`' `sysctl` reads this process's start time, not boot time |
| Export compliance | `ITSAppUsesNonExemptEncryption = NO` | Only Apple's HTTPS/CloudKit transport encryption, which is exempt |

### 2.1 Module layout

```
SpacedHabits/
├── project.yml                 # XcodeGen spec
├── Makefile
├── Brewfile
├── .swiftformat
├── .swiftlint.yml
├── .xcode-version
├── DESIGN.md                   # this file
├── Packages/
│   ├── HabitCore/              # PURE logic. No SwiftUI/UIKit/SwiftData imports. Fully tested.
│   │   ├── Sources/HabitCore/
│   │   │   ├── Model/          # Habit, Question, Events, DayRecord, Settings, Truth
│   │   │   ├── Scheduler/      # AdherenceModel, QuestionPlanner, SpotCheck, Dependencies, Pauses
│   │   │   ├── Projection/     # Truth -> DayRecords + SchedulerState (materialization)
│   │   │   ├── Insights/       # §12 chart data: AdherenceFilter, HabitInsights, Overview, ClusterInsights
│   │   │   ├── Export/         # CSV/JSON encoders, schema versioning
│   │   │   └── Support/        # DayKey, DayCalendar, Clock, RandomSource
│   │   ├── Sources/HabitSimulation/  # §4.8 synthetic users + day-by-day driver, LargeFixture (not shipped)
│   │   ├── Sources/simulate/   # `swift run simulate <scenario> [--end day] [--json]`: 180-day table or Truth fixture
│   │   └── Tests/HabitCoreTests/
│   │       ├── Unit/
│   │       └── Simulation/     # §4.8 acceptance tests
│   ├── HabitStore/             # SwiftData models + CloudKit config + mapping to HabitCore types
│   └── HabitUI/                # AppModel (session, answers, edits; shared with watch/widgets later) + SwiftUI components (cards, glyphs); Charts/ (§12)
├── Apps/
│   ├── iOS/                    # Spaced Habits (iOS app target) + Assets.xcassets
│   ├── iOSTests/               # app-hosted unit tests (Swift Testing)
│   ├── iOSUITests/             # XCUITest smoke flows; the app erases its data on `-resetData` (debug builds)
│   ├── iOSWidgets/             # iOS widget extension's Info.plist and entitlements
│   ├── Widgets/                # question + status widgets, compiled into both widget extensions
│   ├── Shared/                 # compiled into app and widget extension: AnswerHabitIntent, IntentModel
│   ├── watchOS/                # Spaced Habits Watch app: Today cards, habit list, habit quick view
│   ├── WatchBridge/            # WatchConnectivity (§7), compiled into the iOS and watch apps
│   └── watchOSWidgets/         # watch widget extension's Info.plist and entitlements
├── Docs/
│   ├── Brand/                  # SVG marks, App Store 1024 icon
│   └── checkpoints/            # milestone screenshots
└── Scripts/                    # simulator picker, export fixtures, etc.
```

Rule: **`HabitCore` never imports Foundation-UI, SwiftUI, SwiftData, or HealthKit.** It receives
plain values and returns plain values. This is what makes it testable and lets the scheduler be
swapped or tuned without touching the apps.

### 2.2 Tooling

The tooling files (`project.yml`, `Makefile`, `Brewfile`, `.swiftformat`, `.swiftlint.yml`,
`.pre-commit-config.yaml`, `.xcode-version`) landed in M0 and are the source of truth. Notes:

- Package manifests use `swift-tools-version: 6.2` for `.treatAllWarnings(as: .error)`
  (warnings-as-errors without `unsafeFlags`), and list `.macOS(.v14)` so `swift test` runs on the Mac.
- `make test` runs `swift test` for all three packages plus the app-hosted `SpacedHabitsTests`
  target via xcodebuild; package test targets are not in the Xcode scheme. The XCUITests
  (`SpacedHabitsUITests`, ~60 s) run only in `make test-ui`, which `make ci` includes.
- Hard 60 s cap (`TEST_TIME_LIMIT`): xcodebuild fails any single test that runs longer; each package's
  whole `swift test` run (built first, so compile time doesn't count) is killed past it by
  `Scripts/time-limit.sh`. A UI flow that is slow or flaky is deleted or moved to unit tests, not given more time.
- Bundle ID prefix `ga.emira.spacedhabits`. Info.plist is generated from build settings
  (`GENERATE_INFOPLIST_FILE` + `INFOPLIST_KEY_*`), merged with `Apps/iOS/Info.plist`, which
  `make gen` writes from `project.yml`'s `info.properties` for keys that have no `INFOPLIST_KEY_*`
  (M5: `UIBackgroundModes`, `BGTaskSchedulerPermittedIdentifiers`). Like the entitlements file it is
  generated but checked in; edit `project.yml`, not the plist.

Since M6 the app and the `SpacedHabitsWidgets` extension (`ga.emira.spacedhabits.widgets`, embedded
in the app) both carry the App Group `group.ga.emira.spacedhabits` entitlement, written by `make gen`.
`DEVELOPMENT_TEAM` is `EZ6C73TWB8`; a device build needs the group registered for both bundle IDs
under that team. The app declares the `spacedhabits` URL scheme for widget taps.

Since M7 the app also carries the iCloud entitlement (CloudKit, container `iCloud.ga.emira.spacedhabits`),
`aps-environment` and the `remote-notification` background mode for CloudKit's silent pushes. The widget
extension doesn't sync (§10), so it has no iCloud entitlement. A device build needs the container
registered under the team (Xcode → Signing & Capabilities → iCloud creates it).

`SpacedHabitsWatch` (M7) is a single-target watchOS app (`type: application`, `platform: watchOS`,
`WKApplication`, `WKCompanionAppBundleIdentifier`; not the legacy `application.watchapp2` + extension
pair), bundle ID `ga.emira.spacedhabits.watchkitapp`, embedded in the iOS app's `Watch/` folder, so the
iOS scheme builds it. It has the same App Group and iCloud entitlements as the app.

`SpacedHabitsWatchWidgets` (`ga.emira.spacedhabits.watchkitapp.widgets`, App Group only) is embedded in
the watch app and compiles the same `Apps/Widgets` sources as the iOS extension.

Localization (M11): English is the development language and the only one shipped. Every target has a
`Localizable.xcstrings` (the app, both widget extensions and the watch app in their `Apps/` folder;
`HabitUI` and `HabitCore` under `Sources/<name>/Resources`, with `defaultLocalization: "en"`). SwiftUI
literals are localized by type; a user-facing `String` built in code uses `String(localized:)`, and in a
package `String(localized: …, bundle: .module)` / `Text(…, bundle: .module)`: a package's plain
`Text("…")` would look in the app's table, not its own. `make strings` (`xcodebuild -exportLocalizations`)
syncs the catalogs with the sources; run it after changing UI text. A string it doesn't pick up is typed
`String`, not localized. English-only catalogs compile to no tables (every value is its key), so adding a
language is a translation in the catalogs, not a code change.

Still to add to `project.yml` in later milestones:
- HealthKit entitlement and `NSHealthShareUsageDescription`: "Spaced Habits reads workouts to
  auto-complete matching habits." (M8, deferred; see O7).

---

## 3. Domain model

All types live in `HabitCore` as plain `Sendable` structs/enums. `HabitStore` mirrors them as
SwiftData `@Model` classes and converts in both directions.

### 3.1 Time

Implemented in `HabitCore/Support/` (M1): `DayKey`, `DayCalendar` (day starts at
`settings.dayStartHour`, default 04:00), `Clock` and `RandomSource`. Rules that still bind new code:

- All habit data is keyed by `DayKey`, never by `Date`. Store the timezone identifier alongside
  each answer for audit purposes.
- Only `DayCalendar.dayKey(for:)` maps instants to days; nothing else may compute day boundaries.
- A habit's history starts at `Habit.createdDay`, fixed by `DayCalendar` at creation. Never
  re-derive it from `createdAt`: that would move if the time zone or day-start hour changes.
- Every scheduler entry point takes an injected `Clock`; code that needs randomness takes a
  `RandomSource` (tests and simulations use `FixedClock` / `SeededRandomSource`).

### 3.2 Source-of-truth vs projection

The store is **event-sourced-lite**:

- **Truth** (append-only, synced): `Habit` definitions, `HabitRevision`s (a snapshot after each
  edit), `Cluster`s, presented `Question`s (including dismissed ones), `Answer`s, `PauseEvent`s,
  `HealthObservation`s, `Settings`. Revisions, clusters and questions are record-keeping for history
  and export (§11); the scheduler and projection never read them.
- **Projection** (derived, rebuildable, local): `DayRecord`s and `SchedulerState`. A deterministic
  function `Projection.rebuild(events) -> (dayRecords, schedulerStates)` recomputes them.

Why: it lets the scheduler algorithm change without migrating data, makes retroactive edits and
backdated pauses trivial (just re-project), and makes CloudKit conflicts nearly impossible
(appends don't conflict). Projection must be fast enough to rebuild the whole history for
~50 habits × 3 years in well under a second on device; incremental re-projection from the
earliest changed day is an optimization for later.

### 3.3 Types

Implemented in `HabitCore/Model/` (M1) as `Sendable`, `Codable`, `Hashable` value types; the code is
the reference for fields and defaults:

- `Habit.swift`: `Habit` (+ `HabitKind`, `Importance`, `VacationBehavior`, `HealthBinding`),
  `HabitRevision`, `Dependency` / `DependencyMode` (§4.5), `Cluster`.
- `Question.swift`: `Question`, `QuestionShape` (`.singleDay` / `.perDay(days:)` / `.count(total:)`),
  `ParentContext`.
- `Events.swift`: truth events `Answer` / `AnswerValue` / `Channel`, `PauseEvent` / `PauseReason`,
  `HealthObservation`.
- `DayRecord.swift`: derived `DayRecord` (with `conditionalDenominatorExcluded`, §4.5), `DaySource`
  (`feedsModel` encodes the §4.1 weights), `SchedulerState`.
- `Settings.swift`: `Settings` (`.default` holds the tunables used throughout §4),
  `NotificationSettings`, `TimeOfDay` (not `DateComponents`: no calendar/time-zone baggage),
  `QuietHours` (half-open hours that wrap past midnight; `ClosedRange<Int>` like `22...7` traps).

Rules that still bind new code:

- Planner, projection and UI read parents via `habit.gateParentIDs`; `allParentIDs` is for
  `Dependencies.validate` only.
- Truth arriving from outside the engine (widget, watch, notification, import) goes through the
  type's `validate()` before it is stored; decoding `TimeOfDay` / `QuietHours` already validates.
- JSON uses `DayKey` strings (`yyyy-MM-dd`), including as dictionary keys (`[DayKey: Bool]` is an
  object); `ClosedRange<DayKey>` is `[lower, upper]`.

---

## 4. Scheduling engine (`HabitCore/Scheduler`)

### 4.1 Adherence model (per habit)

A Beta distribution over the probability `p` that the user does the habit on a given day.

```
prior:   alpha0 = 1, beta0 = 1
state:   alpha, beta

daily decay (applied once per elapsed calendar day, not per app open):
    alpha = alpha0 + (alpha - alpha0) * d
    beta  = beta0  + (beta  - beta0)  * d
    d = settings.decayPerDay (0.92 → half-life ≈ 8 days)

update on a day with value v ∈ [0,1] and weight w:
    alpha += v * w
    beta  += (1 - v) * w
    w = 1.0 for observed/health, 1.0 for aggregated (per day in window),
        0.0 for inferred/unknown/paused/blocked (they never feed the model)

derived:
    n    = alpha + beta
    mean = alpha / n
    var  = mean * (1 - mean) / (n + 1)
    sd   = sqrt(var)
```

Decay is what makes questions come back: as evidence ages, `n` shrinks, `sd` grows, and the
habit becomes due again. Lots of consistent yeses → large `n` → long time before `sd` crosses the
threshold. Paused days apply **no decay** (state is frozen).

Decay also pulls `mean` toward 0.5, which says nothing about the user: it is forgetting, not
evidence of struggling. So the model also keeps **`answeredMean`**: `mean` right after the latest
day that fed it, left alone by decay and moved only by new evidence (nil before any). §4.2 rule 2
compares the target against `answeredMean`, never the decayed `mean`. Without the prior's pull
toward 0.5 (a prior-free evidence ratio was tried), a 50/50 habit that answers "yes" twice looks
like a 100% habit, so the smoothed mean is what gets frozen.

**Ask interval** (`AdherenceModel.askIntervalDays`, stored as
`SchedulerState.currentIntervalDays`): the number of days, in `1...maxIntervalDays`, until decay
alone makes the habit due by §4.2 rules 1–3. It is 1 if rule 1 or 2 already holds. Decay never moves
`answeredMean`, so rule 2 holds now or never; otherwise the interval is the first day `sd` crosses
`uncertaintyThreshold` (decay only increases `sd`), capped at `maxIntervalDays`. It is the "ask
interval" in the UI and charts and the "> 7 days" test of §4.2 rule 5. An exact 50/50 habit settles
at `sd ≈ 0.13`, below threshold, so an sd-only interval would claim ~7 days while rule 2 asks it
daily; that mismatch (M1 `flaky` simulation) is why the interval includes rules 2 and 3.

**Two weeks is the design ceiling.** Decay caps evidence: daily "yes" settles at `alpha ≈ 13.5,
beta = 1, sd ≈ 0.06`, and `sd` crosses the threshold ~16 days after the last answer, whatever the
history. `maxIntervalDays = 14` makes that ceiling explicit. In practice evidence is lower (one
check-in feeds at most `maxRecallGapDays` = 7 days; the rest are inferred and feed nothing), so a
95% habit settles at a 9–12 day interval (§4.8 `steady`). Longer intervals are a non-goal.

### 4.2 When is a habit due?

`QuestionPlanner.isDue(habit, state, today) -> DueReason?`

A habit is due if **any** of:

1. `sd > settings.uncertaintyThreshold` (evidence too thin/old) — the normal path.
2. `answeredMean < habit.targetAdherence` and `lastAskedDay < today` — struggling habits get daily
   attention. `answeredMean` (§4.1), not the decayed `mean`: a habit is never "struggling" just
   because it has not been asked for a while.
3. `today - lastCoveredDay >= settings.maxIntervalDays` (default 14) — hard ceiling.
4. `state.forcedReentryCheck` — first day after a pause ends.
5. Spot check: with probability `settings.spotCheckRate`, only when the ask interval (§4.1) is > 7 days.
   Keeps the model calibrated against silent collapse. Decided **once per (habit, day)**, not per
   planner run: hash `(habit.id, today)` with a stable hash (not Swift's `Hasher`, which is
   seeded per process) to a value in `0..<1` and compare it to `spotCheckRate`. Re-opening the app,
   the widget and the watch therefore all agree, and the effective rate stays at `spotCheckRate`
   regardless of how often the planner runs.

A habit is **never** due if: it is paused today, archived, blocked by a paused parent, gated by a
failing parent (§4.5), or `lastCoveredDay == today`. `QuestionPlanner` gates dependents itself from
the projected `DayRecords` it is given (§4.5); it knows nothing about pauses: callers pass the paused
and blocked habits as `unavailable`.

### 4.3 Question construction

```
gapDays = today - lastCoveredDay            (or today - createdDay + 1 for new habits)
coverDays = min(gapDays, habit.maxRecallGapDays)   (default 7, adjustable per habit)
covers = (today - coverDays + 1) ... today
shape = coverDays == 1 ? .singleDay
      : coverDays <= 3 ? .perDay
      : .count(total: coverDays)
```

Days in the gap **before** `covers` (when `gapDays > maxRecallGapDays`) are not asked about.
They become `.inferred` with `value = mean` and `confidence = 1 - 2*sd` (clamped), or `.unknown`
if `sd` is above threshold. This is the deliberate trade-off: recall past ~a week is unreliable,
so we infer rather than collect bad self-reports.

Every question card also offers **"Don't remember"** and **"Delay N days…"** regardless of shape.

### 4.4 Session budget and prioritization

When the user opens the app / widget / watch, or a notification fires:

```
candidates = active habits where isDue != nil
score(h) = uncertainty(h) * importanceWeight(h) * staleness(h)
    uncertainty = sd (0...0.5)
    importanceWeight = 1 / 1.5 / 2 for low / normal / high
    staleness = 1 + (today - lastAskedDay) / 7
    order: forcedReentryCheck first, then below target (rule 2), then score; ties by habit ID
    (tiers rather than a score bonus: staleness is unbounded and would overtake any fixed bonus)
present top settings.sessionBudget (default 3); rest remain queued with a "More…" affordance
```

Questions are created lazily at presentation time (so a habit answered from the watch does not
leave a stale question on the phone). A `Question` that is dismissed ("Later") is discarded and
re-planned next session; it is not carried as scheduler state. Every presented question is still
appended to `Truth.questions` with `presentedAt` (and `dismissedAt` on "Later") so history and export
show what was asked; the planner never reads that log.

### 4.5 Dependencies

`habit.dependencies` is a list of `Dependency { parentID, mode }`. The parent IDs (all modes)
form a DAG; `Dependencies.validate` rejects cycles at edit time and on import.

**Edge modes.** Everything below — gating, the conditional metric, pause propagation, the
parent-context line on cards — applies to **`.gate` edges only**. `.sequence` edges exist in the
model so that habit stacking (ATOMIC_HABITS_IDEAS.md F2) needs no data migration; in v1 they are
inert: the planner, projection and UI must read parents through `habit.gateParentIDs`, never
`habit.allParentIDs`, so a `.sequence` edge (e.g. from a JSON import) changes nothing except
cycle validation. The editor creates `.gate` edges only and does not expose the mode.

**Gating** (`Scheduler/Dependencies.swift`, `Gate`). A dependent habit `B` with gate-parent `A` is
only due when, over `B`'s prospective `covers` window, `A`'s **known** done-days ≥ 1 and
`A.mean ≥ 0.5`. Otherwise asking about `B` produces noise. Only evidence counts: a parent day's value
is its record `value` if the source is observed, aggregated or health, and 0 otherwise (inferred,
unknown, missing, paused, blocked). Using inferred parent days was tried and rejected. The §4.8
dependent-pair simulation showed cards asking about `B` on days `A` never happened; truthful "no"
answers then biased `P(B|A)` from 0.80 to 0.70. So `B` waits until `A` has been answered for the
window, and follows `A`'s question schedule. Clients must build questions at presentation time
(§4.4), so a `B` card shown after `A`'s answer in the same session sees it. Multiple gate parents:
every mean ≥ 0.5 (AND), and the per-day value is the product over parents, so "done days" means
days on which all parents were done. Gate edges to archived parents are ignored (an archived
parent gets no evidence and would gate forever).

**Conditional metric.** `B`'s adherence is `P(B | A)`, not `P(B)`:

- `parentContext.parentDoneDays = round(Σ A.dayRecords[day].value for day in covers)`.
- The `count` question reads: *"You did A on 4 of 6 days. On how many of those 4 did you do B?"*
  `total` = `parentDoneDays`, not `coverDays`.
- Per-day shape: only show toggles for days where `A.value ≥ 0.5`, and only when each of those
  days is exactly known (observed or Health). If any is aggregated, the card falls back to `count`
  so the user reconciles against the days they remember. No such days: the gate is closed.
- Projection: on days where `A.value == 0` (observed), `B` gets `source = .observed, value = 0`
  with a flag `conditionalDenominatorExcluded = true` so charts can compute both `P(B)` and
  `P(B|A)`.

**Pause propagation.** If gate-parent `A` is paused on a day, `B`'s DayRecord is `.blocked` (not
`.paused`), so the user can distinguish "I paused protein" from "protein was moot because gym was
paused". Blocking is transitive (a child of a blocked habit is blocked) and a habit's own pause wins
over blocked. A paused `.sequence` parent has no effect on its children. `Pauses.unavailable(on:)`
computes both for a day; the planner takes its keys as `unavailable`.

### 4.6 Pauses and vacation

Both features are one primitive: `PauseEvent`.

- **Delay from a question card:** answer `.delayed(days: n)` → `PauseEvent(habitIDs: [h], start: today, end: today + n - 1, reason: .manual)`.
- **Backdated pause:** UI lets the user set `start` in the past ("I was sick the last 3 days").
  Re-projection converts those days from whatever they were into `.paused`.
- **Extend / end early:** edit `end`. "End now" sets `end = today - 1`, so today is active and gets
  the re-entry check; a pause that hasn't started yet is cancelled (`cancelledAt`) rather than
  deleted, since truth is append-only. Habit rows always show "Resumes <date>". Vacation pauses are
  changed from the vacation sheet, not habit detail, because they cover several habits.
- **Scheduler during pause:** no decay, no questions, state frozen. Blocked days behave the same.
- **Resume:** `forcedReentryCheck = true` → guaranteed question on the first active day. The
  question covers only days since `end + 1`, never the pause. If the answer is yes, the interval
  continues from its frozen value; if no, the normal model update handles it.
- **Vacation mode:** one `PauseEvent` with `reason: .vacation` and `habitIDs = all active habits
  where vacationBehavior == .pause`. The enable screen shows a checklist pre-filled from each
  habit's `vacationBehavior`; changes write back to the habit so the next vacation remembers.
  "Skip" uses the stored set as-is. Vacations can be scheduled in advance (`start` in the future).
- **Dependency warning on enable:** if a kept habit depends on a paused habit, offer "also keep
  parent" or "accept blocked".
- **Re-entry flood control:** many habits resuming the same day all set `forcedReentryCheck`; the
  session budget and priority ranking absorb this over a few days. Do not special-case it.
- **Silence nudge:** if no answer for `nudgeAfterSilentDays` and no pause is active, a single
  notification offers "Enable vacation mode retroactively".
- **Delay analytics:** count `PauseEvent`s with `reason == .manual` per habit; ≥ 3 in 60 days
  surfaces an insight card ("You keep delaying this. Lower the target or archive it?").

### 4.7 Projection (`HabitCore/Projection`)

`Projection.rebuild(truth, clock) -> Projected` (`Projection/Projection.swift`). `Truth`
(`Model/Truth.swift`) bundles habits, clusters, habit revisions, questions, answers, pauses, health
observations and settings, and is validated first (including that every reference names a known
habit or cluster). Projection ignores clusters, revisions and questions. Habits are projected in
topological order so parents' records exist when their children are projected.

1. For each habit, for each day from `createdDay` to `today`:
   - if inside a pause for this habit → `.paused`; else if a gate parent is paused or blocked → `.blocked`
     (both: value 0, confidence 0)
   - else if a HealthObservation matches → `.health`, value 1
   - else if an Answer covers the day → `.observed` (singleDay/perDay) or `.aggregated` (count). When
     answers overlap, the latest `answeredAt` wins (ties by answer ID)
   - else if `.dontRemember` covers it → `.unknown` (value = model mean, confidence 0)
   - else if a gate parent is `.observed` with value 0 → `.observed` value 0 with
     `conditionalDenominatorExcluded` (§4.5)
   - else → `.inferred` or `.unknown` per §4.3, from the model state after that day's decay
2. Replay the adherence model chronologically, applying decay per elapsed non-paused, non-blocked
   day and updates per observed/aggregated/health day (excluded days add nothing: the model is
   P(child | parents)), to obtain `SchedulerState` as of today. Also emit a `ModelPoint` series of
   `(day, mean, sd, intervalDays)` for the "ask interval over time" chart.
   - `lastCoveredDay`: latest of answer `covers.upperBound` (not `.delayed`), health days, and
     paused/blocked days. Counting a pause as covered is what keeps questions out of it.
   - `lastAskedDay`: latest `covers.upperBound` of any answer. A question's `covers` always end on the
     day it was asked, so no `Date` → day mapping is needed.
   - `forcedReentryCheck`: set on the first available day after a paused/blocked stretch unless an
     answer's `covers` end on or after that day.
3. Output is deterministic; the same inputs must produce byte-identical output (tests assert this).
   `Projected` encodes its habit-keyed maps as objects keyed by UUID string for this reason.

Aggregated answers are spread evenly (`value = done / total` on each day of `covers`; for a gated
habit, on each parent-done day). Placing them on "likely" days would invent data.

Performance: 50 habits × 3 years (answers every 3 days) rebuilds in 0.11 s in a release build on an
M-series Mac (0.37 s debug).

### 4.8 Simulation test harness

`Sources/HabitSimulation` drives synthetic users through the real planner and projection for 180
days with a seeded RNG. Habit IDs are seeded too, because spot checks hash them. Each day it answers
up to `sessionBudget` questions truthfully and re-plans after each answer, as the app does.
`Tests/HabitCoreTests/Simulation/` asserts, and `swift run simulate <scenario>` prints the day table:

- `steady` (p 0.95) → from week 4 on, every 4-week window averages < 1.5 questions/week. Over
  inferred days, |mean inferred value − true rate| < 0.15. Per-day error can't meet that bound: a
  miss is 0 against an inferred ~0.85. Seed 42: asked every 9–12 days, all by rule 1 after the first
  week (none tagged `belowTarget`).
- `flaky` (p 0.5) → asked on ≥ 80% of days, and never unasked for more than `maxIntervalDays`.
  Not "every week": a long lucky streak lifts `answeredMean` above target and legitimately earns a
  break until the next check-in. Seed 42: 170/180 days; a 14-day "yes" run (days 133–146) earned
  a 10-day break, then 2 of 7 put it back on daily questions.
- `collapsing` (p 0.95 for 60 days, then 0.1) → the end-of-day mean the engine actually held (not
  the retrospective projection) drops below target within 10 days. Seed 42: day 62. Detection
  waits for the next check-in, so it can take up to the ask interval (≤ 14 days) in general.
- `vacation` (p 0.9, paused days 60–73) → no questions during the pause, frozen mean/sd across it,
  exactly one `.reentry` question (day 74) covering only that day.
- `dependent-pair` (A 0.9, B|A 0.8) → every B question has parent context and a window in which A
  truly happened. `P(B|A)` estimated from B's non-excluded evidence days 0–59 is within 0.1 of 0.8.
  Seed 42: 0.784; 0.805 over 180 days.

These are the acceptance tests for the engine. They must pass before UI work begins (Milestone 1).

`simulate <scenario> --json` prints the run as a §11 JSON export instead of the table (with the creation
revision the app stores for each habit), and `--end yyyy-MM-dd` moves the run to end on that day. Settings →
Import reads it; a debug build launched with `-importFixture <path>` imports it through the same
`AppModel.importJSON` (the simulator app reads host paths), and `-exportData <folder>` writes `export.json`
and `export-csv.zip` there. Pass the app's current day as `--end`: before `dayStartHour` that is still
yesterday.

---

## 5. User interface (iOS)

### 5.1 Screens

0. **Onboarding** (M11; first launch on a device with no habits, so iCloud or an import skips it; a
   `UserDefaults` flag, not synced). Three pages moved by buttons only (no swipe, no transition): the idea
   with three points; "Add your first habit" (name field and suggestion chips, whose emoji is kept unless
   the name is edited; Skip); notifications (Allow → system prompt, or Not now). Then Today.
1. **Today** (root). A stack of question cards (≤ session budget), then a compact list of all
   active habits with today's status glyph (✓ observed done, ✗ observed not done, ♥ Health,
   ◐ aggregated, ≈ inferred, ? unknown, ⏸ paused, ⛔ blocked), grouped by cluster (clusters by name,
   then "Other"; one "Habits" group without clusters). Until today is answered its record is
   only the model's guess, so the list shows ○ due or · not due instead (`DayStatus.today`); history
   rows show ≈ / ? for such days. Aggregated (answered as a count) and inferred (no answer; filled in
   by the model) never share a glyph (§1.1). Pull-to-refresh replans. Empty state: "Nothing to ask.
   Next check-in: <habit>, <day>." (the day may read "Tomorrow", so no "on"; `QuestionPlanner.nextCheckIn`:
   today + ask interval, capped by `maxIntervalDays` since the last covered day).
2. **Habit detail.** Header with current ask interval ("Asking every ~9 days"), adherence 30d (for a
   gated habit both `P(B|A)` "On Gym days" and `P(B)` "All days"), Resumes-on banner if paused (a
   blocked banner if a parent is), charts (§10), history calendar, dependency list (cluster, depends on,
   needed by), edit button.
3. **Habit editor.** Name, emoji, color, importance, target adherence and max recall gap (both in a
   collapsed "Advanced" group, each with a plain-language explanation), vacation
   behavior, depends-on picker (with cycle rejection), cluster, Health binding, archive. The picker
   lists every other active habit; a pick that would close a loop (`Dependencies.cycle(ifAdding:)`) is
   refused on the spot with the loop spelled out ("Gym would need Protein, which needs Gym"), and
   `AppModel.save` maps a `validate` cycle to the same message. Clusters are created and renamed from
   the editor (name, color); v1 has no cluster deletion, since an empty cluster simply isn't listed.
4. **Pause sheet.** Presented from a question card ("Delay…") or habit detail. Duration presets
   (1, 3, 7, 14 days, custom), start date (default today; can be backdated or scheduled; from habit
   detail only, since a card delay always starts today), reason.
5. **Vacation sheet.** Start/end dates, checklist of habits (pre-checked = `.keep`), "Also keep
   parents" resolver, "Quiet all notifications" toggle. Persisting checklist changes to
   `vacationBehavior` is on by default with a visible toggle.
6. **Insights.** Overall charts + insight cards (delayed-often, regressions, autonomy score).
7. **Settings.** Notifications cadence, quiet hours, session budget, day start hour, spot check
   rate (advanced), export/import, Health permissions, iCloud status, About (version, Help & Support and
   Privacy Policy links to `emira.ga/spaced-habits/{support,privacy}`, text in MARKETING.md), debug
   (rebuild projection).

### 5.2 Question card

```
┌──────────────────────────────────────┐
│ 🏋️ Gym                    high · ~6d │
│ Did you go to the gym today?          │
│ [   Yes   ] [   No   ]                │
│ Don't remember · Delay… · Later       │
└──────────────────────────────────────┘
```

- `.perDay`: one row per day with a toggle; days pre-set to the model's guess if `mean ≥ 0.8`,
  otherwise off; the user confirms with one tap.
- `.count`: stepper `N of K` with quick chips *None / Some / Most / All* mapping to
  0 / round(0.35K) / round(0.75K) / K.
- Dependent habits show the parent context line ("You did Gym on 4 of 6 days").
- Answering animates the card away and immediately shows the next one. Haptic on answer.
- Cards must be answerable one-handed; primary actions ≥ 44pt tall.

### 5.3 Performance targets

- Cold launch → first card interactive: < 400 ms on a 3-year-old iPhone. Projection runs
  incrementally (only days since last projected day) in the common case.
- Answering a card → UI update: synchronous on main actor from in-memory state; persistence
  happens after.
- No spinners on the Today screen ever; if projection is stale, show last known and update.

---

## 6. Widgets (iOS + watchOS)

- **Question widget** (`QuestionWidget`: small, medium, Lock Screen rectangular; StandBy shows the
  small one): the session's top question with Yes/No buttons via `Button(intent:)`; medium shows the
  top two. Per-day and count questions need the card's toggles or stepper, so the widget says "Open to
  answer" and a tap opens Today. After answering, WidgetKit reloads the timeline and the widget shows
  the next question. With nothing due: "Nothing to ask" and the next check-in.
- **Status widget** (`StatusWidget`: small, medium, Lock Screen circular "N due" and inline): habits
  with today's glyphs; a row deep-links to habit detail (`DeepLink`: `spacedhabits://habit/<id>`,
  `spacedhabits://today`).
- App Intents: `AnswerHabitIntent(habitID, done)` for the widget buttons (not discoverable in
  Shortcuts; `Apps/Shared`, so it runs in the widget extension), and in the app only
  `LogHabitIntent(habit, done = true)`, `DelayHabitIntent(habit, days)` (a pause from today) and
  `ReviewHabitsIntent()` (opens Today), with `HabitEntity` / `HabitQuery` over active habits. Questions
  are planned lazily and widgets don't log them (below), so a button carries the habit, not a question
  ID. App Shortcuts: "Log \(habit) in Spaced Habits", "Delay \(habit) in …", "Review habits in …".
  The app calls `updateAppShortcutParameters()` at launch and on entering the background so new habit
  names are matched.
- Intents run on `IntentModel.open()`: the app's live model when they run in the app (the app sets
  `IntentModel.live` at launch), otherwise a fresh non-logging model on the App Group store (the
  widget extension). The app reloads all timelines on every `AppModel.onRefresh`.
- An answer from a widget doesn't reschedule notifications (planning is too heavy for the
  extension); that happens on the next app open or background refresh, and a notification planned
  before the answer is refused as `alreadyCovered` if acted on.
- Widgets read/write the **shared App Group SwiftData store**. Widget writes append an `Answer`
  and call `WidgetCenter.reloadAllTimelines()`; the app re-reads truth (`AppModel.reload`) when it
  returns from the background. A fresh `TruthStore.load()` sees the other process's rows, so no
  persistent-history tracking is needed. The debug day offset lives in the App Group's defaults so
  widgets plan the same day as the app.
- Widgets and intents plan with `AppModel(logsPresentedQuestions: false)`: a timeline is speculative,
  so it doesn't log to `Truth.questions`. A Yes / No from a widget or Siri is
  `AppModel.answerToday(habitID, done:, channel:)`, which logs a single-day question presented at the
  tap. Like a notification action (§8) it goes through `checkAnswerable` and throws `AnswerRefusal`
  if the habit is archived, paused or blocked today, or today is already covered.
  Siri and Shortcuts answers use `Channel.shortcut`.
- Timeline: one entry now + one at the next day boundary (`WidgetTimeline`). Within a day the plan
  only changes when truth does, and every writer reloads the timelines then, so the notification
  times add nothing.
- watchOS: the same widget sources (`Apps/Widgets`) in `SpacedHabitsWatchWidgets`, reading the watch's
  own App Group store: the question widget as the Smart Stack card (`.accessoryRectangular`, Yes / No via
  `AnswerHabitIntent`: `Button(intent:)` is available in watchOS widgets), and the status widget as
  complications (`.accessoryCircular` "N due" or a checkmark, `.accessoryInline`). The watch app reloads
  them on every `AppModel.onRefresh`.

---

## 7. Watch app

- Thin SwiftUI app using `HabitUI` cards (`AppModel.card(for:)`, shared with the phone; the card's footer
  stacks where a row doesn't fit). Screens, as vertical pages: Today (cards; "Delay…" offers 1, 3, 7 or
  14 days, while backdating and vacations stay on the phone) and the habit list, which opens a quick view:
  a 7-day glyph strip (`AppModel.recentStatuses`: glyphs rather than a sparkline, so the source of each
  day stays visible, §1.1), the ask interval and the next check-in. No editor, no charts. With no habits,
  Today says to add them on the iPhone.
- Data: own SwiftData store with the same CloudKit container (truth), **plus** `WatchConnectivity`
  for immediacy. Both sides send every local write as `TruthChange`s (kind, UUID, `HabitCore` JSON,
  `updatedAt`; `TruthStore.onChange`, reported once per save with all its changes, so an import of thousands
of records is chunked rather than sent one message each): by `sendMessage` (50 per message, under
  the ~64 KB limit) while the other device is reachable, else by `transferUserInfo`, which queues while
  it's unreachable and is also the fallback when a message fails. (Simulators deliver messages but not
  user-info or file transfers, so only the message path can be checked there.) The `WatchBridge` hooks the
  store before `AppModel` is created, so the first session's logged questions are sent too.
  The receiver calls `AppModel.merge`: latest `updatedAt` wins
  per `(kind, id)`, each value is validated like a local write, merged changes aren't echoed back, and
  a change delivered twice (WatchConnectivity and CloudKit) is stored once. The watch plans its own
  session with the same `AppModel` (`channel: .watch`) rather than receiving the phone's plan: the plan
  is a function of truth, so sending truth keeps one code path and works standalone. A card whose open
  question (logged, not dismissed, not answered) arrived from the phone reuses that question instead of
  logging another (§11), so phone and watch show one question per card. A watch with an
  empty store asks the phone for `TruthStore.allChanges()` on activation and whenever the phone becomes
  reachable, instead of waiting for CloudKit; the phone replies by messages if reachable, else as a file.
- Runs standalone if the phone is unreachable; CloudKit catches up later.

---

## 8. Notifications

- Categories with actions: `HABIT_QUESTION` → *Yes*, *No*, *Later*. Actions are handled in
  `UNUserNotificationCenterDelegate` (app launches in background) and append an `Answer`. The
  conformance is `@MainActor`: with `nonisolated async` methods the completion handler ran on the
  cooperative pool and UIKit aborted on every tap.
  Only `.singleDay` questions get the category; per-day and count questions need the card, so a tap
  opens the app. `Notifier` (app target) is created in `App.init` so it is the delegate before a
  background launch finishes. The notification carries its `Question` as JSON;
  `AppModel.respond(to:deliveredAt:with:)` logs it as presented at delivery, then records the answer
  (channel `.notification`) or the "Later" dismissal. It refuses a notification whose days were
  covered since (answered in the app, or paused): answers are latest-wins (§4.7), so a stale tap
  would silently override a newer answer. On app open, delivered notifications' questions are logged
  to `Truth.questions` and cleared, since the cards supersede them.
- Scheduling: local notifications computed from `NotificationSettings.cadence`, clipped by quiet
  hours, and only scheduled when `onlyWhenQuestionsDue` finds ≥ 1 due habit at that time
  (re-evaluated on each app foreground and via `BGAppRefreshTask`).
  `HabitCore` `NotificationPlanner.plan(truth, calendar, now)` (pure) decides it; the app replaces
  every pending request with its output. A slot's content is what the app would plan at that instant
  if nothing were answered first: `Projection.rebuild` and the session planner run with a clock at the
  slot (cached per day), so decay, pauses, gates and spot checks all apply and the first notification
  lands on the Today screen's "Next check-in" day. It plans 7 days ahead (longer for
  `.everyNDays(n)` with n > 7), at most 60 requests (iOS keeps 64). `.everyNDays(n)` fires on every
  n-th day since the last answer (before any, since the first habit's `createdDay`), so it means "if I
  haven't checked in for n days". A time before `dayStartHour` belongs to the previous habit day.
- Content: the top-priority question text, so the user can answer without opening anything.
  Group multiple due habits into one notification ("3 habits to review") when > 1.
- Silence nudge (§4.6) and vacation-quiet toggle both live here. The nudge replaces the first
  slot on day `lastActiveDay + nudgeAfterSilentDays` (any cadence time, even off an `.everyNDays`
  day) unless a pause is active then; once that day has passed it is not re-sent. A vacation with
  "Quiet all notifications" silences every slot on its days, kept habits included.
- Never notify about a paused or blocked habit.

---

## 9. HealthKit

**Deferred (optional, post-v1).** The domain side (`HealthBinding`, `HealthObservation`, the
`.health` day source in projection) already exists in `HabitCore`; the HealthKit integration below
(entitlement, permission flow, queries, binding editor) is not built. Until it is, the editor shows no
Health binding and Settings shows no Health permissions row. See O7.

- Optional per habit. `HealthBinding` cases: `.workout(minMinutes:)`, `.steps(min:)`,
  `.sleep(minHours:)`, `.mindfulMinutes(min:)`. Read-only.
- A background `HKObserverQuery` (and a foreground fetch) turns matching samples into
  `HealthObservation(habitID, day, sampleID)` truth events. Projection marks those days
  `.health`, value 1, weight 1. The habit is then not asked about for that day.
- A Health-bound habit can still be asked about days with no sample (the user may have trained
  without logging); the answer overrides nothing — Health and Answer are both truth, and
  projection prefers Health when present, Answer otherwise.

---

## 10. Sync (CloudKit) and store constraints

- `ModelContainer` with `ModelConfiguration(groupContainer: .identifier("group.…"), cloudKitDatabase: .private("iCloud.…"))`
  in the app and the watch app (`StoreLocation.appGroup(syncs: true)`). The widget extension opens the
  same file with `cloudKitDatabase: .none`: SwiftData always records persistent history (the store has
  `ATRANSACTION`/`ACHANGE` tables even without CloudKit), so the app's mirror exports the extension's
  writes on its next run, and a widget timeline doesn't start a sync engine. Without an iCloud account
  setup fails with `134400` and everything keeps working locally.
- CloudKit-backed SwiftData constraints (enforce in `HabitStore`):
  - no `@Attribute(.unique)`; uniqueness is by UUID handled in code
  - every property has a default or is optional; every relationship is optional
  - no relationships at all. `HabitStore` (M2) has one `@Model`, `TruthRecord { kind, id, payload,
    updatedAt }`: every truth value is stored as its `HabitCore` JSON, so `dependencies` and the enums
    with associated values (`AnswerValue`, `QuestionShape`, `PauseReason`, `HealthBinding`) are never
    SwiftData composite attributes, which mishandle such enums. One table also avoids eight identical
    `@Model` classes (no shared base class on iOS 17). `TruthStore` upserts by `(kind, id)`; if sync
    ever yields duplicate rows, `load()` keeps the latest `updatedAt`. CloudKit imports (and watch
    messages) arrive in no particular order, so an answer can land before its habit, or a habit before
    its cluster or parent: `load()` holds back every value naming a record that hasn't arrived
    (`Truth.withoutPendingReferences`, cascading to children) instead of failing validation, and
    shows it once the reference resolves. Settings are one record under a
    fixed ID. `TruthStoreTests` checks the schema against these rules by reflection and that a
    `.sequence` edge round-trips unchanged.
- Conflict policy: truth tables are append-only; edits to `Habit`, `Cluster`, `PauseEvent` and a
  `Question`'s `dismissedAt` are last-writer-wins per record, which is acceptable for single-user data. Projections are never
  synced.
- `HabitStore` `SyncMonitor` observes `NSPersistentCloudKitContainer.eventChangedNotification` (SwiftData
  posts it). After each successful import the app calls `AppModel.reload(newSession: false)`: truth is
  re-read and fully re-projected (projection is always a full rebuild, §4.7), and `onRefresh` reloads
  widgets and notifications. It isn't a new session, so "Later" cards stay hidden.
- Settings → Sync shows the iCloud account state, the last successful merge and the last sync error;
  a debug button re-reads and re-projects everything.

---

## 11. Export / import

- **CSV** (zip of several files): `days.csv` (habit_id, habit_name, day, value, source,
  confidence, conditional_denominator_excluded, question_id), `habits.csv`, `habit_revisions.csv`
  (revision_id, habit_id, edited_at, then the habit's columns), `answers.csv`, `questions.csv`
  (including dismissed ones, with presented_at and dismissed_at), `pauses.csv` (with reason),
  `clusters.csv`, `dependencies.csv` (habit_id, parent_id, mode), `health_observations.csv`.
- **JSON**: one document `{ schemaVersion, exportedAt, settings, habits, habitRevisions, clusters,
  answers, questions, pauses, healthObservations }`, i.e. the full `Truth` (§4.7). Each habit carries
  `"dependencies": [{ "parentID": "...", "mode": "gate" }]`. This is the complete truth set;
  `DayRecord`s are omitted because they are derived (an optional `includeProjection` flag adds them).
- **Import** (JSON only): merge by UUID, never delete, re-validate the dependency DAG (reject the
  whole import on a cycle), then re-project. Unknown `mode` values fail the import with a clear
  error rather than being coerced. Used for backup/restore and for moving between test devices.
- Delivered via `ShareLink` / Files. All encoders live in `HabitCore/Export` and are unit-tested
  against golden fixtures; `schemaVersion` bumps require a migration note in this document.

Implemented in M10 (`schemaVersion = 1`, no migrations yet):
- `HabitCore/Export`: `DataExport` (a `Sendable` snapshot of truth and projection; the share sheet encodes it off
  the main actor), `ExportDocument` + `ExportCodec` (JSON), `CSVColumns` (the CSV columns, the reference for
  their names and value formats), `ZipArchive` (stored entries, fixed timestamps: same files, same bytes; no
  dependency), `TruthImport` (the merge). Golden files: `Tests/HabitCoreTests/Fixtures/Export`, rewritten by
  `RECORD_GOLDENS=1 swift test` (which then fails, so a recording run never passes).
- Dates are UTC ISO 8601 with milliseconds (`2026-09-27T12:00:00.000Z`), in JSON and CSV. Export rounds to the
  millisecond, and a parsed date formats back to itself. JSON keys are sorted, and each collection is in a
  canonical order that doesn't depend on store write order (habits and questions by creation, revisions by edit,
  answers by answer time, pauses by creation, clusters by name, Health observations by day, ties by ID; times
  compared at export precision). Together these make export → import → export byte-identical apart from
  `exportedAt`. Enums with associated values use Swift's synthesized coding, the store's own format
  (`{"count":{"done":2,"total":3}}`).
- The export holds the loaded truth, so it leaves out records held back for a missing reference (§10).
- CSV: RFC 4180 quoting, `\n` line ends, UTF-8, `;` between list items inside a field. `days.csv` has one row
  per habit per day from `createdDay` through today (the projection's records), each with a `source`.
  `answers.csv` splits the value into `value, done, total, per_day, delay_days`, `questions.csv` splits the
  shape into `shape, days, total`, `pauses.csv` has `reason, reason_text`, and `habit_revisions.csv` ends
  with the snapshot's `dependencies` (`parentID:mode;…`).
- Import (`AppModel.importJSON`, Settings → Your data → Import JSON…): the schema version must be 1, and a
  value that doesn't decode fails with its path (`habits[3].dependencies[0].mode: … chain`). Only the merged
  truth is validated, so a file may reference local records. A cycle names its habits, like an edit does.
  An imported record that is new, or differs from the local one with its ID, is written as it is (no new
  revision) in one save, stamped with the import time, so on other devices the import wins as an edit
  would. Imported settings replace local ones when they differ. Both sides compare at export precision,
  so importing a device's own export writes nothing. The app then reloads, which starts a new session.
- Re-exports stay stable because a planned card reuses the latest logged question for that habit asking the same
  thing that was neither dismissed nor answered (`AppModel.reusableQuestion`). Otherwise the session after an
  import, a relaunch, or the watch receiving the phone's question would log a duplicate. A card shown again
  after "Later" is still a new question (§12).

---

## 12. Charts (`HabitUI/Charts`, Swift Charts)

Per habit:
- **Ask interval over time** — line; the signature chart. Rising = becoming automatic.
- Calendar heatmap — cell fill by value, dotted outline for aggregated, hatched for inferred, gray
  for paused, striped for blocked, hollow for unknown. Aggregated and inferred always look different.
- Rolling 7- and 30-day adherence — line, with a horizontal target line.
- Model confidence — area of `mean ± sd`.
- Delays count / paused days (small stat tiles).

Per cluster:
- Stacked adherence per member; `P(B|A)` vs `P(B)` for dependent pairs; funnel A → B → C.

Overall:
- Questions per day (burden), 90-day line — should trend down.
- Autonomy score = mean ask interval across active habits.
- Regressions: habits whose 14-day mean dropped ≥ 0.2 vs prior 30 days.
- Day-of-week adherence heatmap across all habits.
- Vacation/pause bands overlaid on every timeline. Toggle "include paused days" (default off).

Every chart has a data-source legend. Do not show a chart if fewer than 7 non-paused days exist.

Implemented in M9. Data is computed in `HabitCore/Insights` (pure, tested), drawn by `HabitUI/Charts`:
- **Adherence counts evidence only** (`AdherenceFilter`): observed, aggregated and Health days. Inferred and
  unknown days never count. For a gated habit the default is `P(B|A)`; `includingParentMisses` gives `P(B)`.
  "Include paused days" (stored in `@AppStorage`, shared by Insights and habit detail) makes paused and blocked
  days count as not done; off, they are left out and shown only as bands. Rolling lines break across windows
  with nothing to count instead of bridging them.
- **Questions per day** counts distinct (habit, day) pairs across logged questions and answers
  (`covers.upperBound`): widget and Siri answers log no question, and a card shown again after "Later" logs a
  second one. Vacation pauses are the bands on this chart; per-habit timelines band that habit's paused and
  blocked days.
- **Regressions** need ≥ 3 counted days in both windows. The **funnel** runs along the cluster's longest gate
  chain over the last 30 days that have evidence for every member; aggregated days add their fraction.
  **Stacked adherence** is per member per 7-day week, 12 weeks. The day-of-week heatmap is habits × weekdays
  plus an "All habits" row.
- The **calendar heatmap** is a `Canvas`, not Swift Charts: hatching, stripes and dotted outlines are paths
  there. It shows the last 26 weeks; one `HeatmapCell.draw` renders both cells and legend.
- Chart x values are noon UTC on the civil date, labeled in UTC (`ChartDay`), like `DayFormat`.
- Insight cards: regressions, then delayed-often (`Pauses.frequentlyDelayedHabitIDs` rule), then autonomy.
- Insights is a lazy `List`: every section's data is computed on open, charts draw as they scroll in.

---

## 13. Implementation plan

Each milestone ends with a **checkpoint**: something you can run, tap, or inspect. Do not start
the next milestone until the checkpoint passes and `make ci` is green. Milestones are ordered
so that a usable app exists from M2 onward and every later milestone adds a feature to a working
build.

### M0 — Scaffold — done (2026-09-27)

### M1 — Engine — done (2026-09-27)

`Support/`, `Model/` (§3.3), `Scheduler/` (§4.1–4.6), `Projection/` (§4.7) and the simulation
harness with the `simulate` executable (§4.8). Checkpoint evidence is in the final M1 commit.

### M2 — Daily driver, single device — done (2026-09-27)

`HabitStore` (one `TruthRecord` model in the App Group container, §10), `HabitUI` `AppModel` and
cards, Today / habit detail / editor / Settings screens, debug "Advance one day" and seed data.
`AppModelTests.checkpointEightDays` drives the §4.8 `steady` day 1–8 expectations, including the count
card after a gap; `TodayFlowUITests` covers relaunch persistence (screenshots `Docs/checkpoints/m2-*.png`).
The count-card XCUITest was dropped as a duplicate: it cost ~18 s. UI tests launch with
`-disableAnimations` (debug builds) so sheets don't hold up every tap. Physical
iPhone 16 Pro: "yes" habits fade, "no" habits are asked daily, a 4+ day gap gives a count card, and
answers survive kill and relaunch. `LaunchMetrics` cold launch on that device: 80–82 ms from process
start (3 runs). Launch it with `xcrun devicectl device process launch --console --terminate-existing
--environment-variables '{"OS_ACTIVITY_DT_MODE":"1"}'` to see the log line.

### M3 — Pauses and vacation — done (2026-09-27)

Pause sheet (card "Delay…" and habit detail, backdated or scheduled), Resumes-on label and
extend / end now in detail, Vacation sheet (checklist from `vacationBehavior`, remember toggle,
"Also keep parents", quiet toggle, scheduled start) with a Today banner, re-entry check,
`Pauses.frequentlyDelayedHabitIDs` (its card is on the Insights screen since M9). The three checkpoints (delay 3 days, backdate
over answered days, vacation with one kept habit remembered) are `HabitUI` `PauseTests.checkpoint*`,
driven through `AppModel` and "Advance one day". They're not XCUITests because those took ~20 s per
advanced day and hung the simulator.

### M4 — Dependencies and clusters — done (2026-09-27)

Gating, `.blocked` and `P(B|A)` landed in the M1 engine; M4 added the editor's depends-on picker and
cluster editor, the card's parent context line ("You did Gym on 4 of the last 6 days." / "On how many of
those 4?"), the detail dependency list with `P(B|A)` and `P(B)`, and the cluster-grouped Today list.
The checkpoints are `HabitUI` `DependencyTests.checkpoint*` (through `AppModel` and "Advance one day"),
`HabitCore` `SequenceEdgeTests`, and `DependencyFlowUITests` for the picker, the gated card and the
refused loop (screenshots `Docs/checkpoints/m4-*.png`).

Deliver: depends-on picker with cycle rejection (creates `.gate` edges;
mode is not exposed), cluster editor, gating in the planner, parent context line on cards,
conditional per-day toggles, `.blocked` propagation, `P(B|A)` in the projection. All dependency
reads in planner, projection and UI go through `gateParentIDs`; `allParentIDs` is used only by
`Dependencies.validate`.

Checkpoint:
- Gym → Protein. Answer Gym "no" for a week: Protein is never asked. Answer Gym 4/6: the Protein
  card says "of those 4". Pause Gym: Protein history shows `.blocked`.
- Try to create A → B → A: editor refuses with a clear message.
- `HabitCore` tests: a fixture with a `.sequence` edge Gym → Stretch behaves exactly like no
  edge (Stretch is asked while Gym fails, never `.blocked`, no parent context) **and** a
  `.sequence` edge that closes a cycle is rejected by `validate`. JSON export → import
  preserves the mode.

### M5 — Notifications — done (2026-09-27)

`HabitCore` `NotificationPlanner` (§8), `HabitUI` notification content/payloads and
`AppModel.respond(to:deliveredAt:with:)`, the app's `Notifier` (delegate, categories, rescheduling,
background refresh), Settings → Reminders, and the silence nudge opening a retroactive vacation.
Automated: `NotificationPlannerTests`, `NotificationCheckpointTests` (answer from a model launched just
for the action, seen after relaunch; quiet hours skip the next slot), `AppBundleTests` (background
refresh keys). Physical iPhone 16 Pro: answered from the notification with the app killed and the answer
appeared on launch. The first device run crashed on every tap: a `nonisolated async` delegate method
completed the notification center's handler off the main thread, so the conformance is now
`@MainActor` (§8). An XCUITest driving SpringBoard banners hung and was dropped; debug builds have
Settings → "Notify in 5 seconds" (and "… and quit", which exits once it is scheduled) for checking by hand.

Deliver: permission flow, cadence UI (times per day / every N days), quiet hours, actionable
notifications with Yes/No/Later, grouping, `onlyWhenQuestionsDue`, silence nudge, background
refresh rescheduling.

Checkpoint:
- Set two times per day; verify notifications arrive only when something is due; answer "Yes"
  from the notification with the app killed; open the app and see the answer recorded.
- Enable quiet hours spanning the next slot; confirm it is skipped.

### M6 — Interactive widgets and App Intents — done (2026-09-27)

`SpacedHabitsWidgets` extension (question widget small/medium/Lock Screen, status widget with Lock
Screen variants and deep links), `AnswerHabitIntent` (widget buttons), `LogHabitIntent` /
`DelayHabitIntent` / `ReviewHabitsIntent` with App Shortcuts, `AppModel.answerToday` / `reload` and
`WidgetTimeline` (§6). Automated: `HabitUI` `WidgetTests.checkpointAnswerFromWidgetAdvancesToNextQuestion`
(widget and app as two models on one store file), `IntentTests` (each intent's `perform()` in the app),
`AppBundleTests` (appex, URL scheme, App Shortcuts metadata), `TruthStoreTests.loadSeesWritesFromAnotherContainer`.
Physical iPhone: answered from the Home Screen widget without opening the app, the widget moved to the
next question and the app showed the answer on launch; "Hey Siri, log gym in Spaced Habits" logged it.


Deliver: iOS widget extension (question widget small/medium, status widget, Lock Screen
variants), App Intents (`AnswerHabitIntent`, `DelayHabitIntent`, `ReviewHabitsIntent`), Siri
phrases, timeline refresh at day boundaries.

Checkpoint:
- Answer a question from the Home Screen widget without opening the app; the widget advances
  to the next question; the app shows the answer on next launch.
- "Hey Siri, log gym in Spaced Habits" works.

### M7 — CloudKit sync + Watch — done (2026-09-27)

CloudKit-backed store in the app and watch app, `SyncMonitor` re-projection and Settings → Sync (§10),
`TruthChange` feed with idempotent latest-wins `merge`, `WatchBridge`, the watch app and its Smart Stack
widget and complications (§7). Automated: `HabitUI` `WatchSyncTests.checkpointWatchAnswerReachesThePhoneExactlyOnce`,
`HabitStore` `TruthChangeTests` (idempotent merge, `allChanges`, out-of-order arrival),
`TruthStoreTests.schemaMeetsCloudKitConstraints`. Physical iPhone + Apple Watch: answered on the watch
with the phone in airplane mode, the watch showed it at once, and after reconnecting it appeared on the
phone exactly once. Hardware testing found that out-of-order sync failed `load()` with `unknownHabit`; fixed
by holding back pending references (§10). The second-iPhone check was **waived** (no second device);
see O6.

Deliver: CloudKit configuration and `HabitStore` constraint audit (§10), remote-change
re-projection, sync status row; watchOS app (Today cards, list, sparkline), watch Smart Stack
widget + complications, WatchConnectivity bridge with idempotent event IDs.

Checkpoint:
- Answer on the watch with the phone in airplane mode; the watch shows it immediately; turn the
  phone back on; the answer appears on the phone within a minute, exactly once.
- Install on a second iPhone with the same iCloud account; habits and history appear; answer on
  one, see it on the other; no duplicates in `answers.csv`.

### M8 — HealthKit — deferred (optional, post-v1)

Skipped for now: it needs the HealthKit entitlement and Health permissions. Go straight to M9. See O7.

Deliver: Health binding editor, permission flow, observer + foreground fetch, `HealthObservation`
truth events, `.health` day source.

Checkpoint:
- Bind Gym to workouts ≥ 20 min; log a workout in the Health app; Gym is marked done for today
  and is not asked about; history shows the `.health` glyph.

### M9 — Charts and insights — done (2026-09-28)

`HabitCore/Insights`, `HabitUI/Charts`, the Insights screen (Today toolbar, `spacedhabits://insights`) and a
charts section in habit detail (§12). Automated: `HabitCore` `InsightsTests` / `OverviewTests`, `HabitUI`
`ChartTests.checkpointSteadyAskIntervalRises` (steady run exported as a fixture, imported through
`importJSON` since M10: 1 day for the first 4 days, ≥ 7 over the last 30) and
`ChartTests.checkpointChartsRenderFastForThreeYearsOfThirtyHabits` (`LargeFixture`, debug build, best of 3
runs: data plus drawing < 100 ms for habit detail, for the Insights screen's first screenful and for each
further cluster section; measured 65, 51 and ~10 ms on an M-series Mac), and `TodayFlowUITests` opening
Insights. Screenshots of the imported steady run: `Docs/checkpoints/m9-*.png`. A freshly booted iOS 27
simulator saturates the Mac for minutes (load average > 100): single timing runs failed and `xcodebuild`
stalled with no output until the simulator had settled, hence best of 3.


Deliver: all charts in §12 in `HabitUI/Charts`, Insights screen, insight cards (delays,
regressions, autonomy score), data-source legends, pause bands, "include paused days" toggle.

Checkpoint:
- With the M1 simulation exported as fixtures and imported (M10 import can land first if easier),
  the "ask interval over time" chart visibly rises for the steady habit. Commit screenshots under `Docs/checkpoints/`.
- Charts render in < 100 ms for a 3-year, 30-habit dataset (use a generated fixture).

### M10 — Export / import — done (2026-09-28)

§11 as implemented. Settings → Your data: Export JSON and Export CSV (share sheet, `SpacedHabits-<day>.json` /
`-csv.zip`), Import JSON… (Files) with a summary. Found missing while building it: the store had no write for
Health observations (the import writes them), the M9 debug fixture import dropped habit revisions and
simulated fixtures had none, and every relaunch logged the open cards again as new questions (now reused).
Automated: `HabitCore` `ExportTests` / `CSVExportTests` (goldens, date precision, schema and decode errors,
merge, unzip), `HabitStore` import write, `HabitUI` `ExportImportTests.checkpointExportWipeImportReexportIsIdentical`,
and `TodayFlowUITests` finding the export buttons. Checked in the simulator with `simulate dependent-pair
--json`: import → `-exportData` → erase → import that export → `-exportData`. The JSON matched apart from
`exportedAt`, the CSV zip and screenshots of Today, both habit details and Insights were byte-identical
(`Docs/checkpoints/m10-reimported-*.png`), and eight relaunches later the export was still identical. The real
export's `days.csv` opened in Numbers: 361 rows (header + 2 habits × 180 days), no empty `source` cell.


Deliver: CSV zip and JSON export via `ShareLink`, JSON import with merge-by-UUID and
re-projection, golden-fixture tests, `schemaVersion = 1`.

Checkpoint:
- Export → wipe the app → import → every screen looks identical, and re-exporting produces a
  byte-identical JSON (modulo `exportedAt`).
- Open `days.csv` in Numbers: every day of every habit has a `source` value.

### M11 — Polish and release prep (2–3 days)

Deliver: onboarding (3 screens: idea, add first habit, notifications), accessibility audit
(VoiceOver labels on cards and chart summaries, Dynamic Type, Reduce Motion), haptics,
localization scaffolding (`String(localized:)` everywhere, en base), app icon, App Store
metadata, privacy manifest, TestFlight build.

Checkpoint:
- Full VoiceOver pass through Today → answer → detail → settings.
- TestFlight build installs on iPhone + Watch from the same build.

Status (2026-09-28): built; checkpoint pending (needs physical devices). VoiceOver summaries on every chart,
cards are one "Check-in: <habit>" container, Reduce Motion fades answered cards instead of sliding them,
the card header stacks at accessibility text sizes (AX5 screenshots: `Docs/checkpoints/m11-ax5-*.png`),
haptic on answer (phone and watch). Privacy manifests and export compliance per §2. Builds 0.1.0 (1) and (2) uploaded
with `make testflight`. Before testers install it, deploy the CloudKit schema to Production (CloudKit Console
→ Deploy Schema Changes): TestFlight builds use the Production environment, and SwiftData only creates the
schema in Development.

**Rough total:** ~3–4 weeks of focused work. M0–M2 is the MVP you can live with; M3–M4 make it
the app described in §1; M5–M7 make it frictionless (M8 HealthKit is deferred); M9–M11 make it shippable.

---

## 14. Testing strategy

| Layer | Tool | What |
|---|---|---|
| `HabitCore` unit | Swift Testing | every public function; edge cases: DST changes, day-start hour, empty habits, gap == cap, gap > max interval, zero-parent-done windows |
| `HabitCore` simulation | Swift Testing | §4.8 synthetic users with seeded RNG; runs in < 2 s total |
| `HabitCore` determinism | Swift Testing | projection twice → equal; export → import → export equal |
| `HabitStore` | Swift Testing, in-memory `ModelContainer` | mapping round-trips; CloudKit constraint lint (reflection test: no `.unique`, all relationships optional) |
| `HabitUI` | Swift Testing + snapshot tests (optional, `swift-snapshot-testing`) | question card shapes, glyphs, chart rendering with fixtures |
| App | XCTest UI tests, minimal | launch → answer a card → relaunch → state persisted |
| Manual | checkpoints above | anything involving notifications, widgets, Health, CloudKit, Watch |

All tests run in `make ci`; `make test` skips the UI tests, which run in `make test-ui`. Anything that needs a physical device or an iCloud account is a
documented manual checkpoint, not a flaky automated test.

---

## 15. Working agreements for the implementing agent

1. Read this document before each milestone; when a decision changes, update the section it
   governs (not a separate log).
2. Run `make format && make lint && make test` before declaring any task done (add `make test-ui` when
   the change touches app screens); `make ci` must be green before pushing.
3. `HabitCore` stays dependency-free and UI-free. If you need a platform API in the engine, you
   are in the wrong module — pass the value in instead.
4. Commit directly to `main` in small, atomic commits; no branches or pull requests. Include the
   checkpoint evidence (test output, simulation table, screenshot paths) in the milestone's final
   commit message.
5. No force-unwraps outside tests; no `print` in production code (use `os.Logger` with
   subsystem `ga.emira.spacedhabits`).
6. When an Apple API behaves differently from what this document assumes (deployment target,
   SwiftData/CloudKit constraints, WidgetKit limits), fix the document and the plan, not just the
   code.
7. Default to `Sendable` value types and `@MainActor` view models; no `@unchecked Sendable`
   without a comment explaining why.

---

## 16. Open questions

Decide during the relevant milestone, then move the answer into the section it governs.

- O2. Should the "Later" dismissal count toward staleness, or be ignored by the scheduler? Ignored
  for M2 (it is logged in `Truth.questions` but not read); revisit if users report nagging.
- O3. Third vacation behavior "keep but relaxed" (reduced target). Not in v1.
- O4. Import of Loop/Streaks CSVs. Not in v1; JSON import only.
- O5. Whether to expose model parameters (decay, threshold) in Settings or keep them hidden
  behind an "advanced" section. Advanced section for v1.
- O6. The M7 two-iPhone check (§13) is unverified: no second device was available. Run it once one
  is (a TestFlight tester's phone would do): habits and history appear, an answer on one shows on
  the other, no duplicates in `answers.csv`.
- O7. HealthKit (§9, M8) is deferred as optional post-v1 work because it needs the Health entitlement
  and user permission. Decide after M11 whether to build it; if so, run the M8 checkpoint as written.

