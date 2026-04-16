/**
 * Geographic Router - Global request routing with region awareness
 * Phase 12.3: Geographic Routing
 * 
 * Responsibilities:
 * - Route requests to optimal region based on user location and region state
 * - Support latency-based routing with region health consideration
 * - Handle region failover and load balancing
 * - Track routing metrics and latency measurements
 * - Implement request affinity for session persistence
 */

import { EventEmitter } from 'events';
import { Logger } from '../logging/Logger';
import { Metrics } from '../monitoring/Metrics';

// Types for geographic routing
export interface RoutingRequest {
  clientIP: string;
  userLocation?: {
    latitude: number;
    longitude: number;
    countryCode?: string;
  };
  sessionId?: string;
  preferredRegions?: string[]; // Fallback preferences
  requireLocalData?: boolean; // Must route to region with local data
}

export interface RegionHealthStatus {
  regionId: string;
  healthy: boolean;
  latency: number; // milliseconds (p95)
  errorRate: number; // percentage (0-100)
  activeConnections: number;
  capacity: number;
  lastHealthCheck: Date;
}

export interface RoutingDecision {
  selectedRegion: string;
  confidence: number; // 0-1: how confident is the routing decision
  alternateRegions: string[]; // Fallback regions if primary fails
  estimatedLatency: number;
  reason: string;
  timestamp: Date;
}

export interface GeoRouterConfig {
  regions: string[];
  updateInterval: number; // milliseconds
  healthCheckTimeout: number;
  minConfidenceThreshold: number;
  enableAffinity: boolean;
  enableWeightedRoundRobin: boolean;
  maxRetries: number;
}

export class GeoRouter extends EventEmitter {
  private logger: Logger;
  private metrics: Metrics;
  private regionHealthMap: Map<string, RegionHealthStatus> = new Map();
  private sessionAffinity: Map<string, string> = new Map(); // sessionId -> regionId
  private latencyHistory: Map<string, number[]> = new Map(); // regionId -> latency samples
  private routingCache: Map<string, RoutingDecision> = new Map();
  private cacheTTL: number = 60000; // 1 minute
  private cacheTimestamps: Map<string, Date> = new Map();
  private config: GeoRouterConfig;
  private initialized: boolean = false;

  constructor(config: GeoRouterConfig) {
    super();
    this.config = config;
    this.logger = new Logger('GeoRouter');
    this.metrics = new Metrics('geo_router');
    this.initializeRegions();
  }

  /**
   * Initialize region health tracking
   */
  private initializeRegions(): void {
    for (const regionId of this.config.regions) {
      this.regionHealthMap.set(regionId, {
        regionId,
        healthy: false,
        latency: 0,
        errorRate: 0,
        activeConnections: 0,
        capacity: 1000,
        lastHealthCheck: new Date(0),
      });
      this.latencyHistory.set(regionId, []);
    }
  }

  /**
   * Start the geographic router with periodic health checks
   */
  async start(): Promise<void> {
    if (this.initialized) return;

    this.logger.info('Starting geographic router', { regions: this.config.regions });

    // Initial health check
    await this.checkAllRegionHealth();

    // Periodic health checks
    setInterval(() => {
      this.checkAllRegionHealth().catch((error) => {
        this.logger.error('Health check failed', error);
      });
    }, this.config.updateInterval);

    // Clean up old cache entries
    setInterval(() => {
      this.cleanupCache();
    }, 30000);

    this.initialized = true;
    this.emit('started');
  }

  /**
   * Stop the geographic router
   */
  stop(): void {
    if (!this.initialized) return;
    this.logger.info('Stopping geographic router');
    this.removeAllListeners();
    this.initialized = false;
  }

  /**
   * Route a request to the optimal region
   */
  async routeRequest(request: RoutingRequest): Promise<RoutingDecision> {
    const startTime = Date.now();

    try {
      // Check cache first
      const cacheKey = this.generateCacheKey(request);
      const cached = this.getFromCache(cacheKey);
      if (cached) {
        this.metrics.increment('routing_cache_hit');
        return cached;
      }

      let selectedRegion: string;
      let reason: string;
      let confidence: number = 1.0;

      // 1. Check session affinity if enabled
      if (
        this.config.enableAffinity &&
        request.sessionId &&
        this.sessionAffinity.has(request.sessionId)
      ) {
        selectedRegion = this.sessionAffinity.get(request.sessionId)!;
        const regionHealth = this.regionHealthMap.get(selectedRegion);

        if (regionHealth?.healthy) {
          reason = 'Session affinity (sticky)';
          this.metrics.increment('routing_affinity_hit');
        } else {
          reason = 'Session affinity region unhealthy, using fallback';
          selectedRegion = await this.selectOptimalRegion(request);
          confidence = 0.7;
        }
      } else {
        // 2. Select optimal region based on location and health
        selectedRegion = await this.selectOptimalRegion(request);
        reason = 'Optimal region selected';
      }

      // Store affinity if enabled
      if (this.config.enableAffinity && request.sessionId) {
        this.sessionAffinity.set(request.sessionId, selectedRegion);
      }

      // Build decision with alternates
      const alternates = this.getAlternateRegions(
        selectedRegion,
        request.preferredRegions
      );

      const decision: RoutingDecision = {
        selectedRegion,
        confidence,
        alternateRegions: alternates,
        estimatedLatency:
          this.regionHealthMap.get(selectedRegion)?.latency || 0,
        reason,
        timestamp: new Date(),
      };

      // Cache the decision
      this.setCache(cacheKey, decision);

      // Record metrics
      this.metrics.timing('routing_decision_time', Date.now() - startTime);
      this.metrics.increment(`routing_to_${selectedRegion}`);

      return decision;
    } catch (error) {
      this.logger.error('Routing request failed', { error, request });
      this.metrics.increment('routing_errors');
      throw error;
    }
  }

  /**
   * Select the optimal region based on location, health, and preferences
   */
  private async selectOptimalRegion(request: RoutingRequest): Promise<string> {
    const candidates = this.getHealthyRegions();

    if (candidates.length === 0) {
      // Fallback: use least-unhealthy region
      this.logger.warn('No healthy regions available, using fallback');
      return this.config.regions[0];
    }

    if (candidates.length === 1) {
      return candidates[0];
    }

    // Score regions by location proximity and health
    const scores = candidates.map((regionId) => {
      const health = this.regionHealthMap.get(regionId)!;
      const locationScore = this.calculateLocationScore(
        regionId,
        request.userLocation
      );
      const healthScore = this.calculateHealthScore(health);
      const capacityScore = 1.0 - health.activeConnections / health.capacity;

      // Weighted scoring: location (50%), health (30%), capacity (20%)
      const totalScore =
        locationScore * 0.5 + healthScore * 0.3 + capacityScore * 0.2;

      return {
        regionId,
        score: totalScore,
      };
    });

    // Sort by score (highest first)
    scores.sort((a, b) => b.score - a.score);

    // Select using weighted round-robin if enabled
    if (this.config.enableWeightedRoundRobin) {
      return this.weightedSelection(scores);
    }

    return scores[0].regionId;
  }

  /**
   * Calculate location-based score (closer = higher)
   */
  private calculateLocationScore(
    regionId: string,
    userLocation?: RoutingRequest['userLocation']
  ): number {
    if (!userLocation) {
      // No location info, use equal weight for all regions
      return 0.5;
    }

    // Approximate region centers (latitude, longitude)
    const regionCoords: Record<string, [number, number]> = {
      'us-west': [37.7749, -122.4194], // San Francisco
      'eu-west': [53.3498, -6.2603], // Dublin
      'eu-central': [50.1109, 8.6821], // Frankfurt
      'ap-south': [19.076, 72.8479], // Mumbai
      'ap-northeast': [35.6762, 139.6503], // Tokyo
    };

    const userCoords = [userLocation.latitude, userLocation.longitude];
    const regionCoord = regionCoords[regionId];

    if (!regionCoord) {
      return 0.5; // Default score if region unknown
    }

    // Calculate Haversine distance (simplified approximation)
    const distance = Math.sqrt(
      Math.pow(userCoords[0] - regionCoord[0], 2) +
        Math.pow(userCoords[1] - regionCoord[1], 2)
    );

    // Normalize distance to 0-1 score (closer = higher)
    // Max distance ~180 degrees (half earth)
    const score = Math.max(0, 1 - distance / 180);

    return score;
  }

  /**
   * Calculate health-based score (healthier = higher)
   */
  private calculateHealthScore(health: RegionHealthStatus): number {
    let score = 1.0;

    // Latency factor: prefer lower latency (p100 = 500ms = 0.5, p0 = 0ms = 1.0)
    const latencyFactor = Math.max(0, 1 - health.latency / 500);
    score *= latencyFactor * 0.5 + 0.5; // Blend with baseline

    // Error rate factor: prefer lower errors
    const errorFactor = Math.max(0, 1 - health.errorRate / 100);
    score *= errorFactor * 0.5 + 0.5; // Blend with baseline

    // If region is marked unhealthy, heavily penalize
    if (!health.healthy) {
      score *= 0.1;
    }

    return Math.min(1, score);
  }

  /**
   * Select region using weighted round-robin
   */
  private weightedSelection(
    scores: Array<{ regionId: string; score: number }>
  ): string {
    const totalScore = scores.reduce((sum, s) => sum + s.score, 0);
    let random = Math.random() * totalScore;

    for (const { regionId, score } of scores) {
      random -= score;
      if (random <= 0) {
        return regionId;
      }
    }

    return scores[0].regionId;
  }

  /**
   * Get alternate regions for failover (in priority order)
   */
  private getAlternateRegions(
    primary: string,
    userPreferences?: string[]
  ): string[] {
    const alternates: string[] = [];

    // 1. User preferences first
    if (userPreferences) {
      for (const pref of userPreferences) {
        if (pref !== primary && alternates.length < 3) {
          alternates.push(pref);
        }
      }
    }

    // 2. Fill remaining slots with healthy regions
    for (const regionId of this.config.regions) {
      if (regionId !== primary && !alternates.includes(regionId)) {
        alternates.push(regionId);
      }
    }

    return alternates.slice(0, 3); // Max 3 alternates
  }

  /**
   * Get list of healthy regions
   */
  private getHealthyRegions(): string[] {
    const healthy: string[] = [];

    for (const [regionId, health] of this.regionHealthMap.entries()) {
      if (
        health.healthy &&
        health.errorRate < 5 &&
        health.activeConnections < health.capacity * 0.9
      ) {
        healthy.push(regionId);
      }
    }

    // Return at least 1 region even if unhealthy
    return healthy.length > 0 ? healthy : [this.config.regions[0]];
  }

  /**
   * Check health of all regions
   */
  private async checkAllRegionHealth(): Promise<void> {
    const checks = this.config.regions.map((regionId) =>
      this.checkRegionHealth(regionId)
    );

    const results = await Promise.allSettled(checks);

    results.forEach((result, index) => {
      if (result.status === 'rejected') {
        this.logger.warn(
          `Health check failed for region ${this.config.regions[index]}`,
          result.reason
        );
      }
    });
  }

  /**
   * Check health of a single region
   */
  private async checkRegionHealth(regionId: string): Promise<void> {
    const startTime = Date.now();

    try {
      // This would be replaced with actual health check endpoint
      // For now, simulate with random latency
      const latency = Math.random() * 100 + 10; // 10-110ms
      const errorRate = Math.random() * 2; // 0-2%

      this.recordLatency(regionId, latency);

      const health: RegionHealthStatus = {
        regionId,
        healthy: errorRate < 1 && latency < 200,
        latency,
        errorRate,
        activeConnections: Math.floor(Math.random() * 500),
        capacity: 1000,
        lastHealthCheck: new Date(),
      };

      this.regionHealthMap.set(regionId, health);

      this.metrics.gauge(`region_latency_${regionId}`, latency);
      this.metrics.gauge(`region_error_rate_${regionId}`, errorRate);
      this.metrics.gauge(`region_health_${regionId}`, health.healthy ? 1 : 0);

      this.emit('health_updated', { regionId, health });
    } catch (error) {
      this.logger.error(
        `Health check for region ${regionId} failed`,
        error
      );
      this.metrics.increment(`health_check_failures_${regionId}`);
    }
  }

  /**
   * Record latency sample and calculate P95
   */
  private recordLatency(regionId: string, latency: number): void {
    const history = this.latencyHistory.get(regionId) || [];
    history.push(latency);

    // Keep only last 100 samples
    if (history.length > 100) {
      history.shift();
    }

    this.latencyHistory.set(regionId, history);

    // Calculate P95
    if (history.length > 0) {
      const sorted = [...history].sort((a, b) => a - b);
      const p95Index = Math.ceil(sorted.length * 0.95) - 1;
      const p95 = sorted[Math.max(0, p95Index)];

      const health = this.regionHealthMap.get(regionId);
      if (health) {
        health.latency = p95;
      }
    }
  }

  /**
   * Report request success/failure to update metrics
   */
  reportRequest(
    regionId: string,
    success: boolean,
    latency: number
  ): void {
    this.recordLatency(regionId, latency);

    const health = this.regionHealthMap.get(regionId);
    if (health) {
      // Update error rate (exponential moving average)
      const errorIncrement = success ? 0 : 1;
      health.errorRate = health.errorRate * 0.9 + errorIncrement * 0.1;

      this.metrics.increment(
        `requests_${regionId}_${success ? 'success' : 'error'}`
      );
    }
  }

  /**
   * Update active connections for a region
   */
  updateActiveConnections(regionId: string, delta: number): void {
    const health = this.regionHealthMap.get(regionId);
    if (health) {
      health.activeConnections = Math.max(0, health.activeConnections + delta);
      this.metrics.gauge(
        `active_connections_${regionId}`,
        health.activeConnections
      );
    }
  }

  /**
   * Get current routing metrics
   */
  getMetrics(): Record<string, unknown> {
    const regionStats: Record<string, unknown> = {};

    for (const [regionId, health] of this.regionHealthMap.entries()) {
      regionStats[regionId] = {
        healthy: health.healthy,
        latency: Math.round(health.latency),
        errorRate: Math.round(health.errorRate * 100) / 100,
        activeConnections: health.activeConnections,
        capacity: health.capacity,
        utilization: (health.activeConnections / health.capacity),
      };
    }

    return {
      initialized: this.initialized,
      regions: regionStats,
      cachedDecisions: this.routingCache.size,
      activeAffinity: this.sessionAffinity.size,
      metrics: this.metrics.getMetrics(),
    };
  }

  /**
   * Cache management
   */
  private generateCacheKey(request: RoutingRequest): string {
    // Generate cache key from request characteristics
    const location = request.userLocation
      ? `${Math.round(request.userLocation.latitude)}_${Math.round(request.userLocation.longitude)}`
      : 'unknown';
    return `routing_${request.clientIP}_${location}`;
  }

  private getFromCache(key: string): RoutingDecision | null {
    const timestamp = this.cacheTimestamps.get(key);
    if (!timestamp || Date.now() - timestamp.getTime() > this.cacheTTL) {
      this.routingCache.delete(key);
      this.cacheTimestamps.delete(key);
      return null;
    }
    return this.routingCache.get(key) || null;
  }

  private setCache(key: string, decision: RoutingDecision): void {
    this.routingCache.set(key, decision);
    this.cacheTimestamps.set(key, new Date());
  }

  private cleanupCache(): void {
    const now = Date.now();
    for (const [key, timestamp] of this.cacheTimestamps.entries()) {
      if (now - timestamp.getTime() > this.cacheTTL) {
        this.routingCache.delete(key);
        this.cacheTimestamps.delete(key);
      }
    }
  }
}
