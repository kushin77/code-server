/**
 * Geographic region configuration
 */
export interface RegionConfig {
    regionId: string;
    regionName: string;
    latitude: number;
    longitude: number;
    primaryEndpoint: string;
    replicaEndpoints: string[];
    priority: number;
    enabled: boolean;
}
/**
 * Service replica information
 */
export interface ServiceReplica {
    replicaId: string;
    regionId: string;
    endpoint: string;
    status: 'healthy' | 'degraded' | 'unhealthy' | 'offline';
    latency: number;
    lastHealthCheck: Date;
    datacenter?: string;
    rack?: string;
}
/**
 * Service registration entry
 */
export interface ServiceEntry {
    serviceName: string;
    version: string;
    replicas: Map<string, ServiceReplica>;
    lastUpdated: Date;
    metadata?: Record<string, any>;
}
/**
 * GeographicRegistry - Multi-region service discovery and registration
 * Manages service replicas across geographic boundaries
 */
export declare class GeographicRegistry {
    private regions;
    private services;
    private healthCheckInterval;
    private isRunning;
    constructor();
    /**
     * Initialize default regions
     */
    private initializeDefaultRegions;
    /**
     * Register a new region
     */
    registerRegion(config: RegionConfig): void;
    /**
     * Register a service replica
     */
    registerService(serviceName: string, version: string, regionId: string, endpoint: string, replicaId?: string): boolean;
    /**
     * Discover services in a specific region
     */
    discoverInRegion(serviceName: string, regionId: string): ServiceReplica[];
    /**
     * Discover services across all regions
     */
    discoverGlobal(serviceName: string): ServiceReplica[];
    /**
     * Get nearest healthy replica to coordinates
     */
    getNearestReplica(serviceName: string, latitude: number, longitude: number): ServiceReplica | null;
    /**
     * Calculate great-circle distance between two points (haversine)
     */
    private calculateDistance;
    /**
     * Convert degrees to radians
     */
    private toRad;
    /**
     * Update replica health status
     */
    updateReplicaHealth(serviceName: string, replicaId: string, status: 'healthy' | 'degraded' | 'unhealthy' | 'offline', latency: number): boolean;
    /**
     * Get all regions
     */
    getAllRegions(): RegionConfig[];
    /**
     * Get all services
     */
    getAllServices(): ServiceEntry[];
    /**
     * Get service topology
     */
    getServiceTopology(serviceName: string): Record<string, ServiceReplica[]>;
    /**
     * Get registry statistics
     */
    getStats(): {
        totalRegions: number;
        totalServices: number;
        totalReplicas: number;
        healthyReplicas: number;
    };
}
//# sourceMappingURL=GeographicRegistry.d.ts.map