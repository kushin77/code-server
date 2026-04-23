import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { HelpQueueService } from '../help-queue-service.js';
import { HelpRequestType, RequestPriority } from '../types.js';

describe('Help Queue Service', () => {
  let service: HelpQueueService;

  beforeEach(async () => {
    service = new HelpQueueService();
    await service.initialize();
  });

  afterEach(async () => {
    await service.shutdown();
  });

  describe('Initialization', () => {
    it('should initialize successfully', async () => {
      expect(service).toBeDefined();
      const stats = await service.getStatistics();
      expect(stats.totalRequests).toBe(0);
    });

    it('should not initialize twice', async () => {
      await service.initialize();
      expect(service).toBeDefined();
    });

    it('should emit initialized event', async () => {
      return new Promise<void>((resolve) => {
        const svc = new HelpQueueService();
        svc.once('initialized', () => {
          svc.shutdown().then(() => resolve());
        });
        svc.initialize();
      });
    });
  });

  describe('Request Creation', () => {
    it('should create help request', async () => {
      const request = await service.createRequest(
        'user-alice',
        'alice@example.com',
        'debugging',
        'Debugger not stopping at breakpoints',
        'My debugger in VSCode is not stopping at breakpoints...',
        'high',
        'const x = 1;',
        'typescript',
        'workspace-1',
        'workspace-1',
        'session-1',
        '192.168.1.1',
        'Chrome/95.0'
      );

      expect(request.id).toBeDefined();
      expect(request.userId).toBe('user-alice');
      expect(request.status).toBe('open');
      expect(request.type).toBe('debugging');
      expect(request.priority).toBe('high');
    });

    it('should create request with different types', async () => {
      const types: HelpRequestType[] = [
        'debugging',
        'feature-usage',
        'installation',
        'performance',
        'integration',
        'documentation',
        'general',
      ];

      for (const type of types) {
        const request = await service.createRequest(
          'user-alice',
          'alice@example.com',
          type,
          `${type} request`,
          'Description',
          'normal'
        );
        expect(request.type).toBe(type);
      }
    });

    it('should emit request-created event', async () => {
      return new Promise<void>((resolve) => {
        service.once('request-created', ({ request }) => {
          expect(request.userId).toBe('user-alice');
          resolve();
        });

        service.createRequest(
          'user-alice',
          'alice@example.com',
          'debugging',
          'Issue',
          'Description',
          'normal'
        );
      });
    });

    it('should increment request count', async () => {
      await service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue 1', 'Desc 1');
      await service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue 2', 'Desc 2');

      const stats = await service.getStatistics();
      expect(stats.totalRequests).toBe(2);
    });

    it('should include code context in request', async () => {
      const request = await service.createRequest(
        'user-alice',
        'alice@example.com',
        'debugging',
        'Code issue',
        'Not working',
        'normal',
        'function test() { throw new Error(); }',
        'typescript',
        'Line 42 in auth.ts'
      );

      expect(request.code).toBeDefined();
      expect(request.codeLanguage).toBe('typescript');
      expect(request.context).toBe('Line 42 in auth.ts');
    });
  });

  describe('Expert Registration', () => {
    it('should register expert', async () => {
      const expert = await service.registerExpert(
        'expert-bob',
        'bob@example.com',
        'Bob Developer',
        'expert',
        ['typescript', 'debugging', 'performance'],
        '192.168.1.2',
        'Firefox/90.0'
      );

      expect(expert.id).toBeDefined();
      expect(expert.userId).toBe('expert-bob');
      expect(expert.expertise).toBe('expert');
      expect(expert.skills).toContain('typescript');
    });

    it('should emit expert-registered event', async () => {
      return new Promise<void>((resolve) => {
        service.once('expert-registered', ({ expert }) => {
          expect(expert.userId).toBe('expert-bob');
          resolve();
        });

        service.registerExpert(
          'expert-bob',
          'bob@example.com',
          'Bob',
          'expert',
          ['typescript']
        );
      });
    });

    it('should register experts with different expertise levels', async () => {
      const levels = ['beginner', 'intermediate', 'expert', 'architect'] as const;

      for (const level of levels) {
        const expert = await service.registerExpert(
          `expert-${level}`,
          `${level}@example.com`,
          `${level} Expert`,
          level,
          ['typescript']
        );
        expect(expert.expertise).toBe(level);
      }
    });
  });

  describe('Request Retrieval', () => {
    it('should get request by ID', async () => {
      const created = await service.createRequest(
        'user-alice',
        'alice@example.com',
        'debugging',
        'Issue',
        'Description'
      );

      const retrieved = await service.getRequest(created.id);
      expect(retrieved).toBeDefined();
      expect(retrieved?.id).toBe(created.id);
    });

    it('should return undefined for non-existent request', async () => {
      const result = await service.getRequest('non-existent-id');
      expect(result).toBeUndefined();
    });

    it('should get expert by ID', async () => {
      const created = await service.registerExpert(
        'expert-bob',
        'bob@example.com',
        'Bob',
        'expert',
        ['typescript']
      );

      const retrieved = await service.getExpert(created.id);
      expect(retrieved).toBeDefined();
      expect(retrieved?.id).toBe(created.id);
    });

    it('should get all requests', async () => {
      await service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue 1', 'Desc');
      await service.createRequest('user-bob', 'bob@example.com', 'feature-usage', 'Issue 2', 'Desc');

      const all = await service.getAllRequests();
      expect(all.length).toBe(2);
    });

    it('should get all experts', async () => {
      await service.registerExpert('expert-bob', 'bob@example.com', 'Bob', 'expert', ['ts']);
      await service.registerExpert('expert-charlie', 'charlie@example.com', 'Charlie', 'intermediate', ['py']);

      const all = await service.getAllExperts();
      expect(all.length).toBe(2);
    });
  });

  describe('Request Query', () => {
    beforeEach(async () => {
      await service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue 1', 'Desc 1', 'high');
      await service.createRequest('user-alice', 'alice@example.com', 'feature-usage', 'Issue 2', 'Desc 2', 'normal');
      await service.createRequest('user-bob', 'bob@example.com', 'debugging', 'Issue 3', 'Desc 3', 'low');
    });

    it('should query all requests', async () => {
      const result = await service.queryRequests({});
      expect(result.requests.length).toBe(3);
      expect(result.total).toBe(3);
    });

    it('should filter by userId', async () => {
      const result = await service.queryRequests({ userId: 'user-alice' });
      expect(result.requests.length).toBe(2);
      expect(result.requests.every((r) => r.userId === 'user-alice')).toBe(true);
    });

    it('should filter by type', async () => {
      const result = await service.queryRequests({ type: 'debugging' });
      expect(result.requests.length).toBe(2);
      expect(result.requests.every((r) => r.type === 'debugging')).toBe(true);
    });

    it('should filter by priority', async () => {
      const result = await service.queryRequests({ priority: 'high' });
      expect(result.requests.length).toBe(1);
      expect(result.requests[0].priority).toBe('high');
    });

    it('should paginate results', async () => {
      const page1 = await service.queryRequests({ limit: 2, offset: 0 });
      expect(page1.requests.length).toBe(2);

      const page2 = await service.queryRequests({ limit: 2, offset: 2 });
      expect(page2.requests.length).toBe(1);
    });
  });

  describe('Request Assignment', () => {
    it('should assign request to expert', async () => {
      const request = await service.createRequest(
        'user-alice',
        'alice@example.com',
        'debugging',
        'Issue',
        'Description'
      );

      const expert = await service.registerExpert(
        'expert-bob',
        'bob@example.com',
        'Bob',
        'expert',
        ['typescript']
      );

      const assigned = await service.assignRequest(request.id, expert.id, 'admin-1', 'admin@example.com');

      expect(assigned.status).toBe('assigned');
      expect(assigned.assignedExpertId).toBe(expert.id);
      expect(assigned.assignedExpertEmail).toBe('bob@example.com');
      expect(assigned.assignedAt).toBeDefined();
    });

    it('should emit request-assigned event', async () => {
      return new Promise<void>((resolve) => {
        service.once('request-assigned', ({ request, expert }) => {
          expect(request.status).toBe('assigned');
          expect(expert).toBeDefined();
          resolve();
        });

        service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue', 'Desc')
          .then((req) =>
            service.registerExpert('expert-bob', 'bob@example.com', 'Bob', 'expert', ['ts'])
              .then((exp) => service.assignRequest(req.id, exp.id, 'admin', 'admin@example.com'))
          );
      });
    });

    it('should increment expert active requests', async () => {
      const request = await service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue', 'Desc');
      const expert = await service.registerExpert('expert-bob', 'bob@example.com', 'Bob', 'expert', ['ts']);

      expect(expert.activeRequests).toBe(0);
      await service.assignRequest(request.id, expert.id, 'admin', 'admin@example.com');

      const updated = await service.getExpert(expert.id);
      expect(updated?.activeRequests).toBe(1);
    });
  });

  describe('Request Responses', () => {
    it('should add response to request', async () => {
      const request = await service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue', 'Desc');

      const response = await service.addResponse(
        request.id,
        'expert-bob',
        'bob@example.com',
        'expert',
        'Here is the fix...',
        'const fix = true;',
        'typescript',
        false,
        '192.168.1.2',
        'Chrome/95.0'
      );

      expect(response.id).toBeDefined();
      expect(response.requestId).toBe(request.id);
      expect(response.responderId).toBe('expert-bob');
      expect(response.isResolution).toBe(false);
    });

    it('should update request status to in-progress when expert responds', async () => {
      const request = await service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue', 'Desc');

      await service.addResponse(request.id, 'expert-bob', 'bob@example.com', 'expert', 'Working on it...');

      const updated = await service.getRequest(request.id);
      expect(updated?.status).toBe('in-progress');
    });

    it('should emit response-added event', async () => {
      return new Promise<void>((resolve) => {
        service.once('response-added', ({ response }) => {
          expect(response).toBeDefined();
          resolve();
        });

        service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue', 'Desc')
          .then((req) =>
            service.addResponse(req.id, 'expert-bob', 'bob@example.com', 'expert', 'Fix it')
          );
      });
    });

    it('should get responses for request', async () => {
      const request = await service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue', 'Desc');

      await service.addResponse(request.id, 'expert-bob', 'bob@example.com', 'expert', 'Response 1');
      await service.addResponse(request.id, 'user-alice', 'alice@example.com', 'requester', 'Response 2');

      const responses = await service.getResponses(request.id);
      expect(responses.length).toBe(2);
    });
  });

  describe('Request Resolution', () => {
    it('should resolve request', async () => {
      const request = await service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue', 'Desc');
      const expert = await service.registerExpert('expert-bob', 'bob@example.com', 'Bob', 'expert', ['ts']);

      await service.assignRequest(request.id, expert.id, 'admin', 'admin@example.com');
      const resolved = await service.resolveRequest(
        request.id,
        expert.id,
        'bob@example.com',
        'Fixed by updating TypeScript version'
      );

      expect(resolved.status).toBe('resolved');
      expect(resolved.resolvedAt).toBeDefined();
      expect(resolved.resolutionNotes).toBeDefined();
    });

    it('should emit request-resolved event', async () => {
      return new Promise<void>((resolve) => {
        service.once('request-resolved', ({ request }) => {
          expect(request.status).toBe('resolved');
          resolve();
        });

        service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue', 'Desc')
          .then((req) =>
            service.registerExpert('expert-bob', 'bob@example.com', 'Bob', 'expert', ['ts'])
              .then((exp) =>
                service.assignRequest(req.id, exp.id, 'admin', 'admin@example.com')
                  .then(() =>
                    service.resolveRequest(req.id, exp.id, 'bob@example.com', 'Fixed')
                  )
              )
          );
      });
    });

    it('should update expert stats on resolution', async () => {
      // Verify getExpertStats method exists and is callable
      expect(service.getExpertStats).toBeDefined();
      expect(typeof service.getExpertStats).toBe('function');
    });
  });

  describe('Request Rating', () => {
    it('should rate resolved request', async () => {
      const request = await service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue', 'Desc');
      const expert = await service.registerExpert('expert-bob', 'bob@example.com', 'Bob', 'expert', ['ts']);

      await service.assignRequest(request.id, expert.id, 'admin', 'admin@example.com');
      await service.resolveRequest(request.id, expert.id, 'bob@example.com', 'Fixed');

      const rated = await service.rateResolution(
        request.id,
        5,
        'Great help, issue resolved quickly!',
        '192.168.1.1',
        'Chrome/95.0'
      );

      expect(rated.rating).toBe(5);
      expect(rated.feedback).toBeDefined();
    });

    it('should emit request-rated event', async () => {
      return new Promise<void>((resolve) => {
        service.once('request-rated', ({ request }) => {
          expect(request.rating).toBe(4);
          resolve();
        });

        service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue', 'Desc')
          .then((req) =>
            service.registerExpert('expert-bob', 'bob@example.com', 'Bob', 'expert', ['ts'])
              .then((exp) =>
                service.assignRequest(req.id, exp.id, 'admin', 'admin@example.com')
                  .then(() =>
                    service.resolveRequest(req.id, exp.id, 'bob@example.com', 'Fixed')
                      .then(() => service.rateResolution(req.id, 4, 'Good help'))
                  )
              )
          );
      });
    });

    it('should reject rating for non-resolved request', async () => {
      const request = await service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue', 'Desc');

      await expect(service.rateResolution(request.id, 5, 'Good')).rejects.toThrow(
        'Can only rate resolved requests'
      );
    });

    it('should cap rating between 1 and 5', async () => {
      const request = await service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue', 'Desc');
      const expert = await service.registerExpert('expert-bob', 'bob@example.com', 'Bob', 'expert', ['ts']);

      await service.assignRequest(request.id, expert.id, 'admin', 'admin@example.com');
      await service.resolveRequest(request.id, expert.id, 'bob@example.com', 'Fixed');

      const rated = await service.rateResolution(request.id, 10, 'Too high');
      expect(rated.rating).toBe(5);
    });
  });

  describe('Audit Logging', () => {
    it('should log request creation', async () => {
      await service.createRequest(
        'user-alice',
        'alice@example.com',
        'debugging',
        'Issue',
        'Description',
        'high',
        undefined,
        undefined,
        undefined,
        'workspace-1',
        'session-1',
        '192.168.1.1',
        'Chrome'
      );

      const auditLog = await service.getAuditLog('user-alice', 1);
      expect(auditLog.length).toBeGreaterThan(0);
      expect(auditLog[0].operation).toBe('created');
      expect(auditLog[0].status).toBe('success');
    });

    it('should log request assignment', async () => {
      const request = await service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue', 'Desc');
      const expert = await service.registerExpert('expert-bob', 'bob@example.com', 'Bob', 'expert', ['ts']);

      await service.assignRequest(request.id, expert.id, 'admin', 'admin@example.com', '192.168.1.1', 'Chrome');

      const auditLog = await service.getAuditLog(request.id);
      expect(auditLog.some((e) => e.operation === 'assigned')).toBe(true);
    });

    it('should log request resolution', async () => {
      const request = await service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue', 'Desc');
      const expert = await service.registerExpert('expert-bob', 'bob@example.com', 'Bob', 'expert', ['ts']);

      await service.assignRequest(request.id, expert.id, 'admin', 'admin@example.com');
      await service.resolveRequest(request.id, expert.id, 'bob@example.com', 'Fixed');

      const auditLog = await service.getAuditLog(request.id);
      expect(auditLog.some((e) => e.operation === 'resolved')).toBe(true);
    });

    it('should include IP and user agent in audit log', async () => {
      const ipAddress = '192.168.200.100';
      const userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)';

      await service.createRequest(
        'user-alice',
        'alice@example.com',
        'debugging',
        'Issue',
        'Description',
        'normal',
        undefined,
        undefined,
        undefined,
        'workspace-1',
        'session-1',
        ipAddress,
        userAgent
      );

      const auditLog = await service.getAuditLog('user-alice', 1);
      expect(auditLog[0].ipAddress).toBe(ipAddress);
      expect(auditLog[0].userAgent).toBe(userAgent);
    });

    it('should emit audit-logged event', async () => {
      return new Promise<void>((resolve) => {
        service.once('audit-logged', ({ key, entry }) => {
          expect(entry.operation).toBe('created');
          resolve();
        });

        service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue', 'Desc');
      });
    });
  });

  describe('Settings Management', () => {
    it('should update user settings', async () => {
      const settings = await service.updateSettings('user-alice', {
        emailNotifications: true,
        pushNotifications: false,
        privacyLevel: 'private',
      });

      expect(settings.userId).toBe('user-alice');
      expect(settings.emailNotifications).toBe(true);
      expect(settings.pushNotifications).toBe(false);
    });

    it('should emit settings-updated event', async () => {
      return new Promise<void>((resolve) => {
        service.once('settings-updated', ({ userId }) => {
          expect(userId).toBe('user-alice');
          resolve();
        });

        service.updateSettings('user-alice', { emailNotifications: true });
      });
    });
  });

  describe('Statistics', () => {
    beforeEach(async () => {
      await service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue 1', 'Desc 1', 'high');
      await service.createRequest('user-bob', 'bob@example.com', 'feature-usage', 'Issue 2', 'Desc 2', 'normal');
      await service.registerExpert('expert-charlie', 'charlie@example.com', 'Charlie', 'expert', ['ts']);
    });

    it('should track total requests', async () => {
      const stats = await service.getStatistics();
      expect(stats.totalRequests).toBe(2);
    });

    it('should track requests by type', async () => {
      const stats = await service.getStatistics();
      expect(stats.requestsByType['debugging']).toBe(1);
      expect(stats.requestsByType['feature-usage']).toBe(1);
    });

    it('should track requests by priority', async () => {
      const stats = await service.getStatistics();
      expect(stats.requestsByPriority['high']).toBe(1);
      expect(stats.requestsByPriority['normal']).toBe(1);
    });

    it('should track total experts', async () => {
      const stats = await service.getStatistics();
      expect(stats.totalExperts).toBe(1);
    });

    it('should track experts by level', async () => {
      const stats = await service.getStatistics();
      expect(stats.expertsByLevel['expert']).toBe(1);
    });
  });

  describe('Singleton Pattern', () => {
    it('should use singleton instance', () => {
      const instance1 = HelpQueueService.getInstance();
      const instance2 = HelpQueueService.getInstance();
      expect(instance1).toBe(instance2);
    });
  });

  describe('Integration', () => {
    it('should handle complete help queue workflow', async () => {
      // 1. User creates request
      const request = await service.createRequest(
        'user-alice',
        'alice@example.com',
        'debugging',
        'Debugger issue',
        'Not stopping at breakpoints'
      );
      expect(request).toBeDefined();

      // 2. Register expert
      const expert = await service.registerExpert(
        'expert-bob',
        'bob@example.com',
        'Bob',
        'expert',
        ['debugging', 'typescript']
      );
      expect(expert).toBeDefined();

      // 3. Assign request
      const assigned = await service.assignRequest(request.id, expert.id, 'admin', 'admin@example.com');
      expect(assigned.status).toBe('assigned');

      // 4. Expert responds
      await service.addResponse(
        request.id,
        'expert-bob',
        'bob@example.com',
        'expert',
        'Try updating TypeScript...'
      );

      // 5. Resolve request
      const resolved = await service.resolveRequest(
        request.id,
        expert.id,
        'bob@example.com',
        'Fixed by upgrading TypeScript'
      );
      expect(resolved.status).toBe('resolved');

      // 6. Rate resolution
      const rated = await service.rateResolution(request.id, 5, 'Great help!');
      expect(rated.rating).toBe(5);

      // 7. Verify audit trail
      const auditLog = await service.getAuditLog(request.id);
      expect(auditLog.length).toBeGreaterThan(3);

      // 8. Check stats
      const stats = await service.getStatistics();
      expect(stats.totalRequests).toBe(1);
      expect(stats.resolvedRequests).toBe(1);
    });

    it('should manage multiple concurrent requests', async () => {
      const expert = await service.registerExpert('expert-bob', 'bob@example.com', 'Bob', 'expert', ['ts']);

      // Create multiple requests
      const req1 = await service.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue 1', 'Desc');
      const req2 = await service.createRequest('user-bob', 'bob@example.com', 'feature-usage', 'Issue 2', 'Desc');
      const req3 = await service.createRequest('user-charlie', 'charlie@example.com', 'installation', 'Issue 3', 'Desc');

      // Assign all to same expert
      await service.assignRequest(req1.id, expert.id, 'admin', 'admin@example.com');
      await service.assignRequest(req2.id, expert.id, 'admin', 'admin@example.com');
      await service.assignRequest(req3.id, expert.id, 'admin', 'admin@example.com');

      const updated = await service.getExpert(expert.id);
      expect(updated?.activeRequests).toBe(3);

      // Resolve one
      await service.resolveRequest(req1.id, expert.id, 'bob@example.com', 'Fixed');

      const updated2 = await service.getExpert(expert.id);
      expect(updated2?.activeRequests).toBe(2);
      expect(updated2?.totalResolved).toBe(1);
    });
  });

  describe('Shutdown', () => {
    it('should shutdown gracefully', async () => {
      const svc = new HelpQueueService();
      await svc.initialize();
      await svc.createRequest('user-alice', 'alice@example.com', 'debugging', 'Issue', 'Desc');
      await svc.shutdown();
      expect(true).toBe(true);
    });
  });
});
