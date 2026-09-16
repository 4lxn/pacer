import { test } from "node:test";
import assert from "node:assert/strict";
import { issueSessionToken, verifySessionToken, verifyAppleIdentityToken } from "../src/auth.mjs";
import { DailyLimiter } from "../src/ratelimit.mjs";

test("session token round-trips and expires", async () => {
  const token = await issueSessionToken("user-1", "secret", { now: 1_000_000, ttlSeconds: 60 });
  assert.equal(await verifySessionToken(token, "secret", { now: 1_030_000 }), "user-1");
  await assert.rejects(verifySessionToken(token, "secret", { now: 1_070_000 }), /expired/);
  await assert.rejects(verifySessionToken(token, "other", { now: 1_030_000 }), /bad signature/);
});

test("apple identity token: signature, issuer, audience, expiry", async () => {
  const pair = await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]);
  const jwk = { ...(await crypto.subtle.exportKey("jwk", pair.publicKey)), kid: "k1", alg: "RS256", use: "sig" };
  const fetchImpl = async () => ({ ok: true, json: async () => ({ keys: [jwk] }) });
  const enc = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const now = 1_700_000_000_000;
  const sign = async (payload) => {
    const input = `${enc({ alg: "RS256", kid: "k1" })}.${enc(payload)}`;
    const sig = Buffer.from(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", pair.privateKey, Buffer.from(input))).toString("base64url");
    return `${input}.${sig}`;
  };
  const good = { iss: "https://appleid.apple.com", aud: "com.alan.autopiloto", sub: "apple-123", exp: now / 1000 + 600 };
  assert.equal(await verifyAppleIdentityToken(await sign(good), { bundleId: "com.alan.autopiloto", fetchImpl, now }), "apple-123");
  await assert.rejects(verifyAppleIdentityToken(await sign({ ...good, aud: "other" }), { bundleId: "com.alan.autopiloto", fetchImpl, now }), /bad audience/);
  await assert.rejects(verifyAppleIdentityToken(await sign({ ...good, exp: now / 1000 - 1 }), { bundleId: "com.alan.autopiloto", fetchImpl, now }), /expired/);
  const tampered = (await sign(good)).replace(/\.[^.]+$/, ".AAAA");
  await assert.rejects(verifyAppleIdentityToken(tampered, { bundleId: "com.alan.autopiloto", fetchImpl, now }), /bad signature|malformed/);
});

test("daily limiter caps per user per day", () => {
  const l = new DailyLimiter(2);
  assert.deepEqual(l.hit("u", "2026-09-16"), { allowed: true, remaining: 1 });
  assert.deepEqual(l.hit("u", "2026-09-16"), { allowed: true, remaining: 0 });
  assert.deepEqual(l.hit("u", "2026-09-16"), { allowed: false, remaining: 0 });
  assert.deepEqual(l.hit("u", "2026-09-17"), { allowed: true, remaining: 1 });
  assert.deepEqual(l.hit("v", "2026-09-16"), { allowed: true, remaining: 1 });
});
