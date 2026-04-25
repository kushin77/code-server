import test from "node:test";
import assert from "node:assert/strict";

import { CopilotMemory } from "../src/memory.js";
import {
  MEMORY_SCHEMA_VERSION,
  migrateAndValidateMemorySnapshot,
  migrateMemorySnapshot,
  validateMemorySnapshot,
} from "../src/memory-schema.js";

test("canonical persistence snapshot validates against JSON schema", () => {
  const memory = new CopilotMemory();
  memory.addGoal("code", "validate schema");
  const canonical = memory.exportPersistenceSnapshot();

  const result = validateMemorySnapshot(canonical);
  assert.equal(result.valid, true);
});

test("legacy lightweight exportSnapshot format migrates to canonical v1", () => {
  const memory = new CopilotMemory();
  memory.addGoal("code", "legacy export compatibility");
  const legacy = memory.exportSnapshot();

  const migrated = migrateAndValidateMemorySnapshot(legacy);

  assert.equal(migrated.schema_version, MEMORY_SCHEMA_VERSION);
  assert.ok(Array.isArray(migrated.suggestion_history));
  assert.deepEqual(migrated.vector_store, {});
  assert.ok(Array.isArray(migrated.conversation_history));
});

test("pre-version full persistence snapshot migrates with schema tag", () => {
  const memory = new CopilotMemory();
  const snapshot = memory.exportPersistenceSnapshot();
  delete snapshot.schema_version;

  const migrated = migrateMemorySnapshot(snapshot);
  const validation = validateMemorySnapshot(migrated);

  assert.equal(migrated.schema_version, MEMORY_SCHEMA_VERSION);
  assert.equal(validation.valid, true);
});
