import { describe, expect, it } from "vitest";
import {
  RepositoryIndexer,
  evaluateRetrievalQuality,
  type RetrievalBenchmarkCase,
  type RepositoryFile,
} from "../indexing";

const CORPUS: RepositoryFile[] = [
  { path: "src/auth/login.ts", content: "function loginUser token validate session cookie" },
  { path: "src/auth/logout.ts", content: "function logoutUser revoke session token" },
  { path: "src/auth/refresh.ts", content: "function refreshToken rotate jwt expiry" },
  { path: "src/db/users.ts", content: "function queryUsers postgres index where email" },
  { path: "src/db/orders.ts", content: "function queryOrders postgres join orderItems" },
  { path: "src/cache/redis.ts", content: "function cacheSet redis ttl key value" },
  { path: "src/cache/invalidate.ts", content: "function invalidateCache redis delete key" },
  { path: "src/http/router.ts", content: "function routeRequest express middleware handler" },
  { path: "src/http/retry.ts", content: "function retryRequest backoff timeout http client" },
  { path: "src/observability/tracing.ts", content: "function traceSpan opentelemetry jaeger exporter" },
  { path: "src/observability/logging.ts", content: "function logEvent json structured correlation" },
  { path: "src/queue/worker.ts", content: "function processQueue async worker concurrency" },
  { path: "src/queue/scheduler.ts", content: "function scheduleJob cron interval nextRun" },
  { path: "src/security/rbac.ts", content: "function enforceRbac role permission policy" },
  { path: "src/security/audit.ts", content: "function writeAudit immutable event chain" },
  { path: "src/deploy/compose.ts", content: "function deployCompose docker service healthcheck" },
  { path: "src/deploy/rollback.ts", content: "function rollbackDeploy version revert release" },
  { path: "src/ai/indexer.ts", content: "function chunkSemantic overlap token deduplicate" },
  { path: "src/ai/search.ts", content: "function searchChunks ranking precision recall" },
  { path: "src/ai/bench.ts", content: "function benchmarkRetrieval p95 latency hitrate" },
];

const CASES: RetrievalBenchmarkCase[] = [
  { query: "login token session", expectedFilePaths: ["src/auth/login.ts"] },
  { query: "logout revoke session", expectedFilePaths: ["src/auth/logout.ts"] },
  { query: "rotate jwt expiry", expectedFilePaths: ["src/auth/refresh.ts"] },
  { query: "postgres query users", expectedFilePaths: ["src/db/users.ts"] },
  { query: "orders join postgres", expectedFilePaths: ["src/db/orders.ts"] },
  { query: "redis ttl key value", expectedFilePaths: ["src/cache/redis.ts"] },
  { query: "invalidate redis delete", expectedFilePaths: ["src/cache/invalidate.ts"] },
  { query: "express middleware handler", expectedFilePaths: ["src/http/router.ts"] },
  { query: "retry timeout backoff", expectedFilePaths: ["src/http/retry.ts"] },
  { query: "opentelemetry jaeger span", expectedFilePaths: ["src/observability/tracing.ts"] },
  { query: "structured json correlation", expectedFilePaths: ["src/observability/logging.ts"] },
  { query: "queue worker concurrency", expectedFilePaths: ["src/queue/worker.ts"] },
  { query: "cron schedule interval", expectedFilePaths: ["src/queue/scheduler.ts"] },
  { query: "rbac role permission", expectedFilePaths: ["src/security/rbac.ts"] },
  { query: "audit immutable chain", expectedFilePaths: ["src/security/audit.ts"] },
  { query: "docker compose healthcheck", expectedFilePaths: ["src/deploy/compose.ts"] },
  { query: "rollback release revert", expectedFilePaths: ["src/deploy/rollback.ts"] },
  { query: "semantic chunk overlap", expectedFilePaths: ["src/ai/indexer.ts"] },
  { query: "ranking precision recall", expectedFilePaths: ["src/ai/search.ts"] },
  { query: "benchmark p95 hitrate", expectedFilePaths: ["src/ai/bench.ts"] },
];

describe("evaluateRetrievalQuality", () => {
  it("computes precision/recall/hit-rate over 20 benchmark cases", async () => {
    const indexer = new RepositoryIndexer({ chunkSizeTokens: 32, chunkOverlapTokens: 4 });
    await indexer.indexRepository(CORPUS);

    const result = evaluateRetrievalQuality(indexer, CASES, 3);

    expect(result.totalCases).toBe(20);
    expect(result.hitRate).toBeGreaterThanOrEqual(0.9);
    expect(result.precision).toBeGreaterThanOrEqual(0.9);
    expect(result.recall).toBeGreaterThanOrEqual(0.9);
    expect(result.p95LatencyMs).toBeGreaterThanOrEqual(0);
  });
});
