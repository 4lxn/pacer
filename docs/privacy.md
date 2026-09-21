# Pacer — Privacy Policy

_Last updated: 2026-09-21_

Pacer (bundle id com.alan.autopiloto) runs your day. Four promises, then the details.

1. **Your data lives on your phone.** Your plan, what you did, your places, your training, meals
   and notes are stored only on your iPhone (in the app's container, shared with its widgets).
   Nothing is uploaded, synced or backed up by us. Export it any time from Settings; delete the
   app and it is gone.
2. **Ask sends only what a question needs, and we don't keep it.** When you ask Pacer something,
   the question plus a short snapshot of your plan (and, if those sections are on, your training,
   food and study summaries and the "About you" text) go to the AI model for that one answer.
   Our proxy forwards the request and stores nothing from it — not the question, not the answer,
   not your health data. Anthropic does not train on API traffic (their commercial terms).
3. **No account unless you pay.** The app works without signing in. A subscription uses Sign in
   with Apple, which gives us an anonymous, app-specific identifier and nothing else — no name,
   no email. Purchases are handled by Apple.
4. **We count, we don't read.** Once a day the app sends a random id and a few numbers — times
   opened, blocks closed, check-ins answered from a notification, moves, whether the day was on
   pace — so we can tell whether Pacer works. Never what the blocks are, where you were, or what
   you asked. One switch in Settings turns it off; turning it off also discards the id.

## Details

- **Apple Health** (workouts, weight, steps, sleep, resting heart rate) is read on your device to
  show your training and to close blocks. The weight you log is written to Apple Health. Health
  data never leaves your device unless a Train summary is part of an Ask question (see 2).
- **Places** are looked up with Apple Maps on your device; search and travel-time estimates go
  to Apple's MapKit service under Apple's privacy policy. Your location is read only when you
  tap "Use my current location", never tracked, and pins are never sent to us.
- **Weather** for the Closet section uses Apple WeatherKit with the coordinates of the place you
  pinned; nothing else is sent. (Data provided by  Weather.)
- **Notifications** and Live Activities are scheduled locally on your device.
- **Own API key.** If you enter your own Anthropic key, Ask requests go straight from your
  device to Anthropic (https://www.anthropic.com/privacy) and never touch our proxy. The key is
  kept in the iOS Keychain.
- **The proxy** keeps, per signed-in user, only the anonymous Apple identifier and a per-day
  request count for rate limiting. It logs errors (status code and message), not content.
- **Usage counts** are stored on our server as lines of `{ random id, day, counts }`. There is no
  IP address, device name or account in them.
- **No third-party SDKs.** No analytics vendors, no advertising identifiers, no tracking across
  apps or websites.

## Deleting your data

Delete the app to delete everything stored on the device. To drop the anonymous identifier from
the proxy, sign out in Ask (the identifier is not stored beyond the daily counter). To have usage
counts for your random id deleted, email the address below with the id shown in Settings → About
→ Diagnostics.

## Contact

alangibrancs@icloud.com
