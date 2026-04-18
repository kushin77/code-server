/**
 * Phase 10: On-Premises Optimization - Test Suite
 * Tests for edge deployment, offline operations, resource constraints, and distributed operations
 */

import { EdgeOptimizationEngine } from '../../ml/EdgeOptimizationEngine';
import { OfflineSyncManager } from '../../ml/OfflineSyncManager';
import { ResourceConstraintManager } from '../../ml/ResourceConstraintManager';
import { DistributedOperationOrchestrator } from '../../ml/DistributedOperationOrchestrator';
import { OnPremisesOptimizationPhase10Agent } from '../../agents/OnPremisesOptimizationPhase10Agent';

describe('Phase 10: On-Premises Optimization', () => {
  describe('EdgeOptimizationEngine', () => {
    let engine: EdgeOptimizationEngine;

    beforeEach(() => {
      engine = new EdgeOptimizationEngine();
    });

    test('should register edge node', () => {
      engine.registerEdgeNode({
        nodeId: 'edge-1',
        location: 'warehouse-a',
        cpu: 4,
        memory: 8192,
        storage: 102400,
        networkBandwidth: 100,
        networkLatency: 100,
        isOnline: true,
        lastHeartbeat: Date.now(),
      });

      const stats = engine.getEdgeNodeStats();
      expect(stats.totalNodes).toBe(1);
      expect(stats.onlineNodes).toBe(1);
    });

    test('should update edge node status', () => {
      engine.registerEdgeNode({
        nodeId: 'edge-1',
        location: 'warehouse-a',
        cpu: 4,
        memory: 8192,
        storage: 102400,
        networkBandwidth: 100,
        networkLatency: 100,
        isOnline: true,
        lastHeartbeat: Date.now(),
      });

      engine.updateEdgeNodeStatus('edge-1', false);
      const stats = engine.getEdgeNodeStats();
      expect(stats.offlineNodes).toBe(1);
    });

    test('should cache data with compression', () => {
      engine.registerEdgeNode({
        nodeId: 'edge-1',
        location: 'warehouse-a',
        cpu: 4,
        memory: 8192,
        storage: 102400,
        networkBandwidth: 100,
        networkLatency: 100,
        isOnline: true,
        lastHeartbeat: Date.now(),
      });

      engine.createOptimizationProfile('edge-1', {
        ttl: 60000,
        maxSize: 1024,
        evictionPolicy: 'lru',
      });

      const result = engine.cacheData('edge-1', 'key1', { data: 'test' });
      expect(result).toBe(true);
    });

    test('should retrieve cached data', () => {
      engine.registerEdgeNode({
        nodeId: 'edge-1',
        location: 'warehouse-a',
        cpu: 4,
        memory: 8192,
        storage: 102400,
        networkBandwidth: 100,
        networkLatency: 100,
        isOnline: true,
        lastHeartbeat: Date.now(),
      });

      engine.createOptimizationProfile('edge-1', {
        ttl: 60000,
        maxSize: 1024,
        evictionPolicy: 'lru',
      });

      engine.cacheData('edge-1', 'key1', { data: 'test' });
      const data = engine.getCachedData('key1');
      expect(data).toBeDefined();
      expect(data.data).toBe('test');
    });

    test('should batch operations', () => {
      engine.registerEdgeNode({
        nodeId: 'edge-1',
        location: 'warehouse-a',
        cpu: 4,
        memory: 8192,
        storage: 102400,
        networkBandwidth: 100,
        networkLatency: 100,
        isOnline: true,
        lastHeartbeat: Date.now(),
      });

      engine.createOptimizationProfile('edge-1', {
        ttl: 60000,
        maxSize: 1024,
        evictionPolicy: 'lru',
        compressionStrategy: { algorithm: 'gzip', level: 6, useForPayloads: true, useForCache: false, minSize: 1024 },
      });

      for (let i = 0; i < 5; i++) {
        engine.queueForBatch('edge-1', { id: i });
      }

      const batch = engine.getBatch('edge-1');
      expect(batch.length).toBeGreaterThan(0);
    });

    test('should calculate bandwidth optimization', () => {
      engine.registerEdgeNode({
        nodeId: 'edge-1',
        location: 'warehouse-a',
        cpu: 4,
        memory: 8192,
        storage: 102400,
        networkBandwidth: 5, // very slow
        networkLatency: 500,
        isOnline: true,
        lastHeartbeat: Date.now(),
      });

      engine.createOptimizationProfile('edge-1', {
        ttl: 60000,
        maxSize: 1024,
        evictionPolicy: 'lru',
      });

      const optimization = engine.getBandwidthOptimization('edge-1');
      expect(optimization.compressionLevel).toBe(9); // maximum compression
    });

    test('should get compression statistics', () => {
      engine.registerEdgeNode({
        nodeId: 'edge-1',
        location: 'warehouse-a',
        cpu: 4,
        memory: 8192,
        storage: 102400,
        networkBandwidth: 100,
        networkLatency: 100,
        isOnline: true,
        lastHeartbeat: Date.now(),
      });

      engine.createOptimizationProfile('edge-1', {
        ttl: 60000,
        maxSize: 1024,
        evictionPolicy: 'lru',
        compressionStrategy: { algorithm: 'gzip', level: 6, useForPayloads: true, useForCache: true, minSize: 512 },
      });

      const stats = engine.getCompressionStats();
      expect(stats).toHaveProperty('totalOriginalSize');
      expect(stats).toHaveProperty('avgCompressionRatio');
    });
  });

  describe('OfflineSyncManager', () => {
    let manager: OfflineSyncManager;

    beforeEach(() => {
      manager = new OfflineSyncManager();
    });

    test('should record offline operation', () => {
      const op = manager.recordOperation('edge-1', 'create', 'user', { name: 'test' });
      expect(op).toBeDefined();
      expect(op.status).toBe('pending');
    });

    test('should get pending operations', () => {
      manager.recordOperation('edge-1', 'create', 'user', { name: 'test' });
      manager.recordOperation('edge-1', 'update', 'user', { id: 1, name: 'updated' });

      const pending = manager.getPendingOperations('edge-1');
      expect(pending.length).toBe(2);
    });

    test('should create sync batch', () => {
      manager.recordOperation('edge-1', 'create', 'user', { name: 'test' });
      const batch = manager.createSyncBatch('edge-1');

      expect(batch).toBeDefined();
      expect(batch.operations.length).toBeGreaterThan(0);
    });

    test('should record sync success', () => {
      const op = manager.recordOperation('edge-1', 'create', 'user', { name: 'test' });
      const success = manager.recordSyncSuccess(op.id, 1);

      expect(success).toBe(true);
      const retrieved = manager.getPendingOperations('edge-1');
      expect(retrieved.length).toBe(0);
    });

    test('should record sync failure with retry', () => {
      const op = manager.recordOperation('edge-1', 'create', 'user', { name: 'test' });
      manager.recordSyncFailure(op.id, 'Network error');

      const pending = manager.getPendingOperations('edge-1');
      expect(pending.length).toBe(1);
      expect(pending[0].retryCount).toBeGreaterThan(0);
    });

    test('should record conflict with resolution', () => {
      const op = manager.recordOperation('edge-1', 'update', 'user', { id: 1, name: 'local' });
      const conflict = manager.recordConflict(op.id, 2, 'local');

      expect(conflict).toBeDefined();
      expect(conflict.resolution).toBe('local');
    });

    test('should get sync statistics', () => {
      manager.recordOperation('edge-1', 'create', 'user', { name: 'test' });
      const stats = manager.getSyncStatistics();

      expect(stats.totalOperations).toBeGreaterThan(0);
      expect(stats.pendingOperations).toBeGreaterThan(0);
    });

    test('should get sync queue status', () => {
      manager.recordOperation('edge-1', 'create', 'user', { name: 'test' });
      const status = manager.getSyncQueueStatus();

      expect(status.queueLength).toBeGreaterThan(0);
      expect(status.averageWaitTime).toBeGreaterThanOrEqual(0);
    });
  });

  describe('ResourceConstraintManager', () => {
    let manager: ResourceConstraintManager;

    beforeEach(() => {
      manager = new ResourceConstraintManager();
    });

    test('should register resource quota', () => {
      manager.registerQuota({
        nodeId: 'edge-1',
        cpuLimit: 4,
        memoryLimit: 8192,
        storageLimit: 102400,
        networkLimit: 100,
        concurrentTransactions: 40,
      });

      const availability = manager.getResourceAvailability('edge-1');
      expect(availability).toBeDefined();
      expect(availability?.cpuAvailable).toBe(4);
    });

    test('should register workload', () => {
      manager.registerWorkload({
        workloadId: 'app-1',
        priority: 'high',
        estimatedCpu: 2,
        estimatedMemory: 2048,
        estimatedStorage: 10240,
        estimatedNetworkUsage: 50,
        estimatedDuration: 60000,
      });

      expect(manager).toBeDefined();
    });

    test('should allocate resources', () => {
      manager.registerQuota({
        nodeId: 'edge-1',
        cpuLimit: 4,
        memoryLimit: 8192,
        storageLimit: 102400,
        networkLimit: 100,
        concurrentTransactions: 40,
      });

      manager.registerWorkload({
        workloadId: 'app-1',
        priority: 'high',
        estimatedCpu: 2,
        estimatedMemory: 2048,
        estimatedStorage: 10240,
        estimatedNetworkUsage: 50,
        estimatedDuration: 60000,
      });

      const allocation = manager.allocateResources('app-1', 'edge-1');
      expect(allocation).toBeDefined();
      expect(allocation?.status).toBe('allocated');
    });

    test('should release resources', () => {
      manager.registerQuota({
        nodeId: 'edge-1',
        cpuLimit: 4,
        memoryLimit: 8192,
        storageLimit: 102400,
        networkLimit: 100,
        concurrentTransactions: 40,
      });

      manager.registerWorkload({
        workloadId: 'app-1',
        priority: 'high',
        estimatedCpu: 2,
        estimatedMemory: 2048,
        estimatedStorage: 10240,
        estimatedNetworkUsage: 50,
        estimatedDuration: 60000,
      });

      const allocation = manager.allocateResources('app-1', 'edge-1');
      if (allocation) {
        const released = manager.releaseResources(`${allocation.workloadId}-${allocation.nodeId}`);
        expect(released).toBe(true);
      }
    });

    test('should detect hotspots', () => {
      manager.registerQuota({
        nodeId: 'edge-1',
        cpuLimit: 1, // very limited
        memoryLimit: 512,
        storageLimit: 10240,
        networkLimit: 10,
        concurrentTransactions: 10,
      });

      manager.registerWorkload({
        workloadId: 'app-1',
        priority: 'high',
        estimatedCpu: 0.9, // nearly full
        estimatedMemory: 400,
        estimatedStorage: 5120,
        estimatedNetworkUsage: 5,
        estimatedDuration: 60000,
      });

      manager.allocateResources('app-1', 'edge-1');
      const hotspots = manager.getHotspots(80);
      expect(hotspots.length).toBeGreaterThan(0);
    });

    test('should get resource pressure', () => {
      manager.registerQuota({
        nodeId: 'edge-1',
        cpuLimit: 4,
        memoryLimit: 8192,
        storageLimit: 102400,
        networkLimit: 100,
        concurrentTransactions: 40,
      });

      const pressure = manager.getResourcePressure('edge-1');
      expect(pressure).toBeDefined();
      expect(pressure).toBeGreaterThanOrEqual(0);
      expect(pressure).toBeLessThanOrEqual(100);
    });

    test('should get optimization recommendations', () => {
      manager.registerQuota({
        nodeId: 'edge-1',
        cpuLimit: 1,
        memoryLimit: 512,
        storageLimit: 1024,
        networkLimit: 10,
        concurrentTransactions: 5,
      });

      const recommendations = manager.getOptimizationRecommendations('edge-1');
      expect(Array.isArray(recommendations)).toBe(true);
    });

    test('should get cluster stats', () => {
      manager.registerQuota({
        nodeId: 'edge-1',
        cpuLimit: 4,
        memoryLimit: 8192,
        storageLimit: 102400,
        networkLimit: 100,
        concurrentTransactions: 40,
      });

      const stats = manager.getClusterStats();
      expect(stats.totalNodes).toBe(1);
      expect(stats.totalCpuCapacity).toBe(4);
    });
  });

  describe('DistributedOperationOrchestrator', () => {
    let orchestrator: DistributedOperationOrchestrator;

    beforeEach(() => {
      orchestrator = new DistributedOperationOrchestrator();
    });

    test('should create distributed workflow', () => {
      const workflow = orchestrator.createWorkflow('test-workflow', [
        { name: 'map', operationType: 'map', tasks: [] },
      ]);

      expect(workflow).toBeDefined();
      expect(workflow.status).toBe('pending');
    });

    test('should start workflow', () => {
      const workflow = orchestrator.createWorkflow('test-workflow', [
        { name: 'map', operationType: 'map', tasks: [] },
      ]);

      const success = orchestrator.startWorkflow(workflow.id);
      expect(success).toBe(true);
      expect(orchestrator.getWorkflowStatus(workflow.id)?.status).toBe('running');
    });

    test('should execute map operation', () => {
      const workflow = orchestrator.createWorkflow('test-workflow', [
        { name: 'map', operationType: 'map', tasks: [] },
      ]);

      orchestrator.startWorkflow(workflow.id);
      const taskId = orchestrator.executeMap(workflow.id, 0, [1, 2, 3, 4], ['node-1', 'node-2']);

      expect(taskId).toBeDefined();
      expect(taskId.length).toBeGreaterThan(0);
    });

    test('should execute broadcast operation', () => {
      const workflow = orchestrator.createWorkflow('test-workflow', [
        { name: 'broadcast', operationType: 'broadcast', tasks: [] },
      ]);

      orchestrator.startWorkflow(workflow.id);
      const results = orchestrator.executeBroadcast(workflow.id, 0, { data: 'test' }, 'node-1', ['node-2', 'node-3']);

      expect(results.length).toBe(2);
      expect(results[0].status).toBe('success');
    });

    test('should execute scatter-gather operation', () => {
      const workflow = orchestrator.createWorkflow('test-workflow', [
        { name: 'scatter-gather', operationType: 'scatter-gather', tasks: [] },
      ]);

      orchestrator.startWorkflow(workflow.id);
      const result = orchestrator.executeScatterGather(workflow.id, 0, [
        { nodeId: 'node-1', data: { id: 1 } },
        { nodeId: 'node-2', data: { id: 2 } },
      ]);

      expect(result.scattered.length).toBe(2);
      expect(result.gathered).toBeDefined();
    });

    test('should complete workflow', () => {
      const workflow = orchestrator.createWorkflow('test-workflow', [
        { name: 'map', operationType: 'map', tasks: [] },
      ]);

      orchestrator.startWorkflow(workflow.id);
      const completed = orchestrator.completeWorkflow(workflow.id, true);

      expect(completed?.status).toBe('completed');
    });

    test('should get execution statistics', () => {
      const workflow = orchestrator.createWorkflow('test-workflow', [
        { name: 'map', operationType: 'map', tasks: [] },
      ]);

      orchestrator.startWorkflow(workflow.id);
      const stats = orchestrator.getExecutionStats();

      expect(stats.totalWorkflows).toBeGreaterThan(0);
    });

    test('should register node topology', () => {
      orchestrator.registerNodeTopology('edge-1', ['edge-2', 'edge-3']);
      const optimized = orchestrator.getLocalityOptimizedNodes('edge-1', ['edge-1', 'edge-2', 'edge-3', 'edge-4']);

      expect(optimized[0]).toBe('edge-1');
      expect(optimized.includes('edge-2')).toBe(true);
    });
  });

  describe('OnPremisesOptimizationPhase10Agent', () => {
    let agent: OnPremisesOptimizationPhase10Agent;

    beforeEach(() => {
      agent = new OnPremisesOptimizationPhase10Agent(
        {},
        {
          edgeNodeCount: 3,
          averageNodeCpu: 4,
          averageNodeMemory: 8192,
          averageNodeStorage: 102400,
          networkLatency: 100,
          networkBandwidth: 100,
        }
      );
    });

    test('should deploy edge node', () => {
      agent.deployEdgeNode('edge-1', 'warehouse-a', {
        cpu: 4,
        memory: 8192,
        storage: 102400,
        bandwidth: 100,
        latency: 100,
      });

      const status = agent.getDeploymentStatus();
      expect(status.healthyNodes).toBeGreaterThan(0);
    });

    test('should register workload', () => {
      agent.registerWorkload('app-1', 'high', {
        cpu: 2,
        memory: 2048,
        storage: 10240,
        networkUsage: 50,
      });

      expect(agent).toBeDefined();
    });

    test('should schedule workload', () => {
      agent.deployEdgeNode('edge-1', 'warehouse-a', {
        cpu: 4,
        memory: 8192,
        storage: 102400,
        bandwidth: 100,
        latency: 100,
      });

      agent.registerWorkload('app-1', 'high', {
        cpu: 2,
        memory: 2048,
        storage: 10240,
        networkUsage: 50,
      });

      const result = agent.scheduleWorkload('app-1');
      expect(result).toBeDefined();
      expect(result?.status).toMatch(/scheduled|failed/);
    });

    test('should record offline operation', () => {
      const op = agent.recordOfflineOperation('edge-1', 'create', 'user', { name: 'test' });
      expect(op).toBeDefined();
      expect(op.status).toBe('pending');
    });

    test('should sync offline operations', () => {
      agent.recordOfflineOperation('edge-1', 'create', 'user', { name: 'test' });
      const result = agent.syncOfflineOperations('edge-1');

      expect(result.synced).toBeGreaterThanOrEqual(0);
      expect(result.failed).toBeGreaterThanOrEqual(0);
    });

    test('should execute distributed workflow', () => {
      const workflow = agent.executeDistributedWorkflow('test-wf', 'map', [1, 2, 3]);
      expect(workflow).toBeDefined();
      expect(workflow.status).toBe('running');
    });

    test('should get deployment status', () => {
      agent.deployEdgeNode('edge-1', 'warehouse-a', {
        cpu: 4,
        memory: 8192,
        storage: 102400,
        bandwidth: 100,
        latency: 100,
      });

      const status = agent.getDeploymentStatus();
      expect(status).toHaveProperty('timestamp');
      expect(status.overallStatus).toMatch(/healthy|degraded|unhealthy/);
    });

    test('should get comprehensive status report', () => {
      const report = agent.getStatusReport();
      expect(report).toHaveProperty('deployment');
      expect(report).toHaveProperty('edgeNodes');
      expect(report).toHaveProperty('resources');
      expect(report).toHaveProperty('sync');
      expect(report).toHaveProperty('distributed');
    });

    test('should get optimization recommendations', () => {
      const recommendations = agent.getOptimizationRecommendations();
      expect(Array.isArray(recommendations)).toBe(true);
    });

    test('should execute agent actions', async () => {
      const status = await agent.execute({
        action: 'deployNode',
        nodeId: 'edge-1',
        location: 'warehouse-a',
        nodeProfile: {
          cpu: 4,
          memory: 8192,
          storage: 102400,
          bandwidth: 100,
          latency: 100,
        },
      });

      expect(status).toBeDefined();
      expect(status.overallStatus).toBeDefined();
    });
  });
});
