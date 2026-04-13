/**
 * Phase 4A: ML Semantic Search Foundation
 * MLEmbeddingEngine - Generate code embeddings using Ollama LLM service
 */

export interface EmbeddingRequest {
  text: string;
  id?: string;
}

export interface EmbeddingResult {
  id: string;
  text: string;
  vector: number[];
  timestamp: number;
}

export interface EmbeddingCache {
  [key: string]: EmbeddingResult;
}

export class MLEmbeddingEngine {
  private ollamaEndpoint: string;
  private modelName: string = 'llama2:7b-chat';
  private cache: EmbeddingCache = {};
  private batchSize: number = 10;
  private cacheHits: number = 0;
  private cacheMisses: number = 0;

  constructor(ollamaEndpoint: string = 'http://localhost:11434') {
    this.ollamaEndpoint = ollamaEndpoint;
  }

  /**
   * Generate a single embedding for text
   */
  async generateEmbedding(text: string, id?: string): Promise<EmbeddingResult> {
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

      const data = (await response.json()) as { embedding?: number[] };
      
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

      const result: EmbeddingResult = {
        id: id || this.generateId(),
        text,
        vector,
        timestamp: Date.now(),
      };

      // Cache the result
      this.cache[cacheKey] = result;

      return result;
    } catch (error) {
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
  async generateBatchEmbeddings(
    texts: EmbeddingRequest[]
  ): Promise<EmbeddingResult[]> {
    const results: EmbeddingResult[] = [];

    // Process in batches
    for (let i = 0; i < texts.length; i += this.batchSize) {
      const batch = texts.slice(i, i + this.batchSize);
      const batchPromises = batch.map((req) =>
        this.generateEmbedding(req.text, req.id)
      );
      const batchResults = await Promise.all(batchPromises);
      results.push(...batchResults);
    }

    return results;
  }

  /**
   * Clear cache entries
   */
  clearCache(pattern?: RegExp): void {
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
  getCacheStats(): {
    size: number;
    hitRate: number;
    totalRequests: number;
  } {
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
  setModel(modelName: string): void {
    this.modelName = modelName;
    this.clearCache();
  }

  /**
   * Generate cache key from text
   */
  private generateCacheKey(text: string): string {
    return Buffer.from(text).toString('base64');
  }

  /**
   * Generate unique ID
   */
  private generateId(): string {
    return `embedding_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }
}
