import { ServiceReplica } from './GeographicRegistry';
import { ReplicationEvent } from './CrossRegionReplicator';
import { RoutingDecision } from './GeoLoadBalancer';
/**
 * Federation configuration
 */
export interface FederationConfig {
    primaryRegion: string;
    enableAutoFailover: boolean;
    replicationMode: 'async' | 'sync';
    consistencyLevel: 'eventual' | 'strong';
    maxReplicationLatency: number;
}
/**
 * Federation status
 */
export interface FederationStatus {
    isOnline: boolean;
    regions: {
        regionId: string;
        status: 'primary' | 'secondary' | 'standby';
        replicaHealth: number;
    }[];
    globalServices: number;
    dataReplicationLag: Record<string, number>;
    conflictCount: number;
}
/**
 * MultiSiteFederationOrchestrator - Coordinates Agent Farm across geographic regions
 * Manages service discovery, replication, and intelligent routing
 */
export declare class MultiSiteFederationOrchestrator {
    private registry;
    private replicator;
    private loadBalancer;
    private config;
    private isRunning;
    private replicationQueue;
    constructor(config?: Partial<FederationConfig>);
    /**
     * Start federation system
     */
    start(): Promise<void>;
    /**
     * Register a service replica in a region
     */
    registerServiceReplica(serviceName: string, version: string, regionId: string, endpoint: string): boolean;
    /**
     * Route client request to optimal endpoint
     */
    routeRequest(serviceName: string, clientLatitude?: number, clientLongitude?: number, clientRegion?: string, preferredRegions?: string[]): RoutingDecision;
    /**
     * Replicate data change across regions
     */
    replicateDataChange(dataId: string, eventType: 'CREATE' | 'UPDATE' | 'DELETE', sourceRegion: string, data: any): Promise<ReplicationEvent>;
    /**
     * Detect and resolve replication conflicts
     */
    detectAndResolveConflicts(dataId: string): boolean;
    /**
     * Get route to nearest service replica
     */
    getNearestService(serviceName: string, clientLatitude: number, clientLongitude: number): ServiceReplica | null;
    /**
     * Start replication monitoring
     */
    private startReplicationMonitoring;
    /**
     * Get federation status
     */
    getFederationStatus(): FederationStatus;
    /**
     * Get load balancer statistics
     */
    getLoadBalancingStats(): any;
    /**
     * Get replication statistics
     */
    getReplicationStats(): any;
    /**
     * Calculate checksum for data
     */
    private calculateChecksum;
    /**
     * Shutdown federation
     */
    shutdown(): Promise<void>;
}
//# sourceMappingURL=MultiSiteFederationOrchestrator.d.ts.map
