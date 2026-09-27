# Atomic Habits–inspired features (optional backlog)

Ideas drawn from habit-formation practice (largely as popularized by *Atomic Habits*) that fit
Fade's model. **None of these are in scope for v1.** Each is written as a standalone feature
with its own model changes, UI, scheduler impact, and rough effort, so any one can be picked up
independently after the milestones in `DESIGN.md` are done. Where a feature builds on another,
it says so.

Effort scale: S = hours, M = 1–2 days, L = 3+ days.

---

## F1. Anchors (untracked cues)

**What.** A habit stack attaches a new behavior to something you already do automatically
(pour coffee, brush teeth). Today the only possible "parent" is a tracked habit that gets asked
about. An *anchor* is a cue that is assumed to happen and is never asked about.

**Why.** Without it, users have to create a fake "drink coffee" habit and answer questions
about it forever, which contradicts the whole app.

**Model.** New `Habit.kind = .anchor` (or a separate `Anchor` type with `id`, `name`, `emoji`,
`timeOfDay: TimeOfDay?`). Anchors are valid entries in `dependsOn`. Projection treats an anchor
as done every non-paused day (`source = .assumed`, value 1, weight 0 — never feeds a model).
Anchors have no `SchedulerState` and never appear on cards. Vacation: anchors are neither kept
nor paused; they just exist.

**UI.** "Anchors" section in the habit editor's depends-on picker; onboarding scorecard (F8)
seeds them. Habit rows never show anchors; the Today screen never asks about them.

**Scheduler.** No change except that gating (§4.5) always passes for an anchor parent.

**Effort.** S–M. **Depends on:** nothing. **Enables:** F2, F3, F8.

---

## F2. Dependency edge mode: `gate` vs `sequence`

**What.** Today every `dependsOn` edge is a logical conditional: B is measured as P(B|A) and
not asked when A is failing. A *sequence* edge means "B comes after A in my routine" without B
being meaningless on its own.

**Why.** Meditate-after-coffee is a sequence; protein-after-gym is a gate. Treating both as
gates hides B's real adherence and blocks questions that should be asked.

**Model.** Replace `dependsOn: [UUID]` with `dependencies: [Dependency]` where
`Dependency { parentID: UUID; mode: .gate | .sequence }`. Migration: existing edges → `.gate`.
Cycle validation unchanged (applies to both modes).

**Projection / scheduler.** `.sequence` edges: no gating, no `.blocked` propagation, no
conditional denominator; B is a normal habit. They only affect card ordering (F3) and phrasing
(F4). `.gate` edges keep current behavior.

**Charts.** For `.sequence` pairs still show P(B|A) vs P(B) side by side as an insight — a
large difference means the stack is doing real work.

**Effort.** S. **Depends on:** nothing (works better with F1, F3, F4).

---

## F3. Ordered stacks (routines)

**What.** A cluster can be marked as an ordered stack. Members have an `order` index, and the
Today screen presents due questions for that stack as one top-to-bottom flow.

**Why.** Stacks are sequences in time; showing their cards in order reinforces the sequence and
lets the user answer a whole morning routine in one swipe.

**Model.** `Cluster.isOrderedStack: Bool`, `Habit.orderInCluster: Int?`. Validation: if
`isOrderedStack`, every member has an order and `.sequence`/`.gate` edges must point backward
(earlier → later) so the order and the DAG agree.

**UI.** Drag-to-reorder in the cluster editor. On Today, a stack's due cards are grouped under
a header and presented in order; the session budget counts a whole stack as **one** item so a
5-step routine doesn't eat the entire budget or get split across days. Widget: medium size
shows the next unanswered step of the top-priority stack.

**Scheduler.** Planner groups candidates by stack before ranking; the stack's score is the max
of its members' scores.

**Effort.** M. **Depends on:** F2 recommended.

---

## F4. Implementation intention text and cue-based phrasing

**What.** Each habit gets an optional structured intention: *after/at [cue], I will [behavior]
[in location]*. Cards use it: "After the gym, did you have your protein?" instead of "Did you do
Protein?"

**Why.** Implementation intentions have the strongest research support of anything in this
list; repeating the cue-behavior pairing on every card reinforces it.

**Model.** `Habit.intention: Intention?` with `Intention { cueKind: .afterHabit(UUID) | .atTime(DateComponents) | .atLocation(String) | .freeText(String); location: String? }`.
When `cueKind == .afterHabit`, keep it consistent with `dependencies` (editor offers to create
the edge).

**UI.** Guided editor row ("After I ___, I will ___") with the anchor/habit picker inline;
cards, notifications, and widgets use the phrased form when present. Onboarding asks for it
when creating the first habit.

**Scheduler.** None.

**Effort.** S–M. **Depends on:** nothing; F1/F2 make the picker richer.

---

## F5. Anchor reliability check

**What.** When the user attaches a habit to a tracked parent whose adherence is weak, warn at
edit time: "Gym is at ~40% lately. Stacking on it will fail — pick a steadier anchor, or fix
Gym first." Also surface it later as an insight if a parent decays after the stack was built.

**Why.** The book says "choose a reliable anchor"; the app is the only thing that actually
knows whether the anchor is reliable.

**Model.** None. Uses `SchedulerState.mean` of the parent over its last 30 days.

**UI.** Inline warning in the depends-on picker (threshold: parent mean < 0.6 with n ≥ 5 days
of evidence). Insight card in Insights: "Stack at risk: <child> depends on <parent>, which
dropped to <x>%."

**Effort.** S. **Depends on:** nothing.

---

## F6. Never miss twice

**What.** Two consecutive *observed* misses on a habit trigger an explicit recovery state:
guaranteed daily questions until one yes, a "Get back on track" card, and (with F7) an offer to
do the minimal version today.

**Why.** Missing once is noise; missing twice is the start of a new pattern. The scheduler
already asks daily when the mean is below target, but it can take several misses for the mean
to get there. This makes the second miss the event.

**Model.** `SchedulerState.consecutiveObservedMisses: Int` (reset on any yes/health/aggregated
value ≥ 0.5). Add `DueReason.recovery`.

**Scheduler.** `isDue` returns `.recovery` when `consecutiveObservedMisses >= 2`; recovery
outranks everything but re-entry checks in prioritization.

**UI.** Card variant with recovery copy and, if F7 exists, a "Just the 2-minute version" button.
Notification copy changes accordingly. Chart: mark recovery episodes on the habit timeline and
count "recoveries" (episodes that ended in a yes) as a stat.

**Effort.** S. **Depends on:** nothing; pairs with F7.

---

## F7. Two-minute (minimal) version

**What.** Each habit may define a `minimalVersion` ("put on running shoes", "one push-up").
When the habit is struggling or in recovery, the card offers the minimal version. Answers
record whether the full or minimal version was done.

**Why.** Showing up is the vote; lowering the bar during a slump keeps the identity intact and
gets the user back to the full version faster than a string of no's.

**Model.** `Habit.minimalVersion: String?`; `AnswerValue.yes(minimal: Bool)` (and a
`minimalCount` in `.count`). `DayRecord.minimal: Bool`.

**Projection.** Minimal counts as value 1.0 for adherence (decision: it is a yes). Track the
full/minimal split separately for charts.

**Scheduler.** Offer the minimal option when `mean < targetAdherence` or in F6 recovery.
Insight: if ≥ 70% of the last 14 yeses were minimal, suggest either accepting the minimal
version as the real habit or planning a step up.

**UI.** Editor field; three-button card (Full / Minimal / No) in the offering state, standard
two-button card otherwise; minimal days hatched differently on the heatmap.

**Effort.** M. **Depends on:** nothing; pairs with F6 and F9.

---

## F8. Habit scorecard onboarding

**What.** First-run flow that asks "What do you already do every day?" and turns the answers
into anchors (F1) before the user creates their first habit. The first habit is then created by
stacking onto one of those anchors (F4 phrasing).

**Why.** Users who start from goals build fragile habits; users who start from existing routine
build stacks. It also produces a meaningful anchor list without the user understanding the
concept.

**Model.** None beyond F1.

**UI.** Two onboarding screens: a checklist of common anchors (wake up, coffee, brush teeth,
commute, lunch, get home, dinner, bed) with time-of-day chips and a free-text add; then the
"After ___, I will ___" habit creator. Skippable.

**Effort.** M. **Depends on:** F1 (F4 recommended).

---

## F9. Identity votes

**What.** Optional identity statement per habit ("I'm someone who trains"). The detail screen
shows total yes-days as *votes cast for that identity*, never reset by a miss.

**Why.** Reframes progress as accumulation rather than streak maintenance, which matches
Fade's no-streak stance. It is the same number as a completion count; only the framing differs.

**Model.** `Habit.identity: String?`. Votes = count of days with value ≥ 0.5 and source in
{observed, aggregated, health} (minimal yeses count; inferred days do not).

**UI.** Editor field; a "votes" tile on habit detail and an overall "votes this month" tile on
Insights; optional line on the card ("Vote #143 for: someone who trains").

**Effort.** S. **Depends on:** nothing.

---

## F10. Goldilocks insights (right-sizing difficulty)

**What.** Two insight rules using `targetAdherence`:
- *Too easy:* mean ≥ 0.95 for 6+ weeks and interval at ceiling → suggest a harder version,
  stacking a new habit on top of it, or graduating it (F11).
- *Too hard:* mean ≤ 0.4 for 3+ weeks → suggest switching to the minimal version (F7),
  lowering the target, or splitting the habit.

**Why.** Habits stick at manageable difficulty; the app has the data to say when the
difficulty is wrong.

**Model.** None. **Scheduler.** None.

**UI.** Insight cards with one-tap actions (open editor prefilled; set minimal as default).

**Effort.** S. **Depends on:** F7 for the "too hard" action, F11 for the "too easy" action.

---

## F11. Graduation (automatic habits)

**What.** When a habit has sat at `maxIntervalDays` for three consecutive cycles with every
check (including spot checks) answered yes, offer to graduate it: state `.automatic`, removed
from Today, spot-checked once per quarter, still charted. A failed quarterly check un-graduates it.

**Why.** The app's stated goal is to make itself unnecessary per habit. Graduation is that
goal made explicit, and it keeps the active list short.

**Model.** `Habit.status: .active | .automatic | .archived`; `SchedulerState.cyclesAtCeiling`.
Quarterly check reuses `forcedReentryCheck` on a 90-day timer.

**Scheduler.** `.automatic` habits are excluded from candidates except on their quarterly day.
Vacation mode ignores them.

**UI.** Celebration sheet on graduation; "Automatic" section at the bottom of the habit list;
Insights tile "N habits on autopilot." Overall chart: graduated count over time.

**Effort.** M. **Depends on:** nothing.

---

## F12. Bad-habit polarity (inversion)

**What.** Habits can be `polarity = .avoid`. The behavior is phrased as abstaining ("Stayed off
alcohol today?") and yes still means adherence, so the model is unchanged.

**Why.** Breaking habits is half the book. Without polarity the phrasing is awkward and users
invert the meaning of yes/no by accident.

**Model.** `Habit.polarity: .build | .avoid` (default `.build`).

**UI.** Editor toggle; card/notification/widget copy generated from polarity; heatmap legend
reads "clean day" instead of "done." Dependencies work as normal (e.g. "no snacking" gated on
"ate dinner").

**Effort.** S. **Depends on:** nothing.

---

## F13. Environment cue: time and location (light)

**What.** Extend F4's `Intention.cueKind` so `.atTime` schedules a notification at that time
(only when due) and `.atLocation` optionally uses a geofence to make the notification fire on
arrival.

**Why.** Cues that are obvious in the environment beat reminders on a timer. Location is the
strongest cue for gym/library/kitchen habits.

**Model.** `Intention.location` becomes `{ name: String; coordinate: (lat, lon)?; radius: Double }`.

**UI.** Location picker (MapKit search) in the intention editor; a "cue reminders" toggle in
Notifications settings, separate from the cadence-based reminders.

**Scheduler.** None; this only changes *when* an already-due question is surfaced.

**Effort.** M (geofencing permissions, background delivery). **Depends on:** F4.

---

## Skipped on purpose

- **Temptation bundling** (pair a want with a need): a reward field nobody fills in; the
  fading-questions loop is already the reward.
- **Habit contracts / accountability partners**: social, out of scope by design.
- **Commitment devices / money on the line**: out of scope.
- **Streak-based motivation**: deliberately replaced by identity votes (F9) and never-miss-twice (F6).

## Suggested order if picking several

F1 → F2 → F4 → F6 → F7 → F9 → F11, then F3/F5/F8/F10/F12/F13 as desired. F1+F2+F4 together
turn "dependent habits" into real habit stacking; F6+F7 are the recovery loop; F9+F11 are
the motivational framing.
