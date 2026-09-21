import http from "node:http";
import { verifyAppleIdentityToken, issueSessionToken, verifySessionToken } from "./auth.mjs";
import { DailyLimiter } from "./ratelimit.mjs";
import { appendFile, readFile } from "node:fs/promises";
import { fold, stats } from "./stats.mjs";

const {
  ANTHROPIC_API_KEY,
  SESSION_SECRET,
  APPLE_BUNDLE_ID = "com.alan.autopiloto",
  DAILY_LIMIT = "40",
  MODEL = "claude-opus-5",
  MAX_TOKENS = "4096",
  PORT = "8080",
  DATA_DIR = "",
  STATS_KEY = "",
} = process.env;

if (!ANTHROPIC_API_KEY || !SESSION_SECRET) {
  console.error("ANTHROPIC_API_KEY and SESSION_SECRET are required");
  process.exit(1);
}

const limiter = new DailyLimiter(Number(DAILY_LIMIT));

function json(res, status, body) {
  if (status >= 400) console.error(status, body.error);
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
}

async function readJSON(req, limitBytes = 3_000_000) {
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > limitBytes) throw new Error("body too large");
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
}

function bearer(req) {
  const h = req.headers.authorization || "";
  return h.startsWith("Bearer ") ? h.slice(7) : null;
}

async function handleSession(req, res) {
  const { identityToken } = await readJSON(req);
  if (!identityToken) return json(res, 400, { error: "identityToken required" });
  try {
    const sub = await verifyAppleIdentityToken(identityToken, { bundleId: APPLE_BUNDLE_ID });
    const token = await issueSessionToken(sub, SESSION_SECRET);
    return json(res, 200, { token });
  } catch (e) {
    return json(res, 401, { error: `invalid identity token: ${e.message}` });
  }
}

async function handleCoach(req, res) {
  const token = bearer(req);
  if (!token) return json(res, 401, { error: "missing session token" });
  let sub;
  try {
    sub = await verifySessionToken(token, SESSION_SECRET);
  } catch (e) {
    return json(res, 401, { error: `invalid session: ${e.message}` });
  }
  const { allowed, remaining } = limiter.hit(sub);
  if (!allowed) return json(res, 429, { error: "daily limit reached", remaining: 0 });

  const body = await readJSON(req);
  if (!Array.isArray(body.system)) return json(res, 400, { error: "system[] required" });

  let messages;
  let tools;
  if (Array.isArray(body.messages)) {
    // Agent shape: the client owns the conversation (thinking/tool_use blocks replay verbatim).
    if (body.messages.length > 60) return json(res, 400, { error: "too many messages (max 60)" });
    if (body.tools && (!Array.isArray(body.tools) || body.tools.length > 80)) return json(res, 400, { error: "too many tools (max 80)" });
    messages = body.messages;
    tools = body.tools;
  } else if (typeof body.question === "string") {
    // Legacy one-shot shape, optionally with a photo (wardrobe scanner).
    const content = body.image && typeof body.image.data === "string"
      ? [
          { type: "image", source: { type: "base64", media_type: body.image.media_type || "image/jpeg", data: body.image.data } },
          { type: "text", text: body.question },
        ]
      : body.question;
    messages = [{ role: "user", content }];
  } else {
    return json(res, 400, { error: "messages[] or question required" });
  }

  const stream = body.stream === true && Array.isArray(body.messages);
  const payload = {
    model: MODEL,
    max_tokens: body.image ? 512 : Number(MAX_TOKENS),
    system: body.system,
    messages,
    fallbacks: "default",
  };
  if (tools) payload.tools = tools;
  if (stream) payload.stream = true;

  const upstream = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "anthropic-beta": "server-side-fallback-2026-07-01",
    },
    body: JSON.stringify(payload),
  });
  if (stream && upstream.ok) {
    // Pipe Anthropic's SSE straight through; one extra event carries the day's remaining calls.
    res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "keep-alive" });
    res.write(`event: remaining\ndata: ${JSON.stringify({ remaining })}\n\n`);
    try {
      for await (const chunk of upstream.body) res.write(chunk);
    } catch (e) {
      console.error("stream", e.message);
    }
    return res.end();
  }
  const data = await upstream.json();
  if (!upstream.ok) {
    console.error("anthropic", upstream.status, data?.error?.message);
    return json(res, 502, { error: data?.error?.message || "upstream error" });
  }
  const text = (data.content || []).filter((b) => b.type === "text").map((b) => b.text).join("\n");
  return json(res, 200, { text, content: data.content, stop_reason: data.stop_reason, stop_details: data.stop_details, remaining, usage: data.usage });
}

// Anonymous usage counts (docs/privacy.md): a random id, a day, and a few integers. No auth, no
// content, no IP stored. One line per ping on the volume; newest wins per (id, day).
const pingsFile = DATA_DIR ? `${DATA_DIR}/pings.ndjson` : null;

async function handlePing(req, res) {
  if (!pingsFile) return json(res, 503, { error: "telemetry off" });
  const body = await readJSON(req, 2_000);
  if (typeof body.id !== "string" || !/^[0-9a-f-]{36}$/i.test(body.id)) return json(res, 400, { error: "id required" });
  if (!/^\d{4}-\d{2}-\d{2}$/.test(body.day || "")) return json(res, 400, { error: "day required" });
  const events = {};
  for (const [k, v] of Object.entries(body.events || {})) if (/^[a-zA-Z]{1,24}$/.test(k) && Number.isInteger(v) && v >= 0 && v < 10_000) events[k] = v;
  await appendFile(pingsFile, JSON.stringify({ id: body.id, day: body.day, events, build: String(body.build || "").slice(0, 8), at: Date.now() }) + "\n");
  return json(res, 200, { ok: true });
}

async function handleStats(req, res) {
  const url = new URL(req.url, "http://x");
  if (!STATS_KEY || url.searchParams.get("key") !== STATS_KEY) return json(res, 401, { error: "key" });
  if (!pingsFile) return json(res, 503, { error: "telemetry off" });
  const text = await readFile(pingsFile, "utf8").catch(() => "");
  const lines = text.split("\n").filter(Boolean).map((l) => { try { return JSON.parse(l); } catch { return null; } });
  return json(res, 200, stats(fold(lines), url.searchParams.get("today") || new Date().toISOString().slice(0, 10)));
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === "GET" && req.url === "/health") return json(res, 200, { ok: true });
    if (req.method === "POST" && req.url === "/v1/session") return await handleSession(req, res);
    if (req.method === "POST" && req.url === "/v1/coach") return await handleCoach(req, res);
    if (req.method === "POST" && req.url === "/v1/ping") return await handlePing(req, res);
    if (req.method === "GET" && req.url.startsWith("/v1/stats")) return await handleStats(req, res);
    return json(res, 404, { error: "not found" });
  } catch (e) {
    console.error(e);
    return json(res, 500, { error: "internal error" });
  }
});

server.listen(Number(PORT), () => console.log(`coach proxy on :${PORT}, model ${MODEL}, limit ${DAILY_LIMIT}/day`));
