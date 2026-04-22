// @file        apps/backend/src/services/screen-share/__tests__/index.test.ts
// @module      collaboration/screen-share
// @description Screen share service tests

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { Pool } from 'pg';
import Redis from 'ioredis';
import { ScreenShareService } from '../index.js';

describe('ScreenShareService', () => {
  let service: ScreenShareService;
  let mockPool: Pool;
  let mockRedis: Redis;
  let mockAuditService: any;

  beforeEach(() => {
    mockPool = {} as Pool;
    mockRedis = {} as Redis;
    mockAuditService = {
      emit: vi.fn(),
    };
    service = new ScreenShareService(
      { workspaceId: 'workspace-123' },
      mockPool,
      mockRedis,
      mockAuditService
    );
  });

  describe('Session Management', () => {
    it('should start a new screen share session', async () => {
      const session = await service.startSession('presenter-1');
      expect(session.presenterId).toBe('presenter-1');
      expect(session.participantIds).toContain('presenter-1');
      expect(session.isActive).toBe(true);
    });

    it('should emit session_started event', async () => {
      const listener = vi.fn();
      service.on('session_started', listener);
      await service.startSession('presenter-1');
      expect(listener).toHaveBeenCalled();
    });

    it('should audit session start', async () => {
      await service.startSession('presenter-1');
      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'CREATE',
          resource: 'ScreenShareSession',
        })
      );
    });

    it('should join existing session', async () => {
      const session = await service.startSession('presenter-1');
      const updated = await service.joinSession(session.id, 'participant-1');
      expect(updated.participantIds).toContain('participant-1');
    });

    it('should audit participant join', async () => {
      const session = await service.startSession('presenter-1');
      await service.joinSession(session.id, 'participant-1');
      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'UPDATE',
          metadata: expect.objectContaining({ event: 'participant_joined' }),
        })
      );
    });

    it('should leave session', async () => {
      const session = await service.startSession('presenter-1');
      await service.joinSession(session.id, 'participant-1');
      await service.leaveSession(session.id, 'participant-1');
      const updated = service.getSession(session.id);
      expect(updated?.participantIds).not.toContain('participant-1');
    });

    it('should end session when presenter leaves', async () => {
      const session = await service.startSession('presenter-1');
      await service.leaveSession(session.id, 'presenter-1');
      const updated = service.getSession(session.id);
      expect(updated?.isActive).toBe(false);
    });

    it('should audit session end', async () => {
      const session = await service.startSession('presenter-1');
      await service.endSession(session.id);
      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'DELETE',
          resource: 'ScreenShareSession',
        })
      );
    });
  });

  describe('Annotations', () => {
    it('should add drawing annotation', async () => {
      const session = await service.startSession('presenter-1');
      const ann = await service.addAnnotation(session.id, 'participant-1', 'drawing', 100, 200, '#FF0000');
      expect(ann.type).toBe('drawing');
      expect(ann.x).toBe(100);
      expect(ann.y).toBe(200);
    });

    it('should audit annotation creation', async () => {
      const session = await service.startSession('presenter-1');
      await service.addAnnotation(session.id, 'participant-1', 'pointer', 50, 75);
      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'CREATE',
          resource: 'ScreenShareAnnotation',
        })
      );
    });

    it('should get session annotations', async () => {
      const session = await service.startSession('presenter-1');
      await service.addAnnotation(session.id, 'participant-1', 'drawing', 100, 200);
      await service.addAnnotation(session.id, 'participant-1', 'highlight', 150, 250);
      const annotations = service.getSessionAnnotations(session.id);
      expect(annotations).toHaveLength(2);
    });

    it('should emit annotation_added event', async () => {
      const listener = vi.fn();
      service.on('annotation_added', listener);
      const session = await service.startSession('presenter-1');
      await service.addAnnotation(session.id, 'participant-1', 'drawing', 100, 200);
      expect(listener).toHaveBeenCalled();
    });
  });

  describe('Cursor Tracking', () => {
    it('should update cursor position', async () => {
      const session = await service.startSession('presenter-1');
      await service.updateCursorPosition(session.id, 'participant-1', 150, 250);
      // Verify no error thrown
      expect(true).toBe(true);
    });

    it('should emit cursor_moved event', async () => {
      const listener = vi.fn();
      service.on('cursor_moved', listener);
      const session = await service.startSession('presenter-1');
      await service.updateCursorPosition(session.id, 'participant-1', 100, 200);
      expect(listener).toHaveBeenCalled();
    });
  });

  describe('Workspace Sessions', () => {
    it('should get all active workspace sessions', async () => {
      const s1 = await service.startSession('presenter-1');
      const s2 = await service.startSession('presenter-2');
      const sessions = service.getWorkspaceSessions();
      expect(sessions).toHaveLength(2);
    });

    it('should not include inactive sessions', async () => {
      const s1 = await service.startSession('presenter-1');
      await service.endSession(s1.id);
      const sessions = service.getWorkspaceSessions();
      expect(sessions).toHaveLength(0);
    });
  });

  describe('Error Handling', () => {
    it('should throw error for missing workspace ID', () => {
      expect(() => {
        new ScreenShareService({} as any, mockPool, mockRedis);
      }).toThrow('Workspace ID required');
    });

    it('should throw error for non-existent session join', async () => {
      await expect(service.joinSession('invalid-id', 'user-1')).rejects.toThrow();
    });

    it('should throw error for non-existent session annotation', async () => {
      await expect(
        service.addAnnotation('invalid-id', 'user-1', 'drawing', 100, 200)
      ).rejects.toThrow();
    });
  });
});
