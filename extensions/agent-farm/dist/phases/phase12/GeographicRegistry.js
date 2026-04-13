"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.GeographicRegistry = void 0;
/**
 * GeographicRegistry - Multi-region service discovery and registration
 * Manages service replicas across geographic boundaries
 */
class GeographicRegistry {
    constructor() {
        this.regions = new Map();
        this.services = new Map();
        this.healthCheckInterval = 30000; // 30 seconds
        this.isRunning = false;
        this.initializeDefaultRegions();
    }
    /**
     * Initialize default regions
     */
    initializeDefaultRegions() {
        // US East
        this.registerRegion({
            regionId: 'us-east-1',
            regionName: 'US East (N. Virginia)',
            latitude: 38.8003,
            longitude: -77.0469,
            primaryEndpoint: 'https://api-us-east-1.example.com',
            replicaEndpoints: [
                'https://replica-1-us-east-1.example.com',
                'https://replica-2-us-east-1.example.com',
            ],
            priority: 1,
            enabled: true,
        });
        // US West
        this.registerRegion({
            regionId: 'us-west-2',
            regionName: 'US West (Oregon)',
            latitude: 43.8041,
            longitude: -120.5542,
            primaryEndpoint: 'https://api-us-west-2.example.com',
            replicaEndpoints: [
                'https://replica-1-us-west-2.example.com',
                'https://replica-2-us-west-2.example.com',
            ],
            priority: 2,
            enabled: true,
        });
        // EU West
        this.registerRegion({
            regionId: 'eu-west-1',
            regionName: 'EU West (Ireland)',
            latitude: 53.3498,
            longitude: -6.2603,
            primaryEndpoint: 'https://api-eu-west-1.example.com',
            replicaEndpoints: [
                'https://replica-1-eu-west-1.example.com',
                'https://replica-2-eu-west-1.example.com',
            ],
            priority: 3,
            enabled: true,
        });
        // APAC
        this.registerRegion({
            regionId: 'ap-southeast-1',
            regionName: 'Asia Pacific (Singapore)',
            latitude: 1.3521,
            longitude: 103.8198,
            primaryEndpoint: 'https://api-ap-southeast-1.example.com',
            replicaEndpoints: [
                'https://replica-1-ap-southeast-1.example.com',
                'https://replica-2-ap-southeast-1.example.com',
            ],
            priority: 4,
            enabled: true,
        });
    }
    /**
     * Register a new region
     */
    registerRegion(config) {
        this.regions.set(config.regionId, config);
        console.info(`Registered region: ${config.regionName} (${config.regionId})`);
    }
    /**
     * Register a service replica
     */
    registerService(serviceName, version, regionId, endpoint, replicaId) {
        const region = this.regions.get(regionId);
        if (!region) {
            console.error(`Region not found: ${regionId}`);
            return false;
        }
        if (!this.services.has(serviceName)) {
            this.services.set(serviceName, {
                serviceName,
                version,
                replicas: new Map(),
                lastUpdated: new Date(),
            });
        }
        const service = this.services.get(serviceName);
        const id = replicaId || `${regionId}-${Date.now()}`;
        service.replicas.set(id, {
            replicaId: id,
            regionId,
            endpoint,
            status: 'healthy',
            latency: 0,
            lastHealthCheck: new Date(),
            datacenter: region.regionName,
        });
        service.lastUpdated = new Date();
        console.info(`Registered service: ${serviceName} in region ${regionId}`);
        return true;
    }
    /**
     * Discover services in a specific region
     */
    discoverInRegion(serviceName, regionId) {
        const service = this.services.get(serviceName);
        if (!service) {
            return [];
        }
        const replicas = Array.from(service.replicas.values()).filter((r) => r.regionId === regionId && r.status === 'healthy');
        return replicas.sort((a, b) => a.latency - b.latency);
    }
    /**
     * Discover services across all regions
     */
    discoverGlobal(serviceName) {
        const service = this.services.get(serviceName);
        if (!service) {
            return [];
        }
        return Array.from(service.replicas.values())
            .filter((r) => r.status === 'healthy')
            .sort((a, b) => {
            // Sort by region priority first, then latency
            const regionA = this.regions.get(a.regionId);
            const regionB = this.regions.get(b.regionId);
            if (!regionA || !regionB)
                return 0;
            if (regionA.priority !== regionB.priority) {
                return regionA.priority - regionB.priority;
            }
            return a.latency - b.latency;
        });
    }
    /**
     * Get nearest healthy replica to coordinates
     */
    getNearestReplica(serviceName, latitude, longitude) {
        const service = this.services.get(serviceName);
        if (!service) {
            return null;
        }
        const healthyReplicas = Array.from(service.replicas.values()).filter((r) => r.status === 'healthy');
        if (healthyReplicas.length === 0) {
            return null;
        }
        // Calculate distances using haversine formula
        let nearest = null;
        let minDistance = Infinity;
        healthyReplicas.forEach((replica) => {
            const region = this.regions.get(replica.regionId);
            if (!region)
                return;
            const distance = this.calculateDistance(latitude, longitude, region.latitude, region.longitude);
            if (distance < minDistance) {
                minDistance = distance;
                nearest = replica;
            }
        });
        return nearest;
    }
    /**
     * Calculate great-circle distance between two points (haversine)
     */
    calculateDistance(lat1, lon1, lat2, lon2) {
        const R = 6371; // Earth's radius in km
        const dLat = this.toRad(lat2 - lat1);
        const dLon = this.toRad(lon2 - lon1);
        const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(this.toRad(lat1)) *
                Math.cos(this.toRad(lat2)) *
                Math.sin(dLon / 2) *
                Math.sin(dLon / 2);
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return R * c;
    }
    /**
     * Convert degrees to radians
     */
    toRad(degrees) {
        return (degrees * Math.PI) / 180;
    }
    /**
     * Update replica health status
     */
    updateReplicaHealth(serviceName, replicaId, status, latency) {
        const service = this.services.get(serviceName);
        if (!service) {
            return false;
        }
        const replica = service.replicas.get(replicaId);
        if (!replica) {
            return false;
        }
        replica.status = status;
        replica.latency = latency;
        replica.lastHealthCheck = new Date();
        return true;
    }
    /**
     * Get all regions
     */
    getAllRegions() {
        return Array.from(this.regions.values())
            .filter((r) => r.enabled)
            .sort((a, b) => a.priority - b.priority);
    }
    /**
     * Get all services
     */
    getAllServices() {
        return Array.from(this.services.values());
    }
    /**
     * Get service topology
     */
    getServiceTopology(serviceName) {
        const service = this.services.get(serviceName);
        if (!service) {
            return {};
        }
        const topology = {};
        service.replicas.forEach((replica) => {
            if (!topology[replica.regionId]) {
                topology[replica.regionId] = [];
            }
            topology[replica.regionId].push(replica);
        });
        return topology;
    }
    /**
     * Get registry statistics
     */
    getStats() {
        let totalReplicas = 0;
        let healthyReplicas = 0;
        this.services.forEach((service) => {
            service.replicas.forEach((replica) => {
                totalReplicas++;
                if (replica.status === 'healthy') {
                    healthyReplicas++;
                }
            });
        });
        return {
            totalRegions: this.regions.size,
            totalServices: this.services.size,
            totalReplicas,
            healthyReplicas,
        };
    }
}
exports.GeographicRegistry = GeographicRegistry;
//# sourceMappingURL=GeographicRegistry.js.map