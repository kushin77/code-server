/**
 * Geographic routing request
 */
export interface GeoRoutingRequest {
  serviceName: string;
  clientLatitude?: number;
  clientLongitude?: number;
  clientRegion?: string;
  preferredRegions?: string[];
  minimumLatency?: number;  // ms
  maximumLatency?: number;  // ms
  metadata?: Record<string, any>;
}

/**
 * Geographic routing decision
 */
export interface RoutingDecision {
  requestId: string;
  serviceName: string;
  selectedEndpoint: string;
  selectedRegion: string;
  routingStrategy: string;
  estimatedLatency: number;
  alternatives: string[];
  timestamp: Date;
}

/**
 * Load balancing strategy
 */
export interface LoadBalancingStrategy {
  name: string;
  weight: number;  // 0-1
  decide: (
    serviceName: string,
    request: GeoRoutingRequest,
    replicas: any[]
  ) => string | null;
}

/**
 * GeoLoadBalancer - Intelligent cross-region routing
 * Routes requests to optimal endpoints based on geography and performance
 */
export class GeoLoadBalancer {
  private strategies: LoadBalancingStrategy[] = [];
  private routingHistory: RoutingDecision[] = [];
  private performanceMetrics: Map<string, number[]> = new Map();
  private readonly maxHistorySize: number = 10000;
  private roundRobinCounters: Map<string, number> = new Map();

  constructor() {
    this.registerDefaultStrategies();
  }

  /**
   * Register default routing strategies
   */
  private registerDefaultStrategies(): void {
    // Strategy 1: Geographic proximity (60% weight)
    this.registerStrategy({
      name: 'geographic-proximity',
      weight: 0.6,
      decide: (serviceName: string, request: GeoRoutingRequest, replicas: any[]) => {
        if (request.clientRegion) {
          const regionReplicas = replicas.filter(
            (r) => r.regionId === request.clientRegion
          );

          if (regionReplicas.length > 0) {
            return regionReplicas[0].endpoint;
          }
        }

        return null;
      },
    });

    // Strategy 2: Latency-based routing (25% weight)
    this.registerStrategy({
      name: 'latency-based',
      weight: 0.25,
      decide: (serviceName: string, request: GeoRoutingRequest, replicas: any[]) => {
        const sortedByLatency = [...replicas].sort((a, b) => a.latency - b.latency);

        const validReplica = sortedByLatency.find((r) => {
          if (request.minimumLatency && r.latency < request.minimumLatency) {
            return false;
          }
          if (request.maximumLatency && r.latency > request.maximumLatency) {
            return false;
          }
          return true;
        });

        return validReplica?.endpoint || null;
      },
    });

    // Strategy 3: Load balancing (15% weight)
    this.registerStrategy({
      name: 'round-robin',
      weight: 0.15,
      decide: (serviceName: string, request: GeoRoutingRequest, replicas: any[]) => {
        if (replicas.length === 0) {
          return null;
        }

        const counter = this.roundRobinCounters.get(serviceName) || 0;
        const selected = replicas[counter % replicas.length];
        this.roundRobinCounters.set(serviceName, counter + 1);

        return selected.endpoint;
      },
    });
  }

  /**
   * Register custom routing strategy
   */
  registerStrategy(strategy: LoadBalancingStrategy): void {
    this.strategies.push(strategy);
    // Normalize weights
    const totalWeight = this.strategies.reduce((sum, s) => sum + s.weight, 0);
    this.strategies.forEach((s) => {
      s.weight = s.weight / totalWeight;
    });

    console.info(`Registered routing strategy: ${strategy.name}`);
  }

  /**
   * Make routing decision for a request
   */
  makeRoutingDecision(
    request: GeoRoutingRequest,
    availableReplicas: any[]
  ): RoutingDecision {
    const requestId = `route-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;

    if (availableReplicas.length === 0) {
      throw new Error(`No available replicas for service: ${request.serviceName}`);
    }

    // Apply strategies in weighted order
    let selectedEndpoint: string | null = null;
    let selectedRegion = 'unknown';
    let routingStrategy = 'default';
    let estimatedLatency = 0;

    for (const strategy of this.strategies) {
      if (Math.random() < strategy.weight) {
        const endpoint = strategy.decide(
          request.serviceName,
          request,
          availableReplicas
        );

        if (endpoint) {
          selectedEndpoint = endpoint;
          routingStrategy = strategy.name;

          // Find region for selected endpoint
          const replica = availableReplicas.find((r) => r.endpoint === endpoint);
          if (replica) {
            selectedRegion = replica.regionId;
            estimatedLatency = replica.latency;
          }

          break;
        }
      }
    }

    // Fallback to first available replica
    if (!selectedEndpoint) {
      selectedEndpoint = availableReplicas[0].endpoint;
      selectedRegion = availableReplicas[0].regionId;
      estimatedLatency = availableReplicas[0].latency;
      routingStrategy = 'fallback';
    }

    const decision: RoutingDecision = {
      requestId,
      serviceName: request.serviceName,
      selectedEndpoint: selectedEndpoint as string,
      selectedRegion,
      routingStrategy,
      estimatedLatency,
      alternatives: availableReplicas
        .filter((r) => r.endpoint !== selectedEndpoint)
        .map((r) => r.endpoint)
        .slice(0, 3),
      timestamp: new Date(),
    };

    this.routingHistory.push(decision);
    if (this.routingHistory.length > this.maxHistorySize) {
      this.routingHistory = this.routingHistory.slice(-this.maxHistorySize);
    }

    return decision;
  }

  /**
   * Update performance metrics for endpoint
   */
  updatePerformanceMetrics(endpoint: string, latency: number, success: boolean): void {
    if (!this.performanceMetrics.has(endpoint)) {
      this.performanceMetrics.set(endpoint, []);
    }

    const metrics = this.performanceMetrics.get(endpoint)!;
    metrics.push(latency);

    // Keep only last 100 measurements
    if (metrics.length > 100) {
      metrics.shift();
    }
  }

  /**
   * Get endpoint statistics
   */
  getEndpointStats(endpoint: string): {
    avgLatency: number;
    minLatency: number;
    maxLatency: number;
    measurements: number;
  } {
    const metrics = this.performanceMetrics.get(endpoint) || [];

    if (metrics.length === 0) {
      return {
        avgLatency: 0,
        minLatency: 0,
        maxLatency: 0,
        measurements: 0,
      };
    }

    const avgLatency = metrics.reduce((a, b) => a + b, 0) / metrics.length;
    const minLatency = Math.min(...metrics);
    const maxLatency = Math.max(...metrics);

    return {
      avgLatency,
      minLatency,
      maxLatency,
      measurements: metrics.length,
    };
  }

  /**
   * Get routing statistics
   */
  getRoutingStats(): {
    totalRequests: number;
    strategyDistribution: Record<string, number>;
    averageLatency: number;
    regionDistribution: Record<string, number>;
  } {
    const strategyDistribution: Record<string, number> = {};
    const regionDistribution: Record<string, number> = {};
    let totalLatency = 0;

    this.routingHistory.forEach((decision) => {
      strategyDistribution[decision.routingStrategy] =
        (strategyDistribution[decision.routingStrategy] || 0) + 1;

      regionDistribution[decision.selectedRegion] =
        (regionDistribution[decision.selectedRegion] || 0) + 1;

      totalLatency += decision.estimatedLatency;
    });

    return {
      totalRequests: this.routingHistory.length,
      strategyDistribution,
      averageLatency:
        this.routingHistory.length > 0
          ? totalLatency / this.routingHistory.length
          : 0,
      regionDistribution,
    };
  }

  /**
   * Get recent routing decisions
   */
  getRoutingHistory(limit: number = 100): RoutingDecision[] {
    return this.routingHistory.slice(-limit);
  }

  /**
   * Analyze routing patterns
   */
  analyzeRoutingPatterns(): {
    primaryStrategy: string;
    primaryRegion: string;
    outliers: RoutingDecision[];
  } {
    if (this.routingHistory.length === 0) {
      return {
        primaryStrategy: 'none',
        primaryRegion: 'unknown',
        outliers: [],
      };
    }

    // Find primary strategy
    const strategyCount: Record<string, number> = {};
    this.routingHistory.forEach((decision) => {
      strategyCount[decision.routingStrategy] =
        (strategyCount[decision.routingStrategy] || 0) + 1;
    });

    const primaryStrategy = Object.entries(strategyCount).reduce((a, b) =>
      b[1] > a[1] ? b : a
    )[0];

    // Find primary region
    const regionCount: Record<string, number> = {};
    this.routingHistory.forEach((decision) => {
      regionCount[decision.selectedRegion] =
        (regionCount[decision.selectedRegion] || 0) + 1;
    });

    const primaryRegion = Object.entries(regionCount).reduce((a, b) =>
      b[1] > a[1] ? b : a
    )[0];

    // Identify latency outliers
    const avgLatency =
      this.routingHistory.reduce((sum, d) => sum + d.estimatedLatency, 0) /
      this.routingHistory.length;

    const stdDev = Math.sqrt(
      this.routingHistory.reduce(
        (sum, d) => sum + Math.pow(d.estimatedLatency - avgLatency, 2),
        0
      ) / this.routingHistory.length
    );

    const outliers = this.routingHistory.filter(
      (d) => Math.abs(d.estimatedLatency - avgLatency) > 2 * stdDev
    );

    return {
      primaryStrategy,
      primaryRegion,
      outliers: outliers.slice(-10),
    };
  }
}
