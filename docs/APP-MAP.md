# App map and gaps (build 20, 2026-09-21)

Every surface a user can reach, how they get there, and what is missing. Gaps are tagged with
the v3 step that closes them (`docs/PRODUCT.md`), or `later`.

## Entry points

| Entry | Leads to | Gap |
|---|---|---|
| App icon | Today tab (last tab is not remembered) | Remember last tab? No: Now is always right. Keep. |
| Notification: block start (`BLOCK_ACTIONS` Done / Snooze) | Nothing opens; actions run in the background | ok |
| Notification: check-in (`CHECK_IN` Done / Move it later / Skip) | Same | Copy says "did it happen?"; keep. Add "ends in 5 min" for long blocks (step 2). |
| Notification: leave-by, moved, morning brief, `REPLAN_UNDO` | Same | ok |
| Widgets: now-next (S/M/L/lock rect/inline), day-list (M/L), day-progress (circular/S) | `autopiloto://today` | Stale when the app is closed (no push). Widget never suggested in onboarding (step 3). |
| Live Activities: block, focus | `autopiloto://today`, `autopiloto://focus` | No countdown ring, no pace line (step 2); stale when closed (later: APNs). |
| Siri / Shortcuts: What's next, Mark done, Move later, Start/Stop focus, Log water, Log weight | Runs in app process | Fine; unadvertised. |
| URL scheme `autopiloto://<section>` | Selects a tab | If the section is off, nothing happens. Route `coach` to the Ask sheet (step 1). |

## Surfaces

### Onboarding (11 steps)
times → notifications → sections toggles → "Where's home?" → coach intro → 5 free-text
questions → done.
Gaps: too long; home question is intrusive (privacy thesis); sections toggles sell features;
free text is bad UX (Alan, 2026-09-21 screenshot); ends on a static screen.
→ step 3: goals as chips → template → 5 screens, last one is today running.

### Today (DayView) — becomes **Now**
progress bar · 14-day strip + streak · banners (persistence, notifications off) · Now card
(NOW/OVERDUE, minutes left, Done, Move it later, Skip) · Up next + leave-by · Left today ·
Missed / Day review (evening) · Done · Tomorrow (folded, Edit) · undo toast · toolbar:
Days, Just for today, Edit plan, Settings.
Gaps: nothing happens when a block closes (step 2: haptic + fill); no face (step 2: pace
line); strip belongs in Pace (step 2); Ask is not reachable from here (step 1); Missed is red
(step 2 tone); no quick add by text (step 3).

### Days (DaysView) and Day plan (DayPlanView)
Calendar of days with scores → a day's plan, editable for future days (per-day overrides:
moved, extras, notes, skips).
Gaps: fine. Month grid of "days on pace" duplicates part of this; Pace links here (step 2).

### Block detail (BlockDetailSheet)
Times, chips (kind, today-only, moved, status), last 7 days, note, actions (Done / Move it
later / Set time / Skip / Remove / Edit in weekly plan).
Gaps: no per-block notification switch (step 2); a gym block does not show Train data and a
study block does not start Focus here (step 2: block types).

### Weekly plan (PlanView + BlockEditor)
List of template blocks; editor with label, kind, times, weekdays, anchor, place, auto-close.
Gaps: form-heavy; no templates; no duplicate-block; no drag to reorder. → step 3 templates;
later: drag.

### Places (PlacesView, PlaceForm)
Pins with Maps search, travel matrix with Maps ETA and departure time, mode.
Gaps: reached only from Settings; should appear when a block gets a place (step 3). Copy must
say pins stay on the phone (step 4).

### Settings
Sections (toggle/reorder) · Day (day end, check-ins, Places) · Your week (metrics) · Notifications
(permission, sound + preview, Live Activity, morning brief) · Health · Coach (profile) · Widgets
help · Export · About (Diagnostics).
Gaps: "Coach" wording (step 1); no Feedback (step 4); no Privacy link (step 4); no "delete
everything" (step 4).

### Train
Week bar, workouts with HR, bests, readiness, weight chart + log, training goals; "Ask the coach".
Gaps: tab by default; should open from a gym/run block and stay optional (step 1/2).

### Food
Water, meals vs targets, presets, pantry, recipes, grocery list, plan-my-meals.
Gaps: same; big surface for a secondary need. Optional section (step 1).

### Focus
Chips/lengths/Start, week card, subjects, heat map, recent; full-screen timer with Live Activity.
Gaps: should start from a study block (step 2); optional section (step 1).

### Money, Closet
Complete but off-thesis. → off by default (step 1), first optional modules.

### Coach (CoachView) — becomes **Ask**
Chat with streaming, chips for the moment, tool results as green pills, history, new chat,
profile editor, own key vs subscription (Sign in with Apple + paywall).
Gaps: it is a tab and a chat; the model should act (step 1: sheet from anywhere, "Ask
Pacer"); no voice (step 3); no "what changed" summary after a tool run beyond the pill; empty
state sells features (step 1 copy).

## Flows that have no owner today

- **Day 2 return**: nothing brings the user back except notifications. Morning brief exists;
  add the widget prompt (step 3) and measure D2 (step 4).
- **A block always overruns**: no learning, no suggestion to lengthen it. later.
- **Calendar meetings as obstacles**: none. later (EventKit read-only).
- **Trial → pay**: paywall exists; no trial-end message, no "what you'd lose". later.
- **Crash or data loss**: `.bad` rename + banner; no crash reporting, no CI. step 4.
