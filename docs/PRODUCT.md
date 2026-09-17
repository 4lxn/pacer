# Pacer (was Autopiloto) — product plan (v1 → store)

_2026-09-16. Owner: Alan. Status: core built, not yet in the store. CEO review done 2026-09-16; next-level plan below._

## One line

**Pacer — keeps your day on pace.** Pacer runs your day: a timeline of blocks that notifies you when each starts, one tap to
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


---

# Next level (from /plan-ceo-review, 2026-09-16)

Full record with every decision: `~/.gstack/projects/4lxn-autopiloto/ceo-plans/2026-09-16-autopilot-core.md`.

## Approach B — the day repairs itself, shipped in five PRs

| PR | Contents | Gate |
|---|---|---|
| PR1 ✅ | `Block.checkIn` (default on for window ≥ 20 min), one-shot check-ins at end+5 with Done/Skip today, `.skipped` per day, midnight fix (`notification.date`), PlanStore never overwrites an undecodable file, founder seed removed from the binary, onboarding teaches the long-press, `JSONFile` + persistence banner, BGAppRefresh re-arm, `skip_today` coach tool, Markdown chat rendering | TestFlight internal → ~10 external testers |
| PR2 | `Replanner` (pure) + `DayOverrides` + Undo + `DayMutator` + `REPLAN` action + Replan/Skip on missed rows + coach `move_today` / `skip_today` / `undo_replan` | Keep Replan only if ≥ 30 % of eligible check-ins choose Replan and ≥ 70 % are not undone after 2 weeks with ≥ 5 testers |
| PR3 | App Group (`defaultURL` change, no migration code) + Now/Next widget (systemSmall) sharing `Models/` + `DayLogic` | — |
| PR4 | HealthKit background delivery + Settings sheet + Diagnostics ("Copy report") + "Your week" (on-device only) | — |
| PR5 | Rename to **Pacer** after checking App Store name availability (own PR) + `docs/ARCHITECTURE.md` | — |

## NOT in scope (this round)
- Wake-relative day model for shift workers — calendar day only; `dayEnd` ≤ 23:59 (9A)
- Morning brief notification — validate replanning first (D5.2)
- Tab consolidation — tabs stay; revisit with check-in data (D5.3)
- Lock Screen widget family, Live Activity, Watch app, iCloud sync (D5.4/5.6, ceremony)
- Anonymous weekly metrics ping — reversed by CM5; privacy story stays "Analytics: none"
- `AppStores` environment container — deferred (CM6)
- App Group migration code — no users on the old path (CM4)
- One-shot start notifications — rejected (CM2): repeating triggers stay

## What already exists (reused)
`PlanStore.upsert` / `block(id:)`, `CompletionStore` per-day sets, `DayLogic.sorted / currentBlock / status`, `NotificationScheduler.buildRequests` + `registerCategory`, `NotificationDelegate` background actions, `HealthStore.refresh` + `DayLogic.autoCompletions`, `CoachTools` executor + `CoachAgent` loop, `CoachContext.snapshot`, Liquid Glass components, 57 tests with injected `now`/`Calendar`.

## Dream state delta
12-month ideal: you open the phone, one notification says what was moved and why, one tap agrees; the app is a widget and a coach. After PR1–PR4 we are at: check-ins from the lock screen, self-repairing day behind a kill criterion, widget, health auto-close. Missing: morning brief, Live Activity, Watch, sync, wake-relative day.

## Error & rescue registry
| Codepath | What can go wrong | Error | Rescued | Action / user sees |
|---|---|---|---|---|
| Check-in re-arm | add throws / > 64 | UNError | Y | soonest-first cap, log, Diagnostics count |
| Delegate REPLAN/SKIP | block deleted / already done | nil | Y | no-op, log, widget reload |
| Replanner | no gap ≥ 20 min / now ≥ dayEnd | `.skipped` | Y | "No room for X today — it's back tomorrow" |
| Undo | stale / other day | — | Y | "Nothing to undo" |
| JSONFile.save | disk write fails | CocoaError | Y (2A) | os_log, red banner, Diagnostics |
| Store load | file undecodable | DecodingError | Y | rename `.bad`, banner, start empty (never overwrite) |
| HK enableBackgroundDelivery | throws / denied | HKError | Y | log; check-ins still fire |
| HK observer handler | refresh throws | HKError | Y | log; completion handler always called |
| BGAppRefresh | expires | — | Y | `setTaskCompleted(false)` |
| Widget provider | JSON unreadable | DecodingError | Y | "Open Pacer" placeholder |

## Failure modes registry
| Codepath | Failure | Rescued | Test | User sees | Logged |
|---|---|---|---|---|---|
| Check-in scheduling | over 64 | Y | Y | Diagnostics count | Y |
| Check-in fire | block done meanwhile | Y | Y | nothing (cancelled) | Y |
| Replan | no room | Y | Y | notification | Y |
| Replan | push past dayEnd | Y | Y | named in notification | Y |
| Undo | stale | Y | Y | notification | Y |
| Persistence | write/read failure | Y | Y | banner | Y |
| HK background | denied / late sync | Y | manual | check-in fires anyway | Y |
| Widget | no data | Y | manual | placeholder | — |
No CRITICAL GAPS (every row is rescued and visible).

## Diagrams

System:
```
Garmin ─▶ Apple Health ─▶ HealthStore (observer + bg delivery) ─┐
                                                                 ▼
UNUserNotificationCenter ◀─ NotificationScheduler ◀─ PlanStore ─┬─ CompletionStore (done/skipped per day)
  │ repeating start · one-shot check-ins       (template, dayEnd) │
  ▼                                                               ▼
NotificationDelegate ── Done/Skip/Replan/Undo ──▶ DayMutator ──▶ DayOverrides (today's moves) + undo.json
                                                     │  writes · re-arms · reloads widget · counters
App Group container ── read-only ──▶ AutopilotoWidget (now / next, 2-day timeline)
MetricsStore (on-device counters) ──▶ "Your week" card · Diagnostics report
```

Check-in / replan flow:
```
block end+5 ──▶ check-in (if not done) ──▶ [Done] ──▶ setDone ──▶ cancel today's check-in
                                       ├─▶ [Skip] ──▶ skipped ──▶ "Skipped X [Undo]"
                                       └─▶ [Replan] ─▶ Replanner ─┬─ moved/shrunk ─▶ overrides, start notif, check-in, "Moved X → HH:MM [Undo]"
                                                                  └─ no room ─────▶ skipped, "No room for X today"
shadow paths: nil block → drop+log · empty plan → no check-ins · stale Undo → "Nothing to undo"
```

Block state (per day):
```
upcoming → current → done
                 └─▶ check-in pending → done | skipped | replanned → upcoming' → current' → done
replanned ──Undo──▶ check-in pending      invalid: replan done/anchor (guarded), replan twice (replaces; Undo = previous only)
```

Error flow: any store write → JSONFile.save → (ok | error → os_log + lastPersistenceError → Today banner + Diagnostics counter).

Deployment: entitlements land via automatic signing on first archive → TestFlight internal (Alan, 1 week) → external testers → PR2 gated by the kill criterion → App Store after PR5.

Rollback: App Store builds don't roll back → Check-ins toggle off (PR1) · Replan toggle off (PR2) · remove widget (PR3) · Health auto-close off (PR4). No server changes in this plan.

## Stale diagram audit
No ASCII diagrams exist in the repo yet; `docs/ARCHITECTURE.md` (PR5) will carry these and must change with the flow.

## Scope expansion decisions
Accepted: HealthKit background delivery · Now/Next widget (systemSmall) · on-device metrics + "Your week". Deferred: morning brief · Live Activity · Lock Screen family · Watch · iCloud · metrics ping · AppStores. Skipped: tab consolidation.

## Implementation Tasks
Synthesized from this review's findings. Each task derives from a specific finding above. Run with Claude Code; checkbox as you ship.

- [x] **T1 (P1, human: ~1 day / CC: ~45 min)** — PR1 notifications — Per-block `checkIn` flag, one-shot check-ins at end+5 (today+tomorrow), category `CHECK_IN` with Done/Skip, `dayKey` in userInfo, `notification.date` for Done, 4-method center wrapper, ≤ 64 test
  - Surfaced by: Section 1 (1C→CM2), CM3, spec round 1 #9/#29
  - Files: Sources/Models/Block.swift, Sources/Notifications/NotificationScheduler.swift, NotificationDelegate.swift, Views/BlockEditor.swift, Tests/SchedulerTests.swift
  - Verify: `xcodebuild test`; simctl push a `CHECK_IN` payload → Done marks the right day
- [x] **T2 (P1, human: ~half day / CC: ~30 min)** — PR1 stores — `.skipped` per day in CompletionStore, `BlockStatus.skipped`, N excludes skipped, `JSONFile.load/save` with `lastPersistenceError` + Today banner, never overwrite undecodable files, `settings.json` with `dayEnd` (clamped, sleep<wake rule)
  - Surfaced by: Section 2 (2A), spec round 3 #1/#6, outside voice #10
  - Files: Sources/Store/*, Sources/Models/BlockStatus.swift, Views/DayView.swift, Tests/CompletionStoreTests.swift
  - Verify: read-only URL test; `.bad` rename test; legacy array file loads
- [x] **T3 (P1, human: ~2 h / CC: ~15 min)** — PR1 product — Remove `CoachContext.training` seed and personal labels from `Plan.blocks`; starter never emits post-midnight blocks; onboarding step 2 teaches the long-press
  - Surfaced by: outside voice #4, #10, #15; PRODUCT.md roadmap item 4
  - Files: Sources/Coach/CoachContext.swift, Sources/Models/Plan.swift, Views/OnboardingView.swift
  - Verify: grep for "Minoxidil|retatrutide" in Sources returns nothing; starter test with sleep 00:30
- [x] **T4 (P1, human: ~1.5 days / CC: ~1 h)** — PR2 replan — `Replanner.replan/place` (pure) + `DayOverrides` + `undo.json` + `DayMutator` + `REPLAN`/`UNDO` actions + Replan/Skip on missed NowCard and rows + `DayLogic.effectivePlan`
  - Surfaced by: Section 1 (1A, 1D), D7, spec rounds 2–3 (#8, #9, #4, #10 of r3)
  - Files: Sources/Models/Replanner.swift, DayOverrides.swift, Sources/Store/DayOverridesStore.swift, DayMutator.swift, Views/NowCard.swift, BlockRow.swift, Tests/ReplannerTests.swift
  - Verify: 12 Replanner cases; delegate test: Replan on deleted block is a no-op
- [x] **T5 (P2, human: ~2 h / CC: ~15 min)** — PR2 coach — `move_today` (→ `Replanner.place`), `skip_today`, `undo_replan`; `update_block` marked permanent; snapshot uses effective plan; kill-criterion counters
  - Surfaced by: spec round 1 #33, outside voice #7, #16
  - Files: Sources/Coach/CoachTools.swift, CoachContext.swift, Tests/CoachAgentTests.swift
  - Verify: tool executor test walks every definition
- [x] **T6 (P2, human: ~2 days / CC: ~1 h)** — PR3 widget — App Group entitlement on both targets, `defaultURL` → group container for the 5 day files, `AutopilotoWidget` target (systemSmall, 2-day timeline, 5 states, deep link), `WorkoutMatch` + `clock` moved to shared code
  - Surfaced by: D5.4, 1B→CM4, spec round 3 #5/#9, 1E
  - Files: project.yml, Sources/Models/*, Widget/*, Sources/Store/*
  - Verify: widget renders 5 states in the simulator; Alan copies his files once before installing
- [x] **T7 (P2, human: ~1.5 days / CC: ~1 h)** — PR4 health + settings — `healthkit.background-delivery` entitlement, `HKObserverQuery` in AppDelegate (completion always called), Settings sheet (Check-ins toggle, profile), Diagnostics (permission, pending/64, last re-arm, last HK delivery, last persistence error, counters, Copy report), `MetricsStore` + "Your week"
  - Surfaced by: D5.1, 8A, CM5, spec round 2 #17, outside voice #14
  - Files: project.yml, Sources/AutopilotoApp.swift, Sources/Health/HealthStore.swift, Sources/Metrics/MetricsStore.swift, Views/SettingsView.swift, DiagnosticsView.swift
  - Verify: on device — Garmin run closes Run at first unlock; Diagnostics shows counts
- [x] **T8 (P3, human: ~half day / CC: ~30 min)** — PR5 name + docs — Check "Pacer" availability in App Store Connect, rename display/App Store name/README/docs (bundle id unchanged), `docs/ARCHITECTURE.md` with the diagrams above, update README notification/network claims and the simctl payload
  - Surfaced by: naming decision, TODO-1, spec round 3 #12, outside voice #9
  - Files: project.yml, README.md, docs/*
  - Verify: `grep -ri autopiloto README.md docs/` returns only historical mentions
- [ ] **T9 (P3, human: ~1 h / CC: ~10 min)** — Design — Run `/plan-design-review` on notification copy, NowCard missed state, widget states, "Your week"
  - Surfaced by: Section 11
  - Verify: review report attached before PR2

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 1 | CLEAN | mode SELECTIVE_EXPANSION, 6 proposals (3 accepted, 2 deferred, 1 skipped), 15 decisions, 0 unresolved, 0 critical gaps |
| Outside Review | Claude subagent (Codex not installed) | Independent 2nd opinion | 1 | ISSUES_FOUND (outside_status: unavailable) | 17 problems; 6 cross-model tensions resolved (CM1–CM6) |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 0 | — | — |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | — | — |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | — | — |

- **OUTSIDE COVERAGE:** provider codex — unavailable (not installed); native fallback (Claude subagent, same harness, model identity unknown) completed with 17 findings. Spec loop: 3 rounds (5/10 → 7/10 → 7/10), 60 issues incorporated.
- **VERDICT:** CEO CLEARED — eng review required before implementation (`/plan-eng-review` on PR1's plan).

NO UNRESOLVED DECISIONS


## Status 2026-09-16 (evening)

PR1–PR6 merged (#13–#19): check-ins, replan + undo, widget over an App Group, Health background
delivery, Settings + Diagnostics + on-device metrics, Pacer name + icon, Today polish. Build 1.0 (4)
uploaded to TestFlight. Open: T9 design review; Paid Apps agreement → Active before the sandbox
subscription can be tested; the Replan kill criterion is read from Diagnostics after 2 weeks.
