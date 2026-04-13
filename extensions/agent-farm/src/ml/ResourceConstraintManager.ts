/**
 * Resource Constraint Manager
 * Manages limited CPU, memory, and network resources on edge nodes
 */

export interface ResourceQuota {
  nodeId: string;
  cpuLimit: number; // cores
  memoryLimit: number; // MB
  storageLimit: number; // MB
  networkLimit: number; // Mbps
  concurrentTransactions: number;
}

export interface ResourceUsage {
  nodeId: string;
  cpuUsed: number;
  memoryUsed: number;
  storageUsed: number;
  networkUsed: number;
  activeTransactions: number;
  timestamp: number;
}

export interface WorkloadPriority {
  workloadId: string;
  priority: 'critical' | 'high' | 'medium' | 'low';
  estimatedCpu: number;
  estimatedMemory: number;
  estimatedStorage: number;
  estimatedNetworkUsage: number;
  estimatedDuration: number; // milliseconds
}

export interface ResourceAllocation {
  workloadId: string;
  nodeId: string;
  cpuAllocated: number;
  memoryAllocated: number;
  storageAllocated: number;
  networkAllocated: number;
  allocatedAt: number;
  releasedAt?: number;
  status: 'allocated' | 'released' | 'exceeded';
}

export class ResourceConstraintManager {
  private quotas: Map<string, ResourceQuota> = new Map();
  private usage: Map<string, ResourceUsage> = new Map();
  private allocations: Map<string, ResourceAllocation> = new Map();
  private workloadPriorities: Map<string, WorkloadPriority> = new Map();
  private usageHistory: Map<string, ResourceUsage[]> = new Map();
  private readonly maxHistoryLength = 1000;

  constructor() {}

  /**
   * Register resource quota for node
   */
  registerQuota(quota: ResourceQuota): void {
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
  registerWorkload(priority: WorkloadPriority): void {
    this.workloadPriorities.set(priority.workloadId, priority);
  }

  /**
   * Try to allocate resources
   */
  allocateResources(workloadId: string, nodeId: string): ResourceAllocation | undefined {
    const quota = this.quotas.get(nodeId);
    const usage = this.usage.get(nodeId);
    const workload = this.workloadPriorities.get(workloadId);

    if (!quota || !usage || !workload) return undefined;

    // Check if resources are available
    const cpuAvailable = quota.cpuLimit - usage.cpuUsed >= workload.estimatedCpu;
    const memoryAvailable = quota.memoryLimit - usage.memoryUsed >= workload.estimatedMemory;
    const storageAvailable = quota.storageLimit - usage.storageUsed >= workload.estimatedStorage;
    const networkAvailable = quota.networkLimit - usage.networkUsed >= workload.estimatedNetworkUsage;
    const txnAvailable = quota.concurrentTransactions - usage.activeTransactions >= 1;

    let canAllocate = true;

    // Priority-based resource contention handling
    if (workload.priority === 'critical') {
      // Critical workloads can preempt others (simplified: just check minimum)
      canAllocate = cpuAvailable || memoryAvailable;
    } else if (workload.priority === 'high') {
      canAllocate = cpuAvailable && memoryAvailable && txnAvailable;
    } else if (workload.priority === 'medium') {
      canAllocate = cpuAvailable && memoryAvailable && storageAvailable && txnAvailable;
    } else {
      // Low priority: all resources must be available
      canAllocate = cpuAvailable && memoryAvailable && storageAvailable && networkAvailable && txnAvailable;
    }

    if (!canAllocate) {
      return undefined;
    }

    // Perform allocation
    const allocation: ResourceAllocation = {
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

  /**
   * Release resources
   */
  releaseResources(allocationId: string): boolean {
    const allocation = Array.from(this.allocations.values()).find(
      (a) => `${a.workloadId}-${a.nodeId}` === allocationId
    );

    if (!allocation) return false;

    const usage = this.usage.get(allocation.nodeId);
    if (!usage) return false;

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
  getResourceAvailability(nodeId: string): {
    cpuAvailable: number;
    memoryAvailable: number;
    storageAvailable: number;
    networkAvailable: number;
    cpuUtilization: number;
    memoryUtilization: number;
    storageUtilization: number;
    networkUtilization: number;
  } | undefined {
    const quota = this.quotas.get(nodeId);
    const usage = this.usage.get(nodeId);

    if (!quota || !usage) return undefined;

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
  getHotspots(threshold: number = 80): string[] {
    const hotspots: string[] = [];

    this.quotas.forEach((quota) => {
      const availability = this.getResourceAvailability(quota.nodeId);
      if (availability) {
        if (
          availability.cpuUtilization > threshold ||
          availability.memoryUtilization > threshold ||
          availability.storageUtilization > threshold
        ) {
          hotspots.push(quota.nodeId);
        }
      }
    });

    return hotspots;
  }

  /**
   * Get resource pressure index (0-100)
   */
  getResourcePressure(nodeId: string): number | undefined {
    const availability = this.getResourceAvailability(nodeId);
    if (!availability) return undefined;

    const avgUtilization =
      (availability.cpuUtilization +
        availability.memoryUtilization +
        availability.storageUtilization +
        availability.networkUtilization) /
      4;

    return Math.min(100, avgUtilization);
  }

  /**
   * Recommend resource optimization
   */
  getOptimizationRecommendations(nodeId: string): string[] {
    const recommendations: string[] = [];
    const availability = this.getResourceAvailability(nodeId);

    if (!availability) return recommendations;

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
  getUsageHistory(nodeId: string, limit?: number): ResourceUsage[] {
    const history = this.usageHistory.get(nodeId) || [];
    if (limit) {
      return history.slice(-limit);
    }
    return history;
  }

  /**
   * Get overall cluster stats
   */
  getClusterStats(): {
    totalNodes: number;
    totalCpuCapacity: number;
    totalMemoryCapacity: number;
    totalCpuUsed: number;
    totalMemoryUsed: number;
    avgCpuUtilization: number;
    avgMemoryUtilization: number;
    hotspotCount: number;
  } {
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
