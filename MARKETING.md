# Marketing copy

Drafts for GitHub, the App Store, and launch posts. Keep App Store copy limited to shipped
features: no "Coming later" items, and no mention of Anki or _Atomic Habits_ (App Store
guideline 2.3.7 bans other apps' names and trademarks in metadata).

## GitHub description

1. **Anki for habits: a tracker that asks less the better you do.** (preferred)
2. Spaced repetition for habits. Check-ins fade as your consistency grows.
3. A habit tracker with an Anki-style scheduler: struggle and it asks daily, succeed and it
   backs off.

## Taglines

- The habit tracker that asks less the better you do.
- Build the habit. Lose the checkbox.
- Fewer questions means real progress.
- Spaced repetition, for your life.
- The app that gets out of your way.
- Your progress is how rarely we ask.
- No streaks to break, just habits that stick.

## App Store

### Subtitle (30 characters max)

- `Habits that ask less over time` (30)
- `Check in less as you improve` (28)
- `Spaced repetition for habits` (28)
- `Fewer check-ins, real habits` (28)

### Promotional text (170 max, can be changed without a new app review)

> Most habit apps ask every day, forever. Spaced Habits asks less as you get consistent, so the
> app fades into the background while your habits stick.

### Keywords (100 max)

Words from the app name and subtitle are already indexed, so they aren't repeated here.

```
tracker,routine,daily,goals,streak,reminder,self,improvement,watch,widget,productivity,discipline
```

(97 characters. "streak" is a popular search term even though the app avoids streaks.)

### Description

**The habit tracker that asks less the better you do.**
Most habit apps make you tick a box every day, forever. Spaced Habits uses the idea behind
spaced-repetition flashcards: once you've shown you can keep a habit, it stops asking so
often. If you're struggling, it checks in daily. If you're consistent, it's weekly, then rarely.
**A few quick questions, then you're done**
Open the app and answer a handful of questions: "Did you go to the gym today?" If it's been a
while, it asks "How many of the last five days?" instead.
**Progress you can see**
As a habit sticks, the gap between check-ins grows. Charts show that gap per habit, along with
adherence trends and a "questions per day" line that should keep dropping.
**Honest by design**
Days you answered and days the app filled in are always shown differently. There are no fake
streaks.
**Built for real life**
• Connected habits: if you skipped the gym, it won't ask about your protein shake.
• Delay, don't fail: pause a habit for a week and your progress is kept.
• Vacation mode: one switch pauses everything except the habits you choose.
• Reminders only when there's something to answer, and quiet hours are respected.
**Answer anywhere**
Answer from Home Screen and Lock Screen widgets, Apple Watch, Siri, or straight from a
notification. Everything stays in sync.
**Your data stays yours**
Your data is stored on your devices and in your own iCloud. Export everything to CSV or JSON
at any time.

### Screenshot captions

1. Answer a few questions, then you're done.
2. Doing well? It asks less.
3. Watch your check-in gap grow.
4. Honest history, no fake streaks.
5. Skipped the gym? It won't ask about the shake.
6. Answer from your wrist or Lock Screen.
7. Just tell Siri you did it.

### App Store Connect answers

- **App Privacy:** Data Not Collected. Habits live on the device and in the user's own iCloud
  (private CloudKit database), which Apple doesn't count as developer collection. Matches the
  privacy manifests (DESIGN.md §2).
- **Export compliance:** exempt; `ITSAppUsesNonExemptEncryption = NO` is in every build.
- **Privacy Policy URL:** `https://emira.ga/spaced-habits/privacy`
- **Support URL:** `https://emira.ga/spaced-habits/support`
- Apple Health isn't shipped (DESIGN.md O7). Add it back to the copy only when it is.

## Website pages

The published copies live on emira.ga; Settings → About links to both (`SettingsView`). Keep them
in sync with the app: when a feature, menu path or data flow changes, update the page here and on
the site.

### `https://emira.ga/spaced-habits/privacy`

```markdown
# Spaced Habits — Privacy Policy

*Last updated: 28 September 2026*

Spaced Habits does not collect any data. I (the developer) can't see your habits, answers, or anything else you enter.

## Where your data lives
- **On your devices.** Habits, answers, pauses and settings are stored on your iPhone and Apple Watch, shared with the app's widgets.
- **In your own iCloud, if you use iCloud.** The app syncs through your private iCloud database (Apple CloudKit). Only your Apple Account can read it. The developer can't. Apple's privacy policy covers iCloud.

## What the app doesn't do
- No accounts, analytics, advertising, or tracking.
- No third-party SDKs.
- No data sent to any server run by the developer.

## Notifications and Siri
Reminders are scheduled on your device. If you use Siri or Shortcuts to log a habit, Apple handles that request under its own privacy policy.

## Export and deletion
- **Export:** Settings → Your data exports everything as JSON or CSV at any time.
- **Delete:** delete the app to remove its data from a device. To remove the synced copy, go to iOS Settings → [your name] → iCloud → Manage Account Storage → Spaced Habits.

## Children
The app collects no data from anyone, including children.

## Changes
If this policy changes, the new version will be posted here with a new date.

## Contact
spacedhabits@emira.ga
```

### `https://emira.ga/spaced-habits/support`

```markdown
# Spaced Habits — Support

Questions, bugs or feature ideas: **spacedhabits@emira.ga**. I usually reply within a few days.

## FAQ

**Why doesn't it ask about every habit every day?**
That's the point. The better you keep a habit, the longer it waits before asking again. Struggle, and it asks daily again.

**What if I miss a few days of check-ins?**
Nothing breaks. Next time it asks how many of the last few days you did it.

**I'm going on vacation / I'm sick.**
Use Delay… on a card to pause one habit, or Vacation on the Today screen to pause them all. Your progress is kept.

**My data isn't syncing between devices.**
Make sure you're signed in to the same iCloud account on each device and that iCloud is on for Spaced Habits (iOS Settings → [your name] → iCloud). Sync can take a minute.

**How do I back up or move my data?**
Settings → Your data → Export (JSON or CSV). You can import the JSON file again on any device.

**Privacy:** [Privacy Policy](/spaced-habits/privacy)
```

## Short pitch

> Spaced Habits is a habit tracker built like a flashcard app. Habits you struggle with come up
> daily. Habits you've mastered fade to weekly, then rarely. The fewer questions it asks, the
> better you're doing.
