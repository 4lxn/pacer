// Sign in with Apple identity-token verification and our own session tokens.
// Node 22 only: WebCrypto for RS256 (Apple) and HMAC-SHA256 (ours). No dependencies.

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_JWKS = "https://appleid.apple.com/auth/keys";

let jwksCache = { keys: [], fetchedAt: 0 };

const b64url = {
  decode: (s) => Buffer.from(s.replace(/-/g, "+").replace(/_/g, "/"), "base64"),
  encode: (buf) => Buffer.from(buf).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, ""),
};

function decodeJWT(token) {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("malformed token");
  const header = JSON.parse(b64url.decode(parts[0]).toString("utf8"));
  const payload = JSON.parse(b64url.decode(parts[1]).toString("utf8"));
  return { header, payload, signingInput: `${parts[0]}.${parts[1]}`, signature: b64url.decode(parts[2]) };
}

async function appleKey(kid, fetchImpl) {
  const stale = Date.now() - jwksCache.fetchedAt > 6 * 60 * 60 * 1000;
  let key = jwksCache.keys.find((k) => k.kid === kid);
  if (!key || stale) {
    const res = await fetchImpl(APPLE_JWKS);
    if (!res.ok) throw new Error(`apple jwks ${res.status}`);
    jwksCache = { keys: (await res.json()).keys, fetchedAt: Date.now() };
    key = jwksCache.keys.find((k) => k.kid === kid);
  }
  if (!key) throw new Error("unknown apple key");
  return key;
}

/** Verifies an Apple identity token; returns the stable Apple user id (`sub`). */
export async function verifyAppleIdentityToken(token, { bundleId, fetchImpl = fetch, now = Date.now() } = {}) {
  const { header, payload, signingInput, signature } = decodeJWT(token);
  if (header.alg !== "RS256") throw new Error("unexpected alg");
  const jwk = await appleKey(header.kid, fetchImpl);
  const key = await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
  const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, signature, Buffer.from(signingInput));
  if (!ok) throw new Error("bad signature");
  if (payload.iss !== APPLE_ISSUER) throw new Error("bad issuer");
  if (payload.aud !== bundleId) throw new Error("bad audience");
  if (payload.exp * 1000 < now) throw new Error("expired");
  return payload.sub;
}

async function hmacKey(secret) {
  return crypto.subtle.importKey("raw", Buffer.from(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

/** Our session token: HS256 JWT with { sub, exp }. Default lifetime 30 days. */
export async function issueSessionToken(sub, secret, { now = Date.now(), ttlSeconds = 30 * 24 * 3600 } = {}) {
  const header = b64url.encode(Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const payload = b64url.encode(Buffer.from(JSON.stringify({ sub, iat: Math.floor(now / 1000), exp: Math.floor(now / 1000) + ttlSeconds })));
  const sig = await crypto.subtle.sign("HMAC", await hmacKey(secret), Buffer.from(`${header}.${payload}`));
  return `${header}.${payload}.${b64url.encode(sig)}`;
}

export async function verifySessionToken(token, secret, { now = Date.now() } = {}) {
  const { header, payload, signingInput, signature } = decodeJWT(token);
  if (header.alg !== "HS256") throw new Error("unexpected alg");
  const ok = await crypto.subtle.verify("HMAC", await hmacKey(secret), signature, Buffer.from(signingInput));
  if (!ok) throw new Error("bad signature");
  if (payload.exp * 1000 < now) throw new Error("expired");
  return payload.sub;
}
