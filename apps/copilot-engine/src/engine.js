/**
 * @file apps/copilot-engine/src/engine.js
 * @module copilot-engine/engine
 * @description Self-cleaning multi-domain copilot engine.
 *
 * Wires together:
 *   - CopilotMemory     (Layer 1 — intent map + rolling context)
 *   - checkForDuplicates (Layer 2 — semantic deduplication)
 *   - detectContradictions (rule-based conflict detection)
 *   - Anthropic SDK     (Claude Sonnet 4 backbone)
 *
 * Environment variables required:
 *   ANTHROPIC_API_KEY   — Anthropic API key (never hard-code)
 *
 * @governance GOV-002: All LLM calls and dedup events are logged
 */

import Anthropic from "@anthropic-ai/sdk";
import {
  detectContradictions,
  embedText,
  configureEmbeddingProviderFromEnv,
} from "./deduplication.js";
import { correlationId, logEvent, redact } from "./logger.js";
import { runDedupPreflight } from "./dedup-middleware.js";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const MODEL = "claude-sonnet-4-20250514";
const MAX_TOKENS = 2000;
const TEMPERATURE = 0.7;

/** @type {Anthropic | null} Lazily initialised to avoid crashing on import */
let _client = null;

function getClient() {
  if (!_client) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
      throw new Error(
        "ANTHROPIC_API_KEY environment variable is not set. " +
          "Export it before starting the copilot engine."
      );
    }
    _client = new Anthropic({ apiKey });
  }
  return _client;
}

// ---------------------------------------------------------------------------
// Core system prompt
// ---------------------------------------------------------------------------

const CORE_SYSTEM_PROMPT = `You are an autonomous enterprise copilot with deep expertise across:
- Code/DevOps: FlowCI, GitPeak, CI/CD, Terraform, Kubernetes, Git governance
- Cloud/Infrastructure: ElevatedIQ.ai, VaultOS, cloud security, compliance, storage
- Sales/GTM: LinkedIn/Google Ads, email nurture, Chrome extensions, conversion funnels
- Product: AnimForge, EXPOSED.ai, real estate intelligence, AI video production

CORE MANDATE:
1. Never repeat yourself. If you have suggested something in this session, flag it before repeating.
2. Expose conflicts. If you are about to suggest something that contradicts an earlier decision, explicitly ask for permission to revisit.
3. Lock decisions. Once committed, future advice must align with locked decisions or ask to revisit.
4. Tag everything. Every response, every suggestion, every decision goes into session memory with timestamp, domain, and confidence.
5. Assume nothing. State all assumptions upfront. Update them when wrong.

RESPONSE FORMAT — every response must include:
1. Memory State Summary: "Active goals: [list] | Domain: [domain] | Blockers: [list]"
2. The Suggestion/Answer: your actual advice
3. Dedup Check: "Is this new? [Yes/No]"
4. Next Step: "What should we do next?"

ANTI-PATTERNS (NEVER DO):
- Suggest the same thing twice in one session without flagging it
- Offer conflicting advice without surfacing the conflict first
- Forget prior decisions and suggest revisiting them
- Switch domains without warning
- Make assumptions without stating them`;

// ---------------------------------------------------------------------------
// buildSystemPrompt — inject live memory state
// ---------------------------------------------------------------------------

/**
 * @param {import('./memory.js').CopilotMemory} memory
 * @returns {string}
 */
function buildSystemPrompt(memory) {
  const snap = memory.exportSnapshot();
  const ctx = snap.intent_map.active_context;

  const goalsList =
    snap.active_goals.map((g) => `[${g.domain}] ${g.intent}`).join("; ") ||
    "none";
  const decisionsList =
    snap.recent_decisions.map((d) => d.decision).join("; ") || "none";
  const contradictionCount = snap.contradictions.length;

  return `${CORE_SYSTEM_PROMPT}

[SESSION MEMORY — injected at ${new Date().toISOString()}]
Current domain : ${ctx.current_domain ?? "unset"}
Active goals   : ${goalsList}
Recent decisions (locked): ${decisionsList}
Contradictions logged    : ${contradictionCount}
Blockers       : ${ctx.blockers.join("; ") || "none"}
Assumptions    : ${ctx.assumptions.join("; ") || "none"}`;
}

// ---------------------------------------------------------------------------
// ChatEngine
// ---------------------------------------------------------------------------

export class ChatEngine {
  /**
   * @param {import('./memory.js').CopilotMemory} memory
   * @param {{ logger?: Console }} [options]
   */
  constructor(memory, options = {}) {
    this.memory = memory;
    this.log = options.logger ?? console;
    if (options.configureEmbeddingProvider !== false) {
      configureEmbeddingProviderFromEnv();
    }
    this.dedupStats = {
      checks: 0,
      hits: 0,
    };
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /**
   * Send a user message through the full pipeline:
   *   pre-flight dedup → contradiction check → Claude call → post-flight record.
   *
   * @param {string} userMessage
   * @param {{ domain?: string; assumptions?: string[] }} [options]
   * @returns {Promise<ChatResult>}
   */
  async chat(userMessage, options = {}) {
    const { domain, assumptions = [], correlation_id, scanner_interaction = null } = options;
    const cid = correlationId(correlation_id);

    logEvent(
      "info",
      "turn_started",
      {
        correlation_id: cid,
        domain: domain ?? null,
        assumptions_count: assumptions.length,
        message_preview: userMessage.slice(0, 160),
      },
      this.log
    );

    // ------------------------------------------------------------------
    // 1. Domain switch detection
    // ------------------------------------------------------------------
    if (domain) {
      const prev = this.memory.setDomain(domain);
      if (prev && prev !== domain) {
        logEvent(
          "warn",
          "domain_switched",
          {
            correlation_id: cid,
            previous_domain: prev,
            new_domain: domain,
          },
          this.log
        );
      }
    }

    // ------------------------------------------------------------------
    // 2. Register stated assumptions
    // ------------------------------------------------------------------
    for (const assumption of assumptions) {
      this.memory.addAssumption(assumption);
    }

    if (scanner_interaction) {
      logEvent(
        "info",
        "scanner_interaction",
        {
          correlation_id: cid,
          scanner_interaction,
        },
        this.log
      );
    }

    // ------------------------------------------------------------------
    // 3. Pre-flight deduplication check (Layer 2)
    // ------------------------------------------------------------------
    const duplicateResponse = await runDedupPreflight({
      message: userMessage,
      correlationId: cid,
      memory: this.memory,
      logger: this.log,
      stats: this.dedupStats,
    });

    if (duplicateResponse) {
      const result = duplicateResponse;
      logEvent(
        "info",
        "turn_completed",
        {
          correlation_id: cid,
          result_type: result.type,
          scanner_interaction: scanner_interaction,
        },
        this.log
      );
      return result;
    }

    // ------------------------------------------------------------------
    // 4. Contradiction detection
    // ------------------------------------------------------------------
    const conflicts = detectContradictions(userMessage, this.memory);
    let contradictionNote = "";
    if (conflicts.length > 0) {
      const summary = conflicts
        .map((c) => `"${c.prior_decision}" (locked ${c.locked_at})`)
        .join(", ");
      contradictionNote =
        `\n\n⚠️  Possible conflict with locked decision(s): ${summary}. ` +
        `Please surface this in your response and ask for permission to revisit.`;
      logEvent(
        "warn",
        "contradiction_detected",
        {
          correlation_id: cid,
          conflicts: conflicts,
        },
        this.log
      );
    }

    // ------------------------------------------------------------------
    // 5. Build enriched system prompt
    // ------------------------------------------------------------------
    const systemPrompt = buildSystemPrompt(this.memory) + contradictionNote;

    // ------------------------------------------------------------------
    // 6. Call Claude Sonnet 4
    // ------------------------------------------------------------------
    logEvent(
      "info",
      "llm_call_started",
      {
        correlation_id: cid,
        model: MODEL,
        max_tokens: MAX_TOKENS,
        temperature: TEMPERATURE,
      },
      this.log
    );
    const response = await getClient().messages.create({
      model: MODEL,
      max_tokens: MAX_TOKENS,
      temperature: TEMPERATURE,
      system: systemPrompt,
      messages: [
        ...this.memory.conversationHistory.map((t) => ({
          role: t.role,
          content: t.content,
        })),
        { role: "user", content: userMessage },
      ],
    });

    const assistantText =
      response.content.find((b) => b.type === "text")?.text ?? "";

    logEvent(
      "info",
      "llm_call_completed",
      {
        correlation_id: cid,
        response_preview: assistantText.slice(0, 160),
      },
      this.log
    );

    // ------------------------------------------------------------------
    // 7. Post-flight: record everything
    // ------------------------------------------------------------------
    this.memory.appendTurn("user", userMessage);
    this.memory.appendTurn("assistant", assistantText);

    const embedding = await embedText(assistantText);
    const suggestionId = this.memory.recordSuggestion(
      assistantText,
      domain ?? this.memory.intentMap.active_context.current_domain ?? "general",
      embedding
    );

    this.memory.pruneResolvedGoals();

    logEvent(
      "info",
      "memory_updated",
      {
        correlation_id: cid,
        suggestion_id: suggestionId,
        conversation_turns: this.memory.conversationHistory.length,
        suggestion_history_size: this.memory.suggestionHistory.length,
      },
      this.log
    );

    const result = {
      type: "response",
      correlation_id: cid,
      suggestion_id: suggestionId,
      message: assistantText,
      memory_snapshot: redact(this.memory.exportSnapshot()),
      conflicts_detected: conflicts.length > 0 ? conflicts : null,
    };

    logEvent(
      "info",
      "turn_completed",
      {
        correlation_id: cid,
        result_type: result.type,
        suggestion_id: suggestionId,
        scanner_interaction: scanner_interaction,
      },
      this.log
    );

    return result;
  }
}

// ---------------------------------------------------------------------------
// Convenience factory
// ---------------------------------------------------------------------------

/**
 * Create a fully wired engine from an existing (or new) memory instance.
 * @param {import('./memory.js').CopilotMemory} memory
 * @param {{ logger?: Console }} [options]
 * @returns {ChatEngine}
 */
export function createEngine(memory, options) {
  return new ChatEngine(memory, options);
}
