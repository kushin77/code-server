"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CrossRegionReplicator = void 0;
/**
 * CrossRegionReplicator - Multi-region data replication with conflict resolution
 * Ensures data consistency across geographic boundaries
 */
class CrossRegionReplicator {
    constructor() {
        this.replicationStates = new Map();
        this.replicationEvents = [];
        this.conflicts = new Map();
        this.maxReplicationLatency = 60000; // 60 seconds
        this.conflictCheckInterval = 5000; // 5 seconds
        this.isRunning = false;
    }
    /**
     * Initialize replication for a data object
     */
    initializeReplication(dataId, regionId, checksum) {
        const state = {
            dataId,
            version: 1,
            timestamp: new Date(),
            regionId,
            checksum,
        };
        if (!this.replicationStates.has(dataId)) {
            this.replicationStates.set(dataId, []);
        }
        this.replicationStates.get(dataId).push(state);
        console.info(`Initialized replication for data: ${dataId} in region: ${regionId}`);
    }
    /**
     * Replicate data change to target regions
     */
    async replicateChange(dataId, eventType, sourceRegion, targetRegions, data) {
        const eventId = `repl-${dataId}-${Date.now()}`;
        const event = {
            eventId,
            dataId,
            eventType,
            sourceRegion,
            targetRegions,
            timestamp: new Date(),
            status: 'pending',
        };
        this.replicationEvents.push(event);
        try {
            event.status = 'replicating';
            // Simulate replication to target regions
            const replicationPromises = targetRegions.map((targetRegion) => this.replicateToRegion(dataId, eventType, sourceRegion, targetRegion, data));
            await Promise.allSettled(replicationPromises);
            event.status = 'completed';
            console.info(`Replication completed for ${dataId} to ${targetRegions.length} regions`);
        }
        catch (error) {
            event.status = 'failed';
            event.error = error.message;
            console.error(`Replication failed for ${dataId}:`, error);
        }
        return event;
    }
    /**
     * Replicate data to a specific region
     */
    async replicateToRegion(dataId, eventType, sourceRegion, targetRegion, data) {
        // Simulate network latency
        const latency = Math.random() * this.maxReplicationLatency;
        await new Promise((resolve) => setTimeout(resolve, latency));
        // Simulate occasional replication delays
        if (Math.random() > 0.95) {
            throw new Error(`Replication timeout to ${targetRegion}`);
        }
        // Update replication state
        const states = this.replicationStates.get(dataId) || [];
        const latestState = states[states.length - 1];
        if (latestState) {
            const newState = {
                dataId,
                version: latestState.version + 1,
                timestamp: new Date(),
                regionId: targetRegion,
                checksum: this.calculateChecksum(data),
            };
            states.push(newState);
            this.replicationStates.set(dataId, states);
            console.info(`Replicated ${dataId} (v${newState.version}) to region ${targetRegion}`);
        }
    }
    /**
     * Calculate checksum for data
     */
    calculateChecksum(data) {
        const str = JSON.stringify(data);
        let hash = 0;
        for (let i = 0; i < str.length; i++) {
            const char = str.charCodeAt(i);
            hash = (hash << 5) - hash + char;
            hash = hash & hash; // Convert to 32bit integer
        }
        return Math.abs(hash).toString(16);
    }
    /**
     * Detect replication conflicts
     */
    detectConflicts(dataId) {
        const states = this.replicationStates.get(dataId);
        if (!states || states.length <= 1) {
            return null;
        }
        // Check for conflicting versions (same version, different checksums)
        const versionMap = new Map();
        states.forEach((state) => {
            if (!versionMap.has(state.version)) {
                versionMap.set(state.version, []);
            }
            versionMap.get(state.version).push(state);
        });
        // Find conflicting versions
        for (const [version, statesForVersion] of versionMap) {
            const checksums = new Set(statesForVersion.map((s) => s.checksum));
            if (checksums.size > 1) {
                // Conflict detected
                const conflict = {
                    dataId,
                    conflictingStates: statesForVersion,
                    conflictTime: new Date(),
                    resolutionStrategy: 'last-write-wins',
                };
                this.conflicts.set(`${dataId}-v${version}`, conflict);
                console.warn(`Conflict detected for ${dataId} version ${version}`);
                return conflict;
            }
        }
        return null;
    }
    /**
     * Resolve replication conflict
     */
    resolveConflict(dataId, version, strategy, selectedState) {
        const conflictKey = `${dataId}-v${version}`;
        const conflict = this.conflicts.get(conflictKey);
        if (!conflict) {
            return null;
        }
        let resolvedState;
        switch (strategy) {
            case 'last-write-wins':
                resolvedState = conflict.conflictingStates.reduce((latest, current) => current.timestamp > latest.timestamp ? current : latest);
                break;
            case 'highest-version':
                resolvedState = conflict.conflictingStates[conflict.conflictingStates.length - 1];
                break;
            case 'manual':
                if (!selectedState) {
                    throw new Error('Manual resolution requires selectedState');
                }
                resolvedState = selectedState;
                break;
            default:
                return null;
        }
        conflict.resolvedState = resolvedState;
        conflict.resolutionStrategy = strategy;
        console.info(`Conflict resolved for ${dataId}v${version} using strategy: ${strategy}`);
        return resolvedState;
    }
    /**
     * Get replication state for data
     */
    getReplicationState(dataId) {
        return this.replicationStates.get(dataId) || [];
    }
    /**
     * Get replication status
     */
    getReplicationStatus(dataId) {
        const states = this.replicationStates.get(dataId) || [];
        if (states.length === 0) {
            return {
                synced: false,
                version: 0,
                regions: {},
                conflicts: 0,
            };
        }
        const latestVersion = Math.max(...states.map((s) => s.version));
        const regions = {};
        states.forEach((state) => {
            regions[state.regionId] = state.version;
        });
        const isSynced = Object.values(regions).every((v) => v === latestVersion);
        return {
            synced: isSynced,
            version: latestVersion,
            regions,
            conflicts: Array.from(this.conflicts.values()).filter((c) => c.dataId === dataId).length,
        };
    }
    /**
     * Get replication lag for a region
     */
    getReplicationLag(dataId, regionId) {
        const states = this.replicationStates.get(dataId) || [];
        if (states.length === 0) {
            return Infinity;
        }
        const latestState = states[states.length - 1];
        const regionState = states.find((s) => s.regionId === regionId);
        if (!regionState) {
            return Infinity;
        }
        return latestState.timestamp.getTime() - regionState.timestamp.getTime();
    }
    /**
     * Get replication event history
     */
    getEventHistory(dataId) {
        if (dataId) {
            return this.replicationEvents.filter((e) => e.dataId === dataId);
        }
        return this.replicationEvents;
    }
    /**
     * Get unresolved conflicts
     */
    getUnresolvedConflicts() {
        return Array.from(this.conflicts.values()).filter((c) => !c.resolvedState);
    }
    /**
     * Get replication statistics
     */
    getStats() {
        let totalVersion = 0;
        let count = 0;
        this.replicationStates.forEach((states) => {
            if (states.length > 0) {
                totalVersion += states[states.length - 1].version;
                count++;
            }
        });
        const unresolvedConflicts = Array.from(this.conflicts.values()).filter((c) => !c.resolvedState).length;
        return {
            totalDataIds: this.replicationStates.size,
            averageVersion: count > 0 ? totalVersion / count : 0,
            totalConflicts: this.conflicts.size,
            unresolvedConflicts,
            totalReplicationEvents: this.replicationEvents.length,
        };
    }
}
exports.CrossRegionReplicator = CrossRegionReplicator;
//# sourceMappingURL=CrossRegionReplicator.js.map