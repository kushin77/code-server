/**
 * @file apps/copilot-engine/src/server.js
 * @module copilot-engine/server
 * @description Minimal HTTP server exposing the copilot engine over REST.
 *   Designed to run as a stateless container — all session state is
 *   caller-managed (or wired to Redis in production).
 *
 * Endpoints:
 *   GET  /health   — liveness probe (no auth required)
 *   GET  /ready    — readiness probe (verifies ANTHROPIC_API_KEY is set)
 *   POST /chat     — single-turn chat (JSON body: { message, domain?, assumptions? })
 *
 * Environment variables:
 *   PORT              — HTTP listen port (default: 8030)
 *   ANTHROPIC_API_KEY — Required for /chat; absence makes /ready return 503
 *
 * @governance GOV-002: No secrets in code, idempotent startup, health checks
 */

import { createServer } from "http";
import { CopilotMemory } from "./memory.js";
import { createEngine } from "./engine.js";

// ---------------------------------------------------------------------------
// Config — environment-driven, no hardcoded values
// ---------------------------------------------------------------------------
const PORT = parseInt(process.env.PORT ?? "8030", 10);

// ---------------------------------------------------------------------------
// Per-request engine (stateless — production should inject a shared memory
// backed by Redis, but this is safe for single-turn usage)
// ---------------------------------------------------------------------------
function createEphemeralEngine() {
  const memory = new CopilotMemory();
  return createEngine(memory);
}

// ---------------------------------------------------------------------------
// Request routing
// ---------------------------------------------------------------------------

/**
 * @param {import("http").IncomingMessage} req
 * @param {import("http").ServerResponse}  res
 */
async function router(req, res) {
  const { method, url } = req;

  // GET /health — always 200 (liveness)
  if (method === "GET" && url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok", service: "copilot-engine" }));
    return;
  }

  // GET /ready — 200 if key present, 503 if not
  if (method === "GET" && url === "/ready") {
    const ready = Boolean(process.env.ANTHROPIC_API_KEY);
    const code = ready ? 200 : 503;
    res.writeHead(code, { "Content-Type": "application/json" });
    res.end(
      JSON.stringify({
        status: ready ? "ready" : "not_ready",
        reason: ready ? null : "ANTHROPIC_API_KEY not set",
      })
    );
    return;
  }

  // POST /chat — single-turn copilot invocation
  if (method === "POST" && url === "/chat") {
    if (!process.env.ANTHROPIC_API_KEY) {
      res.writeHead(503, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "ANTHROPIC_API_KEY not set" }));
      return;
    }

    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      // Guard against oversized payloads (16 KB max)
      if (body.length > 16_384) {
        req.destroy();
        res.writeHead(413, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Payload too large" }));
      }
    });

    req.on("end", async () => {
      let parsed;
      try {
        parsed = JSON.parse(body);
      } catch {
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Invalid JSON" }));
        return;
      }

      const { message, domain, assumptions } = parsed;
      if (!message || typeof message !== "string") {
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "message field is required (string)" }));
        return;
      }

      try {
        const engine = createEphemeralEngine();
        const result = await engine.chat(message, {
          domain: typeof domain === "string" ? domain : undefined,
          assumptions: Array.isArray(assumptions) ? assumptions : [],
        });
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify(result));
      } catch (err) {
        console.error("[copilot-engine] Chat error:", err.message);
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Internal server error" }));
      }
    });
    return;
  }

  // 404 fallback
  res.writeHead(404, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ error: "Not found" }));
}

// ---------------------------------------------------------------------------
// Server startup
// ---------------------------------------------------------------------------

const server = createServer((req, res) => {
  router(req, res).catch((err) => {
    console.error("[copilot-engine] Unhandled router error:", err);
    if (!res.headersSent) {
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Internal server error" }));
    }
  });
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(
    `[copilot-engine] Listening on port ${PORT} (ANTHROPIC_API_KEY: ${
      process.env.ANTHROPIC_API_KEY ? "set" : "NOT SET"
    })`
  );
});

// Graceful shutdown — idempotent, safe to SIGTERM multiple times
let shutdownInProgress = false;
function gracefulShutdown(signal) {
  if (shutdownInProgress) return;
  shutdownInProgress = true;
  console.log(`[copilot-engine] ${signal} received — shutting down gracefully`);
  server.close(() => {
    console.log("[copilot-engine] Server closed");
    process.exit(0);
  });
  // Force-exit after 10 s if requests are still in-flight
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on("SIGTERM", () => gracefulShutdown("SIGTERM"));
process.on("SIGINT", () => gracefulShutdown("SIGINT"));
