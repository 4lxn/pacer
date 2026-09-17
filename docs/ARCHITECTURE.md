# Architecture

Pacer is a single-user iOS app: SwiftUI + Swift 6 strict concurrency, no third-party code, JSON
files for state, local notifications for the loop, one optional network client (the Coach).

## The loop

```
plan.json (weekly template)      overrides.json (today's moves)
        └──────────────┬──────────────┘
                DayLogic.effectivePlan(day)          ← the only way to read "today"
                       │
   ┌───────────────────┼─────────────────────┐
   ▼                   ▼                     ▼
 Today tab        NotificationScheduler    Widget (DayTimeline)
 (NowCard, rows)   starts (repeating)       Now / Next entries
                   check-ins (one-shot)
                   moved starts (one-shot)
        │                  │
        ▼                  ▼  (Done / Move it later / Skip today / Undo)
              DayMutator  ── the single write point ──▶ CompletionStore (done/skipped per day)
              (app, notification, coach, Health)        DayStore (overrides, undo, settings)
                                                        MetricsStore (counters)
                       │
                       └─▶ re-arm check-ins + moved starts, reload widget
```

- **Template vs. today.** `PlanStore` holds the weekly blocks. `DayStore.overrides[dayKey]` holds
  today's moved times. `DayLogic.effectivePlan` merges them; nothing else reads `plan.blocks` to
  render a day. Replan never edits the template (the coach's `update_block` does, and says so).
- **One writer.** Every change to a day — done, skip, replan, move, undo, Health auto-close — goes
  through `DayMutator`. It records undo, writes the stores, counts the event, then queues the
  notification work (`rearm()`), which notification actions `flush()` before returning so iOS
  doesn't suspend the process mid-way.
- **Places.** A block can have a place; `Places` holds door-to-door minutes between pairs. Free gaps shrink by the travel from the previous obstacle and to the next; `place` rejects a time with no room for the commute; `DayLogic.travelLegs` drives the "leave by" hints and the one-shot `leave-<id>-<day>` reminders.
- **Replanner** is pure: obstacles = fixed blocks not done, the current window, done blocks; the
  block goes in the first free gap ≥ its length after `max(now, end)`, else shrinks into the largest
  gap ≥ 20 min, else "no room" (skipped today, undoable). Later windows cascade forward and drop
  when they would end after the day end (`settings.json`, calendar-day model, ≤ 23:59).

## Notifications

| Kind | Identifier | Trigger | Category / actions |
|---|---|---|---|
| Start | `<blockId>` or `<blockId>-wd<n>` | repeating calendar | `BLOCK_ACTIONS`: Done, Snooze 10 min |
| Snooze | `<blockId>-snooze` | +10 min | `BLOCK_ACTIONS` |
| Check-in | `checkin-<blockId>-<dayKey>` | end + 5 min, today + tomorrow | `CHECK_IN`: Done, Move it later, Skip today |
| Moved start | `moved-<blockId>-<dayKey>` | new start, one-shot | `BLOCK_ACTIONS` |
| Leave | `leave-<blockId>-<dayKey>` | start − travel, one-shot | — |
| Morning brief | `brief-<dayKey>` | first block's end, one-shot | — |
| Replan result | `replan-<uuid>` | immediate (only from a notification action) | `REPLAN_UNDO`: Undo |

Repeating starts survive force-quit; one-shots are re-armed after every mutation, on foreground, by
a `BGAppRefreshTask` (`com.alan.autopiloto.rearm`) and by the Health observer. The 64 pending cap is
enforced soonest-first. `NotificationCenterClient` wraps `UNUserNotificationCenter` so all of this
is tested with a fake.

## Persistence

`AppFiles.directory` = the App Group container (`group.com.alan.autopiloto`), shared with the
widget; a one-time move from Application Support runs at launch. `JSONFile.load/save` is the only
disk path: atomic writes, undecodable files renamed `.bad`, every failure into `PersistenceState`
(Today banner + Diagnostics).

| File | Store | Shape |
|---|---|---|
| `plan.json` | `PlanStore` | `[Block]` |
| `completions.json` | `CompletionStore` | `[dayKey: {done, skipped}]` |
| `overrides.json`, `undo.json`, `settings.json`, `places.json` | `DayStore` | moves / one-offs / notes per day, one `UndoRecord`, `{dayEnd, checkInsEnabled}`, places + travel minutes |
| `metrics.json` | `MetricsStore` | counters per day + timestamps (device only) |
| `food.json`, `track.json`, `wardrobe.json`, `chat.json` | Food / Track / Wardrobe / CoachChat | — |

Coach profile: `UserDefaults`. API key and session token: Keychain (`APIKeyStore`).

## Coach

`CoachAgent` runs a Messages API tool loop (`claude-opus-5`) with `CoachTools` (35 tools) executing
on the main actor against the stores — including `move_today` / `skip_today` / `undo_replan` through
`DayMutator`. The system prompt = profile (cached) + `CoachContext.snapshot` over the effective plan.
Requests go to `server/` (Railway: Sign in with Apple → session token, StoreKit subscription, daily
limit) or directly with the user's own key.

## Sections

`AppSection` is the registry (title, symbol, tint, pitch, coach tool prefixes); `SectionStore` keeps the enabled list + order in `sections.json`. `RootView` renders tabs from it; Settings → Sections toggles/reorders; the coach filters tools and snapshot by what's on. Each section is one file pair (store + view): Train (`HealthStore`/`TrainView`), Food, Focus + Money (`TrackStore`, `FocusView`, `MoneyView`), Closet (`WardrobeStore`/`WardrobeView` + `WeatherNow` via WeatherKit).

## Siri / Shortcuts

`Sources/Intents/PacerIntents.swift`: What's next, Mark done, Move later, Start/Stop focus, Log water, Log weight; they reach the live stores through `AppDelegate.shared`.

## Targets

- `Autopiloto` — the app (display name Pacer, bundle `com.alan.autopiloto`).
- `AutopilotoWidget` — Live Activity (`PacerLiveActivity`: Dynamic Island + Lock Screen, Done via `MarkDoneIntent` → app process → `DayMutator`), Now/Next (small · medium · large · Lock Screen rectangular · inline) and Day progress (Lock Screen circular · small), one `DayTimeline` provider; shares `Models/` + `Store/{AppFiles,JSONFile,PlanStore,CompletionStore,DayStore}`.
- `AutopilotoTests` — pure logic first: Replanner, DayTimeline, DayMutator, scheduler, delegate, tools.

`project.yml` (XcodeGen) is the source of truth for targets, entitlements and Info.plist keys.
