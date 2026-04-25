/**
 * @file apps/copilot-engine/src/index.js
 * @module copilot-engine
 * @description Public entry point for the self-cleaning copilot engine.
 *
 * Quick start:
 *   import { CopilotMemory, createEngine } from "@code-server/copilot-engine";
 *
 *   const memory = new CopilotMemory();
 *   const engine = createEngine(memory);
 *
 *   const goalId = memory.addGoal("code", "Resolve GitPeak branch conflicts");
 *   const result = await engine.chat("How should I structure the resolver?", { domain: "code" });
 *   if (result.type === "response") {
 *     memory.lockDecision(goalId, "Use AST diffing for semantic conflict detection");
 *   }
 *
 * @governance GOV-002
 */

export { CopilotMemory } from "./memory.js";
export {
  InMemoryPersistenceBackend,
  RedisPersistenceBackend,
  PostgresPersistenceBackend,
  createMemoryPersistenceBackendFromEnv,
} from "./memory-persistence.js";
export {
  MEMORY_SCHEMA_VERSION,
  validateMemorySnapshot,
  migrateMemorySnapshot,
  migrateAndValidateMemorySnapshot,
} from "./memory-schema.js";
export {
  cosineSimilarity,
  mockEmbedding,
  embedText,
  setEmbeddingProvider,
  checkForDuplicates,
  detectContradictions,
  createOllamaEmbeddingProvider,
  createOpenAIEmbeddingProvider,
  configureEmbeddingProviderFromEnv,
} from "./deduplication.js";
export { correlationId, redact, logEvent } from "./logger.js";
export {
  classifyIssue,
  classifyPullRequest,
  extractIssuePrLinks,
  classifyGitHubWork,
} from "./github-sync.js";
export { createGitHubScanner } from "./github-scanner.js";
export { runDedupPreflight, emitDedupMetrics } from "./dedup-middleware.js";
export { ChatEngine, createEngine } from "./engine.js";
