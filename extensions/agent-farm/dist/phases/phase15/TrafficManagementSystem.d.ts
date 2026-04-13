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
    period: {
        start: Date;
        end: Date;
    };
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
export declare class TrafficManagementSystem {
    private trafficRules;
    private circuitBreakers;
    private targetWeights;
    private metricsHistory;
    updateTrafficRules(rules: TrafficRule[]): Promise<void>;
    getActiveTrafficRules(): Promise<TrafficRule[]>;
    balanceTraffic(targets: DeploymentTarget[], metrics: any): Promise<LoadBalancingResult>;
    updateLoadBalancingWeights(targets: DeploymentTarget[], weights: Map<string, number>): Promise<void>;
    evaluateCircuitBreaker(target: DeploymentTarget): Promise<CircuitState>;
    openCircuitBreaker(target: DeploymentTarget, reason: string): Promise<void>;
    closeCircuitBreaker(target: DeploymentTarget): Promise<void>;
    drainConnections(target: DeploymentTarget): Promise<DrainResult>;
    gracefulShutdown(target: DeploymentTarget): Promise<void>;
    getTrafficMetrics(target: DeploymentTarget): TrafficMetrics;
    generateTrafficReport(timeWindow: TimeWindow): TrafficReport;
}
//# sourceMappingURL=TrafficManagementSystem.d.ts.map
