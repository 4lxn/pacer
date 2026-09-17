# Release checklist

```sh
export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
xcodegen generate
xcodebuild -scheme Autopiloto -destination 'platform=iOS Simulator,name=iPhone 17' test
(cd server && npm test)
```

## TestFlight / App Store upload

1. `DEVELOPMENT_TEAM` is set in `project.yml` (UK3KUGFP25). Bump `CURRENT_PROJECT_VERSION`
   per upload (or rely on `manageAppVersionAndBuildNumber` in ExportOptions, which auto-bumps).
2. Archive and export with automatic signing. Xcode's signed-in Apple ID is enough
   (`-allowProvisioningUpdates`); an App Store Connect API key is only needed on CI:

```sh
xcodebuild -scheme Autopiloto -destination 'generic/platform=iOS' -archivePath build/Autopiloto.xcarchive archive \
  -allowProvisioningUpdates

cat > build/ExportOptions.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>UK3KUGFP25</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><true/>
</dict></plist>
PLIST

xcodebuild -exportArchive -archivePath build/Autopiloto.xcarchive -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export -allowProvisioningUpdates
# First upload done 2026-09-16 (build 1.0 (1)) exactly this way.
```

Or: Xcode → Product → Archive → Distribute App → App Store Connect → Upload.

3. App Store Connect: add the build to TestFlight (internal testers need no review), fill the
   App Privacy questionnaire from `docs/app-store.md`, attach screenshots, submit.

## Coach proxy

Railway service from this repo, root directory `server`, env `ANTHROPIC_API_KEY` and
`SESSION_SECRET`, generate a domain, then set `CoachClient.proxyURL` and ship a new build.
