# App Store listing and review notes

## Metadata

- **Name:** Autopiloto
- **Subtitle:** Your day on rails
- **Category:** Productivity (secondary: Health & Fitness)
- **Age rating:** 4+
- **Price:** Free; in-app subscription "Coach monthly" (`com.alan.autopiloto.coach.monthly`, group "Coach", 1-week free trial)
- **Availability:** all territories except the EU (DSA: not a trader; no public address). Add the EU later with a business address.
- **Privacy policy URL:** host `docs/privacy.md` (GitHub Pages, a gist, or Notion) and paste the URL
- **Support URL:** same host, or a mailto page

## Description

Autopiloto runs your day so you don't have to hold it in your head.

Build a plan of blocks — wake up, train, work, lunch, study, wind down — and Autopiloto notifies you
when each fixed block starts. Tap Done or Snooze right from the lock screen. The anchor block breaks
through Focus so you never miss the one thing that matters.

Blocks close themselves. A run or a strength session in Apple Health (from your Garmin, Apple Watch
or Strava) marks your training done. Twenty minutes of study marks your study block done.

Everything you track lives in one place: training week and weight trend, meals against your daily
targets, pantry with an automatic grocery list, study timer, income, and a closet that knows what
needs washing and suggests today's outfit.

Ask the Coach. It knows your plan, your training, your food log and your goals — because you wrote
them — and answers in your language: what's next, what to eat, how the week is going.

Works offline. No account required. Your data stays on your iPhone.

## Keywords

daily planner, routine, habits, time blocking, ADHD, notifications, apple health, garmin, meal
tracker, pantry, study timer, wardrobe

## App Privacy (the questionnaire)

| Data | Collected? | Linked to user | Tracking | Purpose |
|---|---|---|---|---|
| Health & Fitness | Not collected (on-device only) | — | No | — |
| Photos | Not collected (on-device; sent to the AI only when the user scans a garment) | — | No | — |
| User content (Coach questions, plan snapshot) | Collected when the user asks the Coach | Not linked (anonymous Apple id on the proxy only) | No | App functionality |
| Identifiers (Sign in with Apple user id) | Collected (subscribers) | Linked | No | App functionality (rate limiting) |
| Financial info (income entries) | Not collected (on-device only) | — | No | — |
| Purchases | Handled by Apple | — | No | — |
| Diagnostics | Not collected | — | No | — |

Third-party: Anthropic (AI model) receives Coach requests. Declare under "data used by third-party
partners: no" — it is our processor, not a partner collecting for its own purposes.

## Review notes (paste into App Review Information)

Autopiloto is a personal planner. Reviewers can use it fully without an account:

1. Onboarding asks for wake and sleep times and builds a plan. Allow notifications to see block
   alerts; each fixed block schedules a repeating local notification with Done / Snooze actions,
   and longer window blocks get a one-shot "did it happen?" check-in with Done / Skip today.
2. The Train tab reads Apple Health workouts, weight and steps (HealthKit permission). Blocks marked
   "auto-complete: run / strength" complete when a matching workout exists today.
3. The Coach tab requires either a subscription (Sign in with Apple, then "Coach monthly") or the
   user's own Anthropic API key (Menu → "Use my own API key"). The subscription can be tested with
   a sandbox account. Questions are answered by an AI model using the plan and logs on the device.
4. The Life tab holds a study timer, income entries and a closet. Scanning a garment uses the camera
   or photo library and the same AI service to prefill the item; manual entry works without it.

No data is collected by us except the anonymous Sign in with Apple identifier used to rate-limit
Coach requests. Encryption: the app uses only HTTPS (ITSAppUsesNonExemptEncryption = NO).

## Screenshots (6.9" and 6.5" required)

Debug builds honour two launch env vars for screenshots without tapping: `AUTOPILOTO_TAB`
(`today|train|food|life|coach`) and `AUTOPILOTO_SCREENSHOT=paywall` (Coach subscribe screen with
the fallback price, no notification prompt). From a terminal:

```sh
SIMCTL_CHILD_AUTOPILOTO_TAB=coach SIMCTL_CHILD_AUTOPILOTO_SCREENSHOT=paywall \
  xcrun simctl launch <sim-udid> com.alan.autopiloto && xcrun simctl io <sim-udid> screenshot paywall.png
```

The subscription's Review Information screenshot lives at `docs/screenshots/coach-paywall-review.png`.

Take the rest in the simulator with ⌘S: Today (a current block highlighted), Train (workouts + weight chart),
Food (macros + pantry), Life → Closet (outfit + laundry), Coach (an answer), Plan editor.

## Before the first public build

- Remove `CoachContext.training` (the original owner's personal profile) from the binary — it is
  only a legacy seed; the device already has it saved as the Coach profile.
- Deploy `server/` and set `CoachClient.proxyURL`.
- Create the subscription in App Store Connect with the exact product id.
- Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`.
