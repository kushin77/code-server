/**
 * Replication state for conflict resolution
 */
export interface ReplicationState {
    dataId: string;
    version: number;
    timestamp: Date;
    regionId: string;
    checksum: string;
    metadata?: Record<string, any>;
}
/**
 * Replication conflict
 */
export interface ReplicationConflict {
    dataId: string;
    conflictingStates: ReplicationState[];
    conflictTime: Date;
    resolvedState?: ReplicationState;
    resolutionStrategy: 'last-write-wins' | 'highest-version' | 'manual';
}
/**
 * Replication event
 */
export interface ReplicationEvent {
    eventId: string;
    dataId: string;
    eventType: 'CREATE' | 'UPDATE' | 'DELETE';
    sourceRegion: string;
    targetRegions: string[];
    timestamp: Date;
    status: 'pending' | 'replicating' | 'completed' | 'failed';
    error?: string;
}
/**
 * CrossRegionReplicator - Multi-region data replication with conflict resolution
 * Ensures data consistency across geographic boundaries
 */
export declare class CrossRegionReplicator {
    private replicationStates;
    private replicationEvents;
    private conflicts;
    private readonly maxReplicationLatency;
    private readonly conflictCheckInterval;
    private isRunning;
    /**
     * Initialize replication for a data object
     */
    initializeReplication(dataId: string, regionId: string, checksum: string): void;
    /**
     * Replicate data change to target regions
     */
    replicateChange(dataId: string, eventType: 'CREATE' | 'UPDATE' | 'DELETE', sourceRegion: string, targetRegions: string[], data: any): Promise<ReplicationEvent>;
    /**
     * Replicate data to a specific region
     */
    private replicateToRegion;
    /**
     * Calculate checksum for data
     */
    private calculateChecksum;
    /**
     * Detect replication conflicts
     */
    detectConflicts(dataId: string): ReplicationConflict | null;
    /**
     * Resolve replication conflict
     */
    resolveConflict(dataId: string, version: number, strategy: 'last-write-wins' | 'highest-version' | 'manual', selectedState?: ReplicationState): ReplicationState | null;
    /**
     * Get replication state for data
     */
    getReplicationState(dataId: string): ReplicationState[];
    /**
     * Get replication status
     */
    getReplicationStatus(dataId: string): {
        synced: boolean;
        version: number;
        regions: Record<string, number>;
        conflicts: number;
    };
    /**
     * Get replication lag for a region
     */
    getReplicationLag(dataId: string, regionId: string): number;
    /**
     * Get replication event history
     */
    getEventHistory(dataId?: string): ReplicationEvent[];
    /**
     * Get unresolved conflicts
     */
    getUnresolvedConflicts(): ReplicationConflict[];
    /**
     * Get replication statistics
     */
    getStats(): {
        totalDataIds: number;
        averageVersion: number;
        totalConflicts: number;
        unresolvedConflicts: number;
        totalReplicationEvents: number;
    };
}
//# sourceMappingURL=CrossRegionReplicator.d.ts.map