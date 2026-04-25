/**
 * @file apps/copilot-engine/src/memory.js
 * @module copilot-engine/memory
 * @description Layer 1 — Structured Intent Map + suggestion history for the
 *   self-cleaning copilot. Keeps session goals, decisions, contradiction log,
 *   and rolling conversation context.
 * @governance GOV-002: All memory mutations logged for audit
 */

import { randomUUID } from "crypto";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const RESOLVED_GOAL_TTL_MS = 2 * 60 * 60 * 1000; // 2 hours
const MAX_CONVERSATION_TURNS = 30; // 15 exchanges × 2 (user + assistant)

// ---------------------------------------------------------------------------
// CopilotMemory
// ---------------------------------------------------------------------------

export class CopilotMemory {
  constructor() {
    /** @type {IntentMap} */
    this.intentMap = {
      session_goals: [],
      active_context: {
        current_domain: null,
        current_task: null,
        blockers: [],
        assumptions: [],
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
    if (this.conversationHistory.length > MAX_CONVERSATION_TURNS) {
      this.conversationHistory = this.conversationHistory.slice(
        -MAX_CONVERSATION_TURNS
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
    const cutoff = Date.now() - RESOLVED_GOAL_TTL_MS;
    this.intentMap.session_goals = this.intentMap.session_goals.filter((g) => {
      if (g.status === "completed") {
        return new Date(g.created_at).getTime() > cutoff;
      }
      return true;
    });
  }

  // -------------------------------------------------------------------------
  // Serialization (for prompt injection)
  // -------------------------------------------------------------------------

  /**
   * Export a lightweight snapshot to inject into the system prompt.
   * @returns {MemorySnapshot}
   */
  exportSnapshot() {
    return {
      intent_map: this.intentMap,
      active_goals: this.intentMap.session_goals.filter(
        (g) => g.status === "active"
      ),
      contradictions: this.intentMap.contradiction_log,
      recent_decisions: this.intentMap.session_goals
        .flatMap((g) => g.decisions_made)
        .slice(-5),
    };
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  _findGoal(goalId) {
    return this.intentMap.session_goals.find((g) => g.id === goalId) ?? null;
  }
}
