# Autopiloto

Single-user iOS day runner: a fixed list of daily blocks, a local notification when each fixed
block starts, one-tap Done. Swift 6, SwiftUI, iOS 17+, no third-party dependencies.

The only network code lives in `Sources/Coach/`: an optional "Coach" sheet that sends today's
status plus a bundled training/diet context to the Claude Messages API. Everything else works
with no network, ever.

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

## Changing the plan

There is no editing UI. Edit the `Plan.blocks` array in `Sources/Models/Plan.swift` and rebuild.

## Coach (optional)

Tap **Coach** on the main screen, paste an Anthropic API key once (stored in the Keychain, never in
this repo), and ask a question. The system prompt is `Sources/Coach/CoachContext.swift` plus a
snapshot of today's blocks.

## Verify no network code outside Coach

```sh
grep -ri "urlsession\|http\|apikey" Sources/ --exclude-dir=Coach   # must print nothing
```
