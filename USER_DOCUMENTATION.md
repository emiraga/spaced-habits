# Spaced Habits — User Guide

Spaced Habits asks about each habit only as often as it needs to. Habits you keep well get asked
about less and less, up to about every two weeks. Habits you struggle with get asked about every day.
The better you do, the less the app bothers you.

## Today screen

The main screen. It shows a few question cards at the top (3 by default), then a list of all your
habits with a status symbol for today.

- **Pull down to refresh** to re-plan the questions. Anything you put off with "Later" comes back.
- **Nothing to ask** means no habit needs a check-in right now. The screen tells you which habit is
  next and when.
- **More…** appears when more habits are due than fit in one session. It shows the next batch.
- **Reorder:** touch and hold a habit, then drag it onto another habit in the same group to move it
  there. Drag a cluster's name onto another cluster's name to reorder the groups. The order also
  applies on Apple Watch.
- **Quick actions:** touch and hold a habit (without dragging) for Edit, Pause…, Archive and Delete….

### Status symbols

| Symbol | Meaning |
| --- | --- |
| ✓ | You said you did it |
| ✗ | You said you didn't |
| ◐ | Answered as a count ("4 of 6 days"), so this exact day isn't known |
| ≈ | Not asked; the app estimated it from your usual pattern |
| ? | Unknown |
| ⏸ | Paused |
| ⛔ | Blocked, because a habit it depends on is paused |
| ○ | Due today, not answered yet |
| · | Not due today |

## Question cards

A card asks about the days since you last answered, up to 7 days back (you can change this per habit).

- **One day:** "Did you do it today?" with **Yes** / **No**.
- **2 days:** one toggle per day. If you usually do the habit, the toggles start switched on.
- **3 or more days:** "How many of the last N days?" with a stepper and quick buttons for
  *None / Some / Most / All*.

Every card also has:

- **Don't remember:** records that you don't know. It isn't counted as done or not done.
- **Delay…:** pauses the habit for 1, 3, 7, 14 or a custom number of days, starting today. You won't be
  asked about it during the pause, and the pause doesn't count against you.
- **Later:** hides the card until the next time you open the app or pull to refresh. Nothing is
  recorded and the habit stays due.

Touch and hold a card for a menu with Later, Delay… and Edit (to change, archive or delete the habit).

Tapped the wrong answer? For 5 seconds after answering, an **Undo** bar appears at the bottom of the
screen. Undo removes the answer (and the pause, if you chose Delay…) and brings the card back.

Days older than the question's range aren't asked about. The app estimates them from your usual
pattern instead, because it's hard to remember that far back accurately.

## Habits

### Adding and editing

- **Name, emoji, color.**
- **Importance** (low / normal / high): more important habits are asked about first when many are due.
- **Advanced**
  - **Target:** how often you aim to do the habit. Below target, the app asks every day.
  - **Max recall gap:** how many days back a single question may ask about (default 7).
- **When on vacation:** pause or keep this habit when vacation mode is on.
- **Depends on:** see *Connected habits* below.
- **Cluster:** a named group, used to organize the habit list and for group charts. Editing a cluster
  lets you rename, recolor or delete it; deleting a cluster keeps its habits, just ungrouped.
- **Archive habit:** hides the habit and stops asking about it. Its history is kept, and you can
  restore it from Settings → Archived habits.
- **Delete habit…:** permanently deletes the habit and its whole history on all your devices. Export
  your data first if you might want it back.

### Habit detail

Tap a habit to see:

- How often it's being asked ("Asking every ~9 days"). A rising number means the habit is becoming
  automatic.
- How often you've done it in the last 30 days.
- Charts and a history calendar.
- When a paused habit resumes, with options to extend or end the pause.
- The habits it depends on and the habits that depend on it.

### Connected habits

A habit can depend on another one, e.g. *Protein shake* depends on *Gym*.

- You're only asked about the shake for days you went to the gym.
- Questions read like "You did Gym on 4 of 6 days. On how many of those did you have a shake?"
- If Gym is paused, the shake is shown as blocked (⛔) rather than missed.
- The app won't let you create a loop (A needs B, B needs A).

## Pauses and vacation

- **Pause a habit** from a card (Delay…) or from habit detail. From habit detail you can also backdate
  a pause ("I was sick the last 3 days") or schedule one for later.
- **End now** stops a pause early. The habit is asked about on its next day back.
- **Vacation mode** pauses many habits at once. Choose dates (they can be in the future) and which habits
  to keep. The app remembers your choices for next time. You can also silence all notifications for
  the vacation.
- Paused days never count against you, and the app's picture of the habit is frozen while it's paused.
- After a pause, you're always asked about the habit on the first day back.
- If you often delay the same habit, Insights suggests lowering its target or archiving it.

## Notifications

Settings → Notifications:

- **Remind me:** every day at chosen times, or every few days ("if I haven't checked in for N days").
- **Only when something is due:** skips reminders when there's nothing to answer.
- **Quiet hours:** reminders that fall in this window are skipped.
- **Nudge me when I go quiet:** one notification after several days without an answer. It offers to
  turn on vacation mode for that period.

A reminder for a single habit can be answered right from the notification with **Yes**, **No** or
**Later**. Several due habits are combined into one notification ("3 habits to review"), and tapping
it opens the app. Paused habits never get notifications.

## Insights

- **Questions per day:** should go down over time.
- **Autonomy score:** the average time between check-ins across your habits. Higher is better.
- **Regressions:** habits whose last 2 weeks are clearly worse than the month before.
- **Day-of-week heatmap:** which weekdays go well or badly.
- **Cluster charts:** how connected habits relate (e.g. how often a shake follows gym).
- **Include paused days:** when on, paused days count as not done. Off by default.

Charts only appear once a habit has at least 7 unpaused days of data. Estimated days are never counted
as done.

## Widgets and Siri

- **Question widget** (Home Screen, Lock Screen, StandBy): shows the top question with Yes / No buttons.
  Questions that cover several days need the app, so tapping opens it.
- **Status widget:** your habits with today's symbols, or "N due" on the Lock Screen. Tap a habit to
  open it.
- **Siri / Shortcuts:** "Log *habit* in Spaced Habits", "Delay *habit* in Spaced Habits",
  "Review habits in Spaced Habits".

## Apple Watch

- **Today:** the same question cards as on the phone. Delay offers 1, 3, 7 or 14 days.
- **Habits:** tap one for the last 7 days, how often it's asked, and the next check-in.
- **Complications and Smart Stack:** the status and question widgets.
- Works without the phone nearby and catches up when they reconnect. Adding, editing, charts,
  backdated pauses and vacations are on the iPhone only.

## Settings

- **Questions per session:** how many cards are shown at once (1–10, default 3).
- **Day starts at:** answers before this hour count for the previous day. Useful if you're up past midnight.
- **Archived habits:** restore an archived habit, or swipe left to delete it. Shown only when you
  have archived habits.
- **Sync:** habits and answers sync to your other devices through iCloud. Without iCloud everything
  still works on the device.
- **Your data**
  - **Export** as CSV (spreadsheets) or JSON (a full backup).
  - **Import JSON** adds a backup's data to what's already there. It never deletes anything.
- **About:** version, help and privacy policy.
