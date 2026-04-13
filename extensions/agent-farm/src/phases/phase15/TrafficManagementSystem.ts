/**
 * Phase 15: Traffic Management System
 * Intelligent routing with failure isolation
 */

export interface TrafficRule {
  priority: number;
  condition: string;
  action: 'route-to-canary' | 'route-to-production' | 'route-to-fallback';
  percentage?: number;
}

export interface CircuitState {
  state: 'closed' | 'open' | 'half-open';
  failureCount: number;
  successCount: number;
  lastStateChange: Date;
  nextRetryTime?: Date;
}

export interface DeploymentTarget {
  id: string;
  version: string;
  address: string;
  port: number;
  weight: number;
  health: 'healthy' | 'degraded' | 'critical';
}

export interface TrafficMetrics {
  requestsRoutedPerSecond: number;
  errorRate: number;
  averageLatency: number;
  p99Latency: number;
  connectedClients: number;
  bytesIn: number;
  bytesOut: number;
}

export interface LoadBalancingResult {
  targetAllocations: Map<string, number>;
  loadBalancingStrategy: string;
  totalThroughput: number;
}

export interface DrainResult {
  success: boolean;
  connectionsRemaining: number;
  drainDuration: number;
}

export interface TrafficReport {
  period: { start: Date; end: Date };
  totalRequests: number;
  totalErrors: number;
  averageLatency: number;
  peakThroughput: number;
  targetMetrics: Map<string, TrafficMetrics>;
  observations: string[];
}

export interface TimeWindow {
  start: Date;
  end: Date;
}

export class TrafficManagementSystem {
  private trafficRules: TrafficRule[] = [];
  private circuitBreakers: Map<string, CircuitState> = new Map();
  private targetWeights: Map<string, number> = new Map();
  private metricsHistory: Map<string, TrafficMetrics[]> = new Map();

  async updateTrafficRules(rules: TrafficRule[]): Promise<void> {
    this.trafficRules = rules.sort((a, b) => b.priority - a.priority);
  }

  async getActiveTrafficRules(): Promise<TrafficRule[]> {
    return [...this.trafficRules];
  }

  async balanceTraffic(
    targets: DeploymentTarget[],
    metrics: any
  ): Promise<LoadBalancingResult> {
    const allocations = new Map<string, number>();
    const totalWeight = targets.reduce((sum, t) => sum + t.weight, 0);

    targets.forEach(target => {
      const percentage = totalWeight > 0 ? (target.weight / totalWeight) * 100 : 0;
      allocations.set(target.id, percentage);
    });

    const totalThroughput = metrics.throughput || 5000;

    return {
      targetAllocations: allocations,
      loadBalancingStrategy: 'weighted-round-robin',
      totalThroughput,
    };
  }

  async updateLoadBalancingWeights(
    targets: DeploymentTarget[],
    weights: Map<string, number>
  ): Promise<void> {
    weights.forEach((weight, targetId) => {
      this.targetWeights.set(targetId, weight);
      const target = targets.find(t => t.id === targetId);
      if (target) {
        target.weight = weight;
      }
    });
  }

  async evaluateCircuitBreaker(target: DeploymentTarget): Promise<CircuitState> {
    let circuit = this.circuitBreakers.get(target.id);

    if (!circuit) {
      circuit = {
        state: 'closed',
        failureCount: 0,
        successCount: 0,
        lastStateChange: new Date(),
      };
      this.circuitBreakers.set(target.id, circuit);
    }

    // Update state based on health
    if (target.health === 'critical') {
      circuit.failureCount += 1;
      if (circuit.failureCount >= 5) {
        circuit.state = 'open';
        circuit.lastStateChange = new Date();
        circuit.nextRetryTime = new Date(Date.now() + 30000);
      }
    } else if (target.health === 'healthy') {
      circuit.successCount += 1;
      if (circuit.state === 'half-open' && circuit.successCount >= 3) {
        circuit.state = 'closed';
        circuit.failureCount = 0;
        circuit.lastStateChange = new Date();
      }
    }

    return circuit;
  }

  async openCircuitBreaker(target: DeploymentTarget, reason: string): Promise<void> {
    const circuit = this.circuitBreakers.get(target.id);
    if (circuit) {
      circuit.state = 'open';
      circuit.lastStateChange = new Date();
      circuit.nextRetryTime = new Date(Date.now() + 30000);
    }
  }

  async closeCircuitBreaker(target: DeploymentTarget): Promise<void> {
    const circuit = this.circuitBreakers.get(target.id);
    if (circuit) {
      circuit.state = 'closed';
      circuit.failureCount = 0;
      circuit.successCount = 0;
      circuit.lastStateChange = new Date();
    }
  }

  async drainConnections(target: DeploymentTarget): Promise<DrainResult> {
    const startTime = Date.now();
    let connectionsRemaining = target.weight * 200;  // Simulate connections
    const maxDrainTime = 30000;

    while (connectionsRemaining > 0 && (Date.now() - startTime) < maxDrainTime) {
      connectionsRemaining = Math.max(0, connectionsRemaining - 100);
      await new Promise(resolve => setTimeout(resolve, 500));
    }

    return {
      success: connectionsRemaining === 0,
      connectionsRemaining,
      drainDuration: (Date.now() - startTime) / 1000,
    };
  }

  async gracefulShutdown(target: DeploymentTarget): Promise<void> {
    // Drain connections first
    await this.drainConnections(target);
    // Then shut down
    target.health = 'critical';
  }

  getTrafficMetrics(target: DeploymentTarget): TrafficMetrics {
    const history = this.metricsHistory.get(target.id) || [];
    const latestMetrics = history[history.length - 1];

    if (latestMetrics) {
      return latestMetrics;
    }

    return {
      requestsRoutedPerSecond: Math.random() * 1000,
      errorRate: Math.random() * 1,
      averageLatency: 50 + Math.random() * 50,
      p99Latency: 85 + Math.random() * 30,
      connectedClients: Math.floor(Math.random() * 100),
      bytesIn: Math.floor(Math.random() * 1000000),
      bytesOut: Math.floor(Math.random() * 1000000),
    };
  }

  generateTrafficReport(timeWindow: TimeWindow): TrafficReport {
    let totalRequests = 0;
    let totalErrors = 0;
    let aggregateLatency = 0;
    let peakThroughput = 0;
    const targetMetrics = new Map<string, TrafficMetrics>();

    for (const [targetId, metrics] of this.metricsHistory) {
      const filtered = metrics.filter(
        m => m as any === undefined || ((m as any).timestamp as Date) >= timeWindow.start
      );

      if (filtered.length > 0) {
        const latest = filtered[filtered.length - 1];
        targetMetrics.set(targetId, latest);

        totalRequests += latest.requestsRoutedPerSecond * 3600;
        totalErrors += (latest.errorRate / 100) * totalRequests;
        aggregateLatency += latest.averageLatency;
        peakThroughput = Math.max(peakThroughput, latest.requestsRoutedPerSecond);
      }
    }

    const observations: string[] = [];
    if (peakThroughput > 9000) {
      observations.push('Peak throughput exceeded 9000 RPS');
    }
    if ((totalErrors / totalRequests) * 100 > 1) {
      observations.push('Error rate exceeded SLO');
    }

    return {
      period: timeWindow,
      totalRequests: Math.floor(totalRequests),
      totalErrors: Math.floor(totalErrors),
      averageLatency: aggregateLatency / Math.max(1, targetMetrics.size),
      peakThroughput,
      targetMetrics,
      observations,
    };
  }
}
