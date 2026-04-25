import test from "node:test";
import assert from "node:assert/strict";

import {
  checkForDuplicates,
  configureEmbeddingProviderFromEnv,
  createOllamaEmbeddingProvider,
  embedText,
  setEmbeddingProvider,
} from "../src/deduplication.js";
import { CopilotMemory } from "../src/memory.js";

test("configureEmbeddingProviderFromEnv in auto mode falls back to mock embeddings", async () => {
  const originalProvider = process.env.EMBEDDING_PROVIDER;
  const originalFallback = process.env.EMBEDDING_FALLBACK_TO_MOCK;
  const originalOllamaUrl = process.env.OLLAMA_EMBEDDING_URL;

  process.env.EMBEDDING_PROVIDER = "auto";
  process.env.EMBEDDING_FALLBACK_TO_MOCK = "true";
  process.env.OLLAMA_EMBEDDING_URL = "http://127.0.0.1:0/unavailable";

  configureEmbeddingProviderFromEnv();

  const vector = await embedText("provider fallback smoke test");
  assert.ok(Array.isArray(vector));
  assert.ok(vector.length > 0);

  if (originalProvider === undefined) delete process.env.EMBEDDING_PROVIDER;
  else process.env.EMBEDDING_PROVIDER = originalProvider;

  if (originalFallback === undefined)
    delete process.env.EMBEDDING_FALLBACK_TO_MOCK;
  else process.env.EMBEDDING_FALLBACK_TO_MOCK = originalFallback;

  if (originalOllamaUrl === undefined) delete process.env.OLLAMA_EMBEDDING_URL;
  else process.env.OLLAMA_EMBEDDING_URL = originalOllamaUrl;
});

test("createOllamaEmbeddingProvider parses embedding payload", async () => {
  const provider = createOllamaEmbeddingProvider({
    fetchFn: async () => ({
      ok: true,
      json: async () => ({ embedding: [0.1, 0.2, 0.3] }),
    }),
  });

  const embedding = await provider("hello");
  assert.deepEqual(embedding, [0.1, 0.2, 0.3]);
});

test("checkForDuplicates includes latency lookup fields", async () => {
  setEmbeddingProvider(async () => [1, 0, 0, 0]);

  const memory = new CopilotMemory();
  memory.recordSuggestion("previous", "code", [1, 0, 0, 0]);

  const result = await checkForDuplicates("current", memory, 0.1, 10_000);

  assert.equal(typeof result.lookup_latency_ms, "number");
  assert.equal(result.lookup_latency_target_ms, 10000);
  assert.equal(typeof result.lookup_within_target, "boolean");
});
