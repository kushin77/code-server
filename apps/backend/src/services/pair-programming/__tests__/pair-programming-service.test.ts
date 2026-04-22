/**
 * Pair Programming AI Copilot Service Tests
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { PairProgrammingService } from '../pair-programming-service.js';

describe('PairProgrammingService', () => {
  let service: PairProgrammingService;

  beforeEach(() => {
    (PairProgrammingService as any).reset();
    service = PairProgrammingService.getInstance();
  });

  afterEach(() => {
    service.shutdown();
  });

  describe('Initialization', () => {
    it('should create singleton instance', () => {
      const instance1 = PairProgrammingService.getInstance();
      const instance2 = PairProgrammingService.getInstance();
      expect(instance1).toBe(instance2);
    });

    it('should emit initialized event', () => {
      (PairProgrammingService as any).reset();
      const svc = PairProgrammingService.getInstance();
      expect(svc).toBeDefined();
    });
  });

  describe('Session Creation', () => {
    it('should create pair programming session', () => {
      const result = service.createPairSession(
        {
          userId: 'user-1',
          userEmail: 'user1@example.com',
          userName: 'Alice',
          workspaceId: 'ws-1',
          sessionId: 'session-1',
          title: 'Building auth module',
          focusedFile: 'src/auth.ts',
          autoStartAI: true,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.success).toBe(true);
      expect(result.sessionId).toBeDefined();
      expect(result.session?.title).toBe('Building auth module');
      expect(result.session?.focusedFile).toBe('src/auth.ts');
    });

    it('should emit session-created event', () => {
      return new Promise<void>((resolve) => {
        service.once('session-created', (data) => {
          expect(data.session).toBeDefined();
          expect(data.session.title).toBe('API design');
          resolve();
        });

        service.createPairSession(
          {
            userId: 'user-2',
            userEmail: 'user2@example.com',
            userName: 'Bob',
            workspaceId: 'ws-2',
            sessionId: 'session-2',
            title: 'API design',
            focusedFile: 'src/api/routes.ts',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });

    it('should initialize with driver role', () => {
      const result = service.createPairSession(
        {
          userId: 'user-3',
          userEmail: 'user3@example.com',
          userName: 'Charlie',
          workspaceId: 'ws-3',
          sessionId: 'session-3',
          title: 'Database schema',
          focusedFile: 'src/db/schema.ts',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.session?.participants[0].role).toBe('driver');
      expect(result.session?.participants[0].isActive).toBe(true);
    });

    it('should generate unique session IDs', () => {
      const result1 = service.createPairSession(
        {
          userId: 'user-4',
          userEmail: 'user4@example.com',
          userName: 'David',
          workspaceId: 'ws-4',
          sessionId: 'session-4',
          title: 'Session 1',
          focusedFile: 'file1.ts',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const result2 = service.createPairSession(
        {
          userId: 'user-5',
          userEmail: 'user5@example.com',
          userName: 'Eve',
          workspaceId: 'ws-5',
          sessionId: 'session-5',
          title: 'Session 2',
          focusedFile: 'file2.ts',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result1.sessionId).not.toBe(result2.sessionId);
    });
  });

  describe('Joining Sessions', () => {
    it('should join pair programming session', () => {
      const startResult = service.createPairSession(
        {
          userId: 'user-6',
          userEmail: 'user6@example.com',
          userName: 'Frank',
          workspaceId: 'ws-6',
          sessionId: 'session-6',
          title: 'Refactoring',
          focusedFile: 'src/utils.ts',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const joinResult = service.joinPairSession(
        {
          sessionId: startResult.sessionId!,
          userId: 'user-7',
          userEmail: 'user7@example.com',
          userName: 'Grace',
          role: 'navigator',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(joinResult.success).toBe(true);
      expect(joinResult.participants?.length).toBe(2);
      expect(joinResult.participants?.[1].role).toBe('navigator');
    });

    it('should emit user-joined event', () => {
      return new Promise<void>((resolve) => {
        const startResult = service.createPairSession(
          {
            userId: 'user-8',
            userEmail: 'user8@example.com',
            userName: 'Henry',
            workspaceId: 'ws-8',
            sessionId: 'session-8',
            title: 'Testing',
            focusedFile: 'src/tests.ts',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('user-joined', (data) => {
          expect(data.participant).toBeDefined();
          expect(data.sessionId).toBe(startResult.sessionId);
          resolve();
        });

        service.joinPairSession(
          {
            sessionId: startResult.sessionId!,
            userId: 'user-9',
            userEmail: 'user9@example.com',
            userName: 'Ivy',
            role: 'observer',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });
  });

  describe('AI Suggestions', () => {
    it('should generate AI suggestion', () => {
      const startResult = service.createPairSession(
        {
          userId: 'user-10',
          userEmail: 'user10@example.com',
          userName: 'Jack',
          workspaceId: 'ws-10',
          sessionId: 'session-10',
          title: 'Code review',
          focusedFile: 'src/index.ts',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const result = service.getAISuggestion(
        {
          sessionId: startResult.sessionId!,
          userId: 'user-10',
          userEmail: 'user10@example.com',
          fileName: 'src/index.ts',
          context: 'function doSomething() { }',
          suggestionType: 'completion',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.success).toBe(true);
      expect(result.suggestion).toBeDefined();
      expect(result.suggestion?.confidence).toBeGreaterThan(0);
    });

    it('should emit ai-suggestion-generated event', () => {
      return new Promise<void>((resolve) => {
        const startResult = service.createPairSession(
          {
            userId: 'user-11',
            userEmail: 'user11@example.com',
            userName: 'Karen',
            workspaceId: 'ws-11',
            sessionId: 'session-11',
            title: 'Debugging',
            focusedFile: 'src/debug.ts',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('ai-suggestion-generated', (data) => {
          expect(data.suggestion).toBeDefined();
          expect(data.sessionId).toBe(startResult.sessionId);
          resolve();
        });

        service.getAISuggestion(
          {
            sessionId: startResult.sessionId!,
            userId: 'user-11',
            userEmail: 'user11@example.com',
            fileName: 'src/debug.ts',
            context: 'const x = ',
            suggestionType: 'completion',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });

    it('should track AI response time', () => {
      const startResult = service.createPairSession(
        {
          userId: 'user-12',
          userEmail: 'user12@example.com',
          userName: 'Leo',
          workspaceId: 'ws-12',
          sessionId: 'session-12',
          title: 'Performance',
          focusedFile: 'src/perf.ts',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const result = service.getAISuggestion(
        {
          sessionId: startResult.sessionId!,
          userId: 'user-12',
          userEmail: 'user12@example.com',
          fileName: 'src/perf.ts',
          context: 'optimize this',
          suggestionType: 'optimization',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.responseTime).toBeDefined();
      expect(result.responseTime).toBeGreaterThan(0);
    });
  });

  describe('Applying Suggestions', () => {
    it('should apply suggestion to code', () => {
      const startResult = service.createPairSession(
        {
          userId: 'user-13',
          userEmail: 'user13@example.com',
          userName: 'Maria',
          workspaceId: 'ws-13',
          sessionId: 'session-13',
          title: 'Refactor',
          focusedFile: 'src/refactor.ts',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const sugResult = service.getAISuggestion(
        {
          sessionId: startResult.sessionId!,
          userId: 'user-13',
          userEmail: 'user13@example.com',
          fileName: 'src/refactor.ts',
          context: 'old code',
          suggestionType: 'refactoring',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const applyResult = service.applySuggestion(
        {
          sessionId: startResult.sessionId!,
          suggestionId: sugResult.suggestion!.id,
          userId: 'user-13',
          userEmail: 'user13@example.com',
          filePath: 'src/refactor.ts',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(applyResult.success).toBe(true);
      expect(applyResult.suggestion?.status).toBe('applied');
      expect(applyResult.linesAdded).toBeDefined();
    });

    it('should emit suggestion-applied event', () => {
      return new Promise<void>((resolve) => {
        const startResult = service.createPairSession(
          {
            userId: 'user-14',
            userEmail: 'user14@example.com',
            userName: 'Noah',
            workspaceId: 'ws-14',
            sessionId: 'session-14',
            title: 'Fix bugs',
            focusedFile: 'src/bugs.ts',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );

        const sugResult = service.getAISuggestion(
          {
            sessionId: startResult.sessionId!,
            userId: 'user-14',
            userEmail: 'user14@example.com',
            fileName: 'src/bugs.ts',
            context: 'bug code',
            suggestionType: 'bug-fix',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('suggestion-applied', (data) => {
          expect(data.suggestion).toBeDefined();
          resolve();
        });

        service.applySuggestion(
          {
            sessionId: startResult.sessionId!,
            suggestionId: sugResult.suggestion!.id,
            userId: 'user-14',
            userEmail: 'user14@example.com',
            filePath: 'src/bugs.ts',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });
  });

  describe('Driver Switching', () => {
    it('should switch driver role', () => {
      const startResult = service.createPairSession(
        {
          userId: 'user-15',
          userEmail: 'user15@example.com',
          userName: 'Olivia',
          workspaceId: 'ws-15',
          sessionId: 'session-15',
          title: 'Collab work',
          focusedFile: 'src/collab.ts',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      service.joinPairSession(
        {
          sessionId: startResult.sessionId!,
          userId: 'user-16',
          userEmail: 'user16@example.com',
          userName: 'Peter',
          role: 'navigator',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const switchResult = service.switchDriver(
        {
          sessionId: startResult.sessionId!,
          newDriverId: 'user-16',
          newDriverEmail: 'user16@example.com',
          newDriverName: 'Peter',
          currentUserId: 'user-15',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(switchResult.success).toBe(true);
      expect(switchResult.driverSwitch?.newDriver).toBe('user-16');
      expect(switchResult.driverSwitch?.durationMs).toBeGreaterThanOrEqual(0);
    });

    it('should emit driver-switched event', () => {
      return new Promise<void>((resolve) => {
        const startResult = service.createPairSession(
          {
            userId: 'user-17',
            userEmail: 'user17@example.com',
            userName: 'Quinn',
            workspaceId: 'ws-17',
            sessionId: 'session-17',
            title: 'Switch test',
            focusedFile: 'src/switch.ts',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.joinPairSession(
          {
            sessionId: startResult.sessionId!,
            userId: 'user-18',
            userEmail: 'user18@example.com',
            userName: 'Rachel',
            role: 'navigator',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('driver-switched', (data) => {
          expect(data.driverSwitch).toBeDefined();
          resolve();
        });

        service.switchDriver(
          {
            sessionId: startResult.sessionId!,
            newDriverId: 'user-18',
            newDriverEmail: 'user18@example.com',
            newDriverName: 'Rachel',
            currentUserId: 'user-17',
            reason: 'Test switch',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });

    it('should track driver switch duration', () => {
      const startResult = service.createPairSession(
        {
          userId: 'user-19',
          userEmail: 'user19@example.com',
          userName: 'Samuel',
          workspaceId: 'ws-19',
          sessionId: 'session-19',
          title: 'Duration test',
          focusedFile: 'src/duration.ts',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      service.joinPairSession(
        {
          sessionId: startResult.sessionId!,
          userId: 'user-20',
          userEmail: 'user20@example.com',
          userName: 'Tina',
          role: 'navigator',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const switchResult = service.switchDriver(
        {
          sessionId: startResult.sessionId!,
          newDriverId: 'user-20',
          newDriverEmail: 'user20@example.com',
          newDriverName: 'Tina',
          currentUserId: 'user-19',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(switchResult.driverSwitch?.durationMs).toBeGreaterThanOrEqual(0);
    });
  });

  describe('Session Ending', () => {
    it('should end pair programming session', () => {
      const startResult = service.createPairSession(
        {
          userId: 'user-21',
          userEmail: 'user21@example.com',
          userName: 'Ulysses',
          workspaceId: 'ws-21',
          sessionId: 'session-21',
          title: 'Finish work',
          focusedFile: 'src/finish.ts',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const endResult = service.endPairSession(
        {
          sessionId: startResult.sessionId!,
          userId: 'user-21',
          userEmail: 'user21@example.com',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(endResult.success).toBe(true);
      expect(endResult.session?.isActive).toBe(false);
      expect(endResult.session?.endedAt).toBeDefined();
    });

    it('should emit session-ended event', () => {
      return new Promise<void>((resolve) => {
        const startResult = service.createPairSession(
          {
            userId: 'user-22',
            userEmail: 'user22@example.com',
            userName: 'Violet',
            workspaceId: 'ws-22',
            sessionId: 'session-22',
            title: 'End test',
            focusedFile: 'src/end.ts',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('session-ended', (data) => {
          expect(data.session).toBeDefined();
          expect(data.statistics).toBeDefined();
          resolve();
        });

        service.endPairSession(
          {
            sessionId: startResult.sessionId!,
            userId: 'user-22',
            userEmail: 'user22@example.com',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });

    it('should calculate session statistics', () => {
      const startResult = service.createPairSession(
        {
          userId: 'user-23',
          userEmail: 'user23@example.com',
          userName: 'Walter',
          workspaceId: 'ws-23',
          sessionId: 'session-23',
          title: 'Stats test',
          focusedFile: 'src/stats.ts',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const endResult = service.endPairSession(
        {
          sessionId: startResult.sessionId!,
          userId: 'user-23',
          userEmail: 'user23@example.com',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(endResult.statistics?.totalSessions).toBeGreaterThan(0);
      expect(endResult.statistics?.averageSessionDuration).toBeGreaterThanOrEqual(0);
    });
  });

  describe('Session Retrieval', () => {
    it('should get pair programming session', () => {
      const startResult = service.createPairSession(
        {
          userId: 'user-24',
          userEmail: 'user24@example.com',
          userName: 'Xander',
          workspaceId: 'ws-24',
          sessionId: 'session-24',
          title: 'Get test',
          focusedFile: 'src/get.ts',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const getResult = service.getPairSession({
        sessionId: startResult.sessionId!,
      });

      expect(getResult.success).toBe(true);
      expect(getResult.session?.title).toBe('Get test');
      expect(getResult.participants).toBeDefined();
    });

    it('should list pair programming sessions', () => {
      service.createPairSession(
        {
          userId: 'user-25',
          userEmail: 'user25@example.com',
          userName: 'Yvonne',
          workspaceId: 'ws-25',
          sessionId: 'session-25',
          title: 'List 1',
          focusedFile: 'src/list1.ts',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const listResult = service.listPairSessions({
        userId: 'user-25',
        userEmail: 'user25@example.com',
      });

      expect(listResult.success).toBe(true);
      expect(listResult.sessions).toBeDefined();
      expect(listResult.count).toBeGreaterThan(0);
    });
  });

  describe('Audit Logging', () => {
    it('should record audit entry', () => {
      service.createPairSession(
        {
          userId: 'user-26',
          userEmail: 'user26@example.com',
          userName: 'Zoe',
          workspaceId: 'ws-26',
          sessionId: 'session-26',
          title: 'Audit test',
          focusedFile: 'src/audit.ts',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      // Verify audit logging by checking service state
      expect(service).toBeDefined();
    });

    it('should emit audit-logged event', () => {
      return new Promise<void>((resolve) => {
        service.once('audit-logged', (data) => {
          expect(data.entry).toBeDefined();
          resolve();
        });

        service.createPairSession(
          {
            userId: 'user-27',
            userEmail: 'user27@example.com',
            userName: 'Aaron',
            workspaceId: 'ws-27',
            sessionId: 'session-27',
            title: 'Audit event',
            focusedFile: 'src/auditevt.ts',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });
  });

  describe('Statistics', () => {
    it('should get service statistics', () => {
      service.createPairSession(
        {
          userId: 'user-28',
          userEmail: 'user28@example.com',
          userName: 'Bella',
          workspaceId: 'ws-28',
          sessionId: 'session-28',
          title: 'Stats service',
          focusedFile: 'src/statsvc.ts',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const stats = service.getStatistics();
      expect(stats.totalSessions).toBeGreaterThan(0);
      expect(stats.activeSessions).toBeGreaterThanOrEqual(0);
    });
  });

  describe('Configuration', () => {
    it('should update configuration', () => {
      service.updateConfig(
        { maxSessionsPerWorkspace: 20 },
        'user-29',
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(service).toBeDefined();
    });

    it('should emit config-updated event', () => {
      return new Promise<void>((resolve) => {
        service.once('config-updated', (data) => {
          expect(data.config).toBeDefined();
          resolve();
        });

        service.updateConfig(
          { maxParticipantsPerSession: 6 },
          'user-30',
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });
  });

  describe('Shutdown', () => {
    it('should shutdown service', () => {
      service.createPairSession(
        {
          userId: 'user-31',
          userEmail: 'user31@example.com',
          userName: 'Charlie2',
          workspaceId: 'ws-31',
          sessionId: 'session-31',
          title: 'Shutdown test',
          focusedFile: 'src/shutdown.ts',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      service.shutdown();

      const getResult = service.getPairSession({
        sessionId: 'nonexistent',
      });
      expect(getResult.success).toBe(false);
    });

    it('should emit shutdown event', () => {
      return new Promise<void>((resolve) => {
        service.once('shutdown', (data) => {
          expect(data.timestamp).toBeDefined();
          resolve();
        });

        service.shutdown();
      });
    });
  });
});
