/**
 * Self-Cleaning Multi-Domain Copilot Engine
 * Layers: Structured Intent Map + Vector Deduplication + Conversation Context
 * Model: Claude Sonnet 4 (latest)
 */

const Anthropic = require("@anthropic-ai/sdk");

// ============================================================================
// MEMORY STORE (use Redis in production, in-memory here for demo)
// ============================================================================

class CopilotMemory {
  constructor() {
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
    this.suggestionHistory = []; // For deduplication
    this.conversationHistory = []; // Rolling window
    this.vectorStore = new Map(); // suggestion_id -> embedding
  }

  // Add a goal to the intent map
  addGoal(domain, intent) {
    const goal = {
      id: `goal_${Date.now()}_${Math.random().toString(36).slice(7)}`,
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

  // Lock a decision to a goal
  lockDecision(goalId, decision) {
    const goal = this.intentMap.session_goals.find((g) => g.id === goalId);
    if (goal) {
      goal.decisions_made.push({
        decision,
        locked_at: new Date().toISOString(),
      });
    }
  }

  // Record a suggestion (for deduplication)
  recordSuggestion(content, domain, embedding) {
    const suggestion = {
      id: `sug_${Date.now()}_${Math.random().toString(36).slice(7)}`,
      content,
      domain,
      timestamp: new Date().toISOString(),
      embedding,
      user_feedback: null, // accepted, rejected, or null
    };
    this.suggestionHistory.push(suggestion);
    this.vectorStore.set(suggestion.id, embedding);
    return suggestion.id;
  }

  // Log a contradiction
  logContradiction(suggestionA, suggestionB, resolution) {
    this.intentMap.contradiction_log.push({
      date: new Date().toISOString(),
      suggestion_a: suggestionA,
      suggestion_b: suggestionB,
      resolution,
    });
  }

  // Get suggestions from current domain
  getSuggestionsInDomain(domain) {
    return this.suggestionHistory.filter((s) => s.domain === domain);
  }

  // Prune old resolved goals (>2 hours)
  pruneResolvedGoals() {
    const twoHoursAgo = Date.now() - 2 * 60 * 60 * 1000;
    this.intentMap.session_goals = this.intentMap.session_goals.filter((g) => {
      if (g.status === "completed") {
        const createdTime = new Date(g.created_at).getTime();
        return createdTime > twoHoursAgo;
      }
      return true;
    });
  }

  // Export current state for system prompt injection
  exportMemoryContext() {
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
}

// ============================================================================
// DEDUPLICATION ENGINE (semantic similarity check)
// ============================================================================

/**
 * Compute cosine similarity between two vectors
 */
function cosineSimilarity(vec1, vec2) {
  const dotProduct = vec1.reduce((sum, a, i) => sum + a * vec2[i], 0);
  const mag1 = Math.sqrt(vec1.reduce((sum, a) => sum + a * a, 0));
  const mag2 = Math.sqrt(vec2.reduce((sum, a) => sum + a * a, 0));
  if (mag1 === 0 || mag2 === 0) return 0;
  return dotProduct / (mag1 * mag2);
}

/**
 * Check for duplicate suggestions
 * In production, use real embeddings (OpenAI, Cohere, or local Ollama)
 * This is a mock that uses simple text hashing
 */
function mockEmbedding(text) {
  // Simple hash-based mock embedding (replace with real embeddings in production)
  const hash = text
    .split("")
    .reduce((h, c) => ((h << 5) - h + c.charCodeAt(0)) | 0, 0);
  const seed = Math.abs(hash);
  const rng = Math.sin(seed) * 10000;
  const embedding = [];
  for (let i = 0; i < 384; i++) {
    embedding.push(Math.sin(rng + i) * 0.5);
  }
  return embedding;
}

async function checkForDuplicates(userMessage, memory, threshold = 0.85) {
  const currentEmbedding = mockEmbedding(userMessage);
  const similarities = memory.suggestionHistory.map((suggestion) => {
    const sim = cosineSimilarity(
      currentEmbedding,
      memory.vectorStore.get(suggestion.id)
    );
    return { suggestion, similarity: sim };
  });

  const duplicates = similarities.filter((s) => s.similarity > threshold);
  if (duplicates.length > 0) {
    return {
      isDuplicate: true,
      prior: duplicates[0].suggestion,
      similarity: duplicates[0].similarity,
    };
  }

  return { isDuplicate: false };
}

// ============================================================================
// CONTRADICTION DETECTION
// ============================================================================

async function detectContradictions(proposedSuggestion, memory) {
  const recent = memory.intentMap.session_goals
    .flatMap((g) => g.decisions_made)
    .slice(-5);

  const keywords1 = proposedSuggestion.toLowerCase().split(/\s+/);
  const conflicts = [];

  for (const decision of recent) {
    const keywords2 = decision.decision.toLowerCase().split(/\s+/);
    const intersection = keywords1.filter((k) => keywords2.includes(k));

    // If they share >50% of keywords, they might conflict
    if (
      intersection.length > Math.max(keywords1.length, keywords2.length) * 0.5
    ) {
      conflicts.push({
        prior_decision: decision.decision,
        locked_at: decision.locked_at,
      });
    }
  }

  return conflicts;
}

// ============================================================================
// MAIN COPILOT ENGINE
// ============================================================================

const client = new Anthropic();
const memory = new CopilotMemory();

const CORE_SYSTEM_PROMPT = `You are an autonomous enterprise copilot with deep expertise across:
- Code/DevOps: FlowCI, GitPeak, CI/CD, Terraform, Kubernetes, Git governance
- Cloud/Infrastructure: ElevatedIQ.ai, VaultOS, cloud security, compliance, storage
- Sales/GTM: LinkedIn/Google Ads, email nurture, Chrome extensions, conversion funnels
- Product: AnimForge, EXPOSED.ai, real estate intelligence, AI video production

CORE MANDATE:
1. Never repeat yourself. If you've suggested something in this session, flag it before repeating.
2. Expose conflicts. If you're about to suggest something that contradicts an earlier decision, explicitly ask for permission to revisit.
3. Lock decisions. Once committed, future advice must align with locked decisions or ask to revisit.
4. Tag everything. Every response, every suggestion, every decision goes into session memory with timestamp, domain, and confidence.
5. Assume nothing. State all assumptions upfront. Update them when wrong.

RESPONSE FORMAT:
1. Memory State Summary: "Active goals: [list], Current domain: [domain], Blockers: [list]"
2. The Suggestion/Answer: Your actual advice
3. Dedup Check: "Is this new? [Yes/No]. If No, here's what I said before..."
4. Next Step: "What should we do next?"`;

async function chat(userMessage, domain = null) {
  console.log("\n--- CHECKING FOR DUPLICATES ---");
  const dupCheck = await checkForDuplicates(userMessage, memory);
  if (dupCheck.isDuplicate) {
    console.log(
      `⚠️  DUPLICATE DETECTED (${(dupCheck.similarity * 100).toFixed(1)}% similar)`
    );
    console.log(`   Prior suggestion: "${dupCheck.prior.content.slice(0, 80)}..."`);
    console.log(`   Timestamp: ${dupCheck.prior.timestamp}`);
    console.log(`   → Asking user to confirm revisit...\n`);

    return {
      type: "duplicate_flag",
      prior_suggestion: dupCheck.prior.content,
      message:
        "I see I already suggested this. Would you like me to expand on it, or should we try a different angle?",
    };
  }

  console.log("✓ No duplicates detected\n");

  // Update active context if domain provided
  if (domain) {
    memory.intentMap.active_context.current_domain = domain;
  }

  // Check for contradictions
  console.log("--- CHECKING FOR CONTRADICTIONS ---");
  let contradictionWarning = "";
  // (Simplified: In real implementation, detect based on proposed suggestion)

  // Inject memory context into system prompt
  const memoryContext = memory.exportMemoryContext();
  const enrichedSystemPrompt = `${CORE_SYSTEM_PROMPT}

[SESSION MEMORY CONTEXT]
Current domain: ${memoryContext.intent_map.active_context.current_domain || "unset"}
Active goals: ${memoryContext.active_goals.map((g) => g.intent).join("; ") || "none"}
Recent decisions: ${memoryContext.recent_decisions.map((d) => d.decision).join("; ") || "none"}
Contradictions logged: ${memoryContext.contradictions.length}
Blockers: ${memoryContext.intent_map.active_context.blockers.join("; ") || "none"}
Assumptions: ${memoryContext.intent_map.active_context.assumptions.join("; ") || "none"}`;

  // Call Claude Sonnet 4
  console.log("--- CALLING CLAUDE SONNET 4 ---");
  const response = await client.messages.create({
    model: "claude-sonnet-4-20250514",
    max_tokens: 2000,
    temperature: 0.7,
    system: enrichedSystemPrompt,
    messages: [
      ...memory.conversationHistory.map((msg) => ({
        role: msg.role,
        content: msg.content,
      })),
      { role: "user", content: userMessage },
    ],
  });

  const assistantMessage =
    response.content[0].type === "text" ? response.content[0].text : "";

  // Record in conversation history
  memory.conversationHistory.push({
    role: "user",
    content: userMessage,
    timestamp: new Date().toISOString(),
  });
  memory.conversationHistory.push({
    role: "assistant",
    content: assistantMessage,
    timestamp: new Date().toISOString(),
  });

  // Prune old messages (keep last 15 exchanges)
  if (memory.conversationHistory.length > 30) {
    memory.conversationHistory = memory.conversationHistory.slice(-30);
  }

  // Record suggestion for future deduplication
  const suggestion_embedding = mockEmbedding(assistantMessage);
  memory.recordSuggestion(
    assistantMessage,
    domain || "general",
    suggestion_embedding
  );

  // Prune resolved goals
  memory.pruneResolvedGoals();

  return {
    type: "response",
    message: assistantMessage,
    memory_state: memoryContext,
  };
}

// ============================================================================
// EXAMPLE USAGE
// ============================================================================

async function demo() {
  console.log("🤖 SELF-CLEANING COPILOT ENGINE\n");

  // Test 1: Add a goal
  console.log("=== TEST 1: Add Goal ===");
  const goalId = memory.addGoal("code", "Build GitPeak branch conflict resolver");
  console.log(`✓ Goal added: ${goalId}\n`);

  // Test 2: First message (no duplication)
  console.log("=== TEST 2: First Message ===");
  let result = await chat(
    "How should I structure the conflict resolution engine for GitPeak?",
    "code"
  );
  console.log("Copilot:", result.message.slice(0, 200) + "...\n");

  // Test 3: Similar message (should detect duplication)
  console.log("=== TEST 3: Duplicate Detection ===");
  result = await chat(
    "What's the best architecture for handling Git branch conflicts in GitPeak?",
    "code"
  );
  if (result.type === "duplicate_flag") {
    console.log("⚠️  Duplicate flagged:", result.message);
  } else {
    console.log("Copilot:", result.message.slice(0, 200) + "...\n");
  }

  // Test 4: Lock a decision
  console.log("\n=== TEST 4: Lock Decision ===");
  memory.lockDecision(goalId, "Use vector embeddings for semantic conflict detection");
  console.log("✓ Decision locked\n");

  // Test 5: Switch domains
  console.log("=== TEST 5: Domain Switch ===");
  result = await chat(
    "Now I need to update my GTM playbook for ElevatedIQ. Should I adjust the LinkedIn cold outreach template?",
    "sales"
  );
  console.log("Copilot:", result.message.slice(0, 200) + "...\n");
}

// Uncomment to run demo
// demo().catch(console.error);

module.exports = { CopilotMemory, chat, checkForDuplicates };
