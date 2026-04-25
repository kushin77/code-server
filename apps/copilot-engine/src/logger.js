/**
 * @file apps/copilot-engine/src/logger.js
 * @module copilot-engine/logger
 * @description Structured logging utilities with correlation IDs and redaction.
 */

import { randomUUID } from "crypto";

const REDACTION_TOKEN = "[REDACTED]";
const SENSITIVE_KEY_PATTERN =
  /(secret|password|token|authorization|cookie|api[_-]?key|private[_-]?key)/i;

/**
 * Generate or normalize correlation IDs used across a turn lifecycle.
 * @param {string | undefined | null} incoming
 * @returns {string}
 */
export function correlationId(incoming) {
  if (incoming && typeof incoming === "string" && incoming.trim().length > 0) {
    return incoming.trim();
  }
  return randomUUID();
}

/**
 * Redact sensitive values from arbitrary objects before logging.
 * @param {unknown} value
 * @returns {unknown}
 */
export function redact(value) {
  return redactRecursive(value, "");
}

function redactRecursive(value, keyName) {
  if (value === null || value === undefined) return value;

  if (typeof value === "string") {
    if (SENSITIVE_KEY_PATTERN.test(keyName)) return REDACTION_TOKEN;
    if (/bearer\s+[a-z0-9._-]+/i.test(value)) return REDACTION_TOKEN;
    return value;
  }

  if (typeof value !== "object") return value;

  if (Array.isArray(value)) {
    return value.map((entry) => redactRecursive(entry, keyName));
  }

  const out = {};
  for (const [k, v] of Object.entries(value)) {
    if (SENSITIVE_KEY_PATTERN.test(k)) {
      out[k] = REDACTION_TOKEN;
      continue;
    }
    out[k] = redactRecursive(v, k);
  }
  return out;
}

/**
 * Emit a single structured log event.
 * @param {"debug"|"info"|"warn"|"error"} level
 * @param {string} event
 * @param {Record<string, unknown>} payload
 * @param {Console} logger
 */
export function logEvent(level, event, payload, logger = console) {
  const entry = {
    ts: new Date().toISOString(),
    level,
    event,
    ...redact(payload),
  };

  const line = JSON.stringify(entry);
  const sink = typeof logger[level] === "function" ? logger[level] : logger.log;
  sink.call(logger, line);
}
