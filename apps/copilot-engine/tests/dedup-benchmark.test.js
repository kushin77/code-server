import test from "node:test";
import assert from "node:assert/strict";
import { performance } from "node:perf_hooks";

import { checkForDuplicates, setEmbeddingProvider } from "../src/deduplication.js";
import { CopilotMemory } from "../src/memory.js";

test("dedup lookup p95 latency stays within default target window", async () => {
  setEmbeddingProvider(async () => [1, 0, 0, 1]);

  const memory = new CopilotMemory();
  for (let i = 0; i < 250; i++) {
    memory.recordSuggestion(`suggestion-${i}`, "code", [1, 0, 0, 1]);
  }

  const samples = [];
  for (let i = 0; i < 30; i++) {
    const started = performance.now();
    const result = await checkForDuplicates("target-message", memory, 0.1, 150);
    const elapsed = performance.now() - started;

    assert.equal(result.lookup_within_target, true);
    samples.push(elapsed);
  }

  samples.sort((a, b) => a - b);
  const p95 = samples[Math.floor(samples.length * 0.95) - 1] ?? samples[samples.length - 1];

  assert.ok(p95 <= 150, `expected p95 <= 150ms, got ${p95.toFixed(2)}ms`);
});
