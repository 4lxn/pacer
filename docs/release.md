# Release checklist

```sh
export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
xcodegen generate
xcodebuild -scheme Autopiloto -destination 'platform=iOS Simulator,name=iPhone 17' test
(cd server && npm test)
```

## TestFlight / App Store upload

1. In `project.yml` set `DEVELOPMENT_TEAM` (or pick the team once in Xcode) and bump the version.
2. Archive and export with automatic signing. With an App Store Connect API key
   (Issuer ID, Key ID, `.p8` in `~/.appstoreconnect/private_keys/`):

```sh
xcodebuild -scheme Autopiloto -destination 'generic/platform=iOS' -archivePath build/Autopiloto.xcarchive archive \
  -allowProvisioningUpdates -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 \
  -authenticationKeyID <KEYID> -authenticationKeyIssuerID <ISSUER>

cat > build/ExportOptions.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST

xcodebuild -exportArchive -archivePath build/Autopiloto.xcarchive -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export -allowProvisioningUpdates \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 -authenticationKeyID <KEYID> -authenticationKeyIssuerID <ISSUER>
```

Or: Xcode → Product → Archive → Distribute App → App Store Connect → Upload.

3. App Store Connect: add the build to TestFlight (internal testers need no review), fill the
   App Privacy questionnaire from `docs/app-store.md`, attach screenshots, submit.

## Coach proxy

Railway service from this repo, root directory `server`, env `ANTHROPIC_API_KEY` and
`SESSION_SECRET`, generate a domain, then set `CoachClient.proxyURL` and ship a new build.
