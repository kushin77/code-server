/**
 * @file apps/copilot-engine/src/dedup-middleware.js
 * @module copilot-engine/dedup-middleware
 * @description Preflight dedup middleware with hit-rate metrics emission.
 */

import { checkForDuplicates } from "./deduplication.js";
import { logEvent } from "./logger.js";

/**
 * @param {{checks: number, hits: number}} stats
 * @param {string} correlationId
 * @param {Console} logger
 */
export function emitDedupMetrics(stats, correlationId, logger) {
  const hitRate = stats.checks === 0 ? 0 : stats.hits / stats.checks;
  logEvent(
    "info",
    "dedup_hit_rate",
    {
      correlation_id: correlationId,
      checks: stats.checks,
      hits: stats.hits,
      hit_rate: Number(hitRate.toFixed(4)),
    },
    logger
  );
}

/**
 * Run duplicate preflight before recommendation generation.
 * Returns duplicate response payload when duplicate is detected, otherwise null.
 *
 * @param {{message: string, correlationId: string, memory: any, logger: Console, stats: {checks:number, hits:number}}} input
 */
export async function runDedupPreflight(input) {
  const { message, correlationId, memory, logger, stats } = input;

  logEvent(
    "info",
    "dedup_check_started",
    { correlation_id: correlationId },
    logger
  );

  stats.checks += 1;
  const dupResult = await checkForDuplicates(message, memory);

  if (!dupResult.isDuplicate) {
    logEvent(
      "info",
      "dedup_check_passed",
      { correlation_id: correlationId },
      logger
    );
    emitDedupMetrics(stats, correlationId, logger);
    return null;
  }

  stats.hits += 1;
  const pct = (dupResult.similarity * 100).toFixed(1);

  logEvent(
    "warn",
    "dedup_check_matched",
    {
      correlation_id: correlationId,
      similarity: dupResult.similarity,
      prior_timestamp: dupResult.prior.timestamp,
    },
    logger
  );

  emitDedupMetrics(stats, correlationId, logger);

  return {
    type: "duplicate_flag",
    correlation_id: correlationId,
    similarity: dupResult.similarity,
    prior_suggestion: dupResult.prior.content,
    prior_timestamp: dupResult.prior.timestamp,
    next_actions: ["expand", "pivot"],
    message:
      `I already addressed something very similar at ${dupResult.prior.timestamp} ` +
      `(${pct}% semantic overlap). Would you like me to expand on that, ` +
      `or should we take a different angle?`,
  };
}
