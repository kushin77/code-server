import test from "node:test";
import assert from "node:assert/strict";

import { CopilotMemory } from "../src/memory.js";
import {
  InMemoryPersistenceBackend,
  PostgresPersistenceBackend,
  RedisPersistenceBackend,
} from "../src/memory-persistence.js";

test("InMemory backend persists and hydrates CopilotMemory snapshot", async () => {
  const backend = new InMemoryPersistenceBackend();
  const sessionId = "session-1";

  const source = new CopilotMemory();
  source.addGoal("code", "ship persistence");
  source.recordSuggestion("do x", "code", [0.1, 0.2, 0.3]);
  source.appendTurn("user", "hello");
  await source.persist(backend, sessionId);

  const target = new CopilotMemory();
  await target.hydrate(backend, sessionId);

  assert.equal(target.intentMap.session_goals.length, 1);
  assert.equal(target.suggestionHistory.length, 1);
  assert.equal(target.conversationHistory.length, 1);
});

test("Redis backend writes indexed session metadata and prunes by retention", async () => {
  const calls = [];
  const client = {
    set: async (...args) => calls.push(["set", ...args]),
    zAdd: async (...args) => calls.push(["zAdd", ...args]),
    zRangeByScore: async () => ["old-session"],
    del: async (...args) => calls.push(["del", ...args]),
    zRemRangeByScore: async (...args) => calls.push(["zRemRangeByScore", ...args]),
    get: async () => null,
  };

  const backend = new RedisPersistenceBackend({
    client,
    keyPrefix: "test:memory",
    retentionDays: 1,
  });

  await backend.saveSnapshot("abc", { ok: true });
  await backend.pruneExpired();

  const setCall = calls.find((c) => c[0] === "set");
  const zAddCall = calls.find((c) => c[0] === "zAdd");
  const delCall = calls.find((c) => c[0] === "del");
  const zRemCall = calls.find((c) => c[0] === "zRemRangeByScore");

  assert.ok(setCall, "expected SET call");
  assert.ok(zAddCall, "expected ZADD index call");
  assert.ok(delCall, "expected DEL stale snapshot call");
  assert.ok(zRemCall, "expected ZREMRANGEBYSCORE cleanup call");
});

test("Postgres backend creates index-friendly schema and performs indexed reads", async () => {
  const queries = [];
  const client = {
    query: async (sql, params) => {
      queries.push({ sql, params });
      if (sql.includes("SELECT snapshot")) {
        return { rows: [{ snapshot: { ok: true } }] };
      }
      return { rows: [] };
    },
  };

  const backend = new PostgresPersistenceBackend({
    client,
    schema: "public",
    retentionDays: 14,
  });

  await backend.saveSnapshot("session-1", { a: 1 });
  const loaded = await backend.loadSnapshot("session-1");
  await backend.pruneExpired();

  assert.deepEqual(loaded, { ok: true });

  const hasIndex = queries.some((q) =>
    q.sql.includes("CREATE INDEX IF NOT EXISTS idx_copilot_memory_snapshots_updated_at")
  );
  const hasIndexedRead = queries.some(
    (q) =>
      q.sql.includes("ORDER BY updated_at DESC") && q.sql.includes("LIMIT 1")
  );
  const hasPrune = queries.some((q) => q.sql.includes("DELETE FROM public.copilot_memory_snapshots"));

  assert.ok(hasIndex, "expected updated_at index creation");
  assert.ok(hasIndexedRead, "expected indexed read query");
  assert.ok(hasPrune, "expected retention prune query");
});

test("CopilotMemory retention config prunes old suggestions and contradictions", () => {
  const memory = new CopilotMemory({
    suggestionRetentionMs: 10,
    contradictionRetentionMs: 10,
    maxConversationTurns: 2,
  });

  memory.suggestionHistory.push({
    id: "old",
    content: "old",
    domain: "code",
    timestamp: new Date(Date.now() - 1000).toISOString(),
    user_feedback: null,
  });
  memory.vectorStore.set("old", [1, 2, 3]);
  memory.intentMap.contradiction_log.push({
    date: new Date(Date.now() - 1000).toISOString(),
    suggestion_a: "a",
    suggestion_b: "b",
    resolution: "r",
  });

  memory.appendTurn("user", "1");
  memory.appendTurn("assistant", "2");
  memory.appendTurn("user", "3");

  memory.pruneRetention();

  assert.equal(memory.suggestionHistory.length, 0);
  assert.equal(memory.vectorStore.size, 0);
  assert.equal(memory.intentMap.contradiction_log.length, 0);
  assert.equal(memory.conversationHistory.length, 2);
});
