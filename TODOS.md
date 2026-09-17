# TODOS

Deferred work with enough context to pick up cold. Effort is human-team → with Claude Code.

## P2

- **Moved/one-off notifications beyond tomorrow** — `rearmCheckIns` covers today + tomorrow, so a
  block moved for the day after tomorrow gets its one-shot start only once that day is within the
  window (app open, BG refresh, or a notification action). Extend `checkInDays` or arm on edit.
  Effort: S → S.

- **Wake-relative day model (shift workers)** — Today the day is the calendar day (`dayKey`
  yyyy-MM-dd) and `dayEnd` is clamped to 23:59. Users who sleep after midnight see "Sleep" as
  tomorrow's block. Redefine the day as `[earliest timed start, +24 h)` across `DayLogic`,
  completions, overrides, notifications and the widget. Decided 2026-09-16 (CEO review 9A).
  Effort: L → M. Blocked by: the Pacer core PR landing first.
- **Anonymous weekly metrics ping** — Decided against for now (CM5): counts without an id
  can't compute D7 retention and would flip the "Analytics: none" privacy story. Reopen when
  there are enough real users for aggregates to mean something. Effort: S → S.
- **`AppStores` environment container** — One `@Observable` holding every store, injected via
  `.environment`, to stop the AppDelegate → RootView → view parameter churn. Deferred (CM6) until
  a PR actually needs it. Effort: S → S.
- **Morning brief notification** — BGAppRefresh + `CoachAgent`, one call per day at the anchor
  block: today's blocks, run, macros, weight trend, yesterday's misses. Deferred to validate
  replanning first and avoid API spend before users (D5.2). Effort: S → S.
- **Coach chat: keyboard dismiss + scroll polish** — the input bar is glass; check the transcript
  keeps its place when the keyboard opens on device. Effort: S → S.
- **Repeating start notifications for moved blocks fire at the template time** — a block moved
  from 13:00 to 17:55 still gets its 13:00 start ping (repeating trigger, CM2). Cancel that
  day's repeating start when a block is moved, or accept it. Effort: S → S.

## P3

- **Live Activity for the current block** — Dynamic Island countdown + Done. Needs APNs on the
  proxy for reliable background starts (D5.6). Effort: M → S. Blocked by: widget target, APNs.
- **Watch app (Done from the wrist)** — WatchConnectivity or its own container; App Groups do
  not span iPhone ↔ Watch. Effort: L → M.
- **iCloud sync** — NSUbiquitousKeyValueStore is too small; CloudKit records per store.
  Effort: L → M. Blocked by: a second device asking for it.
- **Streaming Coach answers** — SSE from the Messages API through the proxy. Effort: M → S.
- **App Store Server API verification on the proxy** — today the subscription is trusted from
  the client; the per-Apple-id daily cap is the only guard. Verify `Transaction.jwsRepresentation`
  server-side before issuing a session. Effort: M → S.
- **SQLite rate counter on a Railway volume** — `server/src/ratelimit.mjs` is in-memory and
  resets on redeploy (`ponytail:` marker). Effort: S → S.
