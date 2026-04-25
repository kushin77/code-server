/**
 * @file apps/copilot-engine/src/deduplication.js
 * @module copilot-engine/deduplication
 * @description Layer 2 — Semantic deduplication and contradiction detection.
 *
 * Production path: swap `mockEmbedding` for a real embedding provider
 * (Ollama nomic-embed-text, OpenAI text-embedding-3-small, or Cohere).
 * The rest of the pipeline is provider-agnostic.
 *
 * @governance GOV-002
 */

// ---------------------------------------------------------------------------
// Cosine similarity
// ---------------------------------------------------------------------------

/**
 * Compute cosine similarity between two equal-length numeric vectors.
 * Returns 0 for zero-magnitude vectors.
 * @param {number[]} vec1
 * @param {number[]} vec2
 * @returns {number}  value in [-1, 1]
 */
export function cosineSimilarity(vec1, vec2) {
  if (vec1.length !== vec2.length) {
    throw new RangeError(
      `Vector length mismatch: ${vec1.length} vs ${vec2.length}`
    );
  }
  let dot = 0;
  let mag1 = 0;
  let mag2 = 0;
  for (let i = 0; i < vec1.length; i++) {
    dot += vec1[i] * vec2[i];
    mag1 += vec1[i] * vec1[i];
    mag2 += vec2[i] * vec2[i];
  }
  const denom = Math.sqrt(mag1) * Math.sqrt(mag2);
  return denom === 0 ? 0 : dot / denom;
}

// ---------------------------------------------------------------------------
// Embedding provider
// ---------------------------------------------------------------------------

/**
 * Deterministic mock embedding from text hash.
 * ⚠ REPLACE with a real embedding provider in production.
 *
 * @param {string} text
 * @returns {number[]}  384-dimensional unit-ish vector
 */
export function mockEmbedding(text) {
  // FNV-1a hash for reproducibility
  let hash = 2166136261;
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i);
    hash = (hash * 16777619) >>> 0; // keep 32-bit unsigned
  }
  const embedding = new Array(384);
  for (let i = 0; i < 384; i++) {
    embedding[i] = Math.sin(hash + i) * 0.5;
  }
  return embedding;
}

/**
 * Pluggable embedding function.
 * Override by calling `setEmbeddingProvider(yourFn)` before first use.
 */
let _embedText = mockEmbedding;

/**
 * Register a production embedding function.
 * @param {(text: string) => Promise<number[]> | number[]} fn
 */
export function setEmbeddingProvider(fn) {
  _embedText = fn;
}

/** @returns {Promise<number[]>} */
export async function embedText(text) {
  return _embedText(text);
}

// ---------------------------------------------------------------------------
// Deduplication check
// ---------------------------------------------------------------------------

const DEFAULT_DEDUP_THRESHOLD = 0.85;

/**
 * Check whether `userMessage` is semantically similar to any prior suggestion.
 *
 * @param {string} userMessage
 * @param {import('./memory.js').CopilotMemory} memory
 * @param {number} [threshold]
 * @returns {Promise<DedupResult>}
 */
export async function checkForDuplicates(
  userMessage,
  memory,
  threshold = DEFAULT_DEDUP_THRESHOLD
) {
  const currentEmbedding = await embedText(userMessage);

  let bestMatch = null;
  let bestSimilarity = -Infinity;

  for (const suggestion of memory.suggestionHistory) {
    const stored = memory.vectorStore.get(suggestion.id);
    if (!stored) continue;
    const sim = cosineSimilarity(currentEmbedding, stored);
    if (sim > bestSimilarity) {
      bestSimilarity = sim;
      bestMatch = suggestion;
    }
  }

  if (bestMatch && bestSimilarity >= threshold) {
    return {
      isDuplicate: true,
      prior: bestMatch,
      similarity: bestSimilarity,
    };
  }

  return { isDuplicate: false, prior: null, similarity: bestSimilarity };
}

// ---------------------------------------------------------------------------
// Contradiction detection
// ---------------------------------------------------------------------------

/**
 * Rough keyword-overlap heuristic to surface potential contradictions between
 * a proposed suggestion and recently locked decisions.
 *
 * In production, replace with an LLM-based entailment check or a dedicated
 * NLI model for higher accuracy.
 *
 * @param {string} proposedSuggestion
 * @param {import('./memory.js').CopilotMemory} memory
 * @param {number} [overlapThreshold=0.5]  fraction of shared keywords to flag
 * @returns {Array<{prior_decision: string, locked_at: string}>}
 */
export function detectContradictions(
  proposedSuggestion,
  memory,
  overlapThreshold = 0.5
) {
  const recentDecisions = memory.intentMap.session_goals
    .flatMap((g) => g.decisions_made)
    .slice(-5);

  const tokenize = (text) =>
    text
      .toLowerCase()
      .replace(/[^\w\s]/g, "")
      .split(/\s+/)
      .filter((w) => w.length > 3); // ignore stop words by length

  const proposedTokens = new Set(tokenize(proposedSuggestion));

  return recentDecisions.filter((d) => {
    const decisionTokens = tokenize(d.decision);
    if (decisionTokens.length === 0) return false;
    const intersection = decisionTokens.filter((k) => proposedTokens.has(k));
    const overlap =
      intersection.length / Math.max(proposedTokens.size, decisionTokens.length);
    return overlap >= overlapThreshold;
  });
}
