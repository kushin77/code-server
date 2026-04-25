/**
 * @file apps/copilot-engine/src/memory-schema.js
 * @module copilot-engine/memory-schema
 * @description Canonical memory schema validation and migration helpers.
 */

import schemaV1 from "../schemas/memory-snapshot.v1.schema.json" with { type: "json" };

export const MEMORY_SCHEMA_VERSION = "1.0.0";

function addError(errors, instancePath, message) {
  errors.push({ instancePath, message });
}

function validateRequiredObject(shape, value, path, errors) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    addError(errors, path, "must be an object");
    return;
  }

  for (const key of shape.required ?? []) {
    if (!(key in value)) {
      addError(errors, `${path}/${key}`, "is required");
    }
  }
}

function validateSchemaVersion(snapshot, errors) {
  const expected = schemaV1.properties?.schema_version?.const;
  if (snapshot.schema_version !== expected) {
    addError(
      errors,
      "/schema_version",
      `must be equal to constant '${expected}'`
    );
  }
}

function validateCoreStructures(snapshot, errors) {
  const top = schemaV1;
  validateRequiredObject(top, snapshot, "", errors);

  const intentMap = snapshot.intent_map;
  validateRequiredObject(top.properties.intent_map, intentMap, "/intent_map", errors);

  if (!Array.isArray(snapshot.suggestion_history)) {
    addError(errors, "/suggestion_history", "must be an array");
  }

  if (
    !snapshot.vector_store ||
    typeof snapshot.vector_store !== "object" ||
    Array.isArray(snapshot.vector_store)
  ) {
    addError(errors, "/vector_store", "must be an object");
  }

  if (!Array.isArray(snapshot.conversation_history)) {
    addError(errors, "/conversation_history", "must be an array");
  }

  validateRequiredObject(
    top.properties.retention,
    snapshot.retention,
    "/retention",
    errors
  );

  if (intentMap) {
    if (!Array.isArray(intentMap.session_goals)) {
      addError(errors, "/intent_map/session_goals", "must be an array");
    }
    if (!Array.isArray(intentMap.contradiction_log)) {
      addError(errors, "/intent_map/contradiction_log", "must be an array");
    }
    validateRequiredObject(
      top.properties.intent_map.properties.active_context,
      intentMap.active_context,
      "/intent_map/active_context",
      errors
    );
  }
}

/**
 * Validate canonical snapshot.
 * @param {any} snapshot
 */
export function validateMemorySnapshot(snapshot) {
  const errors = [];

  if (!snapshot || typeof snapshot !== "object" || Array.isArray(snapshot)) {
    return {
      valid: false,
      errors: [{ instancePath: "", message: "must be an object" }],
    };
  }

  validateSchemaVersion(snapshot, errors);
  validateCoreStructures(snapshot, errors);

  return {
    valid: errors.length === 0,
    errors,
  };
}

/**
 * Coerce legacy/current memory exports into canonical snapshot v1.
 * @param {any} snapshot
 */
export function migrateMemorySnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== "object") {
    throw new Error("snapshot must be an object");
  }

  if (snapshot.schema_version === MEMORY_SCHEMA_VERSION) {
    return snapshot;
  }

  // Legacy full persistence snapshot (pre-version field).
  if (
    snapshot.intent_map &&
    snapshot.suggestion_history &&
    snapshot.vector_store &&
    snapshot.conversation_history
  ) {
    return {
      schema_version: MEMORY_SCHEMA_VERSION,
      ...snapshot,
    };
  }

  // Legacy lightweight exportSnapshot() format.
  if (snapshot.intent_map && snapshot.active_goals && snapshot.contradictions) {
    return {
      schema_version: MEMORY_SCHEMA_VERSION,
      intent_map: snapshot.intent_map,
      suggestion_history: [],
      vector_store: {},
      conversation_history: [],
      retention: {
        resolvedGoalTtlMs: Number(process.env.MEMORY_RESOLVED_GOAL_TTL_MS ?? 7200000),
        maxConversationTurns: Number(process.env.MEMORY_MAX_CONVERSATION_TURNS ?? 30),
        suggestionRetentionMs: Number(
          process.env.MEMORY_SUGGESTION_RETENTION_MS ?? 7 * 24 * 60 * 60 * 1000
        ),
        contradictionRetentionMs: Number(
          process.env.MEMORY_CONTRADICTION_RETENTION_MS ??
            30 * 24 * 60 * 60 * 1000
        ),
      },
    };
  }

  throw new Error("unsupported memory snapshot format");
}

/**
 * Migrate then validate.
 * @param {any} snapshot
 */
export function migrateAndValidateMemorySnapshot(snapshot) {
  const migrated = migrateMemorySnapshot(snapshot);
  const validation = validateMemorySnapshot(migrated);

  if (!validation.valid) {
    const details = validation.errors
      .map((e) => `${e.instancePath || "/"} ${e.message}`)
      .join("; ");
    throw new Error(`invalid memory snapshot v${MEMORY_SCHEMA_VERSION}: ${details}`);
  }

  return migrated;
}
