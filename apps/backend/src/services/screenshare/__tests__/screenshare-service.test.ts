/**
 * Screen Share Service Tests
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { ScreenShareService } from '../screenshare-service.js';

describe('ScreenShareService', () => {
  let service: ScreenShareService;

  beforeEach(() => {
    (ScreenShareService as any).reset();
    service = ScreenShareService.getInstance();
  });

  afterEach(() => {
    service.shutdown();
  });

  describe('Initialization', () => {
    it('should create singleton instance', () => {
      const instance1 = ScreenShareService.getInstance();
      const instance2 = ScreenShareService.getInstance();
      expect(instance1).toBe(instance2);
    });

    it('should emit initialized event', () => {
      (ScreenShareService as any).reset();
      const svc = ScreenShareService.getInstance();
      expect(svc).toBeDefined();
    });
  });

  describe('Screen Share Session Creation', () => {
    it('should start screen share', () => {
      const result = service.startScreenShare(
        {
          userId: 'user-1',
          userEmail: 'user1@example.com',
          userName: 'Alice',
          workspaceId: 'ws-1',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.success).toBe(true);
      expect(result.sessionId).toBeDefined();
      expect(result.session).toBeDefined();
      expect(result.session?.state).toBe('capturing');
    });

    it('should emit screen-share-started event', () => {
      return new Promise<void>((resolve) => {
        service.once('screen-share-started', (data) => {
          expect(data.session).toBeDefined();
          expect(data.session.presenterId).toBe('user-2');
          resolve();
        });

        service.startScreenShare(
          {
            userId: 'user-2',
            userEmail: 'user2@example.com',
            userName: 'Bob',
            workspaceId: 'ws-2',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });

    it('should generate unique session IDs', () => {
      const result1 = service.startScreenShare(
        {
          userId: 'user-3',
          userEmail: 'user3@example.com',
          userName: 'Charlie',
          workspaceId: 'ws-3',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const result2 = service.startScreenShare(
        {
          userId: 'user-4',
          userEmail: 'user4@example.com',
          userName: 'David',
          workspaceId: 'ws-3',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result1.sessionId).not.toBe(result2.sessionId);
    });

    it('should set custom screen title', () => {
      const result = service.startScreenShare(
        {
          userId: 'user-5',
          userEmail: 'user5@example.com',
          userName: 'Eve',
          workspaceId: 'ws-5',
          screenTitle: 'Code Review',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.session?.screenTitle).toBe('Code Review');
    });

    it('should set custom screen resolution', () => {
      const result = service.startScreenShare(
        {
          userId: 'user-6',
          userEmail: 'user6@example.com',
          userName: 'Frank',
          workspaceId: 'ws-6',
          screenResolution: { width: 2560, height: 1440 },
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(result.session?.screenResolution).toEqual({ width: 2560, height: 1440 });
    });
  });

  describe('Participant Management', () => {
    it('should join screen share', () => {
      const startResult = service.startScreenShare(
        {
          userId: 'user-7',
          userEmail: 'user7@example.com',
          userName: 'Grace',
          workspaceId: 'ws-7',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const joinResult = service.joinScreenShare(
        {
          userId: 'user-8',
          userEmail: 'user8@example.com',
          userName: 'Henry',
          sessionId: startResult.sessionId,
          role: 'viewer',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(joinResult.success).toBe(true);
      expect(joinResult.session?.viewers).toBe(1);
    });

    it('should emit participant-joined event', () => {
      return new Promise<void>((resolve) => {
        const startResult = service.startScreenShare(
          {
            userId: 'user-9',
            userEmail: 'user9@example.com',
            userName: 'Ivy',
            workspaceId: 'ws-9',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('participant-joined', (data) => {
          expect(data.userId).toBe('user-10');
          expect(data.role).toBe('annotator');
          resolve();
        });

        service.joinScreenShare(
          {
            userId: 'user-10',
            userEmail: 'user10@example.com',
            userName: 'Jack',
            sessionId: startResult.sessionId,
            role: 'annotator',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });

    it('should track annotators count', () => {
      const startResult = service.startScreenShare(
        {
          userId: 'user-11',
          userEmail: 'user11@example.com',
          userName: 'Karen',
          workspaceId: 'ws-11',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      service.joinScreenShare(
        {
          userId: 'user-12',
          userEmail: 'user12@example.com',
          userName: 'Leo',
          sessionId: startResult.sessionId,
          role: 'annotator',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const session = service.getSession(startResult.sessionId);
      expect(session?.annotators).toBe(1);
    });

    it('should leave screen share', () => {
      const startResult = service.startScreenShare(
        {
          userId: 'user-13',
          userEmail: 'user13@example.com',
          userName: 'Maria',
          workspaceId: 'ws-13',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const joinResult = service.joinScreenShare(
        {
          userId: 'user-14',
          userEmail: 'user14@example.com',
          userName: 'Noah',
          sessionId: startResult.sessionId,
          role: 'viewer',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const leaveResult = service.leaveScreenShare(
        {
          userId: 'user-14',
          userEmail: 'user14@example.com',
          sessionId: startResult.sessionId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(leaveResult.success).toBe(true);
      expect(service.getSession(startResult.sessionId)?.viewers).toBe(0);
    });
  });

  describe('Drawing Annotations', () => {
    it('should add drawing', () => {
      const startResult = service.startScreenShare(
        {
          userId: 'user-15',
          userEmail: 'user15@example.com',
          userName: 'Olivia',
          workspaceId: 'ws-15',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const drawResult = service.addDrawing(
        {
          userId: 'user-15',
          userEmail: 'user15@example.com',
          sessionId: startResult.sessionId,
          annotationType: 'pen',
          points: [{ x: 10, y: 20, timestamp: Date.now() }],
          color: 'black',
          lineWidth: 2,
          style: 'solid',
          opacity: 1,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(drawResult.success).toBe(true);
      expect(drawResult.annotationId).toBeDefined();
      expect(drawResult.annotation).toBeDefined();
    });

    it('should emit drawing-added event', () => {
      return new Promise<void>((resolve) => {
        const startResult = service.startScreenShare(
          {
            userId: 'user-16',
            userEmail: 'user16@example.com',
            userName: 'Peter',
            workspaceId: 'ws-16',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('drawing-added', (data) => {
          expect(data.annotation.annotationType).toBe('arrow');
          resolve();
        });

        service.addDrawing(
          {
            userId: 'user-16',
            userEmail: 'user16@example.com',
            sessionId: startResult.sessionId,
            annotationType: 'arrow',
            points: [
              { x: 0, y: 0, timestamp: Date.now() },
              { x: 100, y: 100, timestamp: Date.now() },
            ],
            color: 'red',
            lineWidth: 3,
            style: 'solid',
            opacity: 1,
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });

    it('should clear annotation', () => {
      const startResult = service.startScreenShare(
        {
          userId: 'user-17',
          userEmail: 'user17@example.com',
          userName: 'Quinn',
          workspaceId: 'ws-17',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const drawResult = service.addDrawing(
        {
          userId: 'user-17',
          userEmail: 'user17@example.com',
          sessionId: startResult.sessionId,
          annotationType: 'rectangle',
          points: [{ x: 50, y: 50, timestamp: Date.now() }],
          color: 'blue',
          lineWidth: 2,
          style: 'solid',
          opacity: 1,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const clearResult = service.clearAnnotation(
        {
          userId: 'user-17',
          userEmail: 'user17@example.com',
          sessionId: startResult.sessionId,
          annotationId: drawResult.annotationId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(clearResult.success).toBe(true);
      const annotations = service.getAnnotations({ sessionId: startResult.sessionId });
      expect(annotations.count).toBe(0);
    });

    it('should emit annotation-cleared event', () => {
      return new Promise<void>((resolve) => {
        const startResult = service.startScreenShare(
          {
            userId: 'user-18',
            userEmail: 'user18@example.com',
            userName: 'Rachel',
            workspaceId: 'ws-18',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );

        const drawResult = service.addDrawing(
          {
            userId: 'user-18',
            userEmail: 'user18@example.com',
            sessionId: startResult.sessionId,
            annotationType: 'circle',
            points: [{ x: 75, y: 75, timestamp: Date.now() }],
            color: 'green',
            lineWidth: 2,
            style: 'solid',
            opacity: 1,
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('annotation-cleared', (data) => {
          expect(data.annotationId).toBe(drawResult.annotationId);
          resolve();
        });

        service.clearAnnotation(
          {
            userId: 'user-18',
            userEmail: 'user18@example.com',
            sessionId: startResult.sessionId,
            annotationId: drawResult.annotationId,
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });
  });

  describe('Cursor Tracking', () => {
    it('should update cursor position', () => {
      const startResult = service.startScreenShare(
        {
          userId: 'user-19',
          userEmail: 'user19@example.com',
          userName: 'Samuel',
          workspaceId: 'ws-19',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const cursorResult = service.updateCursor(
        {
          userId: 'user-19',
          userName: 'Samuel',
          sessionId: startResult.sessionId,
          position: { x: 100, y: 150, timestamp: Date.now() },
          isVisible: true,
          color: 'red',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(cursorResult.success).toBe(true);
      expect(cursorResult.cursor?.position.x).toBe(100);
    });

    it('should emit cursor-updated event', () => {
      return new Promise<void>((resolve) => {
        const startResult = service.startScreenShare(
          {
            userId: 'user-20',
            userEmail: 'user20@example.com',
            userName: 'Tina',
            workspaceId: 'ws-20',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('cursor-updated', (data) => {
          expect(data.cursor.position.y).toBe(200);
          resolve();
        });

        service.updateCursor(
          {
            userId: 'user-20',
            userName: 'Tina',
            sessionId: startResult.sessionId,
            position: { x: 50, y: 200, timestamp: Date.now() },
            isVisible: true,
            color: 'blue',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });

    it('should get all cursors', () => {
      const startResult = service.startScreenShare(
        {
          userId: 'user-21',
          userEmail: 'user21@example.com',
          userName: 'Ulysses',
          workspaceId: 'ws-21',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      service.updateCursor(
        {
          userId: 'user-21',
          userName: 'Ulysses',
          sessionId: startResult.sessionId,
          position: { x: 100, y: 100, timestamp: Date.now() },
          isVisible: true,
          color: 'black',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const cursorsResult = service.getCursors({ sessionId: startResult.sessionId });
      expect(cursorsResult.count).toBeGreaterThan(0);
    });
  });

  describe('Recording', () => {
    it('should start recording', () => {
      const startResult = service.startScreenShare(
        {
          userId: 'user-22',
          userEmail: 'user22@example.com',
          userName: 'Violet',
          workspaceId: 'ws-22',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const recordResult = service.startRecording(
        {
          userId: 'user-22',
          userEmail: 'user22@example.com',
          sessionId: startResult.sessionId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(recordResult.success).toBe(true);
      expect(recordResult.recordingId).toBeDefined();
    });

    it('should stop recording', () => {
      const startResult = service.startScreenShare(
        {
          userId: 'user-23',
          userEmail: 'user23@example.com',
          userName: 'Walter',
          workspaceId: 'ws-23',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const recordStart = service.startRecording(
        {
          userId: 'user-23',
          userEmail: 'user23@example.com',
          sessionId: startResult.sessionId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const recordStop = service.stopRecording(
        {
          userId: 'user-23',
          userEmail: 'user23@example.com',
          sessionId: startResult.sessionId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(recordStop.success).toBe(true);
      expect(recordStop.duration).toBeGreaterThanOrEqual(0);
    });
  });

  describe('Share Control', () => {
    it('should pause share', () => {
      const startResult = service.startScreenShare(
        {
          userId: 'user-24',
          userEmail: 'user24@example.com',
          userName: 'Xander',
          workspaceId: 'ws-24',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const pauseResult = service.pauseShare(
        {
          userId: 'user-24',
          userEmail: 'user24@example.com',
          sessionId: startResult.sessionId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(pauseResult.success).toBe(true);
      expect(service.getSession(startResult.sessionId)?.state).toBe('paused');
    });

    it('should emit share-paused event', () => {
      return new Promise<void>((resolve) => {
        const startResult = service.startScreenShare(
          {
            userId: 'user-25',
            userEmail: 'user25@example.com',
            userName: 'Yvonne',
            workspaceId: 'ws-25',
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );

        service.once('share-paused', (data) => {
          expect(data.sessionId).toBe(startResult.sessionId);
          resolve();
        });

        service.pauseShare(
          {
            userId: 'user-25',
            userEmail: 'user25@example.com',
            sessionId: startResult.sessionId,
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });

    it('should resume share', () => {
      const startResult = service.startScreenShare(
        {
          userId: 'user-26',
          userEmail: 'user26@example.com',
          userName: 'Zoe',
          workspaceId: 'ws-26',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      service.pauseShare(
        {
          userId: 'user-26',
          userEmail: 'user26@example.com',
          sessionId: startResult.sessionId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const resumeResult = service.resumeShare(
        {
          userId: 'user-26',
          userEmail: 'user26@example.com',
          sessionId: startResult.sessionId,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(resumeResult.success).toBe(true);
      expect(service.getSession(startResult.sessionId)?.state).toBe('streaming');
    });
  });

  describe('Annotations Retrieval', () => {
    it('should get all annotations', () => {
      const startResult = service.startScreenShare(
        {
          userId: 'user-27',
          userEmail: 'user27@example.com',
          userName: 'Aaron',
          workspaceId: 'ws-27',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      service.addDrawing(
        {
          userId: 'user-27',
          userEmail: 'user27@example.com',
          sessionId: startResult.sessionId,
          annotationType: 'pen',
          points: [{ x: 10, y: 20, timestamp: Date.now() }],
          color: 'black',
          lineWidth: 2,
          style: 'solid',
          opacity: 1,
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const annotationsResult = service.getAnnotations({ sessionId: startResult.sessionId });
      expect(annotationsResult.count).toBe(1);
      expect(annotationsResult.annotations.length).toBe(1);
    });

    it('should enforce max annotations limit', () => {
      (ScreenShareService as any).reset();
      service = ScreenShareService.getInstance({ maxAnnotationsPerSession: 3 });

      const startResult = service.startScreenShare(
        {
          userId: 'user-28',
          userEmail: 'user28@example.com',
          userName: 'Bella',
          workspaceId: 'ws-28',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      for (let i = 0; i < 5; i++) {
        service.addDrawing(
          {
            userId: 'user-28',
            userEmail: 'user28@example.com',
            sessionId: startResult.sessionId,
            annotationType: 'pen',
            points: [{ x: i * 10, y: i * 10, timestamp: Date.now() }],
            color: 'black',
            lineWidth: 2,
            style: 'solid',
            opacity: 1,
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );
      }

      const annotationsResult = service.getAnnotations({ sessionId: startResult.sessionId });
      expect(annotationsResult.count).toBeLessThanOrEqual(3);
    });
  });

  describe('Audit Logging', () => {
    it('should record audit entry on share start', () => {
      service.startScreenShare(
        {
          userId: 'user-29',
          userEmail: 'user29@example.com',
          userName: 'Cameron',
          workspaceId: 'ws-29',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const audit = service.getAuditLog('user-29');
      expect(audit.length).toBeGreaterThan(0);
      expect(audit[0].operation).toBe('start-screen-share');
    });

    it('should limit audit log size', () => {
      (ScreenShareService as any).reset();
      service = ScreenShareService.getInstance({ maxAuditLogSize: 5 });

      for (let i = 0; i < 10; i++) {
        service.startScreenShare(
          {
            userId: 'user-30',
            userEmail: 'user30@example.com',
            userName: `User${i}`,
            workspaceId: `ws-30-${i}`,
          },
          '192.168.1.1',
          'Mozilla/5.0'
        );
      }

      const audit = service.getAuditLog('user-30');
      expect(audit.length).toBeLessThanOrEqual(5);
    });
  });

  describe('Statistics', () => {
    it('should get service statistics', () => {
      service.startScreenShare(
        {
          userId: 'user-31',
          userEmail: 'user31@example.com',
          userName: 'Diana',
          workspaceId: 'ws-31',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const stats = service.getStatistics();
      expect(stats.totalSessions).toBeGreaterThan(0);
    });

    it('should track active sessions', () => {
      const result = service.startScreenShare(
        {
          userId: 'user-32',
          userEmail: 'user32@example.com',
          userName: 'Ethan',
          workspaceId: 'ws-32',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      const stats = service.getStatistics();
      expect(stats.activeSessions).toBeGreaterThanOrEqual(0);
    });
  });

  describe('Configuration', () => {
    it('should update configuration', () => {
      service.updateConfig(
        { enableRecording: false },
        'user-33',
        '192.168.1.1',
        'Mozilla/5.0'
      );

      expect(service['config'].enableRecording).toBe(false);
    });

    it('should emit config-updated event', () => {
      return new Promise<void>((resolve) => {
        service.once('config-updated', (data) => {
          expect(data.config).toBeDefined();
          resolve();
        });

        service.updateConfig(
          { maxParticipantsPerSession: 50 },
          'user-34',
          '192.168.1.1',
          'Mozilla/5.0'
        );
      });
    });
  });

  describe('Shutdown', () => {
    it('should shutdown service', () => {
      const result = service.startScreenShare(
        {
          userId: 'user-35',
          userEmail: 'user35@example.com',
          userName: 'Fiona',
          workspaceId: 'ws-35',
        },
        '192.168.1.1',
        'Mozilla/5.0'
      );

      service.shutdown();

      expect(service.getSession(result.sessionId)).toBeNull();
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
