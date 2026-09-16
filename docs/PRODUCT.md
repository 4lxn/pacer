# Autopiloto — product plan (v1 → store)

_2026-09-16. Owner: Alan. Status: core built, not yet in the store._

## One line

Autopiloto runs your day: a timeline of blocks that notifies you when each starts, one tap to
confirm from the lock screen, blocks that close themselves from Apple Health, and a coach that
knows your plan and your body — and can change any of it by chat.

## Who it's for

People whose routine fails silently: ADHD adults, remote/shift workers, anyone juggling training +
work + habits. Single-player. Not teams.

## What exists today (merged, 57 tests, iOS 26, Liquid Glass)

| Tab | What it does |
|---|---|
| Today | Current block in large type, minutes left, Done; overdue fallback; up next; full day list; editable plan (blocks, times, weekdays, anchor, auto-complete); onboarding from wake/sleep times |
| Train | Apple Health workouts (Garmin/Strava/Watch write there) with source, week totals, weight chart + log; Run/Gym blocks auto-complete |
| Food | Macros vs daily targets, one-tap presets, meals log, pantry with minimums → shareable grocery list |
| Life | Study timer (survives relaunch, closes the Study block at 20 min), income by month/source, closet: multi-photo scan → Claude vision names garments, outfit of the day (weather/style, one accent colour, no repeats), laundry pile |
| Coach | Persistent chat agent with 32 tools: add/change/delete anything above, memory (`remember`/`forget`), editable profile as system prompt; own API key or subscription via Sign in with Apple + Railway proxy (rate-limited) |

Notifications: repeating local triggers per fixed block, Done / Snooze 10 min actions, anchor
breaks through Focus. Everything offline except the Coach.

## Why it can win

Structured, Routinery, TickTick, Streaks, Fabulous do the timeline or the streak. None of them:
1. work notification-first with lock-screen actions,
2. close blocks from real-world data (a run on your watch marks Run done),
3. have an agent that knows your plan + health + food + closet and can edit them by chat.

## Business

Free app; Coach subscription USD 4.99/month, 1-week trial. Cost per question ≈ USD 0.01–0.02
(`claude-opus-5`, cached system prompt, 40 questions/day cap). Break-even per subscriber at
~250 questions/month. Proxy on Railway Hobby (~USD 1/month idle).

## Roadmap to the store

| # | Item | Status |
|---|---|---|
| 1 | Core (M1–M9 above) | done |
| 2 | ASC app record + subscription product | Alan, pending |
| 3 | Privacy policy hosted, App Privacy answers, review notes, screenshots | docs written; hosting + screenshots pending |
| 4 | Remove the founder's personal seed data from the binary | pending (one command) |
| 5 | TestFlight → App Review | pending |

## Known gaps (honest list)

- No streaming in the Coach; answers arrive whole (3–10 s).
- Proxy trusts the client's subscription (rate limit per Apple id is the only guard); no App Store
  Server API verification yet. Daily counter is in memory (resets on redeploy).
- No iCloud sync / multi-device; JSON files on one iPhone.
- No weather API (manual cold/mild/hot); no widgets, no Watch app, no Live Activities.
- Auto-complete polls on foreground; no HealthKit background delivery yet.
- Coach profile is free text the user must write; onboarding doesn't build it.
- Store listing copy and screenshots not produced; no icon variants (dark/tinted).
- Metrics: none. No way to know retention, notification action rate, or coach usage.

## Success metrics (after launch)

Day-7 retention, % of fixed-block notifications acted on (Done/Snooze), coach questions per
active user per week, trial → paid conversion.
