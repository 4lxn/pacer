# Pacer

**Pacer keeps your day on pace.** An iOS planner of daily blocks that notifies you when each fixed
block starts, asks "did it happen?" five minutes after a longer block ends (Done / Move it later /
Skip today from the lock screen), moves a missed block into free time later today with one tap
(undoable), closes training blocks from Apple Health even while closed, shows Now/Next on the home
screen, and bundles the trackers around your day: training week and weight, meals and pantry, study
timer, income, closet with laundry and outfits, and an AI Coach that knows your plan and can change
it. Swift 6, SwiftUI, iOS 26+ (Liquid Glass), no third-party dependencies.

Sections you toggle and order (Settings → Sections): **Today** (plan, calendar, places, settings) ·
**Train** (Apple Health, goals, readiness, bests) · **Food** (macros, water, recipes, groceries) ·
**Focus** (timer in the Dynamic Island, subjects, heat map) · **Money** (income, expenses, budgets)
· **Closet** (scan, outfit from the weather, laundry) · **Coach** (streaming agent that can change
anything). Widgets on Home and Lock Screen, Live Activities, Siri shortcuts, morning brief.

The product was named Autopiloto during development; the bundle id (`com.alan.autopiloto`), scheme,
targets and repo keep that name. Everything the user sees says Pacer. How it fits together:
`docs/ARCHITECTURE.md`.

The only network code lives in `Sources/Coach/` (Claude Messages API, directly with the user's key
or through `server/`). Everything else works with no network, ever. Docs: `docs/privacy.md`,
`docs/app-store.md`, `docs/release.md`, `server/README.md`.

## Requirements

- Xcode 26 (Swift 6). If `xcode-select -p` points at CommandLineTools, either run
  `sudo xcode-select -s /Applications/Xcode-26.6.0.app` once or prefix every command below with
  `DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer`.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Generate, build, test

```sh
xcodegen generate
open Autopiloto.xcodeproj                      # pick your Team under Signing & Capabilities once

xcodebuild -scheme Autopiloto -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme Autopiloto -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Run on the simulator from Xcode (⌘R), or on a connected iPhone:

```sh
xcodebuild -scheme Autopiloto -destination 'platform=iOS,name=<your iPhone name>' build
```

`Autopiloto.xcodeproj` is generated and git-ignored; edit `project.yml` instead.

## Apple Health (Train tab)

Pacer reads workouts, weight and steps from Apple Health and marks the Run / Gym blocks done
when a matching workout lands today. Feed Health from your watch apps once:

- Garmin Connect: More → Settings → Connected Apps → Apple Health → enable workouts, weight, steps.
- Strava: Settings → Applications, Services and Devices → Health → connect.

No Garmin or Strava API keys, no server. The weight you log in the Train tab is written to Health.
Debug builds have an "Add test run" button to exercise the pipeline in the simulator.

## Changing the plan

Today → the sliders button opens the Plan editor (add, edit, delete blocks; weekdays; anchor;
auto-complete). `Sources/Models/Plan.swift` only holds the seeds: the original day for installs
that predate the editor, and `Plan.starter(wake:sleep:)` for onboarding.

## Coach (optional)

Coach tab → either subscribe (Sign in with Apple, needs `server/` deployed and
`CoachClient.proxyURL` set) or Menu → "Use my own API key" and paste an Anthropic key (Keychain,
never in this repo). The system prompt is the editable **Coach profile** (Menu → Coach profile)
plus a snapshot of today's blocks, training, food, study and closet.

## Verify no network code outside Coach

```sh
grep -ri "urlsession\|http" Sources/ --exclude-dir=Coach   # must print nothing
```

## Manual checks in the simulator

```sh
export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
SIM=$(xcrun simctl list devices booted | grep -o '[0-9A-F-]\{36\}' | head -1)

# Fire a start notification now (after tapping Allow once). Long-press it → Done marks b13 complete
# without opening the app; relaunch and the row is checked.
cat > /tmp/block.apns <<'JSON'
{
  "Simulator Target Bundle": "com.alan.autopiloto",
  "aps": { "alert": { "title": "Leave for training", "body": "17:45 – 17:55" }, "category": "BLOCK_ACTIONS", "sound": "default" },
  "blockId": "b13"
}
JSON
xcrun simctl push "$SIM" com.alan.autopiloto /tmp/block.apns

# Fire a check-in: long-press → Done or Skip today; both land on the dayKey, not on "now".
cat > /tmp/checkin.apns <<'JSON'
{
  "Simulator Target Bundle": "com.alan.autopiloto",
  "aps": { "alert": { "title": "Lunch ended", "body": "Did it happen?" }, "category": "CHECK_IN", "sound": "default" },
  "blockId": "b09", "dayKey": "2026-09-16"
}
JSON
xcrun simctl push "$SIM" com.alan.autopiloto /tmp/checkin.apns

# Denial path: reset the permission and tap Don't Allow on the next launch.
xcrun simctl privacy "$SIM" reset all com.alan.autopiloto
```
