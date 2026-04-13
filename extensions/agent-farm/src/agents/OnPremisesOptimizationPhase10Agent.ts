/**
 * Phase 10: On-Premises Optimization Agent
 * Orchestrates edge deployment, offline operations, and resource constraints
 */

import { Agent } from '../phases';
import { EdgeOptimizationEngine, EdgeProfile, CachePolicy, CompressionStrategy } from '../ml/EdgeOptimizationEngine';
import { OfflineSyncManager, OfflineOperation } from '../ml/OfflineSyncManager';
import { ResourceConstraintManager, ResourceQuota, WorkloadPriority } from '../ml/ResourceConstraintManager';
import { DistributedOperationOrchestrator, DistributedWorkflow } from '../ml/DistributedOperationOrchestrator';

export interface OnPremisesDeploymentConfig {
  edgeNodeCount: number;
  averageNodeCpu: number;
  averageNodeMemory: number;
  averageNodeStorage: number;
  networkLatency: number;
  networkBandwidth: number;
}

export interface EdgeDeploymentStatus {
  timestamp: number;
  healthyNodes: number;
  deployedServices: number;
  pendingOperations: number;
  resourceUtilization: number;
  offlineSyncQueueLength: number;
  distributedWorkflowCount: number;
  overallStatus: 'healthy' | 'degraded' | 'unhealthy';
}

export class OnPremisesOptimizationPhase10Agent extends Agent {
  private edgeEngine: EdgeOptimizationEngine;
  private syncManager: OfflineSyncManager;
  private resourceManager: ResourceConstraintManager;
  private distributedOrchestrator: DistributedOperationOrchestrator;
  private deploymentConfig: OnPremisesDeploymentConfig;

  constructor(context: any, config: OnPremisesDeploymentConfig) {
    super('OnPremisesOptimizationPhase10Agent', context);
    this.deploymentConfig = config;
    this.edgeEngine = new EdgeOptimizationEngine();
    this.syncManager = new OfflineSyncManager();
    this.resourceManager = new ResourceConstraintManager();
    this.distributedOrchestrator = new DistributedOperationOrchestrator();
  }

  /**
   * Deploy edge node
   */
  deployEdgeNode(nodeId: string, location: string, profile: { cpu: number; memory: number; storage: number; bandwidth: number; latency: number }): void {
    // Register with edge optimization
    this.edgeEngine.registerEdgeNode({
      nodeId,
      location,
      cpu: profile.cpu,
      memory: profile.memory,
      storage: profile.storage,
      networkBandwidth: profile.bandwidth,
      networkLatency: profile.latency,
      isOnline: true,
      lastHeartbeat: Date.now(),
    });

    // Register resource quota
    this.resourceManager.registerQuota({
      nodeId,
      cpuLimit: profile.cpu,
      memoryLimit: profile.memory,
      storageLimit: profile.storage,
      networkLimit: profile.bandwidth,
      concurrentTransactions: Math.ceil(profile.cpu * 10),
    });

    // Create optimization profile
    const cachePolicy: CachePolicy = {
      ttl: 60000, // 1 minute
      maxSize: Math.floor(profile.memory * 0.2), // 20% of available memory
      evictionPolicy: 'lru',
      compressionStrategy: {
        algorithm: 'gzip',
        level: 6,
        useForPayloads: true,
        useForCache: true,
        minSize: 1024,
      },
    };

    const compressionStrategy: CompressionStrategy = {
      algorithm: profile.bandwidth < 50 ? 'gzip' : 'lz4',
      level: profile.bandwidth < 10 ? 9 : 6,
      useForPayloads: true,
      useForCache: true,
      minSize: 512,
    };

    this.edgeEngine.createOptimizationProfile(nodeId, cachePolicy, compressionStrategy);

    // Register with topology
    this.distributedOrchestrator.registerNodeTopology(nodeId, []);

    this.log(`Deployed edge node ${nodeId} at ${location} (CPU: ${profile.cpu}, Memory: ${profile.memory}MB)`);
  }

  /**
   * Register workload for scheduling
   */
  registerWorkload(
    workloadId: string,
    priority: 'critical' | 'high' | 'medium' | 'low',
    resourceEstimate: { cpu: number; memory: number; storage: number; networkUsage: number }
  ): void {
    this.resourceManager.registerWorkload({
      workloadId,
      priority,
      estimatedCpu: resourceEstimate.cpu,
      estimatedMemory: resourceEstimate.memory,
      estimatedStorage: resourceEstimate.storage,
      estimatedNetworkUsage: resourceEstimate.networkUsage,
      estimatedDuration: 60000,
    });

    this.log(`Registered workload ${workloadId} (priority: ${priority})`);
  }

  /**
   * Schedule workload on best-fit node
   */
  scheduleWorkload(workloadId: string): { nodeId: string; status: 'scheduled' | 'failed' } | undefined {
    // Get all edge nodes and try to allocate
    const edgeStats = this.edgeEngine.getEdgeNodeStats();

    const edgeProfiles = (this.edgeEngine as any).edgeProfiles as Map<string, any>;
    for (const [nodeId] of edgeProfiles) {
      const allocation = this.resourceManager.allocateResources(workloadId, nodeId);
      if (allocation) {
        this.log(`Scheduled workload ${workloadId} on node ${nodeId}`);
        return { nodeId, status: 'scheduled' };
      }
    }

    this.log(`Failed to schedule workload ${workloadId} - insufficient resources`);
    return { nodeId: '', status: 'failed' };
  }

  /**
   * Record offline operation
   */
  recordOfflineOperation(
    nodeId: string,
    operationType: 'create' | 'update' | 'delete' | 'query' | 'execute',
    resource: string,
    payload: any
  ): OfflineOperation {
    return this.syncManager.recordOperation(nodeId, operationType, resource, payload);
  }

  /**
   * Sync offline operations
   */
  syncOfflineOperations(nodeId: string): { synced: number; failed: number; conflicts: number } {
    const batch = this.syncManager.createSyncBatch(nodeId);
    this.syncManager.startSyncBatch(batch.id);

    let syncedCount = 0;
    let failedCount = 0;
    let conflictCount = 0;

    batch.operations.forEach((op) => {
      // Simulate sync (in reality would send to server)
      const success = Math.random() > 0.1; // 90% success rate
      if (success) {
        this.syncManager.recordSyncSuccess(op.id);
        syncedCount++;
      } else {
        this.syncManager.recordSyncFailure(op.id, 'Network error');
        failedCount++;
      }
    });

    this.syncManager.completeSyncBatch(batch.id, failedCount === 0);

    this.log(`Synced ${syncedCount} operations, ${failedCount} failed for node ${nodeId}`);
    return { synced: syncedCount, failed: failedCount, conflicts: conflictCount };
  }

  /**
   * Execute distributed workflow
   */
  executeDistributedWorkflow(
    name: string,
    operationType: 'map' | 'reduce' | 'aggregate' | 'broadcast' | 'scatter-gather',
    input: any
  ): DistributedWorkflow {
    const workflow = this.distributedOrchestrator.createWorkflow(name, [
      { name: operationType, operationType, tasks: [] },
    ]);

    this.distributedOrchestrator.startWorkflow(workflow.id);

    this.log(`Started distributed workflow ${workflow.id} (operation: ${operationType})`);
    return workflow;
  }

  /**
   * Get deployment status
   */
  getDeploymentStatus(): EdgeDeploymentStatus {
    // Edge engine stats
    const edgeStats = this.edgeEngine.getEdgeNodeStats();

    // Resource stats
    const resourceStats = this.resourceManager.getClusterStats();

    // Sync stats
    const syncStats = this.syncManager.getSyncStatistics();

    // Distributed stats
    const distStats = this.distributedOrchestrator.getExecutionStats();

    // Determine overall status
    let overallStatus: 'healthy' | 'degraded' | 'unhealthy';
    if (edgeStats.offlineNodes === 0 && resourceStats.avgCpuUtilization < 80 && syncStats.failedOperations === 0) {
      overallStatus = 'healthy';
    } else if (edgeStats.offlineNodes < edgeStats.totalNodes / 2 && resourceStats.avgCpuUtilization < 90) {
      overallStatus = 'degraded';
    } else {
      overallStatus = 'unhealthy';
    }

    return {
      timestamp: Date.now(),
      healthyNodes: edgeStats.onlineNodes,
      deployedServices: resourceStats.totalNodes,
      pendingOperations: syncStats.pendingOperations,
      resourceUtilization: (resourceStats.avgCpuUtilization + resourceStats.avgMemoryUtilization) / 2,
      offlineSyncQueueLength: syncStats.pendingOperations,
      distributedWorkflowCount: distStats.runningWorkflows,
      overallStatus,
    };
  }

  /**
   * Get comprehensive status report
   */
  getStatusReport(): any {
    return {
      deployment: this.getDeploymentStatus(),
      edgeNodes: this.edgeEngine.getEdgeNodeStats(),
      resources: this.resourceManager.getClusterStats(),
      sync: this.syncManager.getSyncStatistics(),
      distributed: this.distributedOrchestrator.getExecutionStats(),
    };
  }

  /**
   * Get optimization recommendations
   */
  getOptimizationRecommendations(): string[] {
    const recommendations: string[] = [];

    const edgeStats = this.edgeEngine.getEdgeNodeStats();
    const resourceStats = this.resourceManager.getClusterStats();
    const syncStats = this.syncManager.getSyncStatistics();

    if (edgeStats.offlineNodes > 0) {
      recommendations.push(`${edgeStats.offlineNodes} edge nodes are offline - check connectivity`);
    }

    if (resourceStats.hotspotCount > 0) {
      recommendations.push(`${resourceStats.hotspotCount} nodes have high utilization - consider load balancing`);
    }

    if (syncStats.failedOperations > 0) {
      recommendations.push(`${syncStats.failedOperations} sync operations failed - check network and retry`);
    }

    const compressionStats = this.edgeEngine.getCompressionStats();
    if (compressionStats.avgCompressionRatio > 0.7) {
      recommendations.push('Compression ratio is low - consider enabling higher compression levels');
    }

    return recommendations;
  }

  /**
   * Execute Phase 10 Agent
   */
  async execute(input: any): Promise<EdgeDeploymentStatus> {
    const { action, nodeId, workloadId, operationType, priority, resourceEstimate, location, nodeProfile } = input;

    switch (action) {
      case 'deployNode':
        this.deployEdgeNode(nodeId, location, nodeProfile);
        break;
      case 'registerWorkload':
        this.registerWorkload(workloadId, priority, resourceEstimate);
        break;
      case 'scheduleWorkload':
        this.scheduleWorkload(workloadId);
        break;
      case 'recordOfflineOp':
        this.recordOfflineOperation(nodeId, operationType, 'resource', {});
        break;
      case 'syncOfflineOps':
        this.syncOfflineOperations(nodeId);
        break;
      case 'executeDistributedWf':
        this.executeDistributedWorkflow('workflow', operationType, []);
        break;
    }

    return this.getDeploymentStatus();
  }
}

export default OnPremisesOptimizationPhase10Agent;
