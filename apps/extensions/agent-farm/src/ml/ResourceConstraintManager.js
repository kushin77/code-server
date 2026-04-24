/**
 * Resource Constraint Manager
 * Manages limited CPU, memory, and network resources on edge nodes
 */
export class ResourceConstraintManager {
    constructor() {
        this.quotas = new Map();
        this.usage = new Map();
        this.allocations = new Map();
        this.workloadPriorities = new Map();
        this.usageHistory = new Map();
        this.maxHistoryLength = 1000;
    }
    /**
     * Register resource quota for node
     */
    registerQuota(quota) {
        this.quotas.set(quota.nodeId, quota);
        this.usage.set(quota.nodeId, {
            nodeId: quota.nodeId,
            cpuUsed: 0,
            memoryUsed: 0,
            storageUsed: 0,
            networkUsed: 0,
            activeTransactions: 0,
            timestamp: Date.now(),
        });
        this.usageHistory.set(quota.nodeId, []);
    }
    /**
     * Register workload priority
     */
    registerWorkload(priority) {
        this.workloadPriorities.set(priority.workloadId, priority);
    }
    /**
     * Try to allocate resources
     */
    allocateResources(workloadId, nodeId) {
        const quota = this.quotas.get(nodeId);
        const usage = this.usage.get(nodeId);
        const workload = this.workloadPriorities.get(workloadId);
        if (!quota || !usage || !workload)
            return undefined;
        const canAllocate = this.canAllocateWorkload(quota, usage, workload);
        if (!canAllocate) {
            return undefined;
        }
        // Perform allocation
        const allocation = {
            workloadId,
            nodeId,
            cpuAllocated: workload.estimatedCpu,
            memoryAllocated: workload.estimatedMemory,
            storageAllocated: workload.estimatedStorage,
            networkAllocated: workload.estimatedNetworkUsage,
            allocatedAt: Date.now(),
            status: 'allocated',
        };
        // Update usage
        usage.cpuUsed += workload.estimatedCpu;
        usage.memoryUsed += workload.estimatedMemory;
        usage.storageUsed += workload.estimatedStorage;
        usage.networkUsed += workload.estimatedNetworkUsage;
        usage.activeTransactions += 1;
        usage.timestamp = Date.now();
        this.allocations.set(`${workloadId}-${nodeId}`, allocation);
        return allocation;
    }
    canAllocateWorkload(quota, usage, workload) {
        const capacity = this.getCapacitySnapshot(quota, usage, workload);
        switch (workload.priority) {
            case 'critical':
                return this.canAllocateCritical(capacity);
            case 'high':
                return this.canAllocateHigh(capacity);
            case 'medium':
                return this.canAllocateMedium(capacity);
            case 'low':
            default:
                return this.canAllocateLow(capacity);
        }
    }
    getCapacitySnapshot(quota, usage, workload) {
        return {
            cpuAvailable: quota.cpuLimit - usage.cpuUsed >= workload.estimatedCpu,
            memoryAvailable: quota.memoryLimit - usage.memoryUsed >= workload.estimatedMemory,
            storageAvailable: quota.storageLimit - usage.storageUsed >= workload.estimatedStorage,
            networkAvailable: quota.networkLimit - usage.networkUsed >= workload.estimatedNetworkUsage,
            txnAvailable: quota.concurrentTransactions - usage.activeTransactions >= 1,
        };
    }
    canAllocateCritical(capacity) {
        return capacity.cpuAvailable || capacity.memoryAvailable;
    }
    canAllocateHigh(capacity) {
        return capacity.cpuAvailable && capacity.memoryAvailable && capacity.txnAvailable;
    }
    canAllocateMedium(capacity) {
        return capacity.cpuAvailable && capacity.memoryAvailable && capacity.storageAvailable && capacity.txnAvailable;
    }
    canAllocateLow(capacity) {
        return (capacity.cpuAvailable &&
            capacity.memoryAvailable &&
            capacity.storageAvailable &&
            capacity.networkAvailable &&
            capacity.txnAvailable);
    }
    /**
     * Release resources
     */
    releaseResources(allocationId) {
        const allocation = Array.from(this.allocations.values()).find((a) => `${a.workloadId}-${a.nodeId}` === allocationId);
        if (!allocation)
            return false;
        const usage = this.usage.get(allocation.nodeId);
        if (!usage)
            return false;
        usage.cpuUsed = Math.max(0, usage.cpuUsed - allocation.cpuAllocated);
        usage.memoryUsed = Math.max(0, usage.memoryUsed - allocation.memoryAllocated);
        usage.storageUsed = Math.max(0, usage.storageUsed - allocation.storageAllocated);
        usage.networkUsed = Math.max(0, usage.networkUsed - allocation.networkAllocated);
        usage.activeTransactions = Math.max(0, usage.activeTransactions - 1);
        usage.timestamp = Date.now();
        allocation.releasedAt = Date.now();
        allocation.status = 'released';
        // Store in history
        const history = this.usageHistory.get(allocation.nodeId) || [];
        history.push({ ...usage });
        if (history.length > this.maxHistoryLength) {
            history.shift();
        }
        this.usageHistory.set(allocation.nodeId, history);
        return true;
    }
    /**
     * Get resource availability
     */
    getResourceAvailability(nodeId) {
        const quota = this.quotas.get(nodeId);
        const usage = this.usage.get(nodeId);
        if (!quota || !usage)
            return undefined;
        return {
            cpuAvailable: Math.max(0, quota.cpuLimit - usage.cpuUsed),
            memoryAvailable: Math.max(0, quota.memoryLimit - usage.memoryUsed),
            storageAvailable: Math.max(0, quota.storageLimit - usage.storageUsed),
            networkAvailable: Math.max(0, quota.networkLimit - usage.networkUsed),
            cpuUtilization: (usage.cpuUsed / quota.cpuLimit) * 100,
            memoryUtilization: (usage.memoryUsed / quota.memoryLimit) * 100,
            storageUtilization: (usage.storageUsed / quota.storageLimit) * 100,
            networkUtilization: (usage.networkUsed / quota.networkLimit) * 100,
        };
    }
    /**
     * Get hot spots (nodes with high utilization)
     */
    getHotspots(threshold = 80) {
        const hotspots = [];
        this.quotas.forEach((quota) => {
            const availability = this.getResourceAvailability(quota.nodeId);
            if (availability) {
                if (availability.cpuUtilization > threshold ||
                    availability.memoryUtilization > threshold ||
                    availability.storageUtilization > threshold) {
                    hotspots.push(quota.nodeId);
                }
            }
        });
        return hotspots;
    }
    /**
     * Get resource pressure index (0-100)
     */
    getResourcePressure(nodeId) {
        const availability = this.getResourceAvailability(nodeId);
        if (!availability)
            return undefined;
        const avgUtilization = (availability.cpuUtilization +
            availability.memoryUtilization +
            availability.storageUtilization +
            availability.networkUtilization) /
            4;
        return Math.min(100, avgUtilization);
    }
    /**
     * Recommend resource optimization
     */
    getOptimizationRecommendations(nodeId) {
        const recommendations = [];
        const availability = this.getResourceAvailability(nodeId);
        if (!availability)
            return recommendations;
        if (availability.cpuUtilization > 80) {
            recommendations.push('Consider distributing CPU-intensive workloads to other nodes');
        }
        if (availability.memoryUtilization > 85) {
            recommendations.push('Memory is constrained - reduce cache size or enable memory-aware strategies');
        }
        if (availability.storageUtilization > 90) {
            recommendations.push('Storage is critically full - clean up old data or compress archives');
        }
        if (availability.networkUtilization > 75) {
            recommendations.push('Network bandwidth is high - enable compression and batch operations');
        }
        return recommendations;
    }
    /**
     * Get usage history
     */
    getUsageHistory(nodeId, limit) {
        const history = this.usageHistory.get(nodeId) || [];
        if (limit) {
            return history.slice(-limit);
        }
        return history;
    }
    /**
     * Get overall cluster stats
     */
    getClusterStats() {
        const quotas = Array.from(this.quotas.values());
        const totalCpuCapacity = quotas.reduce((sum, q) => sum + q.cpuLimit, 0);
        const totalMemoryCapacity = quotas.reduce((sum, q) => sum + q.memoryLimit, 0);
        let totalCpuUsed = 0;
        let totalMemoryUsed = 0;
        quotas.forEach((quota) => {
            const usage = this.usage.get(quota.nodeId);
            if (usage) {
                totalCpuUsed += usage.cpuUsed;
                totalMemoryUsed += usage.memoryUsed;
            }
        });
        const avgCpuUtil = totalCpuCapacity > 0 ? (totalCpuUsed / totalCpuCapacity) * 100 : 0;
        const avgMemUtil = totalMemoryCapacity > 0 ? (totalMemoryUsed / totalMemoryCapacity) * 100 : 0;
        const hotspots = this.getHotspots();
        return {
            totalNodes: quotas.length,
            totalCpuCapacity,
            totalMemoryCapacity,
            totalCpuUsed,
            totalMemoryUsed,
            avgCpuUtilization: avgCpuUtil,
            avgMemoryUtilization: avgMemUtil,
            hotspotCount: hotspots.length,
        };
    }
}
export default ResourceConstraintManager;
//# sourceMappingURL=ResourceConstraintManager.js.map