"use strict";
/**
 * Phase 4A: ML Semantic Search Foundation
 * MLEmbeddingEngine - Generate code embeddings using Ollama LLM service
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.MLEmbeddingEngine = void 0;
class MLEmbeddingEngine {
    constructor(ollamaEndpoint = 'http://localhost:11434') {
        this.modelName = 'llama2:7b-chat';
        this.cache = {};
        this.batchSize = 10;
        this.cacheHits = 0;
        this.cacheMisses = 0;
        this.ollamaEndpoint = ollamaEndpoint;
    }
    /**
     * Generate a single embedding for text
     */
    async generateEmbedding(text, id) {
        const cacheKey = this.generateCacheKey(text);
        // Check cache first
        if (this.cache[cacheKey]) {
            this.cacheHits++;
            return this.cache[cacheKey];
        }
        this.cacheMisses++;
        try {
            // Call Ollama embeddings endpoint
            const response = await fetch(`${this.ollamaEndpoint}/api/embeddings`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    model: this.modelName,
                    prompt: text,
                }),
            });
            if (!response.ok) {
                throw new Error(`Ollama API error: ${response.status}`);
            }
            const data = (await response.json());
            // Normalize embedding to 768 dimensions if needed
            let vector = data.embedding || [];
            if (vector.length === 0) {
                throw new Error('No embedding returned from Ollama');
            }
            // Pad or truncate to 768 dimensions
            while (vector.length < 768) {
                vector.push(0);
            }
            vector = vector.slice(0, 768);
            const result = {
                id: id || this.generateId(),
                text,
                vector,
                timestamp: Date.now(),
            };
            // Cache the result
            this.cache[cacheKey] = result;
            return result;
        }
        catch (error) {
            console.error('Failed to generate embedding:', error);
            // Return zero vector as fallback
            return {
                id: id || this.generateId(),
                text,
                vector: new Array(768).fill(0),
                timestamp: Date.now(),
            };
        }
    }
    /**
     * Generate embeddings for multiple texts in batches
     */
    async generateBatchEmbeddings(texts) {
        const results = [];
        // Process in batches
        for (let i = 0; i < texts.length; i += this.batchSize) {
            const batch = texts.slice(i, i + this.batchSize);
            const batchPromises = batch.map((req) => this.generateEmbedding(req.text, req.id));
            const batchResults = await Promise.all(batchPromises);
            results.push(...batchResults);
        }
        return results;
    }
    /**
     * Clear cache entries
     */
    clearCache(pattern) {
        if (!pattern) {
            this.cache = {};
            this.cacheHits = 0;
            this.cacheMisses = 0;
            return;
        }
        Object.keys(this.cache).forEach((key) => {
            if (pattern.test(key)) {
                delete this.cache[key];
            }
        });
    }
    /**
     * Get cache statistics
     */
    getCacheStats() {
        const total = this.cacheHits + this.cacheMisses;
        return {
            size: Object.keys(this.cache).length,
            hitRate: total > 0 ? (this.cacheHits / total) * 100 : 0,
            totalRequests: total,
        };
    }
    /**
     * Set Ollama model
     */
    setModel(modelName) {
        this.modelName = modelName;
        this.clearCache();
    }
    /**
     * Generate cache key from text
     */
    generateCacheKey(text) {
        return Buffer.from(text).toString('base64');
    }
    /**
     * Generate unique ID
     */
    generateId() {
        return `embedding_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    }
}
exports.MLEmbeddingEngine = MLEmbeddingEngine;
//# sourceMappingURL=MLEmbeddingEngine.js.map