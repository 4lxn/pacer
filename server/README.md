# Coach proxy

Tiny Node 22 server (no dependencies) that lets store users ask the Coach without an Anthropic key.

- `POST /v1/session` `{ identityToken }` — verifies a Sign in with Apple identity token (RS256, Apple
  JWKS, audience = bundle id) and returns a 30-day session token (HS256).
- `POST /v1/coach` `Authorization: Bearer <session>` `{ system: [...], question }` — forwards to the
  Claude Messages API with the server's key, per-user daily limit, returns `{ text, remaining, usage }`.
- `GET /health`

## Env

| Var | Required | Default |
|---|---|---|
| `ANTHROPIC_API_KEY` | yes | |
| `SESSION_SECRET` | yes (long random string) | |
| `APPLE_BUNDLE_ID` | | `com.alan.autopiloto` |
| `DAILY_LIMIT` | | `40` |
| `MODEL` | | `claude-opus-5` |
| `MAX_TOKENS` | | `4096` |
| `PORT` | | `8080` (Railway sets it) |

## Run

```sh
cd server && npm test
ANTHROPIC_API_KEY=… SESSION_SECRET=… npm start
```

Deployed: Railway project `autopiloto-coach`, service `coach` (root `server`, branch `main`,
healthcheck `/health`), domain `https://coach-production-94d9.up.railway.app`, wired into
`CoachClient.proxyURL`. Redeploys on every push to `main` that touches `server/`. Set
`ANTHROPIC_API_KEY` in the Railway dashboard (never in the repo).

Known ceiling (`ponytail:` in code): the daily limiter is in memory and resets on redeploy; the
subscription is trusted from the client. Upgrade path: SQLite on a volume for counts and App Store
Server API verification of the transaction before issuing a session.
