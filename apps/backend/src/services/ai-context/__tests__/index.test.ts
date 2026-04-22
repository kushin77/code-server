// @file        apps/backend/src/services/ai-context/__tests__/index.test.ts
// @module      ai/shared-context
// @description Shared AI context service tests

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { Pool } from 'pg';
import Redis from 'ioredis';
import { SharedAIContextService } from '../index.js';

describe('SharedAIContextService', () => {
  let service: SharedAIContextService;
  let mockPool: Pool;
  let mockRedis: Redis;
  let mockAuditService: any;

  beforeEach(() => {
    mockPool = {} as Pool;
    mockRedis = {} as Redis;
    mockAuditService = {
      emit: vi.fn(),
    };
    service = new SharedAIContextService(
      { workspaceId: 'ws-123' },
      mockPool,
      mockRedis,
      mockAuditService
    );
  });

  describe('Context Management', () => {
    it('should create a new AI context', async () => {
      const ctx = await service.createContext(
        'user-1',
        'session-1',
        [{ path: 'index.ts', language: 'typescript', content: 'code' }],
        [{ role: 'user', content: 'help me', timestamp: new Date() }]
      );
      expect(ctx.userId).toBe('user-1');
      expect(ctx.fileContext).toHaveLength(1);
    });

    it('should audit context creation', async () => {
      await service.createContext(
        'user-1',
        'session-1',
        [{ path: 'index.ts', language: 'typescript', content: 'code' }],
        []
      );
      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'CREATE',
          resource: 'AIContextSnapshot',
        })
      );
    });

    it('should emit context_created event', async () => {
      const listener = vi.fn();
      service.on('context_created', listener);
      await service.createContext('user-1', 'session-1', [], []);
      expect(listener).toHaveBeenCalled();
    });

    it('should share context with another user', async () => {
      const ctx = await service.createContext('user-1', 'session-1', [], []);
      const share = await service.shareContext(ctx.id, 'user-1', 'user-2', false);
      expect(share.sharedWith).toBe('user-2');
    });

    it('should audit context share', async () => {
      const ctx = await service.createContext('user-1', 'session-1', [], []);
      await service.shareContext(ctx.id, 'user-1', 'user-2', false);
      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'UPDATE',
          metadata: expect.objectContaining({ event: 'context_shared' }),
        })
      );
    });

    it('should emit context_shared event', async () => {
      const listener = vi.fn();
      service.on('context_shared', listener);
      const ctx = await service.createContext('user-1', 'session-1', [], []);
      await service.shareContext(ctx.id, 'user-1', 'user-2', false);
      expect(listener).toHaveBeenCalled();
    });

    it('should update context conversation', async () => {
      const ctx = await service.createContext('user-1', 'session-1', [], [
        { role: 'user', content: 'hello', timestamp: new Date() },
      ]);
      const updated = await service.updateContext(ctx.id, 'user-1', [
        { role: 'assistant', content: 'hi', timestamp: new Date() },
      ]);
      expect(updated.recentConversation).toHaveLength(2);
    });

    it('should audit context update', async () => {
      const ctx = await service.createContext('user-1', 'session-1', [], []);
      await service.updateContext(ctx.id, 'user-1', [
        { role: 'assistant', content: 'response', timestamp: new Date() },
      ]);
      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'UPDATE',
        })
      );
    });

    it('should revoke context access', async () => {
      const ctx = await service.createContext('user-1', 'session-1', [], []);
      await service.shareContext(ctx.id, 'user-1', 'user-2', false);
      await service.revokeContext(ctx.id, 'user-1');
      const retrieved = service.getUserContexts('user-2');
      expect(retrieved).toHaveLength(0);
    });

    it('should audit context revocation', async () => {
      const ctx = await service.createContext('user-1', 'session-1', [], []);
      await service.revokeContext(ctx.id, 'user-1');
      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'DELETE',
          resource: 'AIContextSnapshot',
        })
      );
    });
  });

  describe('Context Access', () => {
    it('should allow owner to access context', async () => {
      const ctx = await service.createContext('user-1', 'session-1', [], []);
      const retrieved = await service.getContext(ctx.id, 'user-1');
      expect(retrieved?.id).toBe(ctx.id);
    });

    it('should allow shared user to access context', async () => {
      const ctx = await service.createContext('user-1', 'session-1', [], []);
      await service.shareContext(ctx.id, 'user-1', 'user-2', false);
      const retrieved = await service.getContext(ctx.id, 'user-2');
      expect(retrieved?.id).toBe(ctx.id);
    });

    it('should deny access to non-shared user', async () => {
      const ctx = await service.createContext('user-1', 'session-1', [], []);
      await expect(service.getContext(ctx.id, 'user-3')).rejects.toThrow('Access denied');
    });

    it('should audit context access', async () => {
      const ctx = await service.createContext('user-1', 'session-1', [], []);
      await service.getContext(ctx.id, 'user-1');
      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          action: 'READ',
          resource: 'AIContextSnapshot',
        })
      );
    });

    it('should get user contexts', async () => {
      const ctx1 = await service.createContext('user-1', 'session-1', [], []);
      const ctx2 = await service.createContext('user-2', 'session-2', [], []);
      const userContexts = service.getUserContexts('user-1');
      expect(userContexts).toHaveLength(1);
      expect(userContexts[0].id).toBe(ctx1.id);
    });
  });

  describe('Expiration', () => {
    it('should return null for expired context', async () => {
      const ctx = await service.createContext('user-1', 'session-1', [], []);
      ctx.expiresAt = new Date(Date.now() - 1000);
      const retrieved = await service.getContext(ctx.id, 'user-1');
      expect(retrieved).toBeNull();
    });

    it('should clean expired contexts', async () => {
      const ctx1 = await service.createContext('user-1', 'session-1', [], []);
      const ctx2 = await service.createContext('user-2', 'session-2', [], []);
      ctx1.expiresAt = new Date(Date.now() - 1000);
      const cleaned = await service.cleanExpiredContexts();
      expect(cleaned).toBe(1);
      const remaining = service.getUserContexts('user-2');
      expect(remaining).toHaveLength(1);
    });
  });

  describe('Error Handling', () => {
    it('should throw error for missing workspace ID', () => {
      expect(() => {
        new SharedAIContextService({} as any, mockPool, mockRedis);
      }).toThrow('Workspace ID required');
    });

    it('should throw error for non-existent context share', async () => {
      await expect(
        service.shareContext('invalid-id', 'user-1', 'user-2')
      ).rejects.toThrow('not found');
    });

    it('should throw error for non-existent context update', async () => {
      await expect(
        service.updateContext('invalid-id', 'user-1', [])
      ).rejects.toThrow('not found');
    });
  });
});
