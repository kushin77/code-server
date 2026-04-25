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
  cosineSimilarity,
  mockEmbedding,
  embedText,
  setEmbeddingProvider,
  checkForDuplicates,
  detectContradictions,
} from "./deduplication.js";
export { ChatEngine, createEngine } from "./engine.js";
