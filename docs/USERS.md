# What the users say (community research, 2026-09-21)

Sources: r/ADHD and r/adhdwomen threads surfaced through search snippets (Reddit itself blocks
automated reading; pullpush rate-limits agents, so this is snippet-level, not full-thread), the
Tiimo public feedback board titles, Structured's App Store reviews via a review mirror, and the
ADDitude time-blindness article. Quotes are paraphrased. The point is the needs, ranked by how
often they came up, and what Pacer does about each.

## Needs, ranked

| # | Need | Evidence | Pacer today | Gap → where it lands |
|---|---|---|---|---|
| 1 | **Make time concrete.** Visual timers, "minutes left", a pre-timer 5 min before a block ends, alarms you cannot snooze into oblivion, buffers (people multiply estimates by 3). | Every time-blindness thread; Tiimo's whole pitch; ADDitude tactics. | Minutes left on the Now card and Live Activity; leave-by with travel; check-in at block end. | No "5 min left" nudge; no countdown ring on the lock screen; the app never learns that a block always overruns. → Pace line + ring in the Live Activity (step 2); "ends in 5 min" notification for blocks ≥ 30 min (step 2). |
| 2 | **Capture in seconds.** "A minute to create a task is too long" is the top Structured complaint; voice capture wins in every ADHD roundup. | Structured reviews; Voiset/Tiimo positioning. | "Just for today" sheet (label + times); Ask can add blocks by chat. | Ask is a tab, not a one-tap sheet; no voice; the weekly plan editor is a form. → Ask sheet from Now with mic (step 1/3); natural-language quick add "gym 7pm" (step 3). |
| 3 | **Miss without shame, then fix it.** Users praise Finch for no punishment; the top Tiimo requests are "skip / mark incomplete", "move unfinished to tomorrow", "remind me at the end of the day to reschedule". | r/adhdwomen Finch threads; Tiimo board #126, #273, #133. | Check-in with Done / Move it later / Skip; replan with undo; evening review; carry to tomorrow for non-daily blocks. | Tone and visuals still count misses in red; streak resets to zero. → Pace with one free miss a week, review shows what went right first (step 2). |
| 4 | **Notifications that are actionable and not spammy.** Duplicate notifications get everything muted; people want reminders *before* a block, custom sounds, per-task control. | Structured reviews (4 duplicate notifications), adhdwomen visual-timer thread. | Start + check-in + leave-by + morning brief, all with actions; custom chime; 64-cap. | No per-block "quiet" switch; a busy day fires many; no before-start reminder without a place. → per-block notification toggle and a global "only check-ins" mode (step 2). |
| 5 | **Setup must be cheap and never lose work.** "So much work entering routines got lost" (trial ended), "it spit out a ton of tasks", "couldn't delete tasks I didn't need". | adhdwomen threads on routine apps, Me+. | Starter plan from wake/sleep; export; everything editable. | Onboarding has 11 steps and free-text questions; no templates; no import. → goal chips → templates, profile as chips, 5 screens max (step 3); calendar import as obstacles (later). |
| 6 | **They forget the app exists by day 2.** "Whenever I download an app I forget about it two days later." | r/ADHD "apps that actually help". | Notification-first by design; widgets; Live Activity; morning brief. | Onboarding never puts the widget on the home screen or shows the Live Activity; no day-2 moment. → onboarding ends on a running day with the Live Activity visible and a "add the widget" card (step 3). |
| 7 | **Looking back feels good.** "I LOVE tracking things and looking back at statistics." | r/adhdwomen. | 14-day strip, streak, Your week in Settings. | Buried; no month view; nothing to show a friend. → Pace surface (step 2). |
| 8 | **Someone asking "did you…?"** Due asking at noon "did you eat?" is cited as the thing that works. | r/ADHD time-blindness thread. | This is Pacer's core loop. | Keep it central; the check-in must stay one tap from the lock screen. Measure it (step 4). |
| 9 | **Meetings and appointments live in the calendar.** Calendar import is the most requested Structured feature; reclaim.ai users say "putting it on my calendar is the only thing that works". | Structured reviews; r/ADHD planner threads. | Nothing. | Read-only EventKit import as replanner obstacles, on device. → after step 4 (privacy-compatible, no sync). |
| 10 | **Reliability.** Bugs after updates, double notifications, sync failures, unhelpful support. | Structured, Routinery reviews. | 115 tests, no CI. | No CI, no crash reporting. → CI on PRs (step 4), anonymous crash-free rate. |

## What this changes in the v3 plan

- Step 2 grows: "ends in 5 min" nudge for long blocks, per-block notification switch, and the
  countdown ring in the Live Activity. Time-concreteness is need #1, not a nice-to-have.
- Step 3 confirmed: chips over text everywhere in onboarding; the last screen is a running day.
- New item after step 4: **Calendar as obstacles** (EventKit, read-only, on device).
- Voice capture in Ask moves up: it is the answer to need #2, not a later polish.

## Segment notes

- r/adhdwomen is where routine and self-care apps are discussed most (Finch, Me+, routine
  timers); r/ADHD threads are about time blindness and planners. Both ban promotion; the
  language above is what to use in copy and in the TestFlight post elsewhere.
- Recurring words to reuse: "actually works", "forget about it", "time blindness", "doesn't
  punish you", "carry over or disappear (my choice)", "asks me".
