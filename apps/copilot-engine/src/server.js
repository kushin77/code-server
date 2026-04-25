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
import { correlationId, logEvent, redact } from "./logger.js";

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
  const cid = correlationId(req.headers["x-correlation-id"]);

  res.setHeader("x-correlation-id", cid);
  logEvent(
    "info",
    "http_request_received",
    {
      correlation_id: cid,
      method,
      path: url,
    },
    console
  );

  // GET /health — always 200 (liveness)
  if (method === "GET" && url === "/health") {
    logEvent(
      "info",
      "http_request_completed",
      {
        correlation_id: cid,
        path: "/health",
        status_code: 200,
      },
      console
    );
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok", service: "copilot-engine" }));
    return;
  }

  // GET /ready — 200 if key present, 503 if not
  if (method === "GET" && url === "/ready") {
    const ready = Boolean(process.env.ANTHROPIC_API_KEY);
    const code = ready ? 200 : 503;
    logEvent(
      "info",
      "http_request_completed",
      {
        correlation_id: cid,
        path: "/ready",
        status_code: code,
        ready,
      },
      console
    );
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
        logEvent(
          "warn",
          "http_request_invalid_json",
          { correlation_id: cid, path: "/chat" },
          console
        );
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Invalid JSON" }));
        return;
      }

      const { message, domain, assumptions } = parsed;
      if (!message || typeof message !== "string") {
        logEvent(
          "warn",
          "http_request_invalid_payload",
          {
            correlation_id: cid,
            path: "/chat",
            payload: redact(parsed),
          },
          console
        );
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "message field is required (string)" }));
        return;
      }

      try {
        const engine = createEphemeralEngine();
        const result = await engine.chat(message, {
          domain: typeof domain === "string" ? domain : undefined,
          assumptions: Array.isArray(assumptions) ? assumptions : [],
          correlation_id: cid,
        });
        logEvent(
          "info",
          "http_request_completed",
          {
            correlation_id: cid,
            path: "/chat",
            result_type: result.type,
          },
          console
        );
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify(result));
      } catch (err) {
        logEvent(
          "error",
          "http_request_failed",
          {
            correlation_id: cid,
            path: "/chat",
            error: err.message,
          },
          console
        );
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Internal server error" }));
      }
    });
    return;
  }

  // POST /finetuning/prepare-dataset — prepare dataset for fine-tuning
  if (method === "POST" && url === "/finetuning/prepare-dataset") {
    logEvent(
      "info",
      "finetuning_prepare_dataset_started",
      { correlation_id: cid, path: url },
      console
    );
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 16_384) {
        req.destroy();
        res.writeHead(413, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Payload too large" }));
      }
    });

    req.on("end", async () => {
      try {
        const { FineTuningManager } = await import("./finetuning.js");
        const manager = new FineTuningManager();
        const dataset = await manager.prepareDataset();
        logEvent(
          "info",
          "finetuning_prepare_dataset_completed",
          {
            correlation_id: cid,
            path: url,
            examples: dataset?.metadata?.totalExamples ?? null,
          },
          console
        );
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify(dataset.metadata));
      } catch (err) {
        logEvent(
          "error",
          "finetuning_prepare_dataset_failed",
          {
            correlation_id: cid,
            path: url,
            error: err?.message ?? String(err),
          },
          console
        );
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: err?.message ?? "Unknown error" }));
      }
    });
    return;
  }

  // POST /finetuning/submit-job — submit a fine-tuning job
  if (method === "POST" && url === "/finetuning/submit-job") {
    logEvent(
      "info",
      "finetuning_submit_job_started",
      { correlation_id: cid, path: url },
      console
    );
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 16_384) {
        req.destroy();
        res.writeHead(413, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Payload too large" }));
      }
    });

    req.on("end", async () => {
      try {
        const parsed = JSON.parse(body);
        logEvent(
          "info",
          "finetuning_submit_job_payload_received",
          {
            correlation_id: cid,
            path: url,
            payload: redact(parsed),
          },
          console
        );
        const { FineTuningManager } = await import("./finetuning.js");
        const manager = new FineTuningManager();
        const job = manager.submitJob(`job-${Date.now()}`, parsed);
        logEvent(
          "info",
          "finetuning_submit_job_completed",
          {
            correlation_id: cid,
            path: url,
            job_id: job.id,
            status: job.status,
          },
          console
        );
        res.writeHead(201, { "Content-Type": "application/json" });
        res.end(JSON.stringify(job));
      } catch (err) {
        logEvent(
          "error",
          "finetuning_submit_job_failed",
          {
            correlation_id: cid,
            path: url,
            error: err?.message ?? String(err),
          },
          console
        );
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: err?.message ?? "Unknown error" }));
      }
    });
    return;
  }

  // GET /finetuning/metrics — export fine-tuning metrics
  if (method === "GET" && url === "/finetuning/metrics") {
    try {
      const { FineTuningManager } = await import("./finetuning.js");
      const manager = new FineTuningManager();
      const metrics = manager.exportMetrics();
      logEvent(
        "info",
        "finetuning_metrics_completed",
        {
          correlation_id: cid,
          path: url,
          jobs_tracked: Array.isArray(metrics?.jobs) ? metrics.jobs.length : null,
        },
        console
      );
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(metrics));
    } catch (err) {
      logEvent(
        "error",
        "finetuning_metrics_failed",
        {
          correlation_id: cid,
          path: url,
          error: err?.message ?? String(err),
        },
        console
      );
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: err?.message ?? "Unknown error" }));
    }
    return;
  }

  // 404 fallback
  logEvent(
    "warn",
    "http_request_not_found",
    { correlation_id: cid, method, path: url },
    console
  );
  res.writeHead(404, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ error: "Not found" }));
}

// ---------------------------------------------------------------------------
// Server startup
// ---------------------------------------------------------------------------

const server = createServer((req, res) => {
  router(req, res).catch((err) => {
    const cid = correlationId(req.headers["x-correlation-id"]);
    logEvent(
      "error",
      "http_router_unhandled_error",
      {
        correlation_id: cid,
        error: err?.message ?? String(err),
      },
      console
    );
    if (!res.headersSent) {
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Internal server error" }));
    }
  });
});

server.listen(PORT, "0.0.0.0", () => {
  logEvent(
    "info",
    "server_started",
    {
      port: PORT,
      anthropic_api_key: process.env.ANTHROPIC_API_KEY ? "set" : "NOT_SET",
    },
    console
  );
});

// Graceful shutdown — idempotent, safe to SIGTERM multiple times
let shutdownInProgress = false;
function gracefulShutdown(signal) {
  if (shutdownInProgress) return;
  shutdownInProgress = true;
  logEvent(
    "info",
    "server_shutdown_started",
    { signal },
    console
  );
  server.close(() => {
    logEvent("info", "server_shutdown_completed", {}, console);
    process.exit(0);
  });
  // Force-exit after 10 s if requests are still in-flight
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on("SIGTERM", () => gracefulShutdown("SIGTERM"));
process.on("SIGINT", () => gracefulShutdown("SIGINT"));
