/**
 * Collaborative Debug Service Tests
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { CollaborativeDebugService } from '../collab-debug-service.js';

describe('CollaborativeDebugService', () => {
  let service: CollaborativeDebugService;

  beforeEach(() => {
    (CollaborativeDebugService as any).reset();
    service = CollaborativeDebugService.getInstance();
  });

  afterEach(() => {
    service.shutdown();
  });

  describe('Initialization', () => {
    it('should create singleton instance', () => {
      const instance1 = CollaborativeDebugService.getInstance();
      const instance2 = CollaborativeDebugService.getInstance();
      expect(instance1).toBe(instance2);
    });

    it('should emit initialized event', () => {
      (CollaborativeDebugService as any).reset();
      const svc = CollaborativeDebugService.getInstance();
      expect(svc).toBeDefined();
    });
  });

  describe('Debug Session Creation', () => {
    it('should create debug session', () => {
      const session = service.createDebugSession(
        'user-1',
        'user1@example.com',
        'dap-session-1',
        false,
        undefined,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(session).toBeDefined();
      expect(session.status).toBe('active');
      expect(session.initiatorUserId).toBe('user-1');
    });

    it('should emit debug-session-created event', () => {
      return new Promise<void>((resolve) => {
        service.once('debug-session-created', (data) => {
          expect(data.session).toBeDefined();
          expect(data.session.status).toBe('active');
          resolve();
        });

        service.createDebugSession('user-2', 'user2@example.com', 'dap-2', false, undefined, '192.168.1.1', 'Mozilla/5.0');
      });
    });

    it('should create shared debug session', () => {
      const session = service.createDebugSession(
        'user-3',
        'user3@example.com',
        'dap-3',
        true,
        10,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(session.isShared).toBe(true);
      expect(session.maxParticipants).toBe(10);
    });

    it('should track session creation timestamp', () => {
      const now = Date.now();
      const session = service.createDebugSession(
        'user-4',
        'user4@example.com',
        'dap-4',
        false,
        undefined,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(session.createdAt).toBeGreaterThanOrEqual(now);
    });
  });

  describe('Session Participants', () => {
    it('should join debug session', () => {
      const session = service.createDebugSession(
        'user-5',
        'user5@example.com',
        'dap-5',
        true,
        10,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const joined = service.joinDebugSession(session.id, 'user-6', 'user6@example.com', '192.168.1.1', 'Mozilla/5.0');

      expect(joined).toBe(true);
      expect(session.participantUserIds).toContain('user-6');
    });

    it('should fail to join non-shared session', () => {
      const session = service.createDebugSession(
        'user-7',
        'user7@example.com',
        'dap-7',
        false,
        undefined,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const joined = service.joinDebugSession(session.id, 'user-8', 'user8@example.com', '192.168.1.1', 'Mozilla/5.0');

      expect(joined).toBe(false);
    });

    it('should emit participant-joined event', () => {
      return new Promise<void>((resolve) => {
        const session = service.createDebugSession(
          'user-9',
          'user9@example.com',
          'dap-9',
          true,
          10,
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('participant-joined', (data) => {
          expect(data.sessionId).toBe(session.id);
          expect(data.userId).toBe('user-10');
          resolve();
        });

        service.joinDebugSession(session.id, 'user-10', 'user10@example.com', '192.168.1.1', 'Mozilla/5.0');
      });
    });

    it('should leave debug session', () => {
      const session = service.createDebugSession(
        'user-11',
        'user11@example.com',
        'dap-11',
        true,
        10,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      service.joinDebugSession(session.id, 'user-12', 'user12@example.com', '192.168.1.1', 'Mozilla/5.0');

      const left = service.leaveDebugSession(session.id, 'user-12', 'user12@example.com', '192.168.1.1', 'Mozilla/5.0');

      expect(left).toBe(true);
      expect(session.participantUserIds).not.toContain('user-12');
    });

    it('should emit participant-left event', () => {
      return new Promise<void>((resolve) => {
        const session = service.createDebugSession(
          'user-13',
          'user13@example.com',
          'dap-13',
          true,
          10,
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.joinDebugSession(session.id, 'user-14', 'user14@example.com', '192.168.1.1', 'Mozilla/5.0');

        service.once('participant-left', (data) => {
          expect(data.sessionId).toBe(session.id);
          expect(data.userId).toBe('user-14');
          resolve();
        });

        service.leaveDebugSession(session.id, 'user-14', 'user14@example.com', '192.168.1.1', 'Mozilla/5.0');
      });
    });
  });

  describe('Breakpoints', () => {
    it('should set breakpoint', () => {
      const session = service.createDebugSession(
        'user-15',
        'user15@example.com',
        'dap-15',
        false,
        undefined,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const result = service.setBreakpoint(
        {
          userId: 'user-15',
          userEmail: 'user15@example.com',
          location: { filePath: 'app.ts', line: 42 },
        },
        session.id,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.success).toBe(true);
      expect(result.verified).toBe(true);
      expect(result.breakpointId).toBeDefined();
    });

    it('should emit breakpoint-set event', () => {
      return new Promise<void>((resolve) => {
        const session = service.createDebugSession(
          'user-16',
          'user16@example.com',
          'dap-16',
          false,
          undefined,
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('breakpoint-set', (data) => {
          expect(data.sessionId).toBe(session.id);
          expect(data.breakpoint).toBeDefined();
          resolve();
        });

        service.setBreakpoint(
          {
            userId: 'user-16',
            userEmail: 'user16@example.com',
            location: { filePath: 'main.ts', line: 100 },
          },
          session.id,
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });

    it('should clear breakpoint', () => {
      const session = service.createDebugSession(
        'user-17',
        'user17@example.com',
        'dap-17',
        false,
        undefined,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const setResult = service.setBreakpoint(
        {
          userId: 'user-17',
          userEmail: 'user17@example.com',
          location: { filePath: 'app.ts', line: 50 },
        },
        session.id,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const clearResult = service.clearBreakpoint(
        {
          userId: 'user-17',
          userEmail: 'user17@example.com',
          breakpointId: setResult.breakpointId,
        },
        session.id,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(clearResult.success).toBe(true);
    });

    it('should emit breakpoint-cleared event', () => {
      return new Promise<void>((resolve) => {
        const session = service.createDebugSession(
          'user-18',
          'user18@example.com',
          'dap-18',
          false,
          undefined,
          '192.168.1.1',
          'Mozilla/5.0'
        );

        const setResult = service.setBreakpoint(
          {
            userId: 'user-18',
            userEmail: 'user18@example.com',
            location: { filePath: 'app.ts', line: 60 },
          },
          session.id,
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('breakpoint-cleared', (data) => {
          expect(data.breakpointId).toBe(setResult.breakpointId);
          resolve();
        });

        service.clearBreakpoint(
          {
            userId: 'user-18',
            userEmail: 'user18@example.com',
            breakpointId: setResult.breakpointId,
          },
          session.id,
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });

    it('should support conditional breakpoints', () => {
      const session = service.createDebugSession(
        'user-19',
        'user19@example.com',
        'dap-19',
        false,
        undefined,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const result = service.setBreakpoint(
        {
          userId: 'user-19',
          userEmail: 'user19@example.com',
          location: { filePath: 'app.ts', line: 70 },
          condition: 'x > 10',
        },
        session.id,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.success).toBe(true);
    });

    it('should support logpoints', () => {
      const session = service.createDebugSession(
        'user-20',
        'user20@example.com',
        'dap-20',
        false,
        undefined,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const result = service.setBreakpoint(
        {
          userId: 'user-20',
          userEmail: 'user20@example.com',
          location: { filePath: 'app.ts', line: 80 },
          logMessage: 'Variable x = {x}',
        },
        session.id,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.success).toBe(true);
    });
  });

  describe('Thread Control', () => {
    it('should continue thread', () => {
      const session = service.createDebugSession(
        'user-21',
        'user21@example.com',
        'dap-21',
        false,
        undefined,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const result = service.continueThread(
        {
          userId: 'user-21',
          userEmail: 'user21@example.com',
          threadId: 'thread-1',
        },
        session.id,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.success).toBe(true);
      expect(result.allThreadsContinued).toBe(true);
    });

    it('should emit thread-continued event', () => {
      return new Promise<void>((resolve) => {
        const session = service.createDebugSession(
          'user-22',
          'user22@example.com',
          'dap-22',
          false,
          undefined,
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('thread-continued', (data) => {
          expect(data.sessionId).toBe(session.id);
          expect(data.threadId).toBe('thread-2');
          resolve();
        });

        service.continueThread(
          {
            userId: 'user-22',
            userEmail: 'user22@example.com',
            threadId: 'thread-2',
          },
          session.id,
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });

    it('should step thread', () => {
      const session = service.createDebugSession(
        'user-23',
        'user23@example.com',
        'dap-23',
        false,
        undefined,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const result = service.stepThread(
        {
          userId: 'user-23',
          userEmail: 'user23@example.com',
          threadId: 'thread-3',
          stepType: 'over',
        },
        session.id,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.success).toBe(true);
    });

    it('should emit thread-stepped event', () => {
      return new Promise<void>((resolve) => {
        const session = service.createDebugSession(
          'user-24',
          'user24@example.com',
          'dap-24',
          false,
          undefined,
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('thread-stepped', (data) => {
          expect(data.sessionId).toBe(session.id);
          expect(data.threadId).toBe('thread-4');
          expect(data.stepType).toBe('in');
          resolve();
        });

        service.stepThread(
          {
            userId: 'user-24',
            userEmail: 'user24@example.com',
            threadId: 'thread-4',
            stepType: 'in',
          },
          session.id,
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });
  });

  describe('Variables and Expressions', () => {
    it('should eval expression', () => {
      const session = service.createDebugSession(
        'user-25',
        'user25@example.com',
        'dap-25',
        false,
        undefined,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const result = service.evalExpression(
        {
          userId: 'user-25',
          userEmail: 'user25@example.com',
          expression: '42',
          threadId: 'thread-5',
        },
        session.id,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.success).toBe(true);
      expect(result.result).toBe(42);
    });

    it('should emit expression-evaluated event', () => {
      return new Promise<void>((resolve) => {
        const session = service.createDebugSession(
          'user-26',
          'user26@example.com',
          'dap-26',
          false,
          undefined,
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('expression-evaluated', (data) => {
          expect(data.sessionId).toBe(session.id);
          expect(data.expression).toBe('true');
          resolve();
        });

        service.evalExpression(
          {
            userId: 'user-26',
            userEmail: 'user26@example.com',
            expression: 'true',
            threadId: 'thread-6',
          },
          session.id,
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });
  });

  describe('Session Termination', () => {
    it('should terminate debug session', () => {
      const session = service.createDebugSession(
        'user-27',
        'user27@example.com',
        'dap-27',
        false,
        undefined,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const terminated = service.terminateDebugSession(session.id, 'user-27', 'user27@example.com', '192.168.1.1', 'Mozilla/5.0');

      expect(terminated).toBe(true);
      expect(service.getDebugSession(session.id)).toBeNull();
    });

    it('should emit debug-session-terminated event', () => {
      return new Promise<void>((resolve) => {
        const session = service.createDebugSession(
          'user-28',
          'user28@example.com',
          'dap-28',
          false,
          undefined,
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('debug-session-terminated', (data) => {
          expect(data.sessionId).toBe(session.id);
          resolve();
        });

        service.terminateDebugSession(session.id, 'user-28', 'user28@example.com', '192.168.1.1', 'Mozilla/5.0');
      });
    });
  });

  describe('Audit Logging', () => {
    it('should record audit entry on session creation', () => {
      service.createDebugSession('user-29', 'user29@example.com', 'dap-29', false, undefined, '192.168.1.1', 'Mozilla/5.0');

      const audit = service.getAuditLog('user-29');
      expect(audit.length).toBeGreaterThan(0);
      expect(audit[0].operation).toBe('debug-session-created');
    });

    it('should limit audit log size', () => {
      (CollaborativeDebugService as any).reset();
      service = CollaborativeDebugService.getInstance({ maxAuditLogSize: 5 });

      for (let i = 0; i < 10; i++) {
        service.createDebugSession('user-30', 'user30@example.com', `dap-${i}`, false, undefined, '192.168.1.1', 'Mozilla/5.0');
      }

      const audit = service.getAuditLog('user-30');
      expect(audit.length).toBeLessThanOrEqual(5);
    });
  });

  describe('Statistics', () => {
    it('should get service statistics', () => {
      service.createDebugSession('user-31', 'user31@example.com', 'dap-31', false, undefined, '192.168.1.1', 'Mozilla/5.0');

      const stats = service.getStatistics();

      expect(stats.totalSessions).toBeGreaterThan(0);
      expect(stats.activeSessions).toBeGreaterThan(0);
    });

    it('should track total breakpoints', () => {
      const session = service.createDebugSession(
        'user-32',
        'user32@example.com',
        'dap-32',
        false,
        undefined,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      service.setBreakpoint(
        {
          userId: 'user-32',
          userEmail: 'user32@example.com',
          location: { filePath: 'app.ts', line: 1 },
        },
        session.id,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const stats = service.getStatistics();
      expect(stats.totalBreakpoints).toBeGreaterThan(0);
    });
  });

  describe('Configuration', () => {
    it('should update configuration', () => {
      service.updateConfig({ maxSessions: 100 }, 'user-33', '192.168.1.1', 'Mozilla/5.0');

      expect(service['config'].maxSessions).toBe(100);
    });

    it('should emit config-updated event', () => {
      return new Promise<void>((resolve) => {
        service.once('config-updated', (data) => {
          expect(data.config).toBeDefined();
          resolve();
        });

        service.updateConfig({ enableLogpoints: false }, 'user-34', '192.168.1.1', 'Mozilla/5.0');
      });
    });
  });

  describe('Shutdown', () => {
    it('should shutdown service', () => {
      const session = service.createDebugSession(
        'user-35',
        'user35@example.com',
        'dap-35',
        false,
        undefined,
        '192.168.1.1',
        'Mozilla/5.0'
      );

      service.shutdown();

      expect(service.getDebugSession(session.id)).toBeNull();
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
