"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MultiSiteFederationOrchestrator = void 0;
const GeographicRegistry_1 = require("./GeographicRegistry");
const CrossRegionReplicator_1 = require("./CrossRegionReplicator");
const GeoLoadBalancer_1 = require("./GeoLoadBalancer");
/**
 * MultiSiteFederationOrchestrator - Coordinates Agent Farm across geographic regions
 * Manages service discovery, replication, and intelligent routing
 */
class MultiSiteFederationOrchestrator {
    constructor(config = {}) {
        this.isRunning = false;
        this.replicationQueue = new Map();
        this.config = {
            primaryRegion: 'us-east-1',
            enableAutoFailover: true,
            replicationMode: 'async',
            consistencyLevel: 'eventual',
            maxReplicationLatency: 60000,
            ...config,
        };
        this.registry = new GeographicRegistry_1.GeographicRegistry();
        this.replicator = new CrossRegionReplicator_1.CrossRegionReplicator();
        this.loadBalancer = new GeoLoadBalancer_1.GeoLoadBalancer();
        console.info('MultiSiteFederationOrchestrator initialized');
    }
    /**
     * Start federation system
     */
    async start() {
        if (this.isRunning) {
            console.warn('Federation already running');
            return;
        }
        this.isRunning = true;
        console.info('Starting MultiSiteFederationOrchestrator...');
        try {
            // Verify all regions are accessible
            const regions = this.registry.getAllRegions();
            for (const region of regions) {
                console.info(`Verifying region: ${region.regionName} (${region.regionId})`);
            }
            // Start replication monitoring
            this.startReplicationMonitoring();
            console.info('✓ MultiSiteFederationOrchestrator started successfully');
        }
        catch (error) {
            console.error('Failed to start federation:', error);
            this.isRunning = false;
            throw error;
        }
    }
    /**
     * Register a service replica in a region
     */
    registerServiceReplica(serviceName, version, regionId, endpoint) {
        const success = this.registry.registerService(serviceName, version, regionId, endpoint);
        if (success) {
            // Initialize replication state
            this.replicator.initializeReplication(`${serviceName}-v${version}`, regionId, this.calculateChecksum(serviceName));
        }
        return success;
    }
    /**
     * Route client request to optimal endpoint
     */
    routeRequest(serviceName, clientLatitude, clientLongitude, clientRegion, preferredRegions) {
        // Discover healthy replicas
        const replicas = this.registry.discoverGlobal(serviceName);
        if (replicas.length === 0) {
            throw new Error(`No healthy replicas for service: ${serviceName}`);
        }
        // Create routing request
        const request = {
            serviceName,
            clientLatitude,
            clientLongitude,
            clientRegion,
            preferredRegions,
        };
        // Make routing decision
        const decision = this.loadBalancer.makeRoutingDecision(request, replicas);
        console.info(`Routed ${serviceName} to ${decision.selectedRegion} (${decision.routingStrategy})`);
        return decision;
    }
    /**
     * Replicate data change across regions
     */
    async replicateDataChange(dataId, eventType, sourceRegion, data) {
        // Determine target regions (all except source)
        const allRegions = this.registry
            .getAllRegions()
            .map((r) => r.regionId)
            .filter((r) => r !== sourceRegion);
        // Trigger replication
        const event = await this.replicator.replicateChange(dataId, eventType, sourceRegion, allRegions, data);
        this.replicationQueue.set(event.eventId, event);
        // Check consistency
        if (this.config.consistencyLevel === 'strong' && this.config.replicationMode === 'sync') {
            const status = this.replicator.getReplicationStatus(dataId);
            while (!status.synced && this.isRunning) {
                await new Promise((resolve) => setTimeout(resolve, 100));
            }
        }
        return event;
    }
    /**
     * Detect and resolve replication conflicts
     */
    detectAndResolveConflicts(dataId) {
        const conflict = this.replicator.detectConflicts(dataId);
        if (!conflict) {
            return false;
        }
        // Auto-resolve using configured strategy
        const strategy = this.config.consistencyLevel === 'strong'
            ? 'highest-version'
            : 'last-write-wins';
        const resolved = this.replicator.resolveConflict(dataId, conflict.conflictingStates[0].version, strategy);
        if (resolved) {
            console.info(`Conflict auto-resolved for ${dataId} using ${strategy}`);
            return true;
        }
        return false;
    }
    /**
     * Get route to nearest service replica
     */
    getNearestService(serviceName, clientLatitude, clientLongitude) {
        return this.registry.getNearestReplica(serviceName, clientLatitude, clientLongitude);
    }
    /**
     * Start replication monitoring
     */
    startReplicationMonitoring() {
        const monitorInterval = setInterval(() => {
            if (!this.isRunning) {
                clearInterval(monitorInterval);
                return;
            }
            // Check for unresolved conflicts
            const conflicts = this.replicator.getUnresolvedConflicts();
            if (conflicts.length > 0) {
                console.warn(`${conflicts.length} unresolved replication conflicts detected`);
                // Auto-resolve if configured
                conflicts.forEach((conflict) => {
                    this.replicator.resolveConflict(conflict.dataId, conflict.conflictingStates[0].version, 'last-write-wins');
                });
            }
            // Check replication lag
            const services = this.registry.getAllServices();
            services.forEach((service) => {
                service.replicas.forEach((replica) => {
                    const lag = this.replicator.getReplicationLag(service.serviceName, replica.regionId);
                    if (lag > this.config.maxReplicationLatency) {
                        console.warn(`High replication lag detected: ${service.serviceName} in ${replica.regionId} (${lag}ms)`);
                    }
                });
            });
        }, 10000); // Monitor every 10 seconds
    }
    /**
     * Get federation status
     */
    getFederationStatus() {
        const regions = this.registry.getAllRegions();
        const stats = this.registry.getStats();
        const replicationStats = this.replicator.getStats();
        const dataReplicationLag = {};
        const services = this.registry.getAllServices();
        services.forEach((service) => {
            const avgLag = Array.from(service.replicas.values())
                .reduce((sum, replica) => sum + this.replicator.getReplicationLag(service.serviceName, replica.regionId), 0)
                / service.replicas.size;
            dataReplicationLag[service.serviceName] = avgLag;
        });
        return {
            isOnline: this.isRunning,
            regions: regions.map((region) => ({
                regionId: region.regionId,
                status: region.regionId === this.config.primaryRegion
                    ? 'primary'
                    : 'secondary',
                replicaHealth: stats.healthyReplicas > 0
                    ? (stats.healthyReplicas / stats.totalReplicas) * 100
                    : 0,
            })),
            globalServices: stats.totalServices,
            dataReplicationLag,
            conflictCount: replicationStats.unresolvedConflicts,
        };
    }
    /**
     * Get load balancer statistics
     */
    getLoadBalancingStats() {
        return this.loadBalancer.getRoutingStats();
    }
    /**
     * Get replication statistics
     */
    getReplicationStats() {
        return this.replicator.getStats();
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
            hash = hash & hash;
        }
        return Math.abs(hash).toString(16);
    }
    /**
     * Shutdown federation
     */
    async shutdown() {
        console.info('Shutting down MultiSiteFederationOrchestrator...');
        this.isRunning = false;
        console.info('✓ Federation shutdown complete');
    }
}
exports.MultiSiteFederationOrchestrator = MultiSiteFederationOrchestrator;
//# sourceMappingURL=MultiSiteFederationOrchestrator.js.map