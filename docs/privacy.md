# Pacer — Privacy Policy

_Last updated: 2026-09-16_

Pacer (bundle id com.alan.autopiloto) is a personal day planner. It is built so that your data stays on your device.

## What the app stores, and where

- **Your plan, completions, meals, pantry, study sessions, income entries, closet and photos** are
  stored only on your iPhone, in the app's private container (shared with its home screen widget). They are never uploaded by the app.
- **Apple Health** (workouts, weight, steps) is read on your device to show your training and to
  mark blocks done. The weight you log is written to Apple Health. Health data never leaves your
  device and is never sent to us or to any third party.
- **Places** you pin are looked up with Apple Maps on your device (search and travel-time estimates go to Apple's MapKit service under Apple's privacy policy). Your location is read only when you tap "Use my current location", and never tracked.
- **Notifications** are scheduled locally on your device.

## The Coach (optional)

When you ask the Coach a question, the app sends your question together with a snapshot of today's
plan, your training summary, your food log, your study summary and your closet summary — plus the
"Coach profile" text you wrote — to an AI model so it can answer. Photos you scan for the closet
are sent for description. This happens only when you tap **Ask** or scan a garment.

- **With your own API key**, the request goes directly from your device to Anthropic
  (https://www.anthropic.com/privacy). Your key is stored in the iOS Keychain and never leaves your
  device except to authenticate that request.
- **With a Coach subscription**, the request goes to our proxy server, which forwards it to
  Anthropic. The proxy stores only your anonymous Sign in with Apple identifier and a per-day
  question count for rate limiting. It does not store your questions, answers, health data or photos.

Income entries are never included in Coach requests.

## Sign in with Apple and purchases

Signing in gives us an anonymous, app-specific identifier. We do not request your name or email.
Purchases are handled by Apple; we never see your payment details.

## Analytics and tracking

None. No analytics SDKs, no advertising identifiers, no tracking across apps or websites.

## Deleting your data

Delete the app to delete everything stored on the device. To remove the anonymous identifier from
the proxy, sign out in the Coach tab (the identifier is not stored beyond the daily counter) or
email the address below.

## Contact

alangibrancs@icloud.com
