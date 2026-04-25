/**
 * @file apps/copilot-engine/src/memory.js
 * @module copilot-engine/memory
 * @description Layer 1 — Structured Intent Map + suggestion history for the
 *   self-cleaning copilot. Keeps session goals, decisions, contradiction log,
 *   and rolling conversation context.
 * @governance GOV-002: All memory mutations logged for audit
 */

import { randomUUID } from "crypto";
import { migrateAndValidateMemorySnapshot } from "./memory-schema.js";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const RESOLVED_GOAL_TTL_MS = 2 * 60 * 60 * 1000; // 2 hours
const MAX_CONVERSATION_TURNS = 30; // 15 exchanges × 2 (user + assistant)
const MEMORY_SCHEMA_VERSION = "1.0.0";

// ---------------------------------------------------------------------------
// CopilotMemory
// ---------------------------------------------------------------------------

export class CopilotMemory {
  constructor(options = {}) {
    this.retention = {
      resolvedGoalTtlMs:
        options.resolvedGoalTtlMs ??
        Number(process.env.MEMORY_RESOLVED_GOAL_TTL_MS ?? RESOLVED_GOAL_TTL_MS),
      maxConversationTurns:
        options.maxConversationTurns ??
        Number(process.env.MEMORY_MAX_CONVERSATION_TURNS ?? MAX_CONVERSATION_TURNS),
      suggestionRetentionMs:
        options.suggestionRetentionMs ??
        Number(
          process.env.MEMORY_SUGGESTION_RETENTION_MS ?? 7 * 24 * 60 * 60 * 1000
        ),
      contradictionRetentionMs:
        options.contradictionRetentionMs ??
        Number(
          process.env.MEMORY_CONTRADICTION_RETENTION_MS ??
            30 * 24 * 60 * 60 * 1000
        ),
    };

    /** @type {IntentMap} */
    this.intentMap = {
      session_goals: [],
      active_context: {
        current_domain: null,
        current_task: null,
        blockers: [],
        assumptions: [],
        github_sync: {
          thresholds: {
            issue_stalled_days: 30,
            pr_stalled_days: 14,
          },
          issue_pr_links: [],
          last_ingested_at: null,
          summary: {
            completed: 0,
            in_progress: 0,
            blocked: 0,
            deferred: 0,
          },
        },
      },
      contradiction_log: [],
    };

    /** @type {Array<SuggestionRecord>} Layer 2 — deduplication index */
    this.suggestionHistory = [];

    /** @type {Map<string, number[]>} suggestion_id → embedding vector */
    this.vectorStore = new Map();

    /** @type {Array<ConversationTurn>} Layer 3 — rolling window */
    this.conversationHistory = [];
  }

  // -------------------------------------------------------------------------
  // Goals
  // -------------------------------------------------------------------------

  /**
   * Register a new session goal.
   * @param {"code"|"infra"|"sales"|"product"|"general"} domain
   * @param {string} intent
   * @returns {string} goal id
   */
  addGoal(domain, intent) {
    const goal = {
      id: `goal_${randomUUID()}`,
      domain,
      intent,
      status: "active",
      created_at: new Date().toISOString(),
      last_referenced: new Date().toISOString(),
      decisions_made: [],
    };
    this.intentMap.session_goals.push(goal);
    return goal.id;
  }

  /**
   * Mark a goal as completed or blocked.
   * @param {string} goalId
   * @param {"completed"|"blocked"} status
   */
  updateGoalStatus(goalId, status) {
    const goal = this._findGoal(goalId);
    if (goal) {
      goal.status = status;
      goal.last_referenced = new Date().toISOString();
    }
  }

  /**
   * Append a locked decision to a goal so future suggestions can align.
   * @param {string} goalId
   * @param {string} decision  Human-readable description of the committed choice.
   */
  lockDecision(goalId, decision) {
    const goal = this._findGoal(goalId);
    if (goal) {
      goal.decisions_made.push({
        decision,
        locked_at: new Date().toISOString(),
      });
      goal.last_referenced = new Date().toISOString();
    }
  }

  // -------------------------------------------------------------------------
  // Suggestions
  // -------------------------------------------------------------------------

  /**
   * Record an assistant suggestion for future deduplication.
   * @param {string} content
   * @param {string} domain
   * @param {number[]} embedding
   * @returns {string} suggestion id
   */
  recordSuggestion(content, domain, embedding) {
    const id = `sug_${randomUUID()}`;
    const record = {
      id,
      content,
      domain,
      timestamp: new Date().toISOString(),
      user_feedback: null, // "accepted" | "rejected" | null
    };
    this.suggestionHistory.push(record);
    this.vectorStore.set(id, embedding);
    return id;
  }

  /**
   * Record user feedback on a prior suggestion.
   * @param {string} suggestionId
   * @param {"accepted"|"rejected"} feedback
   */
  recordFeedback(suggestionId, feedback) {
    const record = this.suggestionHistory.find((s) => s.id === suggestionId);
    if (record) record.user_feedback = feedback;
  }

  // -------------------------------------------------------------------------
  // Contradictions
  // -------------------------------------------------------------------------

  /**
   * Log a conflict between two suggestions with its resolution.
   * @param {string} suggestionA
   * @param {string} suggestionB
   * @param {string} resolution
   */
  logContradiction(suggestionA, suggestionB, resolution) {
    this.intentMap.contradiction_log.push({
      date: new Date().toISOString(),
      suggestion_a: suggestionA,
      suggestion_b: suggestionB,
      resolution,
    });
  }

  // -------------------------------------------------------------------------
  // Active context
  // -------------------------------------------------------------------------

  /**
   * Switch to a new domain, returning the previous one for change-detection.
   * @param {string} domain
   * @returns {string|null} previous domain
   */
  setDomain(domain) {
    const prev = this.intentMap.active_context.current_domain;
    this.intentMap.active_context.current_domain = domain;
    return prev;
  }

  addAssumption(text) {
    if (!this.intentMap.active_context.assumptions.includes(text)) {
      this.intentMap.active_context.assumptions.push(text);
    }
  }

  addBlocker(text) {
    if (!this.intentMap.active_context.blockers.includes(text)) {
      this.intentMap.active_context.blockers.push(text);
    }
  }

  clearBlocker(text) {
    this.intentMap.active_context.blockers =
      this.intentMap.active_context.blockers.filter((b) => b !== text);
  }

  // -------------------------------------------------------------------------
  // Conversation history
  // -------------------------------------------------------------------------

  /**
   * Append a turn to the rolling conversation window.
   * @param {"user"|"assistant"} role
   * @param {string} content
   */
  appendTurn(role, content) {
    this.conversationHistory.push({
      role,
      content,
      timestamp: new Date().toISOString(),
    });
    // Prune to last MAX_CONVERSATION_TURNS entries
    if (this.conversationHistory.length > this.retention.maxConversationTurns) {
      this.conversationHistory = this.conversationHistory.slice(
        -this.retention.maxConversationTurns
      );
    }
  }

  // -------------------------------------------------------------------------
  // Maintenance
  // -------------------------------------------------------------------------

  /**
   * Remove resolved goals older than RESOLVED_GOAL_TTL_MS.
   */
  pruneResolvedGoals() {
    const cutoff = Date.now() - this.retention.resolvedGoalTtlMs;
    this.intentMap.session_goals = this.intentMap.session_goals.filter((g) => {
      if (g.status === "completed") {
        return new Date(g.created_at).getTime() > cutoff;
      }
      return true;
    });
  }

  /**
   * Apply retention policies to rolling structures.
   */
  pruneRetention() {
    const now = Date.now();
    const suggestionCutoff = now - this.retention.suggestionRetentionMs;
    const contradictionCutoff = now - this.retention.contradictionRetentionMs;

    const retainedSuggestionIds = new Set();
    this.suggestionHistory = this.suggestionHistory.filter((s) => {
      const keep = new Date(s.timestamp).getTime() >= suggestionCutoff;
      if (keep) retainedSuggestionIds.add(s.id);
      return keep;
    });

    this.vectorStore = new Map(
      Array.from(this.vectorStore.entries()).filter(([id]) =>
        retainedSuggestionIds.has(id)
      )
    );

    this.intentMap.contradiction_log = this.intentMap.contradiction_log.filter(
      (entry) => new Date(entry.date).getTime() >= contradictionCutoff
    );
  }

  // -------------------------------------------------------------------------
  // Serialization (for prompt injection)
  // -------------------------------------------------------------------------

  /**
   * Export a lightweight snapshot to inject into the system prompt.
   * @returns {MemorySnapshot}
   */
  exportSnapshot() {
    const githubSync = this.intentMap.active_context.github_sync;
    return {
      intent_map: this.intentMap,
      active_goals: this.intentMap.session_goals.filter(
        (g) => g.status === "active"
      ),
      contradictions: this.intentMap.contradiction_log,
      recent_decisions: this.intentMap.session_goals
        .flatMap((g) => g.decisions_made)
        .slice(-5),
      github_context: {
        thresholds: githubSync.thresholds,
        issue_pr_links: githubSync.issue_pr_links,
        last_ingested_at: githubSync.last_ingested_at,
        summary: githubSync.summary,
      },
    };
  }

  /**
   * Export complete runtime state for durable persistence.
   */
  exportPersistenceSnapshot() {
    return {
      schema_version: MEMORY_SCHEMA_VERSION,
      intent_map: this.intentMap,
      suggestion_history: this.suggestionHistory,
      vector_store: Object.fromEntries(this.vectorStore.entries()),
      conversation_history: this.conversationHistory,
      retention: this.retention,
    };
  }

  /**
   * Load full runtime state from persistence snapshot.
   * @param {any} snapshot
   */
  hydrateFromPersistenceSnapshot(snapshot) {
    if (!snapshot || typeof snapshot !== "object") return;

    const normalized = migrateAndValidateMemorySnapshot(snapshot);

    if (normalized.intent_map) this.intentMap = normalized.intent_map;
    if (Array.isArray(normalized.suggestion_history)) {
      this.suggestionHistory = normalized.suggestion_history;
    }
    if (normalized.vector_store && typeof normalized.vector_store === "object") {
      this.vectorStore = new Map(Object.entries(normalized.vector_store));
    }
    if (Array.isArray(normalized.conversation_history)) {
      this.conversationHistory = normalized.conversation_history;
    }
    if (normalized.retention && typeof normalized.retention === "object") {
      this.retention = { ...this.retention, ...normalized.retention };
    }
  }

  /**
   * Persist current state to a memory backend.
   * @param {{saveSnapshot: (sessionId: string, snapshot: any) => Promise<void>}} backend
   * @param {string} sessionId
   */
  async persist(backend, sessionId) {
    this.pruneResolvedGoals();
    this.pruneRetention();
    await backend.saveSnapshot(sessionId, this.exportPersistenceSnapshot());
  }

  /**
   * Load state from memory backend.
   * @param {{loadSnapshot: (sessionId: string) => Promise<any|null>}} backend
   * @param {string} sessionId
   */
  async hydrate(backend, sessionId) {
    const snapshot = await backend.loadSnapshot(sessionId);
    if (snapshot) this.hydrateFromPersistenceSnapshot(snapshot);
  }

  /**
   * Persist normalized GitHub sync state into active context.
   * @param {{
   *   thresholds: { issue_stalled_days: number, pr_stalled_days: number },
   *   issue_pr_links: Array<{issue_number: number, pr_number: number}>,
   *   issues: Array<{classification: {status: string}}>,
   *   pullRequests: Array<{classification: {status: string}}>
   * }} classified
   */
  ingestGitHubClassification(classified) {
    const statuses = [
      ...(classified.issues ?? []).map((i) => i?.classification?.status),
      ...(classified.pullRequests ?? []).map((p) => p?.classification?.status),
    ];

    const summary = {
      completed: statuses.filter((s) => s === "completed").length,
      in_progress: statuses.filter((s) => s === "in_progress").length,
      blocked: statuses.filter((s) => s === "blocked").length,
      deferred: statuses.filter((s) => s === "deferred").length,
    };

    this.intentMap.active_context.github_sync = {
      thresholds: classified.thresholds,
      issue_pr_links: classified.issue_pr_links ?? [],
      last_ingested_at: new Date().toISOString(),
      summary,
    };
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  _findGoal(goalId) {
    return this.intentMap.session_goals.find((g) => g.id === goalId) ?? null;
  }
}
