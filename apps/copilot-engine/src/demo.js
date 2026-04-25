/**
 * @file apps/copilot-engine/src/demo.js
 * @description Runnable smoke-test for the self-cleaning copilot engine.
 *   Exercises: goal tracking, dedup detection, decision locking, domain switch.
 *
 * Usage:
 *   ANTHROPIC_API_KEY=sk-ant-... node src/demo.js
 */

import { CopilotMemory } from "./memory.js";
import { createEngine } from "./engine.js";

async function demo() {
  console.log("🤖 SELF-CLEANING COPILOT ENGINE — demo\n");

  const memory = new CopilotMemory();
  const engine = createEngine(memory);

  // ------------------------------------------------------------------
  // TEST 1 — Add a goal
  // ------------------------------------------------------------------
  console.log("=== TEST 1: Register goal ===");
  const goalId = memory.addGoal("code", "Build GitPeak branch conflict resolver");
  console.log(`✓ Goal registered: ${goalId}\n`);

  // ------------------------------------------------------------------
  // TEST 2 — First message (no duplication expected)
  // ------------------------------------------------------------------
  console.log("=== TEST 2: First message ===");
  const r1 = await engine.chat(
    "How should I structure the conflict resolution engine for GitPeak?",
    { domain: "code", assumptions: ["TypeScript codebase", "GitHub API v4"] }
  );
  console.log("Type:", r1.type);
  if (r1.type === "response") {
    console.log("Response (first 200 chars):", r1.message.slice(0, 200));
  }
  console.log();

  // ------------------------------------------------------------------
  // TEST 3 — Semantically similar message → should be flagged
  // ------------------------------------------------------------------
  console.log("=== TEST 3: Duplicate detection ===");
  const r2 = await engine.chat(
    "What's the best architecture for handling Git branch conflicts in GitPeak?",
    { domain: "code" }
  );
  if (r2.type === "duplicate_flag") {
    console.log(`⚠️  Duplicate flagged (${(r2.similarity * 100).toFixed(1)}% similarity)`);
    console.log("Message:", r2.message);
  } else {
    console.log("No duplicate flagged (expected for mock embeddings).");
    console.log("Response (first 200 chars):", r2.message.slice(0, 200));
  }
  console.log();

  // ------------------------------------------------------------------
  // TEST 4 — Lock a decision
  // ------------------------------------------------------------------
  console.log("=== TEST 4: Lock decision ===");
  memory.lockDecision(goalId, "Use vector embeddings for semantic conflict detection");
  console.log("✓ Decision locked\n");

  // ------------------------------------------------------------------
  // TEST 5 — Domain switch (code → sales)
  // ------------------------------------------------------------------
  console.log("=== TEST 5: Domain switch ===");
  const r3 = await engine.chat(
    "Should I adjust the LinkedIn cold outreach template for ElevatedIQ GTM?",
    { domain: "sales" }
  );
  console.log("Type:", r3.type);
  if (r3.type === "response") {
    console.log("Response (first 200 chars):", r3.message.slice(0, 200));
  }
  console.log();

  // ------------------------------------------------------------------
  // Summary
  // ------------------------------------------------------------------
  const snap = memory.exportSnapshot();
  console.log("=== SESSION SUMMARY ===");
  console.log(`Active goals     : ${snap.active_goals.length}`);
  console.log(`Decisions locked : ${snap.recent_decisions.length}`);
  console.log(`Contradictions   : ${snap.contradictions.length}`);
  console.log(`Suggestions logged: ${memory.suggestionHistory.length}`);
}

demo().catch((err) => {
  console.error("Demo failed:", err.message);
  process.exit(1);
});
