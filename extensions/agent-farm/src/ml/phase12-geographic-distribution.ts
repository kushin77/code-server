/**
 * Phase 12: Multi-Site Federation & Geographic Distribution
 * Components for global distribution, smart routing, and cross-region replication
 */

// ============================================================================
// GEOGRAPHIC ROUTER - Geo-aware routing and latency optimization
// ============================================================================

export interface GeographicRegion {
  regionId: string;
  name: string;
  continent: string;
  latLng: [number, number]; // [latitude, longitude]
  replicaIds: string[];
  healthScore: number; // 0-100
  averageLatency: number; // ms
  loadPercentage: number; // 0-100
}

export interface LatencyMeasurement {
  clientRegion: string;
  serverRegion: string;
  latency: number; // milliseconds
  timestamp: number;
  sampleSize: number;
}

export class GeographicRouter {
  private regions: Map<string, GeographicRegion> = new Map();
  private latencyMatrix: Map<string, LatencyMeasurement[]> = new Map();
  private userLocationCache: Map<string, string> = new Map(); // userId -> regionId

  registerRegion(region: GeographicRegion): void {
    this.regions.set(region.regionId, region);
  }

  recordLatency(measurement: LatencyMeasurement): void {
    const key = `${measurement.clientRegion}:${measurement.serverRegion}`;
    if (!this.latencyMatrix.has(key)) {
      this.latencyMatrix.set(key, []);
    }
    this.latencyMatrix.get(key)!.push(measurement);
  }

  routeToNearestRegion(userLocationLatLng: [number, number], excludeRegions: string[] = []): string {
    let nearestRegion = '';
    let minDistance = Infinity;

    for (const [regionId, region] of this.regions.entries()) {
      if (excludeRegions.includes(regionId)) continue;
      if (region.healthScore < 50) continue; // Skip unhealthy regions

      const distance = this.haversineDistance(userLocationLatLng, region.latLng);
      if (distance < minDistance) {
        minDistance = distance;
        nearestRegion = regionId;
      }
    }

    return nearestRegion;
  }

  private haversineDistance(loc1: [number, number], loc2: [number, number]): number {
    const [lat1, lon1] = loc1;
    const [lat2, lon2] = loc2;
    const R = 6371; // Earth's radius in km

    const dLat = ((lat2 - lat1) * Math.PI) / 180;
    const dLon = ((lon2 - lon1) * Math.PI) / 180;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
              Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) *
              Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

    return R * c;
  }

  getRegionHealth(regionId: string): number {
    return this.regions.get(regionId)?.healthScore ?? 0;
  }

  getAverageLatency(fromRegion: string, toRegion: string): number {
    const key = `${fromRegion}:${toRegion}`;
    const measurements = this.latencyMatrix.get(key) ?? [];

    if (measurements.length === 0) return 999;

    const sum = measurements.reduce((a, m) => a + m.latency, 0);
    return sum / measurements.length;
  }

  getAllRegions(): GeographicRegion[] {
    return Array.from(this.regions.values());
  }
}

// ============================================================================
// GLOBAL LOAD BALANCER - Latency-aware global load balancing
// ============================================================================

export interface LoadBalancingStrategy {
  type: 'round-robin' | 'least-loaded' | 'geo-latency' | 'weighted';
  weights?: Map<string, number>;
}

export interface GlobalLoadBalancerMetrics {
  totalRequests: number;
  requestsByRegion: Map<string, number>;
  averageLatency: number;
  p99Latency: number;
  failoverCount: number;
}

export class GlobalLoadBalancer {
  private router: GeographicRouter;
  private strategy: LoadBalancingStrategy;
  private requestCount: Map<string, number> = new Map();
  private latencies: number[] = [];
  private metrics: GlobalLoadBalancerMetrics;

  constructor(router: GeographicRouter, strategy: LoadBalancingStrategy = { type: 'geo-latency' }) {
    this.router = router;
    this.strategy = strategy;
    this.metrics = {
      totalRequests: 0,
      requestsByRegion: new Map(),
      averageLatency: 0,
      p99Latency: 0,
      failoverCount: 0,
    };
  }

  selectRegion(userLocationLatLng: [number, number], clientRegion?: string): string {
    switch (this.strategy.type) {
      case 'round-robin':
        return this.roundRobin();
      case 'least-loaded':
        return this.leastLoaded();
      case 'geo-latency':
        return this.router.routeToNearestRegion(userLocationLatLng);
      case 'weighted':
        return this.weightedSelection();
      default:
        return this.router.routeToNearestRegion(userLocationLatLng);
    }
  }

  private roundRobin(): string {
    const regions = this.router.getAllRegions().map(r => r.regionId);
    const counts = Array.from(this.requestCount.values());
    const minCount = Math.min(...counts, 0);
    const leastUsedRegion = regions.find(r => (this.requestCount.get(r) ?? 0) === minCount);
    return leastUsedRegion ?? regions[0];
  }

  private leastLoaded(): string {
    let leastLoadedRegion = '';
    let minLoad = Infinity;

    for (const region of this.router.getAllRegions()) {
      if (region.loadPercentage < minLoad) {
        minLoad = region.loadPercentage;
        leastLoadedRegion = region.regionId;
      }
    }

    return leastLoadedRegion;
  }

  private weightedSelection(): string {
    if (!this.strategy.weights) return this.leastLoaded();

    const regions = this.router.getAllRegions();
    const totalWeight = regions.reduce((sum, r) => sum + (this.strategy.weights?.get(r.regionId) ?? 1), 0);
    let random = Math.random() * totalWeight;

    for (const region of regions) {
      const weight = this.strategy.weights?.get(region.regionId) ?? 1;
      random -= weight;
      if (random <= 0) return region.regionId;
    }

    return regions[0].regionId;
  }

  recordRequest(regionId: string, latency: number): void {
    this.metrics.totalRequests++;
    this.requestCount.set(regionId, (this.requestCount.get(regionId) ?? 0) + 1);
    this.metrics.requestsByRegion.set(regionId, this.requestCount.get(regionId)!);
    this.latencies.push(latency);

    this.updateMetrics();
  }

  private updateMetrics(): void {
    if (this.latencies.length === 0) return;

    const sum = this.latencies.reduce((a, b) => a + b);
    this.metrics.averageLatency = sum / this.latencies.length;

    const sorted = [...this.latencies].sort((a, b) => a - b);
    const p99Index = Math.floor(sorted.length * 0.99);
    this.metrics.p99Latency = sorted[p99Index] ?? 0;
  }

  getMetrics(): GlobalLoadBalancerMetrics {
    return this.metrics;
  }
}

// ============================================================================
// MULTI-REGION REPLICATOR - Cross-region data replication with CRDT
// ============================================================================

export interface ReplicaSync {
  sourceRegion: string;
  targetRegion: string;
  lastSyncTime: number;
  syncLatency: number; // milliseconds
  itemsSynced: number;
  conflicts: number;
}

export class MultiRegionReplicator {
  private syncs: Map<string, ReplicaSync[]> = new Map();
  private syncHistory: ReplicaSync[] = [];
  private conflictResolver: ((local: any, remote: any) => any) | null = null;

  registerSyncResolver(resolver: (local: any, remote: any) => any): void {
    this.conflictResolver = resolver;
  }

  recordSync(sourceRegion: string, targetRegion: string, itemsSynced: number, latency: number, conflicts: number = 0): ReplicaSync {
    const key = `${sourceRegion}:${targetRegion}`;
    const sync: ReplicaSync = {
      sourceRegion,
      targetRegion,
      lastSyncTime: Date.now(),
      syncLatency: latency,
      itemsSynced,
      conflicts,
    };

    if (!this.syncs.has(key)) {
      this.syncs.set(key, []);
    }

    this.syncs.get(key)!.push(sync);
    this.syncHistory.push(sync);

    return sync;
  }

  getLastSync(sourceRegion: string, targetRegion: string): ReplicaSync | undefined {
    const key = `${sourceRegion}:${targetRegion}`;
    const syncs = this.syncs.get(key);
    return syncs && syncs.length > 0 ? syncs[syncs.length - 1] : undefined;
  }

  getEventualConsistencyLatency(sourceRegion: string): number {
    const syncs = Array.from(this.syncs.values()).flat();
    const relevantSyncs = syncs.filter(s => s.sourceRegion === sourceRegion);

    if (relevantSyncs.length === 0) return 0;

    const sum = relevantSyncs.reduce((a, s) => a + s.syncLatency, 0);
    return sum / relevantSyncs.length;
  }

  getSyncHistory(): ReplicaSync[] {
    return this.syncHistory;
  }

  getConflictRate(): number {
    if (this.syncHistory.length === 0) return 0;

    const totalConflicts = this.syncHistory.reduce((sum, s) => sum + s.conflicts, 0);
    const totalItems = this.syncHistory.reduce((sum, s) => sum + s.itemsSynced, 0);

    return totalItems > 0 ? totalConflicts / totalItems : 0;
  }
}

// ============================================================================
// GEOGRAPHIC REGISTRY - Track regions, replicas, and federation state
// ============================================================================

export interface FederationMember {
  regionId: string;
  replicaIds: string[];
  isPrimary: boolean;
  isHealthy: boolean;
  joinedAt: number;
  lastHeartbeat: number;
}

export interface FederationTopology {
  totalMembers: number;
  healthyMembers: number;
  primaryRegion: string;
  regions: FederationMember[];
}

export class GeographicRegistry {
  private members: Map<string, FederationMember> = new Map();
  private primaryRegion: string = '';

  registerRegion(regionId: string, replicaIds: string[], isPrimary: boolean = false): FederationMember {
    const member: FederationMember = {
      regionId,
      replicaIds,
      isPrimary,
      isHealthy: true,
      joinedAt: Date.now(),
      lastHeartbeat: Date.now(),
    };

    this.members.set(regionId, member);

    if (isPrimary) {
      this.primaryRegion = regionId;
    }

    return member;
  }

  updateMemberHealth(regionId: string, isHealthy: boolean): void {
    const member = this.members.get(regionId);
    if (member) {
      member.isHealthy = isHealthy;
      member.lastHeartbeat = Date.now();
    }
  }

  promoteToPrimary(regionId: string): boolean {
    const newPrimary = this.members.get(regionId);
    if (!newPrimary || !newPrimary.isHealthy) return false;

    // Demote old primary
    const oldPrimary = this.members.get(this.primaryRegion);
    if (oldPrimary) {
      oldPrimary.isPrimary = false;
    }

    // Promote new primary
    newPrimary.isPrimary = true;
    this.primaryRegion = regionId;

    return true;
  }

  getTopology(): FederationTopology {
    const regions = Array.from(this.members.values());
    const healthyMembers = regions.filter(m => m.isHealthy).length;

    return {
      totalMembers: regions.length,
      healthyMembers,
      primaryRegion: this.primaryRegion,
      regions,
    };
  }

  getMember(regionId: string): FederationMember | undefined {
    return this.members.get(regionId);
  }

  getAllMembers(): FederationMember[] {
    return Array.from(this.members.values());
  }
}

// ============================================================================
// MULTI-SITE FEDERATION ORCHESTRATOR - Main orchestration agent
// ============================================================================

export interface FederationConfig {
  primaryRegion: string;
  secondaryRegions: string[];
  replicationStrategy: 'active-active' | 'active-passive' | 'primary-backup';
  eventualConsistencySLA: number; // milliseconds
  globalAvailabilitySLA: number; // percentage (e.g., 99.99)
}

export interface FederationStatus {
  timestamp: number;
  topology: FederationTopology;
  globalLatency: { p50: number; p95: number; p99: number };
  replicationLag: number;
  failoversPastDay: number;
  failoverCount: number;  // Add missing property
  systemHealthScore: number; // 0-100
  totalRequests?: number;  // Add missing property
  deployedRegions?: string[];  // Add missing property
}

export class MultiSiteFederationOrchestrator {
  private config: FederationConfig;
  private registry: GeographicRegistry;
  private router: GeographicRouter;
  private loadBalancer: GlobalLoadBalancer;
  private replicator: MultiRegionReplicator;
  private failoverHistory: Array<{ timestamp: number; fromRegion: string; toRegion: string }> = [];

  constructor(config: FederationConfig, registry: GeographicRegistry, router: GeographicRouter) {
    this.config = config;
    this.registry = registry;
    this.router = router;
    this.loadBalancer = new GlobalLoadBalancer(router);
    this.replicator = new MultiRegionReplicator();
  }

  deployRegion(regionId: string, replicaIds: string[], isPrimary: boolean = false): void {
    this.registry.registerRegion(regionId, replicaIds, isPrimary);

    const lat = Math.random() * 180 - 90;
    const lng = Math.random() * 360 - 180;

    this.router.registerRegion({
      regionId,
      name: regionId,
      continent: this.getContinentFromLatLng([lat, lng]),
      latLng: [lat, lng],
      replicaIds,
      healthScore: 100,
      averageLatency: 0,
      loadPercentage: 0,
    });
  }

  private getContinentFromLatLng([lat, lng]: [number, number]): string {
    // Simplified continent detection
    if (lat > 15) return 'North America';
    if (lat > -10 && lng > -30 && lng < 50) return 'Europe';
    if (lng > 60 && lng < 160) return 'Asia';
    if (lat < -10) return 'Australia';
    return 'Other';
  }

  routeRequest(userLocationLatLng: [number, number]): string {
    return this.loadBalancer.selectRegion(userLocationLatLng);
  }

  recordRequestMetrics(selectedRegion: string, latency: number): void {
    this.loadBalancer.recordRequest(selectedRegion, latency);
  }

  recordReplication(sourceRegion: string, targetRegion: string, itemsSynced: number, latency: number): void {
    this.replicator.recordSync(sourceRegion, targetRegion, itemsSynced, latency);
  }

  executeFailover(failingRegion: string): boolean {
    const topology = this.registry.getTopology();
    const healthyRegions = topology.regions.filter(m => m.isHealthy && !m.isPrimary);

    if (healthyRegions.length === 0) return false;

    const newPrimary = healthyRegions[0];
    const success = this.registry.promoteToPrimary(newPrimary.regionId);

    if (success) {
      this.failoverHistory.push({
        timestamp: Date.now(),
        fromRegion: failingRegion,
        toRegion: newPrimary.regionId,
      });
    }

    return success;
  }

  getFederationStatus(): FederationStatus {
    const topology = this.registry.getTopology();
    const lbMetrics = this.loadBalancer.getMetrics();
    const consistencyLatency = this.replicator.getEventualConsistencyLatency(this.config.primaryRegion);

    // Simulate p50/p95/p99 latencies
    const globalLatencies = {
      p50: consistencyLatency * 0.5,
      p95: consistencyLatency * 0.95,
      p99: consistencyLatency,
    };

    const healthScore = (topology.healthyMembers / topology.totalMembers) * 100;

    return {
      timestamp: Date.now(),
      topology,
      globalLatency: globalLatencies,
      replicationLag: consistencyLatency,
      failoversPastDay: this.failoverHistory.filter(f => Date.now() - f.timestamp < 86400000).length,
      failoverCount: this.failoverHistory.length,
      systemHealthScore: healthScore,
    };
  }

  getConfiguration(): FederationConfig {
    return this.config;
  }
}

/**
 * Phase 12 Configuration & Export
 */
export const Phase12Examples = {
  federationConfig: {
    primaryRegion: 'us-east-1',
    secondaryRegions: ['eu-central-1', 'ap-southeast-1', 'us-west-2'],
    replicationStrategy: 'active-active' as const,
    eventualConsistencySLA: 200,
    globalAvailabilitySLA: 99.99,
  },

  regionConfig: [
    { name: 'US East', regionId: 'us-east-1', isPrimary: true },
    { name: 'EU Central', regionId: 'eu-central-1', isPrimary: false },
    { name: 'APAC Singapore', regionId: 'ap-southeast-1', isPrimary: false },
    { name: 'US West', regionId: 'us-west-2', isPrimary: false },
  ],

  slaTargets: {
    globalAvailability: 99.99,
    maxGlobalLatency: 200, // milliseconds for eventual consistency
    maxReplicationLag: 100,
  },
};
