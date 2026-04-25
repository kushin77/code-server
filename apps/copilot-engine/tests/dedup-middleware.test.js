import test from "node:test";
import assert from "node:assert/strict";

import { CopilotMemory } from "../src/memory.js";
import { mockEmbedding } from "../src/deduplication.js";
import { runDedupPreflight } from "../src/dedup-middleware.js";

function createStructuredLogger(sink) {
  return {
    info(line) {
      sink.push(JSON.parse(line));
    },
    warn(line) {
      sink.push(JSON.parse(line));
    },
    error(line) {
      sink.push(JSON.parse(line));
    },
    log(line) {
      sink.push(JSON.parse(line));
    },
  };
}

test("dedup middleware returns expand/pivot options with timestamp and emits hit-rate metrics", async () => {
  const memory = new CopilotMemory();
  const priorEmbedding = mockEmbedding("repeat me");
  memory.recordSuggestion("Prior recommendation", "code", priorEmbedding);

  const logs = [];
  const logger = createStructuredLogger(logs);
  const stats = { checks: 0, hits: 0 };

  const result = await runDedupPreflight({
    message: "repeat me",
    correlationId: "cid-test-1",
    memory,
    logger,
    stats,
  });

  assert.equal(result.type, "duplicate_flag");
  assert.equal(Array.isArray(result.next_actions), true);
  assert.deepEqual(result.next_actions, ["expand", "pivot"]);
  assert.equal(typeof result.prior_timestamp, "string");
  assert.ok(result.prior_timestamp.length > 0);

  const metric = logs.find((e) => e.event === "dedup_hit_rate");
  assert.ok(metric, "dedup_hit_rate metric event missing");
  assert.equal(metric.checks, 1);
  assert.equal(metric.hits, 1);
  assert.equal(metric.hit_rate, 1);
});
