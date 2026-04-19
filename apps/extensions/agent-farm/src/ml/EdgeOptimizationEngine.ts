/**
 * Edge Optimization Engine
 * Optimizes operations for edge computing with resource constraints
 */

export interface EdgeProfile {
  nodeId: string;
  location: string;
  cpu: number; // cores
  memory: number; // MB
  storage: number; // MB
  networkBandwidth: number; // Mbps
  networkLatency: number; // ms
  isOnline: boolean;
  lastHeartbeat: number;
}

export interface CompressionStrategy {
  algorithm: 'gzip' | 'brotli' | 'lz4' | 'none';
  level: 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9;
  useForPayloads: boolean;
  useForCache: boolean;
  minSize: number; // only compress if > minSize bytes
}

export interface CachePolicy {
  ttl: number; // milliseconds
  maxSize: number; // MB
  evictionPolicy: 'lru' | 'lfu' | 'fifo';
  compressionStrategy?: CompressionStrategy;
}

export interface OptimizationProfile {
  nodeId: string;
  cachePolicy: CachePolicy;
  compressionStrategy: CompressionStrategy;
  batchingEnabled: boolean;
  batchSize: number;
  batchMaxWait: number; // milliseconds
  prefetchEnabled: boolean;
  prefetchAheadFactor: number; // number of items ahead to prefetch
}

export class EdgeOptimizationEngine {
  private edgeProfiles: Map<string, EdgeProfile> = new Map();
  private optimizationProfiles: Map<string, OptimizationProfile> = new Map();
  private cache: Map<string, { data: any; timestamp: number; compressed: boolean }> = new Map();
  private batchQueues: Map<string, any[]> = new Map();
  private compressionStats: Map<string, { original: number; compressed: number; ratio: number }> = new Map();
  private readonly maxCacheEntries = 10000;

  constructor() {}

  /**
   * Register edge node profile
   */
  registerEdgeNode(profile: EdgeProfile): void {
    this.edgeProfiles.set(profile.nodeId, profile);
    this.batchQueues.set(profile.nodeId, []);
  }

  /**
   * Update edge node status
   */
  updateEdgeNodeStatus(nodeId: string, isOnline: boolean, latency?: number): boolean {
    const profile = this.edgeProfiles.get(nodeId);
    if (!profile) return false;

    profile.isOnline = isOnline;
    profile.lastHeartbeat = Date.now();
    if (latency !== undefined) {
      profile.networkLatency = latency;
    }
    return true;
  }

  /**
   * Create optimization profile for edge node
   */
  createOptimizationProfile(
    nodeId: string,
    cachePolicy: CachePolicy,
    compressionStrategy: CompressionStrategy
  ): OptimizationProfile {
    const optimizationProfile: OptimizationProfile = {
      nodeId,
      cachePolicy,
      compressionStrategy,
      batchingEnabled: true,
      batchSize: 50,
      batchMaxWait: 5000,
      prefetchEnabled: true,
      prefetchAheadFactor: 3,
    };

    this.optimizationProfiles.set(nodeId, optimizationProfile);
    return optimizationProfile;
  }

  /**
   * Cache data with compression
   */
  cacheData(nodeId: string, key: string, data: any): boolean {
    const profile = this.optimizationProfiles.get(nodeId);
    if (!profile) return false;

    // Check cache size
    if (this.cache.size >= this.maxCacheEntries) {
      this.evictCache(nodeId, profile.cachePolicy.evictionPolicy);
    }

    // Simulate compression
    let compressed = false;
    if (profile.compressionStrategy.useForCache) {
      const dataSize = JSON.stringify(data).length;
      if (dataSize > profile.compressionStrategy.minSize) {
        compressed = true;
        const compressedSize = Math.floor(dataSize * (1 - profile.compressionStrategy.level / 10));
        const ratio = compressedSize / dataSize;
        this.compressionStats.set(key, { original: dataSize, compressed: compressedSize, ratio });
      }
    }

    this.cache.set(key, {
      data,
      timestamp: Date.now(),
      compressed,
    });

    return true;
  }

  /**
   * Get cached data
   */
  getCachedData(key: string): any | undefined {
    const entry = this.cache.get(key);
    if (!entry) return undefined;

    const profile = Array.from(this.optimizationProfiles.values())[0];
    if (!profile) return entry.data;

    // Check TTL
    if (Date.now() - entry.timestamp > profile.cachePolicy.ttl) {
      this.cache.delete(key);
      return undefined;
    }

    return entry.data;
  }

  /**
   * Evict cache entries
   */
  private evictCache(nodeId: string, policy: 'lru' | 'lfu' | 'fifo'): void {
    const entries = Array.from(this.cache.entries());
    if (entries.length === 0) return;

    let toDelete: string;
    if (policy === 'lru') {
      // Delete least recently used (oldest timestamp)
      let oldestKey = entries[0][0];
      let oldestTime = entries[0][1].timestamp;
      for (const [key, entry] of entries) {
        if (entry.timestamp < oldestTime) {
          oldestKey = key;
          oldestTime = entry.timestamp;
        }
      }
      toDelete = oldestKey;
    } else if (policy === 'lfu') {
      // Simulate LFU by deleting random entry (simplified)
      toDelete = entries[Math.floor(Math.random() * entries.length)][0];
    } else {
      // FIFO: delete oldest
      toDelete = entries[0][0];
    }

    this.cache.delete(toDelete);
  }

  /**
   * Queue data for batching
   */
  queueForBatch(nodeId: string, data: any): number {
    const queue = this.batchQueues.get(nodeId) || [];
    queue.push(data);
    this.batchQueues.set(nodeId, queue);
    return queue.length;
  }

  /**
   * Get batch and clear queue
   */
  getBatch(nodeId: string): any[] {
    const queue = this.batchQueues.get(nodeId) || [];
    const profile = this.optimizationProfiles.get(nodeId);
    if (!profile) return [];

    const batch = queue.slice(0, profile.batchSize);
    const remaining = queue.slice(profile.batchSize);
    this.batchQueues.set(nodeId, remaining);
    return batch;
  }

  /**
   * Calculate bandwidth optimizer
   */
  getBandwidthOptimization(nodeId: string): {
    compressionLevel: number;
    batchSize: number;
    prefetchEnabled: boolean;
  } {
    const edgeProfile = this.edgeProfiles.get(nodeId);
    const optimProfile = this.optimizationProfiles.get(nodeId);

    if (!edgeProfile || !optimProfile) {
      return { compressionLevel: 6, batchSize: 50, prefetchEnabled: true };
    }

    // Adjust compression level based on bandwidth
    let compressionLevel = 6;
    if (edgeProfile.networkBandwidth < 10) {
      compressionLevel = 9; // max compression for very slow networks
    } else if (edgeProfile.networkBandwidth < 50) {
      compressionLevel = 7;
    } else if (edgeProfile.networkBandwidth > 100) {
      compressionLevel = 3; // less compression for fast networks
    }

    // Adjust batch size based on latency
    let batchSize = optimProfile.batchSize;
    if (edgeProfile.networkLatency > 500) {
      batchSize = Math.ceil(batchSize * 1.5); // larger batches for high latency
    } else if (edgeProfile.networkLatency < 50) {
      batchSize = Math.floor(batchSize * 0.7); // smaller batches for low latency
    }

    // Disable prefetch if offline
    const prefetchEnabled = edgeProfile.isOnline && optimProfile.prefetchEnabled;

    return { compressionLevel, batchSize, prefetchEnabled };
  }

  /**
   * Get compression statistics
   */
  getCompressionStats(): {
    totalOriginalSize: number;
    totalCompressedSize: number;
    avgCompressionRatio: number;
    itemsCompressed: number;
  } {
    const stats = Array.from(this.compressionStats.values());
    if (stats.length === 0) {
      return { totalOriginalSize: 0, totalCompressedSize: 0, avgCompressionRatio: 1, itemsCompressed: 0 };
    }

    const totalOriginal = stats.reduce((sum, s) => sum + s.original, 0);
    const totalCompressed = stats.reduce((sum, s) => sum + s.compressed, 0);
    const avgRatio = totalCompressed / totalOriginal;

    return {
      totalOriginalSize: totalOriginal,
      totalCompressedSize: totalCompressed,
      avgCompressionRatio: avgRatio,
      itemsCompressed: stats.length,
    };
  }

  /**
   * Get cache statistics
   */
  getCacheStats(nodeId: string): {
    cacheSize: number;
    entryCount: number;
    comrpessedEntries: number;
    hitRate: number;
  } {
    const entries = Array.from(this.cache.values());
    const compressedCount = entries.filter((e) => e.compressed).length;

    return {
      cacheSize: entries.reduce((sum) => sum + 1, 0),
      entryCount: this.cache.size,
      comrpessedEntries: compressedCount,
      hitRate: entries.length > 0 ? (entries.length - compressedCount) / entries.length : 0,
    };
  }

  /**
   * Get edge node stats
   */
  getEdgeNodeStats(): {
    totalNodes: number;
    onlineNodes: number;
    offlineNodes: number;
    avgLatency: number;
    lowResourceNodes: number;
  } {
    const profiles = Array.from(this.edgeProfiles.values());
    const onlineNodes = profiles.filter((p) => p.isOnline).length;
    const lowResourceNodes = profiles.filter((p) => p.cpu < 2 || p.memory < 512).length;

    const availableLatencies = profiles.map((p) => p.networkLatency).filter((l) => l > 0);
    const avgLatency = availableLatencies.length > 0 ? availableLatencies.reduce((a, b) => a + b) / availableLatencies.length : 0;

    return {
      totalNodes: profiles.length,
      onlineNodes,
      offlineNodes: profiles.length - onlineNodes,
      avgLatency,
      lowResourceNodes,
    };
  }
}

export default EdgeOptimizationEngine;
