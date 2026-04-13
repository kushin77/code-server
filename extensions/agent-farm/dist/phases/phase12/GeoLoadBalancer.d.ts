/**
 * Geographic routing request
 */
export interface GeoRoutingRequest {
    serviceName: string;
    clientLatitude?: number;
    clientLongitude?: number;
    clientRegion?: string;
    preferredRegions?: string[];
    minimumLatency?: number;
    maximumLatency?: number;
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
    weight: number;
    decide: (serviceName: string, request: GeoRoutingRequest, replicas: any[]) => string | null;
}
/**
 * GeoLoadBalancer - Intelligent cross-region routing
 * Routes requests to optimal endpoints based on geography and performance
 */
export declare class GeoLoadBalancer {
    private strategies;
    private routingHistory;
    private performanceMetrics;
    private readonly maxHistorySize;
    private roundRobinCounters;
    constructor();
    /**
     * Register default routing strategies
     */
    private registerDefaultStrategies;
    /**
     * Register custom routing strategy
     */
    registerStrategy(strategy: LoadBalancingStrategy): void;
    /**
     * Make routing decision for a request
     */
    makeRoutingDecision(request: GeoRoutingRequest, availableReplicas: any[]): RoutingDecision;
    /**
     * Update performance metrics for endpoint
     */
    updatePerformanceMetrics(endpoint: string, latency: number, success: boolean): void;
    /**
     * Get endpoint statistics
     */
    getEndpointStats(endpoint: string): {
        avgLatency: number;
        minLatency: number;
        maxLatency: number;
        measurements: number;
    };
    /**
     * Get routing statistics
     */
    getRoutingStats(): {
        totalRequests: number;
        strategyDistribution: Record<string, number>;
        averageLatency: number;
        regionDistribution: Record<string, number>;
    };
    /**
     * Get recent routing decisions
     */
    getRoutingHistory(limit?: number): RoutingDecision[];
    /**
     * Analyze routing patterns
     */
    analyzeRoutingPatterns(): {
        primaryStrategy: string;
        primaryRegion: string;
        outliers: RoutingDecision[];
    };
}
//# sourceMappingURL=GeoLoadBalancer.d.ts.map