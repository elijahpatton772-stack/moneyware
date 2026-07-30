// =============================================================================
//  MoneyWare  ·  AUTH SERVER   (pure Node.js — no npm install needed)
//
//  Holds the hashed key DB, enforces HWID lock + expiry + bans, and only hands
//  back the real script payload AFTER a key + HWID pass. That last part is the
//  whole game: a leaked key on the wrong machine gets NOTHING, because the
//  cheat code never leaves this server until validation succeeds.
//
//  RUN:   node server.js
//  (listens on PORT below, default 8080)
// =============================================================================

const http   = require("http");
const crypto = require("crypto");
const fs     = require("fs");
const path   = require("path");

const HERE        = __dirname;
const SEED_DB     = path.join(HERE, "db.json");           // shipped copy: keys + pepper + admin token
const DB_PATH     = process.env.DB_PATH || SEED_DB;       // in prod, point this at a PERSISTENT volume
const PAYLOAD_LUA = process.env.PAYLOAD_LUA || path.join(HERE, "payload.lua");  // your real MoneyWare script
const PORT        = process.env.PORT || 8080;
const DISCORD_WEBHOOK = process.env.DISCORD_WEBHOOK || "";   // optional: set to enable live alerts

// On a fresh persistent volume the db file won't exist yet — seed it ONCE from
// the shipped db.json so your 100 keys + pepper + admin token are present.
// After that, the volume copy is the source of truth and survives restarts,
// so HWID bindings and bans are NEVER lost on a redeploy.
if (DB_PATH !== SEED_DB && !fs.existsSync(DB_PATH)) {
  try {
    fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });
    fs.copyFileSync(SEED_DB, DB_PATH);
    console.log("seeded persistent DB at " + DB_PATH);
  } catch (e) { console.error("seed copy failed: " + e.message); }
}

// --- rate limit (per IP) -----------------------------------------------------
const RL_WINDOW_MS = 60 * 1000;
const RL_MAX       = 30;               // 30 auth hits / minute / IP
const rl = new Map();

function rateLimited(ip) {
  const now = Date.now();
  const e = rl.get(ip);
  if (!e || now > e.resetAt) { rl.set(ip, { count: 1, resetAt: now + RL_WINDOW_MS }); return false; }
  e.count++;
  return e.count > RL_MAX;
}

// --- db ----------------------------------------------------------------------
let db;
function loadDB() {
  db = JSON.parse(fs.readFileSync(DB_PATH, "utf8"));
  if (!db.keys) db.keys = {};
}
function saveDB() {
  // atomic-ish write: temp file then rename, so a crash mid-write can't corrupt.
  const tmp = DB_PATH + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(db, null, 2));
  fs.renameSync(tmp, DB_PATH);
}
loadDB();

function keyHash(key) {
  return crypto.createHash("sha256")
    .update(`${db.pepper}:${String(key).trim().toUpperCase()}`)
    .digest("hex");
}

function timingSafeEq(a, b) {
  const ba = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  if (ba.length !== bb.length) return false;
  return crypto.timingSafeEqual(ba, bb);
}

// --- helpers -----------------------------------------------------------------
function send(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, { "Content-Type": "application/json", "Cache-Control": "no-store" });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = "";
    req.on("data", (c) => { data += c; if (data.length > 1e6) req.destroy(); });
    req.on("end", () => { try { resolve(JSON.parse(data || "{}")); } catch { resolve(null); } });
  });
}

function clientIP(req) {
  return (req.headers["x-forwarded-for"] || "").split(",")[0].trim()
      || req.socket.remoteAddress || "?";
}

function requireAdmin(body) {
  return body && typeof body.token === "string" && timingSafeEq(body.token, db.admin_token);
}

// --- Discord alerts (optional; set DISCORD_WEBHOOK env to turn on) -----------
// Fire-and-forget: a dead/slow Discord can NEVER stall or break an auth.
function notifyDiscord(kind, key, rec, hwid, ip) {
  if (!DISCORD_WEBHOOK) return;
  const styles = {
    activation: { title: "🟢 Key Activated",               color: 0x2ecc71 },
    theft:      { title: "🔴 Stolen / Shared Key Blocked",  color: 0xe74c3c },
    banned:     { title: "⛔ Revoked Key Attempted",        color: 0xe67e22 },
    expired:    { title: "🟡 Expired Key Attempted",        color: 0xf1c40f },
  };
  const st = styles[kind] || { title: "MoneyWare event", color: 0x8a6eff };
  const cut = (s) => "`" + String(s).slice(0, 60) + "`";
  const fields = [
    { name: "Key",  value: cut(String(key).trim().toUpperCase()), inline: true },
    { name: "Tier", value: rec ? rec.tier : "?",                  inline: true },
  ];
  if (kind === "theft") {
    fields.push({ name: "Locked to HWID",       value: cut(rec.hwid), inline: false });
    fields.push({ name: "Attempted from HWID",  value: cut(hwid),     inline: false });
  } else {
    fields.push({ name: "HWID", value: cut(hwid), inline: false });
  }
  fields.push({ name: "IP", value: String(ip), inline: true });

  const payload = {
    username: "MoneyWare",
    embeds: [{ title: st.title, color: st.color, fields, timestamp: new Date().toISOString() }],
  };
  try {
    fetch(DISCORD_WEBHOOK, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    }).catch(() => {});
  } catch (_) {}
}

// --- /auth -------------------------------------------------------------------
async function handleAuth(req, res) {
  const ip = clientIP(req);
  if (rateLimited(ip)) return send(res, 429, { ok: false, reason: "rate_limited" });

  const body = await readBody(req);
  if (!body || typeof body.key !== "string" || typeof body.hwid !== "string")
    return send(res, 400, { ok: false, reason: "bad_request" });

  const hwid = body.hwid.trim();
  if (hwid.length < 6) return send(res, 400, { ok: false, reason: "no_hwid" });

  const rec = db.keys[keyHash(body.key)];
  if (!rec)          return send(res, 200, { ok: false, reason: "invalid" });
  if (rec.banned)  { notifyDiscord("banned", body.key, rec, hwid, ip);
                     return send(res, 200, { ok: false, reason: "banned" }); }

  const now = Math.floor(Date.now() / 1000);

  // first redeem -> bind this machine forever (and start the clock for month keys)
  if (!rec.hwid) {
    rec.hwid = hwid;
    rec.redeemed_at = now;
    if (rec.duration_days) rec.expires_at = now + rec.duration_days * 86400;
    saveDB();
    notifyDiscord("activation", body.key, rec, hwid, ip);
  } else if (!timingSafeEq(rec.hwid, hwid)) {
    // key is bound to a DIFFERENT machine -> stolen / shared -> denied, always.
    notifyDiscord("theft", body.key, rec, hwid, ip);
    return send(res, 200, { ok: false, reason: "hwid_mismatch" });
  }

  if (rec.expires_at && now > rec.expires_at) {
    notifyDiscord("expired", body.key, rec, hwid, ip);
    return send(res, 200, { ok: false, reason: "expired", expires_at: rec.expires_at });
  }

  // PASSED. hand over the real script (read fresh so you can update it live).
  let payload = "";
  try { payload = fs.readFileSync(PAYLOAD_LUA, "utf8"); }
  catch { payload = 'warn("[MoneyWare] payload.lua missing on server")'; }

  return send(res, 200, {
    ok: true,
    tier: rec.tier,
    expires_at: rec.expires_at,          // null = lifetime
    redeemed_at: rec.redeemed_at,
    payload,
  });
}

// --- /admin/* ----------------------------------------------------------------
async function handleAdmin(req, res, action) {
  const body = await readBody(req);
  if (!requireAdmin(body)) return send(res, 403, { ok: false, reason: "forbidden" });

  if (action === "list") {
    const out = Object.entries(db.keys).map(([h, r]) => ({
      hash: h.slice(0, 12), tier: r.tier, bound: !!r.hwid, banned: r.banned,
      redeemed_at: r.redeemed_at, expires_at: r.expires_at,
    }));
    return send(res, 200, { ok: true, total: out.length, keys: out });
  }

  // ban / unban / reset-hwid all target a specific key
  if (typeof body.key !== "string") return send(res, 400, { ok: false, reason: "need_key" });
  const rec = db.keys[keyHash(body.key)];
  if (!rec) return send(res, 200, { ok: false, reason: "invalid" });

  if (action === "ban")        { rec.banned = true;  saveDB(); return send(res, 200, { ok: true, banned: true }); }
  if (action === "unban")      { rec.banned = false; saveDB(); return send(res, 200, { ok: true, banned: false }); }
  if (action === "reset-hwid") { rec.hwid = null;    saveDB(); return send(res, 200, { ok: true, hwid_reset: true }); }

  return send(res, 404, { ok: false, reason: "unknown_action" });
}

// --- router ------------------------------------------------------------------
const server = http.createServer(async (req, res) => {
  try {
    const url = req.url.split("?")[0];
    if (req.method === "GET" && url === "/health") return send(res, 200, { ok: true, up: true });
    if (req.method === "POST" && url === "/auth")               return handleAuth(req, res);
    if (req.method === "POST" && url === "/admin/list")         return handleAdmin(req, res, "list");
    if (req.method === "POST" && url === "/admin/ban")          return handleAdmin(req, res, "ban");
    if (req.method === "POST" && url === "/admin/unban")        return handleAdmin(req, res, "unban");
    if (req.method === "POST" && url === "/admin/reset-hwid")   return handleAdmin(req, res, "reset-hwid");
    return send(res, 404, { ok: false, reason: "not_found" });
  } catch (e) {
    return send(res, 500, { ok: false, reason: "server_error" });
  }
});

server.listen(PORT, () => {
  console.log("=".repeat(56));
  console.log(" MoneyWare server up on port " + PORT);
  console.log(" keys loaded : " + Object.keys(db.keys).length);
  console.log(" payload     : " + (fs.existsSync(PAYLOAD_LUA) ? "loaded" : "!! payload.lua MISSING !!"));
  console.log(" alerts      : " + (DISCORD_WEBHOOK ? "ON (Discord)" : "off (set DISCORD_WEBHOOK)"));
  console.log(" endpoints   : POST /auth  |  POST /admin/{list,ban,unban,reset-hwid}");
  console.log("=".repeat(56));
});
