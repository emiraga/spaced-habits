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

- A habit you keep consistently gets asked about less and less often (weekly, then rarely).
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

---

## 2. Platforms and tech stack

| Concern | Choice | Notes |
|---|---|---|
| Language | Swift, **Swift 6 language mode**, strict concurrency | Warnings as errors |
| Min deployment | iOS 17 / watchOS 10 | Raise if a required API needs it; document why |
| Xcode | Latest stable | Pin in `.xcode-version` |
| UI | SwiftUI everywhere | UIKit only for wrapped edge cases |
| Persistence | SwiftData in an App Group container | Shared by app + widget extension |
| Sync | SwiftData + CloudKit private database | Plus WatchConnectivity for low-latency phone↔watch |
| Widgets | WidgetKit + App Intents (interactive) | Home, Lock Screen, StandBy, watch Smart Stack |
| Notifications | UserNotifications with action categories | Answer from the notification |
| Health | HealthKit (read-only) | Auto-answer physical habits |
| Charts | Swift Charts | |
| Tests | **Swift Testing** (`import Testing`) for new code; XCTest only where required (UI tests) | |
| Project generation | **XcodeGen** (`project.yml`) | `.xcodeproj` is generated and git-ignored |
| Formatting | **SwiftFormat** (`.swiftformat`) | Run on save + pre-commit + `make ci` check |
| Linting | **SwiftLint** (`.swiftlint.yml`) | `--strict` |
| Build output | **xcbeautify** | |
| Editor LSP | **xcode-build-server** | Lets SourceKit-LSP (VS Code, etc.) resolve app-target flags; `make gen` writes `buildServer.json` |
| Tool pinning | `Brewfile` (+ optional `mise`) | Everyone builds with the same tool versions |
| Task runner | `Makefile` | `make gen / build / test / lint / format / ci` |
| CI | None hosted; `make ci` locally | Run before every push (D13) |
| Git hooks | `pre-commit` (or `lefthook`) | format + lint on staged files |

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
│   │   │   ├── Model/          # Habit, Question, Events, DayRecord, Settings
│   │   │   ├── Scheduler/      # AdherenceModel, QuestionPlanner, SessionBudget, SpotCheck
│   │   │   ├── Projection/     # EventLog -> DayRecords (materialization)
│   │   │   ├── Dependencies/   # DAG validation, gating, conditional metrics
│   │   │   ├── Pauses/         # pause/vacation semantics, re-entry
│   │   │   ├── Export/         # CSV/JSON encoders, schema versioning
│   │   │   └── Support/        # DayKey, DayCalendar, Clock, RandomSource
│   │   └── Tests/HabitCoreTests/
│   │       ├── Unit/
│   │       └── Simulation/     # synthetic users; asserts question counts fall with adherence
│   ├── HabitStore/             # SwiftData models + CloudKit config + mapping to HabitCore types
│   └── HabitUI/                # Shared SwiftUI views (question cards, habit rows, charts)
├── Apps/
│   ├── iOS/                    # Spaced Habits (iOS app target) + Assets.xcassets
│   ├── iOSTests/               # app-hosted unit tests (Swift Testing)
│   ├── iOSWidgets/             # WidgetKit extension (iOS)
│   ├── watchOS/                # Spaced Habits Watch app (Assets.xcassets parked here until M7)
│   └── watchOSWidgets/         # Complications / Smart Stack
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
`.pre-commit-config.yaml`, `.xcode-version`) landed in M0 and are the source of truth; see
D9–D13 for where they deviate from the original sketch. No hosted CI (D13).

Still to add to `project.yml` in later milestones:
- App Group `group.ga.emira.spacedhabits` entitlement on the app (M2) and widget extension (M6).
- `SpacedHabitsWidgets` iOS app extension from `Apps/iOSWidgets` (M6).
- iCloud/CloudKit entitlement `iCloud.ga.emira.spacedhabits` (M7) on app, widgets and watch.
- `SpacedHabitsWatch` (`application.watchapp2`, `Apps/watchOS`) and `SpacedHabitsWatchWidgets`
  (`Apps/watchOSWidgets`), embedded in the iOS app (M7).
- HealthKit entitlement and `NSHealthShareUsageDescription`: "Spaced Habits reads workouts to
  auto-complete matching habits." (M8).

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
- Every scheduler entry point takes an injected `Clock`; code that needs randomness takes a
  `RandomSource` (tests and simulations use `FixedClock` / `SeededRandomSource`).

### 3.2 Source-of-truth vs projection

The store is **event-sourced-lite**:

- **Truth** (append-only, synced): `Habit` definitions and edits, `Answer`s, `PauseEvent`s,
  `HealthObservation`s, `Settings`.
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
  `Dependency` / `DependencyMode` (D8), `Cluster`.
- `Question.swift`: `Question`, `QuestionShape` (`.singleDay` / `.perDay(days:)` / `.count(total:)`),
  `ParentContext`.
- `Events.swift`: truth events `Answer` / `AnswerValue` / `Channel`, `PauseEvent` / `PauseReason`,
  `HealthObservation`.
- `DayRecord.swift`: derived `DayRecord` (with `conditionalDenominatorExcluded`, §4.5), `DaySource`
  (`feedsModel` encodes D4), `SchedulerState`.
- `Settings.swift`: `Settings` (`.default` holds the tunables used throughout §4),
  `NotificationSettings`, `TimeOfDay`, `QuietHours` (D16).

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

**Natural interval** (`AdherenceModel.naturalIntervalDays`, stored as
`SchedulerState.currentIntervalDays`): the number of days, in `1...maxIntervalDays`, until decay
alone pushes `sd` above `uncertaintyThreshold`; 1 if it already is. Decay only ever increases `sd`
(the mean moves toward 0.5 and `n` shrinks), so this is the first crossing. It is the "ask
interval" in the UI and charts and the "> 7 days" test of §4.2 rule 5. With the defaults, a habit
answered "yes" every day settles at `alpha ≈ 13.5, beta = 1, sd ≈ 0.06` and an interval of
~15 days; an exact 50/50 habit settles at `sd ≈ 0.13` (below threshold), so only rule 2 keeps
asking it daily.

### 4.2 When is a habit due?

`QuestionPlanner.isDue(habit, state, today) -> DueReason?`

A habit is due if **any** of:

1. `sd > settings.uncertaintyThreshold` (evidence too thin/old) — the normal path.
2. `mean < habit.targetAdherence` and `lastAskedDay < today` — struggling habits get daily attention.
3. `today - lastCoveredDay >= settings.maxIntervalDays` — hard ceiling.
4. `state.forcedReentryCheck` — first day after a pause ends.
5. Spot check: with probability `settings.spotCheckRate`, only when the natural interval is > 7 days.
   Keeps the model calibrated against silent collapse. Decided **once per (habit, day)**, not per
   planner run (D14): hash `(habit.id, today)` with a stable hash (not Swift's `Hasher`, which is
   seeded per process) to a value in `0..<1` and compare it to `spotCheckRate`. Re-opening the app,
   the widget and the watch therefore all agree, and the effective rate stays at `spotCheckRate`
   regardless of how often the planner runs.

A habit is **never** due if: it is paused today, archived, blocked by a paused parent, gated by a
failing parent (§4.5), or `lastCoveredDay == today`.

### 4.3 Question construction

```
gapDays = today - lastCoveredDay            (or today - createdDay for new habits)
coverDays = min(gapDays, habit.maxRecallGapDays)
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
    forcedReentryCheck and mean < target get a fixed bonus so they surface first
present top settings.sessionBudget (default 3); rest remain queued with a "More…" affordance
```

Questions are created lazily at presentation time (so a habit answered from the watch does not
leave a stale question on the phone). A `Question` that is dismissed ("Later") is discarded and
re-planned next session; it is not carried as state.

### 4.5 Dependencies

`habit.dependencies` is a list of `Dependency { parentID, mode }`. The parent IDs (all modes)
form a DAG; `Dependencies.validate` rejects cycles at edit time and on import.

**Edge modes.** Everything below — gating, the conditional metric, pause propagation, the
parent-context line on cards — applies to **`.gate` edges only**. `.sequence` edges exist in the
model so that habit stacking (ATOMIC_HABITS_IDEAS.md F2) needs no data migration; in v1 they are
inert: the planner, projection and UI must read parents through `habit.gateParentIDs`, never
`habit.allParentIDs`, so a `.sequence` edge (e.g. from a JSON import) changes nothing except
cycle validation. The editor creates `.gate` edges only and does not expose the mode.

**Gating.** A dependent habit `B` with gate-parent `A` is only due when, over `B`'s prospective
`covers` window, `A`'s expected done-days ≥ 1 and `A.mean ≥ 0.5`. Otherwise asking about `B`
produces noise. Multiple gate parents: all must pass (AND). Keep it AND in v1; document as a decision.

**Conditional metric.** `B`'s adherence is `P(B | A)`, not `P(B)`:

- `parentContext.parentDoneDays = round(Σ A.dayRecords[day].value for day in covers)`.
- The `count` question reads: *"You did A on 4 of 6 days. On how many of those 4 did you do B?"*
  `total` = `parentDoneDays`, not `coverDays`.
- Per-day shape: only show toggles for days where `A.value ≥ 0.5`.
- Projection: on days where `A.value == 0` (observed), `B` gets `source = .observed, value = 0`
  with a flag `conditionalDenominatorExcluded = true` so charts can compute both `P(B)` and
  `P(B|A)`.

**Pause propagation.** If gate-parent `A` is paused on a day, `B`'s DayRecord is `.blocked` (not
`.paused`), so the user can distinguish "I paused protein" from "protein was moot because gym was
paused". A paused `.sequence` parent has no effect on its children.

### 4.6 Pauses and vacation

Both features are one primitive: `PauseEvent`.

- **Delay from a question card:** answer `.delayed(days: n)` → `PauseEvent(habitIDs: [h], start: today, end: today + n - 1, reason: .manual)`.
- **Backdated pause:** UI lets the user set `start` in the past ("I was sick the last 3 days").
  Re-projection converts those days from whatever they were into `.paused`.
- **Extend / end early:** edit `end`. Habit rows always show "Resumes <date>".
- **Scheduler during pause:** no decay, no questions, state frozen.
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

`Projection.rebuild(habits, answers, pauses, healthObservations, settings, clock)`:

1. For each habit, for each day from `createdDay` to `today`:
   - if inside a pause for this habit → `.paused`
   - else if any parent is paused that day → `.blocked`
   - else if a HealthObservation matches → `.health`, value 1
   - else if an Answer covers the day → `.observed` (singleDay/perDay) or `.aggregated` (count, value = done/of)
   - else if `.dontRemember` covers it → `.unknown`
   - else → `.inferred` or `.unknown` per §4.3 (computed *after* the model state for that point in time)
2. Replay the adherence model chronologically, applying decay per elapsed non-paused day and
   updates per observed/aggregated/health day, to obtain `SchedulerState` as of today. Also emit
   a time series of `(day, mean, sd, intervalDays)` for the "ask interval over time" chart.
3. Output is deterministic; the same inputs must produce byte-identical output (tests assert this).

### 4.8 Simulation test harness

`Tests/Simulation/` runs synthetic users through the planner for 180 days with a seeded RNG:

- `SteadyUser(p: 0.95)` → assert questions/week falls below 1.5 by week 4 and inferred-day error
  (|inferred value − true value|) stays < 0.15.
- `FlakyUser(p: 0.5)` → assert asked ≥ 5 days/week throughout.
- `CollapsingUser(p: 0.95 for 60 days, then 0.1)` → assert the collapse is detected (mean < target)
  within 10 days thanks to spot checks and the max-interval ceiling.
- `VacationUser` → assert zero questions during the pause, exactly one re-entry check after, and
  frozen state across it.
- `DependentPair(A: 0.9, B|A: 0.8)` → assert B is never asked when A is failing, and the estimated
  `P(B|A)` is within 0.1 of truth by day 60.

These are the acceptance tests for the engine. They must pass before UI work begins (Milestone 1).

---

## 5. User interface (iOS)

### 5.1 Screens

1. **Today** (root). A stack of question cards (≤ session budget), then a compact list of all
   active habits with today's status glyph (✓ observed, ≈ aggregated/inferred, ? unknown,
   ⏸ paused, ⛔ blocked, · not due). Pull-to-refresh replans. Empty state: "Nothing to ask.
   Next check-in: <habit> on <date>."
2. **Habit detail.** Header with current ask interval ("Asking every ~9 days"), adherence 30d,
   Resumes-on banner if paused, charts (§10), history calendar, dependency list, edit button.
3. **Habit editor.** Name, emoji, color, importance, target adherence, max recall gap, vacation
   behavior, depends-on picker (with cycle rejection), cluster, Health binding, archive.
4. **Pause sheet.** Presented from a question card ("Delay…") or habit detail. Duration presets
   (1, 3, 7, 14 days, custom), start date (default today; can be backdated), reason.
5. **Vacation sheet.** Start/end dates, checklist of habits (pre-checked = `.keep`), "Also keep
   parents" resolver, "Quiet all notifications" toggle. Persisting checklist changes to
   `vacationBehavior` is on by default with a visible toggle.
6. **Insights.** Overall charts + insight cards (delayed-often, regressions, autonomy score).
7. **Settings.** Notifications cadence, quiet hours, session budget, day start hour, spot check
   rate (advanced), export/import, Health permissions, iCloud status, debug (rebuild projection).

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

- **Interactive widget** (small/medium, Home + Lock Screen + StandBy): shows the top-priority
  due question with Yes/No buttons via `Button(intent:)`. Medium size shows two questions or
  one `.perDay` card. After answering, the timeline refreshes to the next question.
- **Status widget**: habits with today's glyphs; taps deep-link to habit detail.
- App Intents: `AnswerHabitIntent(questionID, value)`, `DelayHabitIntent(habitID, days)`,
  `ReviewHabitsIntent()` (opens Today). Expose to Siri/Shortcuts: "Log gym in Spaced Habits".
- Widgets read/write the **shared App Group SwiftData store**. Widget writes append an `Answer`
  and call `WidgetCenter.reloadAllTimelines()`; the app re-projects on foreground.
- Timeline: one entry now + entries at the next day boundary and at each notification time.
- watchOS: Smart Stack widget with the same intent; complications show "N due" or a checkmark.

---

## 7. Watch app

- Thin SwiftUI app using `HabitUI` cards sized for the wrist. Screens: Today (cards), habit list,
  a single-habit quick view. No editor, no charts beyond a 7-day sparkline.
- Data: own SwiftData store with the same CloudKit container (truth), **plus** `WatchConnectivity`
  for immediacy: the phone pushes the current planned question set via `updateApplicationContext`;
  the watch sends answers via `transferUserInfo`. All events carry their UUID so duplicates from
  both channels are idempotent.
- Runs standalone if the phone is unreachable; CloudKit catches up later.

---

## 8. Notifications

- Categories with actions: `HABIT_QUESTION` → *Yes*, *No*, *Later*. Actions are handled in
  `UNUserNotificationCenterDelegate` (app launches in background) and append an `Answer`.
- Scheduling: local notifications computed from `NotificationSettings.cadence`, clipped by quiet
  hours, and only scheduled when `onlyWhenQuestionsDue` finds ≥ 1 due habit at that time
  (re-evaluated on each app foreground and via `BGAppRefreshTask`).
- Content: the top-priority question text, so the user can answer without opening anything.
  Group multiple due habits into one notification ("3 habits to review") when > 1.
- Silence nudge (§4.6) and vacation-quiet toggle both live here.
- Never notify about a paused or blocked habit.

---

## 9. HealthKit

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

- `ModelContainer` with `ModelConfiguration(groupContainer: .identifier("group.…"), cloudKitDatabase: .private("iCloud.…"))`.
- CloudKit-backed SwiftData constraints (enforce in `HabitStore`):
  - no `@Attribute(.unique)`; uniqueness is by UUID handled in code
  - every property has a default or is optional; every relationship is optional
  - no ordered relationships; store `dependencies` as a `Codable` value attribute
    (`[Dependency]`, encoded by SwiftData as data), not as a relationship to other `Habit` rows.
    Give it a default of `[]`. Add a mapping test that a `.sequence` edge survives a
    store → CloudKit-shaped model → `HabitCore` round-trip unchanged.
- Conflict policy: truth tables are append-only; edits to `Habit` and `PauseEvent` are
  last-writer-wins per record, which is acceptable for single-user data. Projections are never
  synced.
- On each remote change notification: re-project from the earliest changed day, reload widgets.
- A "Sync status" row in Settings shows account state and last successful merge; a debug button
  forces full re-projection.

---

## 11. Export / import

- **CSV** (zip of several files): `days.csv` (habit_id, habit_name, day, value, source,
  confidence, conditional_denominator_excluded, question_id), `habits.csv`, `answers.csv`,
  `questions.csv`, `pauses.csv` (with reason), `clusters.csv`, `dependencies.csv`
  (habit_id, parent_id, mode).
- **JSON**: one document `{ schemaVersion, exportedAt, settings, habits, clusters, answers,
  questions, pauses, healthObservations }`. Each habit carries
  `"dependencies": [{ "parentID": "...", "mode": "gate" }]`. This is the complete truth set;
  `DayRecord`s are omitted because they are derived (an optional `includeProjection` flag adds them).
- **Import** (JSON only): merge by UUID, never delete, re-validate the dependency DAG (reject the
  whole import on a cycle), then re-project. Unknown `mode` values fail the import with a clear
  error rather than being coerced. Used for backup/restore and for moving between test devices.
- Delivered via `ShareLink` / Files. All encoders live in `HabitCore/Export` and are unit-tested
  against golden fixtures; `schemaVersion` bumps require a migration note in this document.

---

## 12. Charts (`HabitUI/Charts`, Swift Charts)

Per habit:
- **Ask interval over time** — line; the signature chart. Rising = becoming automatic.
- Calendar heatmap — cell fill by value, hatched for inferred/aggregated, gray for paused,
  striped for blocked, hollow for unknown.
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

---

## 13. Implementation plan

Each milestone ends with a **checkpoint**: something you can run, tap, or inspect. Do not start
the next milestone until the checkpoint passes and `make ci` is green. Milestones are ordered
so that a usable app exists from M2 onward and every later milestone adds a feature to a working
build.

### M0 — Scaffold — done (2026-09-27)

### M1 — Engine (2–3 days)

Done: `Support/` (`DayKey`, `DayCalendar`, `Clock`, `RandomSource`), `Model/` (all types in §3.3),
`Scheduler/AdherenceModel` (§4.1).

Deliver in `HabitCore`:
`QuestionPlanner` (due rules, shapes, budget, prioritization, spot checks), `Dependencies`
(DAG validation, gating, conditional context), `Pauses` (freeze, re-entry, backdating),
`Projection.rebuild`, and the simulation harness (§4.8). Add a tiny `Scripts/simulate.swift`
(or a `swift run` executable target) that prints a 180-day table for a chosen synthetic user.

Checkpoint:
- `swift test --package-path Packages/HabitCore` passes, including all five simulations.
- Running the simulator executable shows ask intervals growing for the steady user and staying
  at 1 for the flaky user. Paste that table into the commit message.
- Projection determinism test passes (same input → identical output, twice).

### M2 — Daily driver, single device (2–3 days)

Deliver: `HabitStore` SwiftData models in the App Group container (no CloudKit yet), mapping to
`HabitCore`, Today screen with question cards (all three shapes + Don't remember; Delay shows a
placeholder), habit list with status glyphs, habit editor (name/emoji/color/importance/target/
recall gap), habit detail with a plain history list (no charts yet), Settings with session budget
and day start hour. Seed data behind a debug flag.

Checkpoint:
- Install on a physical iPhone. Create three habits, answer questions for three simulated days
  (use a debug "advance day" control in Settings that shifts the injected `Clock`).
- Confirm: a habit answered "yes" three days running is not asked on day 4; a habit answered
  "no" is asked daily; a four-day gap produces a `count` card.
- Kill and relaunch: state persists. Cold launch < 400 ms measured with Instruments or `os_signpost`.

### M3 — Pauses and vacation (1–2 days)

Deliver: Pause sheet (from card and from detail, with backdating), Resumes-on banner, extend /
end early, Vacation sheet with checklist + persisted `vacationBehavior` + parent resolver + quiet
toggle + scheduled start, re-entry check, delay-often insight rule (data only; card UI in M9).

Checkpoint:
- Delay a habit 3 days; advance clock; confirm no questions, `.paused` days in history, exactly
  one question on the resume day covering only that day.
- Backdate a pause over answered days; confirm they flip to `.paused` in history.
- Enable vacation with one kept habit; confirm only that habit is asked; disable and re-enable
  vacation: the kept set is remembered.

### M4 — Dependencies and clusters (1–2 days)

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

### M5 — Notifications (1 day)

Deliver: permission flow, cadence UI (times per day / every N days), quiet hours, actionable
notifications with Yes/No/Later, grouping, `onlyWhenQuestionsDue`, silence nudge, background
refresh rescheduling.

Checkpoint:
- Set two times per day; verify notifications arrive only when something is due; answer "Yes"
  from the notification with the app killed; open the app and see the answer recorded.
- Enable quiet hours spanning the next slot; confirm it is skipped.

### M6 — Interactive widgets and App Intents (1–2 days)

Deliver: iOS widget extension (question widget small/medium, status widget, Lock Screen
variants), App Intents (`AnswerHabitIntent`, `DelayHabitIntent`, `ReviewHabitsIntent`), Siri
phrases, timeline refresh at day boundaries.

Checkpoint:
- Answer a question from the Home Screen widget without opening the app; the widget advances
  to the next question; the app shows the answer on next launch.
- "Hey Siri, log gym in Spaced Habits" works.

### M7 — CloudKit sync + Watch (2–3 days)

Deliver: CloudKit configuration and `HabitStore` constraint audit (§10), remote-change
re-projection, sync status row; watchOS app (Today cards, list, sparkline), watch Smart Stack
widget + complications, WatchConnectivity bridge with idempotent event IDs.

Checkpoint:
- Answer on the watch with the phone in airplane mode; the watch shows it immediately; turn the
  phone back on; the answer appears on the phone within a minute, exactly once.
- Install on a second iPhone with the same iCloud account; habits and history appear; answer on
  one, see it on the other; no duplicates in `answers.csv`.

### M8 — HealthKit (1 day)

Deliver: Health binding editor, permission flow, observer + foreground fetch, `HealthObservation`
truth events, `.health` day source.

Checkpoint:
- Bind Gym to workouts ≥ 20 min; log a workout in the Health app; Gym is marked done for today
  and is not asked about; history shows the `.health` glyph.

### M9 — Charts and insights (2 days)

Deliver: all charts in §12 in `HabitUI/Charts`, Insights screen, insight cards (delays,
regressions, autonomy score), data-source legends, pause bands, "include paused days" toggle.

Checkpoint:
- With the M1 simulation exported as fixtures and imported (M10 import can land first if easier),
  the "ask interval over time" chart visibly rises for the steady habit. Commit screenshots under `Docs/checkpoints/`.
- Charts render in < 100 ms for a 3-year, 30-habit dataset (use a generated fixture).

### M10 — Export / import (1 day)

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

**Rough total:** ~3–4 weeks of focused work. M0–M2 is the MVP you can live with; M3–M4 make it
the app described in §1; M5–M8 make it frictionless; M9–M11 make it shippable.

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

All tests run in `make ci`. Anything that needs a physical device or an iCloud account is a
documented manual checkpoint, not a flaky automated test.

---

## 15. Working agreements for the implementing agent

1. Read this document before each milestone; update it when a decision changes. Add a dated line
   under §16 for every deviation.
2. Run `make format && make lint && make test` before declaring any task done; `make ci` must be green before pushing.
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

## 16. Decisions and open questions

Decided:
- D1. Boolean habits only in v1; `HabitKind` reserved for quantity later.
- D2. Multiple parents are AND-gated.
- D3. Pauses freeze scheduler state; one forced re-entry check after resume; no decay penalty.
- D4. Inferred days never feed the adherence model (weight 0). Only observed/aggregated/health do.
- D5. Recall cap default 7 days, per-habit adjustable; days beyond the cap are inferred, not asked.
- D6. Event-sourced-lite store; projections are derived and never synced.
- D7. Vacation checklist edits persist to `vacationBehavior` by default (toggle visible).
- D8. Dependencies are `[Dependency { parentID, mode }]` from day one, not `[UUID]`. v1 creates
  only `.gate`; `.sequence` is reserved for habit stacking (ATOMIC_HABITS_IDEAS.md F2) and is
  inert everywhere except DAG validation, store/sync and export/import. Chosen so F2 becomes a
  UI-and-planner change with no data migration.
- D9 (2026-09-27, M0). Toolchain pinned to Xcode 27.0 (`.xcode-version`); package manifests use
  `swift-tools-version: 6.2` for `.treatAllWarnings(as: .error)` (warnings-as-errors without
  `unsafeFlags`). `make test` runs `xcrun swift test` so SwiftPM uses the Xcode toolchain, not
  whatever `swift` is first on `PATH` (a swiftly 6.3 toolchain failed against the macOS 28 SDK).
- D10 (2026-09-27, M0). `make test` runs `swift test` for all three packages (on macOS, hence
  `.macOS(.v14)` in their platforms) plus the app-hosted `SpacedHabitsTests` target via
  xcodebuild; package test targets are not in the Xcode scheme.
- D11 (2026-09-27, M0). Bundle ID prefix `ga.emira.spacedhabits` replaces `com.example`.
  Info.plist is generated from build settings (`GENERATE_INFOPLIST_FILE` + `INFOPLIST_KEY_*`)
  instead of a checked-in `Apps/iOS/Info.plist`. Entitlements (App Group, iCloud, HealthKit)
  and the widget/watch targets are added in the milestones that need them (M2/M6/M7/M8),
  not in M0.
- D12 (2026-09-27, M0). SwiftLint `trailing_comma` is disabled: SwiftFormat owns trailing
  commas (same reasoning as `line_length`).
- D13 (2026-09-27, M0). No hosted CI (GitHub Actions removed): `make ci` run locally before
  every push is the gate. GitHub's macOS runners did not have Xcode 27 when M0 landed.
- D14 (2026-09-27, M1). Spot checks (§4.2 rule 5) are decided once per habit per day from a stable
  hash of `(habit.id, day)`, not by a fresh random draw on each planner run. A per-run draw would
  make the effective rate grow with how often the app is opened and let phone, widget and watch
  disagree. Trade-off: spot-check days are predictable in principle, which is irrelevant here.
- D15 (2026-09-27, M1). `Habit` stores `createdDay: DayKey`, fixed at creation by `DayCalendar`.
  §4.3/§4.7 start a habit's history there instead of re-deriving a day from `createdAt`, which
  would move if the user later changes time zone or day-start hour.
- D16 (2026-09-27, M1). `NotificationSettings` uses `TimeOfDay(hour, minute)` instead of
  `DateComponents` (no calendar/time-zone baggage, trivially `Codable`), and
  `quietHours: QuietHours(startHour, endHour)` (half-open, wraps past midnight) instead of
  `ClosedRange<Int>`: `22...7` traps at runtime.
- D17 (2026-09-27, M1). Case and label renames to satisfy SwiftLint `identifier_name` rather than
  allowlisting short names: `AnswerValue.yes/.no` → `.done/.notDone`, `count(done:of:)` →
  `count(done:total:)`, `QuestionShape.count(of:)` → `.count(total:)`, `Cadence.everyNDays(_:at:)` →
  `everyNDays(_:time:)`. User-facing copy still says Yes / No.
- D18 (2026-09-27, M1). `make gen` also runs `xcode-build-server config` for the `SpacedHabits`
  scheme, writing a git-ignored `buildServer.json` so SourceKit-LSP editors understand the app
  target. It must re-run after every `xcodegen generate` (the regenerated `.xcodeproj`
  invalidates the stored workspace path), hence living in `gen`. The LSP reads per-file flags
  from build logs: run `make build` once afterwards, then reload the editor window. Add the
  watch scheme's line when `SpacedHabitsWatch` lands (M7).

Open (decide during the relevant milestone and record here):
- O1. Should aggregated answers be spread evenly (`value = N/K` per day) or placed on the days
  the model finds most likely? Even spread is simpler and more honest; decide in M1.
- O2. Should the "Later" dismissal count toward staleness, or be entirely stateless? Stateless
  for M2; revisit if users report nagging.
- O3. Third vacation behavior "keep but relaxed" (reduced target). Not in v1.
- O4. Import of Loop/Streaks CSVs. Not in v1; JSON import only.
- O5. Whether to expose model parameters (decay, threshold) in Settings or keep them hidden
  behind an "advanced" section. Advanced section for v1.

