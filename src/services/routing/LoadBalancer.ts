/**
 * Load Balancer - Distribute traffic across regions with multiple strategies
 * Phase 12.3: Geographic Routing
 *
 * Responsibilities:
 * - Implement multiple load balancing strategies
 * - Distribute traffic based on region capacity and health
 * - Support request affinity (sticky sessions)
 * - Track traffic distribution metrics
 * - Implement graceful draining for region updates
 */

import { EventEmitter } from 'events';
import { Logger } from '../logging/Logger';
import { Metrics } from '../monitoring/Metrics';

export enum LoadBalancingStrategy {
  ROUND_ROBIN = 'ROUND_ROBIN',
  WEIGHTED_ROUND_ROBIN = 'WEIGHTED_ROUND_ROBIN',
  LEAST_CONNECTIONS = 'LEAST_CONNECTIONS',
  LATENCY_BASED = 'LATENCY_BASED',
  RANDOM = 'RANDOM',
  GEOGRAPHIC = 'GEOGRAPHIC',
}

export interface RegionLoad {
  regionId: string;
  activeConnections: number;
  capacity: number;
  latency: number;
  errorRate: number;
  healthy: boolean;
  weight: number; // 0-1 for weighted distribution
}

export interface LoadBalancerConfig {
  strategy: LoadBalancingStrategy;
  regions: string[];
  enableAffinity: boolean;
  affinityTimeout: number; // milliseconds
  drainingTimeout: number; // milliseconds for graceful drain
  healthCheckInterval: number;
  maxConnectionsPerRegion: number;
  softLimitPercentage: number; // Soft limit before rejecting (0-100)
}

export interface LoadBalancingDecision {
  selectedRegion: string;
  reason: string;
  capacity: {
    available: number;
    capacity: number;
    utilizationPercent: number;
  };
  alternateRegions: string[];
  timestamp: Date;
}

export class LoadBalancer extends EventEmitter {
  private logger: Logger;
  private metrics: Metrics;
  private regionLoad: Map<string, RegionLoad> = new Map();
  private affinity: Map<string, { region: string; timestamp: Date }> =
    new Map();
  private roundRobinIndex: number = 0;
  private drainingRegions: Set<string> = new Set();
  private config: LoadBalancerConfig;
  private initialized: boolean = false;

  constructor(config: LoadBalancerConfig) {
    super();
    this.config = config;
    this.logger = new Logger('LoadBalancer');
    this.metrics = new Metrics('load_balancer');
    this.initializeRegions();
  }

  /**
   * Initialize region load tracking
   */
  private initializeRegions(): void {
    for (const regionId of this.config.regions) {
      this.regionLoad.set(regionId, {
        regionId,
        activeConnections: 0,
        capacity: this.config.maxConnectionsPerRegion,
        latency: 0,
        errorRate: 0,
        healthy: true,
        weight: 1.0,
      });
    }
  }

  /**
   * Start the load balancer
   */
  async start(): Promise<void> {
    if (this.initialized) return;

    this.logger.info('Starting load balancer', {
      strategy: this.config.strategy,
      regions: this.config.regions,
    });

    // Periodic affinity cleanup
    setInterval(() => {
      this.cleanupAffinity();
    }, 30000);

    this.initialized = true;
    this.emit('started');
  }

  /**
   * Stop the load balancer
   */
  stop(): void {
    if (!this.initialized) return;
    this.logger.info('Stopping load balancer');
    this.removeAllListeners();
    this.initialized = false;
  }

  /**
   * Select region for a new request
   */
  async selectRegion(
    clientId?: string,
    priority?: string[]
  ): Promise<LoadBalancingDecision> {
    try {
      let selectedRegion: string;
      let reason: string;

      // 1. Check affinity first if enabled
      if (
        this.config.enableAffinity &&
        clientId &&
        this.affinity.has(clientId)
      ) {
        const affinity = this.affinity.get(clientId)!;
        const load = this.regionLoad.get(affinity.region);

        if (load && load.healthy && this.canAcceptConnection(affinity.region)) {
          selectedRegion = affinity.region;
          reason = 'Affinity (sticky session)';
          this.metrics.increment('selection_affinity_hit');
        } else {
          reason = 'Affinity region unavailable, reselecting';
          selectedRegion = await this.balanceLoad(priority);
        }
      } else {
        // 2. Balance load using selected strategy
        selectedRegion = await this.balanceLoad(priority);
        reason = `${this.config.strategy} selection`;
      }

      // 3. Store affinity if enabled
      if (this.config.enableAffinity && clientId) {
        this.affinity.set(clientId, {
          region: selectedRegion,
          timestamp: new Date(),
        });
      }

      const load = this.regionLoad.get(selectedRegion)!;
      const decision: LoadBalancingDecision = {
        selectedRegion,
        reason,
        capacity: {
          available: load.capacity - load.activeConnections,
          capacity: load.capacity,
          utilizationPercent:
            (load.activeConnections / load.capacity) * 100,
        },
        alternateRegions: this.getAlternateRegions(selectedRegion),
        timestamp: new Date(),
      };

      this.metrics.increment(`selected_region_${selectedRegion}`);

      return decision;
    } catch (error) {
      this.logger.error('Region selection failed', error);
      this.metrics.increment('selection_errors');
      throw error;
    }
  }

  /**
   * Balance load using configured strategy
   */
  private async balanceLoad(priority?: string[]): Promise<string> {
    // Filter candidates (healthy, not draining, not at capacity)
    const candidates = this.getCandidateRegions();

    if (candidates.length === 0) {
      // Fallback: return least-loaded region regardless of health
      this.logger.warn('No healthy candidates, using least-loaded fallback');
      return this.getLeastLoadedRegion();
    }

    switch (this.config.strategy) {
      case LoadBalancingStrategy.ROUND_ROBIN:
        return this.roundRobinSelect(candidates);

      case LoadBalancingStrategy.WEIGHTED_ROUND_ROBIN:
        return this.weightedRoundRobinSelect(candidates);

      case LoadBalancingStrategy.LEAST_CONNECTIONS:
        return this.leastConnectionsSelect(candidates);

      case LoadBalancingStrategy.LATENCY_BASED:
        return this.latencyBasedSelect(candidates);

      case LoadBalancingStrategy.RANDOM:
        return candidates[Math.floor(Math.random() * candidates.length)];

      case LoadBalancingStrategy.GEOGRAPHIC:
        return this.geographicSelect(candidates);

      default:
        return candidates[0];
    }
  }

  /**
   * Get candidate regions (healthy, not draining, with capacity)
   */
  private getCandidateRegions(): string[] {
    const candidates: string[] = [];

    for (const [regionId, load] of this.regionLoad.entries()) {
      // Skip draining or unhealthy regions
      if (this.drainingRegions.has(regionId) || !load.healthy) {
        continue;
      }

      // Skip regions at capacity
      const utilization =
        (load.activeConnections / load.capacity) * 100;
      if (utilization >= 100) {
        continue;
      }

      // Skip regions hitting soft limit unless no healthy regions
      const softLimit = this.config.softLimitPercentage;
      if (
        utilization >= softLimit &&
        this.regionLoad.size > 1
      ) {
        continue;
      }

      candidates.push(regionId);
    }

    // If no candidates, return all regions
    return candidates.length > 0 ? candidates : Array.from(this.regionLoad.keys());
  }

  /**
   * Round-robin selection
   */
  private roundRobinSelect(candidates: string[]): string {
    const selected =
      candidates[this.roundRobinIndex % candidates.length];
    this.roundRobinIndex++;
    return selected;
  }

  /**
   * Weighted round-robin selection
   */
  private weightedRoundRobinSelect(candidates: string[]): string {
    // Create weighted list
    const weighted: string[] = [];

    for (const regionId of candidates) {
      const load = this.regionLoad.get(regionId)!;
      const weight = Math.round(load.weight * 100); // Convert 0-1 to 0-100
      for (let i = 0; i < weight; i++) {
        weighted.push(regionId);
      }
    }

    if (weighted.length === 0) return candidates[0];

    const selected = weighted[this.roundRobinIndex % weighted.length];
    this.roundRobinIndex++;
    return selected;
  }

  /**
   * Least connections selection
   */
  private leastConnectionsSelect(candidates: string[]): string {
    let leastLoaded = candidates[0];
    let minConnections =
      this.regionLoad.get(candidates[0])?.activeConnections || 0;

    for (const regionId of candidates) {
      const load = this.regionLoad.get(regionId)!;
      if (load.activeConnections < minConnections) {
        leastLoaded = regionId;
        minConnections = load.activeConnections;
      }
    }

    return leastLoaded;
  }

  /**
   * Latency-based selection (prefer lower latency)
   */
  private latencyBasedSelect(candidates: string[]): string {
    let lowest = candidates[0];
    let minLatency = this.regionLoad.get(candidates[0])?.latency || 0;

    for (const regionId of candidates) {
      const load = this.regionLoad.get(regionId)!;
      if (load.latency < minLatency) {
        lowest = regionId;
        minLatency = load.latency;
      }
    }

    return lowest;
  }

  /**
   * Geographic selection (distribute based on geography)
   */
  private geographicSelect(candidates: string[]): string {
    // Simple distribution: prefer non-adjacent regions
    // In production, this would use actual geographic distribution
    return candidates[Math.floor(Math.random() * candidates.length)];
  }

  /**
   * Get least-loaded region regardless of health
   */
  private getLeastLoadedRegion(): string {
    let leastLoaded = this.config.regions[0];
    let minConnections =
      this.regionLoad.get(this.config.regions[0])?.activeConnections || 0;

    for (const regionId of this.config.regions) {
      const load = this.regionLoad.get(regionId)!;
      if (load.activeConnections < minConnections) {
        leastLoaded = regionId;
        minConnections = load.activeConnections;
      }
    }

    return leastLoaded;
  }

  /**
   * Get alternate regions for failover
   */
  private getAlternateRegions(primary: string): string[] {
    const alternates: string[] = [];

    for (const regionId of this.config.regions) {
      if (regionId !== primary) {
        alternates.push(regionId);
      }
    }

    return alternates.slice(0, 3);
  }

  /**
   * Check if region can accept connection
   */
  private canAcceptConnection(regionId: string): boolean {
    const load = this.regionLoad.get(regionId);
    if (!load) return false;

    const utilization = (load.activeConnections / load.capacity) * 100;
    return (
      utilization < 100 &&
      utilization < this.config.softLimitPercentage &&
      load.healthy &&
      !this.drainingRegions.has(regionId)
    );
  }

  /**
   * Record connection establishment
   */
  recordConnectionOpened(regionId: string): void {
    const load = this.regionLoad.get(regionId);
    if (load) {
      load.activeConnections++;
      this.metrics.gauge(
        `active_connections_${regionId}`,
        load.activeConnections
      );
    }
  }

  /**
   * Record connection closure
   */
  recordConnectionClosed(regionId: string): void {
    const load = this.regionLoad.get(regionId);
    if (load) {
      load.activeConnections = Math.max(0, load.activeConnections - 1);
      this.metrics.gauge(
        `active_connections_${regionId}`,
        load.activeConnections
      );
    }
  }

  /**
   * Update region load metrics
   */
  updateRegionLoad(
    regionId: string,
    latency: number,
    errorRate: number,
    healthy: boolean,
    weight?: number
  ): void {
    const load = this.regionLoad.get(regionId);
    if (load) {
      load.latency = latency;
      load.errorRate = errorRate;
      load.healthy = healthy;
      if (weight !== undefined) {
        load.weight = Math.max(0, Math.min(1, weight)); // Clamp to 0-1
      }

      this.metrics.gauge(`region_latency_${regionId}`, latency);
      this.metrics.gauge(`region_error_rate_${regionId}`, errorRate);
      this.metrics.gauge(`region_health_${regionId}`, healthy ? 1 : 0);
    }
  }

  /**
   * Start graceful drain of a region (for updates, maintenance)
   */
  startDrain(regionId: string): void {
    this.drainingRegions.add(regionId);
    this.logger.info(
      `Starting graceful drain for region ${regionId}`,
      { timeout: this.config.drainingTimeout }
    );

    this.metrics.increment(`drain_started_${regionId}`);
    this.emit('drain_started', { regionId });

    // Force drain after timeout
    setTimeout(() => {
      this.completeDrain(regionId);
    }, this.config.drainingTimeout);
  }

  /**
   * Complete drain of a region
   */
  private completeDrain(regionId: string): void {
    const load = this.regionLoad.get(regionId);
    if (load && load.activeConnections > 0) {
      this.logger.warn(
        `Force completed drain for region ${regionId} with ${load.activeConnections} remaining connections`
      );
    }

    this.drainingRegions.delete(regionId);
    this.logger.info(`Drain completed for region ${regionId}`);
    this.metrics.increment(`drain_completed_${regionId}`);
    this.emit('drain_completed', { regionId });
  }

  /**
   * Check if region is draining
   */
  isDraining(regionId: string): boolean {
    return this.drainingRegions.has(regionId);
  }

  /**
   * Clean up expired affinity entries
   */
  private cleanupAffinity(): void {
    const now = Date.now();
    const expired: string[] = [];

    for (const [clientId, affinity] of this.affinity.entries()) {
      if (now - affinity.timestamp.getTime() > this.config.affinityTimeout) {
        expired.push(clientId);
      }
    }

    expired.forEach((clientId) => this.affinity.delete(clientId));

    if (expired.length > 0) {
      this.logger.debug(`Cleaned up ${expired.length} expired affinity entries`);
    }
  }

  /**
   * Get load balancer metrics
   */
  getMetrics(): Record<string, unknown> {
    const regionMetrics: Record<string, unknown> = {};

    for (const [regionId, load] of this.regionLoad.entries()) {
      regionMetrics[regionId] = {
        activeConnections: load.activeConnections,
        capacity: load.capacity,
        utilization: (load.activeConnections / load.capacity),
        latency: Math.round(load.latency),
        errorRate: Math.round(load.errorRate * 100) / 100,
        healthy: load.healthy,
        weight: load.weight,
        draining: this.drainingRegions.has(regionId),
      };
    }

    return {
      initialized: this.initialized,
      strategy: this.config.strategy,
      regionMetrics,
      totalActiveConnections: Array.from(this.regionLoad.values()).reduce(
        (sum, load) => sum + load.activeConnections,
        0
      ),
      affinitySize: this.affinity.size,
      drainingRegions: Array.from(this.drainingRegions),
      metrics: this.metrics.getMetrics(),
    };
  }
}
