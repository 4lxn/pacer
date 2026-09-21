# User stories (2026-09-21)

From `USERS.md` (needs #1–#10) and `APP-MAP.md`. One persona: **Dani, 31, "ADHD-ish", routine
collapses by 2 pm, tried Structured and Tiimo, iPhone + watch, CDMX.** Sizes are CC+gstack time.
Each story is a GitHub issue; status lives there.

| # | Story | Need | Size | Status |
|---|---|---|---|---|
| S1 | Voice capture in Ask | #2 | M | shipped #56 (tap to toggle) |
| S2 | Quick add by text on Now ("gym 7pm 45m") | #2, #5 | S | shipped #56 |
| S3 | Gym/run blocks open Train, study blocks start Focus | map | M | shipped #58 |
| S4 | Calendar events as replanner obstacles | #9 | L | shipped #59 |
| S5 | Day 2: widget card + Live Activity on the first block | #6 | S | shipped #57 |
| S6 | Tone pass: no red, review shows wins first | #3 | S | shipped #57 |
| S7 | Overrun learning: "this block usually takes longer" | #1 | M | later |
| S8 | Trial end: what you keep, what you lose | — | S | later |

## S1 — Voice capture in Ask
As Dani, I want to hold a mic button and say "gym tomorrow at 7 at Smart Fit" so a block exists
without typing, because typing a task takes a minute and I won't do it.
Acceptance:
1. Mic button in the Ask input bar; press-and-hold records, release sends the transcript as the message.
2. On-device speech when available (`SFSpeechRecognizer.supportsOnDeviceRecognition`); the language follows the device.
3. Permission denied → the button explains and links to Settings; typing still works.
4. Transcript appears in the field while speaking; releasing with an empty transcript does nothing.
5. `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription` say audio never leaves the phone when on-device recognition is available.

## S2 — Quick add by text on Now
As Dani, I want to type "gym 7pm 45m" in the "+" sheet and get a block at 19:00–19:45 today,
because forms with pickers are where I give up.
Acceptance:
1. `TodayOnlySheet` gains a single text field at the top; a local parser fills label, start, end.
2. Grammar: `<label> [at] <time> [for <n>m|<n>h]`, `<label> <time>-<time>`, times as `7pm`, `19:00`, `7:30`, `noon`; default length 30 min; no time → free block.
3. Pickers stay visible and reflect the parse, so the user can correct.
4. Parser is pure (`QuickAdd.parse(_:now:)`) with tests for 10 phrasings.
5. Ask's `add_block` tool is unchanged; this is the offline path.

## S3 — Block types open their section
As Dani, I want tapping the Gym block to show this week's workouts and my readiness, and the Study
block to have "Start focus", because that's when I care, not in a separate tab.
Acceptance:
1. `BlockDetailSheet` shows a Train card (week bar, last workout, readiness) for blocks with `autoComplete == .run/.strength` when Health is connected.
2. Blocks with `autoComplete == .study` show "Start focus (25 min)" which starts `TrackStore` focus and the Live Activity.
3. The Train/Focus tabs stay optional and unchanged.

## S4 — Calendar events as obstacles
As Dani, I want my meetings from Calendar to count as busy time, so "Move it later" never lands
a block on top of a call, because that's the first thing that made me distrust Structured.
Acceptance:
1. Settings → Day: "Use Calendar for busy time" (off by default), read-only EventKit access, `NSCalendarsFullAccessUsageDescription` says events never leave the phone.
2. Today's and tomorrow's events become `Replanner.Obstacle`s (all-day events ignored).
3. Events show in Now's timeline as grey rows without actions.
4. Denied or no calendars → toggle shows the state; nothing else changes.
5. Tests: replanner skips a gap covered by an event.

## S5 — Day 2
As Dani, I want the widget on my Home Screen and the Live Activity running by the end of day 1,
because by day 2 I have forgotten the app exists.
Acceptance:
1. A dismissable card on Now for the first 3 days: "Add the widget" with the two-step instruction.
2. The block Live Activity starts on the first block after onboarding without opening Settings.
3. Telemetry `opened` on day 2 is the number gate 1 watches.

## S6 — Tone pass
As Dani, I want misses to look like decisions, not failures, because red counters are why I
deleted the last three apps.
Acceptance:
1. "Missed" count pill and OVERDUE label use orange, never red; copy: "Needs a decision".
2. Evening review lists what got done first, then what slipped.
3. Undo toast wording stays; no exclamation marks anywhere in Now/Pace.
