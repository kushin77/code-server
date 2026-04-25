import test from "node:test";
import assert from "node:assert/strict";

import { CopilotMemory } from "../src/memory.js";
import { detectContradictions } from "../src/deduplication.js";

test("locking decisions persists in goal workflow", () => {
  const memory = new CopilotMemory();
  const goalId = memory.addGoal("code", "Finalize queue architecture");

  memory.lockDecision(goalId, "Use Redis for queue dispatch");

  const goal = memory.intentMap.session_goals.find((g) => g.id === goalId);
  assert.ok(goal);
  assert.equal(goal.decisions_made.length, 1);
  assert.equal(goal.decisions_made[0].decision, "Use Redis for queue dispatch");
});

test("contradiction detector flags overlapping locked decision intent", () => {
  const memory = new CopilotMemory();
  const goalId = memory.addGoal("code", "Queue architecture");
  memory.lockDecision(goalId, "Use Redis queue dispatch for background jobs");

  const conflicts = detectContradictions(
    "We should use Redis queue dispatch for all background jobs immediately",
    memory,
    0.3
  );

  assert.ok(conflicts.length >= 1);
  assert.match(conflicts[0].decision, /Redis queue dispatch/i);
});
