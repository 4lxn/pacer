# Pacer — project summary for a résumé

_Measured on 2026-09-21 from the repository. Numbers are counts, not estimates._

**Pacer** is an iOS app that runs a person's day: it notifies each block, asks "did it happen?"
from the lock screen, moves what didn't happen to a slot that still fits (travel time and
calendar included), closes training blocks from Apple Health on its own, and shows days on pace.
Built for people whose routines fail silently (ADHD and "ADHD-ish" adults), local-first: the
user's data stays on the phone.

## Role

Alan Cervantes — founder, product owner and engineer. All code was written with Claude Code
(Anthropic's agent) under Alan's direction: he set the product thesis, made every scope and
architecture decision, reviewed builds on device, and ran the App Store pipeline. Describe it as
"built with an AI coding agent", not as hand-written code.

## What was built (2026-09-16 → 2026-09-21, six days)

- **iOS app**: Swift 6 (strict concurrency), SwiftUI, iOS 26 Liquid Glass, Observation, Swift
  Charts, XcodeGen. 12,524 lines of app code, 94 Swift files including tests.
- **Core loop**: calendar-day plan with per-day overrides, a pure replanner (first fitting gap,
  cascading pushes, travel-aware obstacles, calendar events as busy time), one-level undo, a
  single write point (`DayMutator`) for every change.
- **Notifications**: repeating starts, end-of-block check-ins with Done / Move it later / Skip
  actions, leave-by reminders from Apple Maps ETAs, "ends in 5 min" nudges, morning brief,
  custom chime, 64-request cap managed soonest-first.
- **Integrations**: HealthKit (workouts, weight, steps, sleep, resting HR, background delivery),
  MapKit (place search, ETAs by departure time), EventKit (read-only busy time), WeatherKit,
  ActivityKit (2 Live Activities with Dynamic Island), WidgetKit (3 widget kinds, 7 families),
  App Intents (7 Siri/Shortcuts actions), Speech (on-device voice capture).
- **Assistant ("Ask")**: Anthropic Messages API with 54 tools, SSE streaming, conversation
  history, tool access filtered by enabled sections; own-API-key mode or subscription via Sign in
  with Apple + StoreKit.
- **Backend**: Node proxy on Railway (320 lines): Apple identity-token verification (JWKS,
  RS256), HS256 sessions, per-user daily limits, streaming passthrough, anonymous usage counts
  on a volume with a stats endpoint (DAU/MAU, cohort D7/D30).
- **Product work**: user research from community sources (`docs/USERS.md`), an app map with
  gaps (`docs/APP-MAP.md`), a product thesis with fail-fast gates and a YC-lens evaluation
  (`docs/PRODUCT.md`), eight user stories filed as GitHub issues (six shipped), a privacy policy
  written as four verifiable promises.
- **Onboarding**: five screens, no typing — goal chips become plan templates, profile chips
  become the assistant's context, last screen is the running day.
- **Quality**: 131 XCTest methods in 23 files (replanner, notifications, streaming transport via
  a `URLProtocol` stub, parsers, migrations), 5 server tests, 72 commits, 51 squash-merged PRs,
  23 TestFlight builds; one App Store metadata rejection (ITMS-90626) fixed same day.

## Notable engineering decisions

- Local-first storage (JSON files in an App Group, atomic writes, corrupt-file quarantine) instead
  of a synced backend; the server only proxies the model and counts.
- Strict Swift 6 concurrency across the codebase, warnings as errors.
- The assistant acts through typed tools against the same single write point as the UI, so
  every change it makes is undoable and notified like a manual one.
- Declarative sections and templates (`AppSection`, `Goal`) so the product can be reduced to
  three surfaces (Now · Pace · Ask) without deleting the rest.
- Anonymous, integer-only telemetry designed so the privacy promise and the retention gates can
  both be true.

## Honest gaps (as of this summary)

No external users yet, so no retention data; no CI; Live Activities go stale when the app is
closed (no push); the proxy issues sessions to any Apple-signed-in user without a subscription
check; localization is English only.

## Résumé lines (pick one)

- Built and shipped Pacer, an iOS 26 day-runner for ADHD adults (Swift 6, SwiftUI, HealthKit,
  MapKit, EventKit, ActivityKit, App Intents), from empty repo to 23 TestFlight builds in six days
  using an AI coding agent under my direction; 131 tests, 51 PRs.
- Designed a local-first architecture with a 320-line Node proxy (Apple identity verification,
  streaming LLM passthrough, anonymous cohort analytics) and a tool-using assistant with 54
  typed tools sharing one undoable write path with the UI.
- Ran product discovery end to end: community research, app map, thesis with fail-fast gates,
  user stories as issues, privacy policy as verifiable promises.
