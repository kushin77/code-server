/**
 * Phase 9: Production Readiness - Test Suite
 * Tests for SLOs, runbooks, and incident response systems
 */

import { SLOTracker, SLO, SLI } from '../../ml/SLOTracker';
import { RunbookManager, Runbook } from '../../ml/RunbookManager';
import { IncidentResponseManager } from '../../ml/IncidentResponseManager';
import { ProductionReadinessPhase9Agent } from '../../agents/ProductionReadinessPhase9Agent';

describe('Phase 9: Production Readiness', () => {
  describe('SLOTracker', () => {
    let tracker: SLOTracker;

    beforeEach(() => {
      tracker = new SLOTracker();
    });

    test('should register SLO', () => {
      const slo: SLO = {
        name: 'api-slo',
        description: 'API availability SLO',
        service: 'api',
        slis: [
          {
            name: 'availability',
            description: 'Availability %',
            type: 'availability',
            unit: '%',
            threshold: 99.9,
            window: 86400000,
          },
        ],
        targetPercentage: 99.9,
        errorBudget: 1000,
        period: 30,
        version: 1,
        tags: [],
      };
      tracker.registerSLO(slo);
      expect(tracker.getSLOStatus('api-slo')).toBeDefined();
    });

    test('should record metrics', () => {
      const slo: SLO = {
        name: 'api-slo',
        description: 'API availability SLO',
        service: 'api',
        slis: [
          {
            name: 'availability',
            description: 'Availability %',
            type: 'availability',
            unit: '%',
            threshold: 99.9,
            window: 86400000,
          },
        ],
        targetPercentage: 99.9,
        errorBudget: 1000,
        period: 30,
        version: 1,
        tags: [],
      };
      tracker.registerSLO(slo);
      tracker.recordMetric('api-slo', 'availability', 99.95);
      const status = tracker.getSLOStatus('api-slo');
      expect(status?.currentValue).toBeGreaterThan(0);
    });

    test('should calculate SLI status', () => {
      const slo: SLO = {
        name: 'api-slo',
        description: 'API availability SLO',
        service: 'api',
        slis: [
          {
            name: 'availability',
            description: 'Availability %',
            type: 'availability',
            unit: '%',
            threshold: 99.9,
            window: 86400000,
          },
        ],
        targetPercentage: 99.9,
        errorBudget: 1000,
        period: 30,
        version: 1,
        tags: [],
      };
      tracker.registerSLO(slo);
      tracker.recordMetric('api-slo', 'availability', 99.95);
      const status = tracker.getSLOStatus('api-slo');
      expect(status?.sliStatuses[0].status).toMatch(/healthy|warning|critical/);
    });

    test('should track error budget', () => {
      const slo: SLO = {
        name: 'api-slo',
        description: 'API availability SLO',
        service: 'api',
        slis: [
          {
            name: 'availability',
            description: 'Availability %',
            type: 'availability',
            unit: '%',
            threshold: 99.9,
            window: 86400000,
          },
        ],
        targetPercentage: 99.9,
        errorBudget: 1000,
        period: 30,
        version: 1,
        tags: [],
      };
      tracker.registerSLO(slo);
      tracker.recordMetric('api-slo', 'availability', 98);
      const summary = tracker.getErrorBudgetSummary();
      expect(summary).toBeDefined();
      expect(summary[0]).toHaveProperty('remaining');
    });

    test('should identify at-risk SLOs', () => {
      const slo: SLO = {
        name: 'api-slo',
        description: 'API availability SLO',
        service: 'api',
        slis: [
          {
            name: 'availability',
            description: 'Availability %',
            type: 'availability',
            unit: '%',
            threshold: 99.9,
            window: 86400000,
          },
        ],
        targetPercentage: 99.9,
        errorBudget: 1000,
        period: 30,
        version: 1,
        tags: [],
      };
      tracker.registerSLO(slo);
      tracker.recordMetric('api-slo', 'availability', 95);
      const atRisk = tracker.getAtRiskSLOs();
      expect(atRisk.length).toBeGreaterThan(0);
    });

    test('should get SLO history', () => {
      const slo: SLO = {
        name: 'api-slo',
        description: 'API availability SLO',
        service: 'api',
        slis: [
          {
            name: 'availability',
            description: 'Availability %',
            type: 'availability',
            unit: '%',
            threshold: 99.9,
            window: 86400000,
          },
        ],
        targetPercentage: 99.9,
        errorBudget: 1000,
        period: 30,
        version: 1,
        tags: [],
      };
      tracker.registerSLO(slo);
      tracker.recordMetric('api-slo', 'availability', 99.95);
      const history = tracker.getSLOHistory('api-slo');
      expect(Array.isArray(history)).toBe(true);
    });

    test('should return stats', () => {
      const slo: SLO = {
        name: 'api-slo',
        description: 'API availability SLO',
        service: 'api',
        slis: [
          {
            name: 'availability',
            description: 'Availability %',
            type: 'availability',
            unit: '%',
            threshold: 99.9,
            window: 86400000,
          },
        ],
        targetPercentage: 99.9,
        errorBudget: 1000,
        period: 30,
        version: 1,
        tags: [],
      };
      tracker.registerSLO(slo);
      const stats = tracker.getStats();
      expect(stats.totalSLOs).toBe(1);
      expect(stats.avgCompliancePercentage).toBeGreaterThanOrEqual(0);
    });
  });

  describe('RunbookManager', () => {
    let manager: RunbookManager;

    beforeEach(() => {
      manager = new RunbookManager();
    });

    test('should register runbook', () => {
      const runbook: Runbook = {
        id: 'rb-1',
        name: 'High Latency',
        description: 'Response to high latency',
        trigger: 'high_latency',
        severity: 'high',
        owner: 'platform',
        steps: [],
        estimatedDuration: 300000,
        createdAt: new Date(),
        updatedAt: new Date(),
        version: 1,
        tags: [],
      };
      manager.registerRunbook(runbook);
      expect(manager.getRunbook('rb-1')).toBeDefined();
    });

    test('should get runbooks by trigger', () => {
      const runbook: Runbook = {
        id: 'rb-1',
        name: 'High Latency',
        description: 'Response to high latency',
        trigger: 'high_latency',
        severity: 'high',
        owner: 'platform',
        steps: [],
        estimatedDuration: 300000,
        createdAt: new Date(),
        updatedAt: new Date(),
        version: 1,
        tags: [],
      };
      manager.registerRunbook(runbook);
      const found = manager.getRunbooksByTrigger('high_latency');
      expect(found.length).toBe(1);
    });

    test('should start execution', () => {
      const runbook: Runbook = {
        id: 'rb-1',
        name: 'High Latency',
        description: 'Response to high latency',
        trigger: 'high_latency',
        severity: 'high',
        owner: 'platform',
        steps: [],
        estimatedDuration: 300000,
        createdAt: new Date(),
        updatedAt: new Date(),
        version: 1,
        tags: [],
      };
      manager.registerRunbook(runbook);
      const exec = manager.startExecution('rb-1', 'engineer');
      expect(exec).toBeDefined();
      expect(exec?.status).toBe('running');
    });

    test('should record step completion', () => {
      const runbook: Runbook = {
        id: 'rb-1',
        name: 'High Latency',
        description: 'Response to high latency',
        trigger: 'high_latency',
        severity: 'high',
        owner: 'platform',
        steps: [
          {
            id: 'step-1',
            title: 'Check',
            description: 'Check status',
            type: 'verify',
            successOptions: ['step-2'],
          },
          {
            id: 'step-2',
            title: 'Fix',
            description: 'Fix issue',
            type: 'execute',
          },
        ],
        estimatedDuration: 300000,
        createdAt: new Date(),
        updatedAt: new Date(),
        version: 1,
        tags: [],
      };
      manager.registerRunbook(runbook);
      const exec = manager.startExecution('rb-1', 'engineer');
      if (exec) {
        const result = manager.recordStepCompletion(exec.id, 'step-1', 'All OK');
        expect(result).toBe(true);
      }
    });

    test('should record step failure', () => {
      const runbook: Runbook = {
        id: 'rb-1',
        name: 'High Latency',
        description: 'Response to high latency',
        trigger: 'high_latency',
        severity: 'high',
        owner: 'platform',
        steps: [
          {
            id: 'step-1',
            title: 'Check',
            description: 'Check status',
            type: 'verify',
            failureOptions: ['step-fallback'],
          },
          {
            id: 'step-fallback',
            title: 'Fallback',
            description: 'Fallback action',
            type: 'execute',
          },
        ],
        estimatedDuration: 300000,
        createdAt: new Date(),
        updatedAt: new Date(),
        version: 1,
        tags: [],
      };
      manager.registerRunbook(runbook);
      const exec = manager.startExecution('rb-1', 'engineer');
      if (exec) {
        const result = manager.recordStepFailure(exec.id, 'step-1', 'Check failed');
        expect(result).toBe(true);
      }
    });

    test('should pause/resume execution', () => {
      const runbook: Runbook = {
        id: 'rb-1',
        name: 'High Latency',
        description: 'Response to high latency',
        trigger: 'high_latency',
        severity: 'high',
        owner: 'platform',
        steps: [],
        estimatedDuration: 300000,
        createdAt: new Date(),
        updatedAt: new Date(),
        version: 1,
        tags: [],
      };
      manager.registerRunbook(runbook);
      const exec = manager.startExecution('rb-1', 'engineer');
      if (exec) {
        manager.pauseExecution(exec.id);
        expect(manager.getExecution(exec.id)?.status).toBe('paused');
        manager.resumeExecution(exec.id);
        expect(manager.getExecution(exec.id)?.status).toBe('running');
      }
    });

    test('should get execution history', () => {
      const runbook: Runbook = {
        id: 'rb-1',
        name: 'High Latency',
        description: 'Response to high latency',
        trigger: 'high_latency',
        severity: 'high',
        owner: 'platform',
        steps: [],
        estimatedDuration: 300000,
        createdAt: new Date(),
        updatedAt: new Date(),
        version: 1,
        tags: [],
      };
      manager.registerRunbook(runbook);
      manager.startExecution('rb-1', 'engineer');
      const history = manager.getExecutionHistory('rb-1');
      expect(Array.isArray(history)).toBe(true);
    });
  });

  describe('IncidentResponseManager', () => {
    let manager: IncidentResponseManager;

    beforeEach(() => {
      manager = new IncidentResponseManager();
    });

    test('should create incident', () => {
      const incident = manager.createIncident('High Latency', 'API latency spike', 'high', ['api']);
      expect(incident).toBeDefined();
      expect(incident.severity).toBe('high');
      expect(incident.status).toBe('new');
    });

    test('should acknowledge incident', () => {
      const incident = manager.createIncident('High Latency', 'API latency spike', 'high', ['api']);
      const updated = manager.acknowledgeIncident(incident.id, 'engineer');
      expect(updated?.status).toBe('acknowledged');
    });

    test('should update incident status', () => {
      const incident = manager.createIncident('High Latency', 'API latency spike', 'high', ['api']);
      manager.updateStatus(incident.id, 'investigating', 'engineer');
      const updated = manager.getIncident(incident.id);
      expect(updated?.status).toBe('investigating');
    });

    test('should add root cause', () => {
      const incident = manager.createIncident('High Latency', 'API latency spike', 'high', ['api']);
      manager.addRootCause(incident.id, 'Database connection pool exhaustion', 'engineer');
      const updated = manager.getIncident(incident.id);
      expect(updated?.rootCause).toBe('Database connection pool exhaustion');
    });

    test('should resolve incident', () => {
      const incident = manager.createIncident('High Latency', 'API latency spike', 'high', ['api']);
      const resolved = manager.resolveIncident(incident.id, 'Scaled up database', 'engineer', 'Pool exhaustion');
      expect(resolved?.status).toBe('resolved');
      expect(resolved?.resolution).toBe('Scaled up database');
    });

    test('should get active incidents', () => {
      manager.createIncident('Incident 1', 'Description', 'high', ['api']);
      manager.createIncident('Incident 2', 'Description', 'medium', ['db']);
      const active = manager.getActiveIncidents();
      expect(active.length).toBe(2);
    });

    test('should list incidents with filters', () => {
      manager.createIncident('Incident 1', 'Description', 'high', ['api']);
      manager.createIncident('Incident 2', 'Description', 'low', ['db']);
      const filtered = manager.listIncidents({ severity: 'high' });
      expect(filtered.length).toBe(1);
    });

    test('should get incident metrics', () => {
      manager.createIncident('Incident 1', 'Description', 'critical', ['api']);
      const metrics = manager.getIncidents();
      expect(metrics.totalIncidents).toBe(1);
      expect(metrics.criticalIncidents).toBe(1);
    });

    test('should set escalation chain', () => {
      const chain = ['oncall', 'manager', 'director'];
      manager.setEscalationChain(chain);
      expect(manager.getEscalationChain()).toEqual(chain);
    });
  });

  describe('ProductionReadinessPhase9Agent', () => {
    let agent: ProductionReadinessPhase9Agent;

    beforeEach(() => {
      agent = new ProductionReadinessPhase9Agent({}, 'production');
    });

    test('should register SLO', () => {
      const slo: SLO = {
        name: 'api-slo',
        description: 'API availability SLO',
        service: 'api',
        slis: [
          {
            name: 'availability',
            description: 'Availability %',
            type: 'availability',
            unit: '%',
            threshold: 99.9,
            window: 86400000,
          },
        ],
        targetPercentage: 99.9,
        errorBudget: 1000,
        period: 30,
        version: 1,
        tags: [],
      };
      agent.registerSLO(slo);
      expect(agent.getSLOStatus('api-slo')).toBeDefined();
    });

    test('should record metrics', () => {
      const slo: SLO = {
        name: 'api-slo',
        description: 'API availability SLO',
        service: 'api',
        slis: [
          {
            name: 'availability',
            description: 'Availability %',
            type: 'availability',
            unit: '%',
            threshold: 99.9,
            window: 86400000,
          },
        ],
        targetPercentage: 99.9,
        errorBudget: 1000,
        period: 30,
        version: 1,
        tags: [],
      };
      agent.registerSLO(slo);
      agent.recordMetric('api-slo', 'availability', 99.95);
      expect(agent.getSLOStatus('api-slo')?.overallPercentage).toBeGreaterThan(0);
    });

    test('should register runbook', () => {
      const runbook: Runbook = {
        id: 'rb-1',
        name: 'High Latency',
        description: 'Response to high latency',
        trigger: 'high_latency',
        severity: 'high',
        owner: 'platform',
        steps: [],
        estimatedDuration: 300000,
        createdAt: new Date(),
        updatedAt: new Date(),
        version: 1,
        tags: [],
      };
      agent.registerRunbook(runbook);
      const runbooks = agent.getRunbooksByTrigger('high_latency');
      expect(runbooks.length).toBe(1);
    });

    test('should create incident', () => {
      const incident = agent.createIncident('High Latency', 'Latency spike', 'high', ['api']);
      expect(incident).toBeDefined();
      expect(incident.severity).toBe('high');
    });

    test('should acknowledge incident', () => {
      const incident = agent.createIncident('High Latency', 'Latency spike', 'high', ['api']);
      const ack = agent.acknowledgeIncident(incident.id, 'engineer');
      expect(ack?.status).toBe('acknowledged');
    });

    test('should resolve incident', () => {
      const incident = agent.createIncident('High Latency', 'Latency spike', 'high', ['api']);
      const resolved = agent.resolveIncident(incident.id, 'Scaled up', 'engineer', 'Pool exhaustion');
      expect(resolved?.status).toBe('resolved');
    });

    test('should get active incidents', () => {
      agent.createIncident('Incident 1', 'Description', 'high', ['api']);
      agent.createIncident('Incident 2', 'Description', 'medium', ['db']);
      const active = agent.getActiveIncidents();
      expect(active.length).toBe(2);
    });

    test('should get production status', () => {
      const status = agent.getProductionStatus();
      expect(status).toBeDefined();
      expect(status.overallHealth).toMatch(/healthy|degraded|unhealthy/);
      expect(status.sloCompliance).toBeGreaterThanOrEqual(0);
      expect(status.activeIncidents).toBeGreaterThanOrEqual(0);
    });

    test('should get comprehensive status report', () => {
      const report = agent.getStatusReport();
      expect(report).toHaveProperty('production');
      expect(report).toHaveProperty('slos');
      expect(report).toHaveProperty('incidents');
      expect(report).toHaveProperty('runbooks');
    });

    test('should perform health check', async () => {
      const check = await agent.healthCheck();
      expect(check).toHaveProperty('status');
      expect(check).toHaveProperty('checks');
      expect(check.status).toMatch(/healthy|degraded|unhealthy/);
    });

    test('should execute agent actions', async () => {
      const slo: SLO = {
        name: 'api-slo',
        description: 'API availability SLO',
        service: 'api',
        slis: [
          {
            name: 'availability',
            description: 'Availability %',
            type: 'availability',
            unit: '%',
            threshold: 99.9,
            window: 86400000,
          },
        ],
        targetPercentage: 99.9,
        errorBudget: 1000,
        period: 30,
        version: 1,
        tags: [],
      };
      const status = await agent.execute({
        action: 'registerSLO',
        slo,
      });
      expect(status).toBeDefined();
      expect(status.overallHealth).toBeDefined();
    });
  });
});
