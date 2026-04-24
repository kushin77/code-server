#!/usr/bin/env node
// @file        apps/backend/src/routes/__tests__/rich-presence.test.ts
// @module      routes/rich-presence
// @description Comprehensive tests for rich presence routes

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import request from 'supertest';
import express from 'express';
vi.mock('../../lib/tracing', () => ({
  getTracer: () => ({
    startActiveSpan: (_name: string, _options: unknown, callback: (span: { setStatus: () => void; recordException: () => void; end: () => void }) => unknown) =>
      callback({
        setStatus: vi.fn(),
        recordException: vi.fn(),
        end: vi.fn(),
      }),
  }),
  withSpanSync: (_tracer: unknown, _name: string, _attributes: Record<string, string | number | boolean>, fn: (span: { setStatus: () => void; recordException: () => void; end: () => void }) => unknown) =>
    fn({
      setStatus: vi.fn(),
      recordException: vi.fn(),
      end: vi.fn(),
    }),
}));
import richPresenceRouter from '../rich-presence';
import service from '../../services/collaboration/rich-presence-service';

const app = express();
app.use(express.json());
app.use('/api', richPresenceRouter);

describe('Rich Presence Routes', () => {
  beforeEach(() => {
    service.reset();
  });

  afterEach(() => {
vi.mock('../../middleware/tracing', () => ({
  tracingMiddleware: (_req: unknown, _res: unknown, next: () => void) => next(),
}));
    service.reset();
  });

  describe('POST /api/presence/update', () => {
    it('should update presence', async () => {
      const res = await request(app).post('/api/presence/update').send({
        userId: 'user1',
        username: 'Alice',
        email: 'alice@example.com',
        status: 'online',
        workspaceId: 'ws-123',
        sessionId: 'sess-123',
      });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.userId).toBe('user1');
      expect(res.body.data.username).toBe('Alice');
    });

    it('should return 400 for missing userId', async () => {
      const res = await request(app).post('/api/presence/update').send({
        username: 'Alice',
        workspaceId: 'ws-123',
        sessionId: 'sess-123',
      });

      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
    });
  });

  describe('PATCH /api/presence/:userId/status', () => {
    it('should set user status', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        workspaceId: 'ws-123',
        sessionId: 'sess-123',
      });

      const res = await request(app).patch('/api/presence/user1/status').send({
        status: 'away',
      });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.status).toBe('away');
    });

    it('should return 400 for invalid status', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        workspaceId: 'ws-123',
        sessionId: 'sess-123',
      });

      const res = await request(app).patch('/api/presence/user1/status').send({
        status: 'invalid',
      });

      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
    });

    it('should return 404 for non-existent user', async () => {
      const res = await request(app).patch('/api/presence/non-existent/status').send({
        status: 'online',
      });

      expect(res.status).toBe(404);
      expect(res.body.success).toBe(false);
    });
  });

  describe('PATCH /api/presence/:userId/file', () => {
    it('should set current file', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        workspaceId: 'ws-123',
        sessionId: 'sess-123',
      });

      const res = await request(app)
        .patch('/api/presence/user1/file')
        .send({
          path: '/src/app.ts',
          line: 42,
          column: 15,
        });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.currentFile.path).toBe('/src/app.ts');
    });

    it('should return 400 for missing path', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        workspaceId: 'ws-123',
        sessionId: 'sess-123',
      });

      const res = await request(app).patch('/api/presence/user1/file').send({
        line: 42,
      });

      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
    });
  });

  describe('PATCH /api/presence/:userId/function', () => {
    it('should set current function', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        workspaceId: 'ws-123',
        sessionId: 'sess-123',
      });

      const res = await request(app)
        .patch('/api/presence/user1/function')
        .send({
          name: 'handleRequest',
          file: '/src/app.ts',
          line: 42,
        });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.currentFunction.name).toBe('handleRequest');
    });

    it('should return 400 for missing fields', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        workspaceId: 'ws-123',
        sessionId: 'sess-123',
      });

      const res = await request(app)
        .patch('/api/presence/user1/function')
        .send({
          name: 'handleRequest',
        });

      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
    });
  });

  describe('PATCH /api/presence/:userId/task', () => {
    it('should set current task', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        workspaceId: 'ws-123',
        sessionId: 'sess-123',
      });

      const res = await request(app)
        .patch('/api/presence/user1/task')
        .send({
          id: 'task-123',
          title: 'Fix login bug',
          status: 'active',
        });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.currentTask.id).toBe('task-123');
    });
  });

  describe('PATCH /api/presence/:userId/custom-status', () => {
    it('should set custom status', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        workspaceId: 'ws-123',
        sessionId: 'sess-123',
      });

      const res = await request(app)
        .patch('/api/presence/user1/custom-status')
        .send({
          emoji: '🎉',
          text: 'Shipped new feature!',
        });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.customStatus.emoji).toBe('🎉');
    });
  });

  describe('DELETE /api/presence/:userId/custom-status', () => {
    it('should clear custom status', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        workspaceId: 'ws-123',
        sessionId: 'sess-123',
      });
      service.setCustomStatus('user1', { emoji: '🎉', text: 'Working' });

      const res = await request(app).delete('/api/presence/user1/custom-status');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.customStatus).toBeUndefined();
    });

    it('should return 404 for non-existent user', async () => {
      const res = await request(app).delete('/api/presence/non-existent/custom-status');

      expect(res.status).toBe(404);
      expect(res.body.success).toBe(false);
    });
  });

  describe('PATCH /api/presence/:userId/cursor', () => {
    it('should set cursor position', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        workspaceId: 'ws-123',
        sessionId: 'sess-123',
      });

      const res = await request(app)
        .patch('/api/presence/user1/cursor')
        .send({
          x: 100,
          y: 200,
        });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.cursorPosition).toEqual({ x: 100, y: 200 });
    });

    it('should return 400 for invalid coordinates', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        workspaceId: 'ws-123',
        sessionId: 'sess-123',
      });

      const res = await request(app)
        .patch('/api/presence/user1/cursor')
        .send({
          x: 'invalid',
          y: 200,
        });

      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
    });
  });

  describe('GET /api/presence/:userId', () => {
    it('should get user presence', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        workspaceId: 'ws-123',
        sessionId: 'sess-123',
      });

      const res = await request(app).get('/api/presence/user1');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.userId).toBe('user1');
    });

    it('should return 404 for non-existent user', async () => {
      const res = await request(app).get('/api/presence/non-existent');

      expect(res.status).toBe(404);
      expect(res.body.success).toBe(false);
    });
  });

  describe('GET /api/presence/workspace/:workspaceId', () => {
    it('should get all users in workspace', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        workspaceId: 'ws-123',
        sessionId: 'sess-1',
      });
      service.updatePresence('user2', {
        username: 'Bob',
        workspaceId: 'ws-123',
        sessionId: 'sess-2',
      });

      const res = await request(app).get('/api/presence/workspace/ws-123');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toHaveLength(2);
      expect(res.body.count).toBe(2);
    });

    it('should return empty array for workspace with no users', async () => {
      const res = await request(app).get('/api/presence/workspace/ws-123');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toHaveLength(0);
    });
  });

  describe('GET /api/presence/file', () => {
    it('should get users editing a file', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        workspaceId: 'ws-123',
        sessionId: 'sess-1',
      });
      service.updatePresence('user2', {
        username: 'Bob',
        workspaceId: 'ws-123',
        sessionId: 'sess-2',
      });

      service.setCurrentFile('user1', { path: '/src/app.ts' });
      service.setCurrentFile('user2', { path: '/src/app.ts' });

      const res = await request(app).get('/api/presence/file?path=/src/app.ts');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toHaveLength(2);
    });

    it('should return 400 for missing path', async () => {
      const res = await request(app).get('/api/presence/file');

      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
    });
  });

  describe('GET /api/presence/function', () => {
    it('should get users debugging a function', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        workspaceId: 'ws-123',
        sessionId: 'sess-1',
      });

      service.setCurrentFunction('user1', {
        name: 'handleRequest',
        file: '/src/app.ts',
        line: 42,
      });

      const res = await request(app).get('/api/presence/function?name=handleRequest');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toHaveLength(1);
    });

    it('should return 400 for missing name', async () => {
      const res = await request(app).get('/api/presence/function');

      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
    });
  });

  describe('GET /api/presence/task', () => {
    it('should get users on a task', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        workspaceId: 'ws-123',
        sessionId: 'sess-1',
      });

      service.setCurrentTask('user1', {
        id: 'task-123',
        title: 'Fix bug',
        status: 'active',
      });

      const res = await request(app).get('/api/presence/task?id=task-123');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toHaveLength(1);
    });
  });

  describe('GET /api/presence/online/all', () => {
    it('should get all online/idle users', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        status: 'online',
        workspaceId: 'ws-123',
        sessionId: 'sess-1',
      });
      service.updatePresence('user2', {
        username: 'Bob',
        status: 'idle',
        workspaceId: 'ws-123',
        sessionId: 'sess-2',
      });
      service.updatePresence('user3', {
        username: 'Charlie',
        status: 'offline',
        workspaceId: 'ws-123',
        sessionId: 'sess-3',
      });

      const res = await request(app).get('/api/presence/online/all');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toHaveLength(2);
    });
  });

  describe('POST /api/presence/query', () => {
    beforeEach(() => {
      service.updatePresence('user1', {
        username: 'Alice',
        status: 'online',
        workspaceId: 'ws-123',
        sessionId: 'sess-1',
      });
      service.updatePresence('user2', {
        username: 'Bob',
        status: 'away',
        workspaceId: 'ws-123',
        sessionId: 'sess-2',
      });
      service.updatePresence('user3', {
        username: 'Charlie',
        status: 'offline',
        workspaceId: 'ws-456',
        sessionId: 'sess-3',
      });

      service.setCurrentFile('user1', { path: '/src/app.ts' });
      service.setCurrentFile('user2', { path: '/src/app.ts' });
    });

    it('should query by workspace', async () => {
      const res = await request(app).post('/api/presence/query').send({
        workspaceId: 'ws-123',
      });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toHaveLength(2);
    });

    it('should query by status', async () => {
      const res = await request(app).post('/api/presence/query').send({
        status: 'online',
      });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toHaveLength(1);
      expect(res.body.data[0].userId).toBe('user1');
    });

    it('should query by file', async () => {
      const res = await request(app).post('/api/presence/query').send({
        currentFile: '/src/app.ts',
      });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toHaveLength(2);
    });
  });

  describe('DELETE /api/presence/:userId', () => {
    it('should remove presence', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        workspaceId: 'ws-123',
        sessionId: 'sess-123',
      });

      const res = await request(app).delete('/api/presence/user1');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(service.getPresence('user1')).toBeUndefined();
    });

    it('should return 404 for non-existent user', async () => {
      const res = await request(app).delete('/api/presence/non-existent');

      expect(res.status).toBe(404);
      expect(res.body.success).toBe(false);
    });
  });

  describe('POST /api/presence/:userId/broadcast', () => {
    it('should broadcast presence update', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        workspaceId: 'ws-123',
        sessionId: 'sess-123',
      });

      const res = await request(app).post('/api/presence/user1/broadcast');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.userId).toBe('user1');
    });

    it('should return 404 for non-existent user', async () => {
      const res = await request(app).post('/api/presence/non-existent/broadcast');

      expect(res.status).toBe(404);
      expect(res.body.success).toBe(false);
    });
  });

  describe('GET /api/presence/stats/all', () => {
    it('should get presence statistics', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        status: 'online',
        workspaceId: 'ws-123',
        sessionId: 'sess-1',
      });
      service.updatePresence('user2', {
        username: 'Bob',
        status: 'away',
        workspaceId: 'ws-123',
        sessionId: 'sess-2',
      });

      const res = await request(app).get('/api/presence/stats/all');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.totalUsers).toBe(2);
      expect(res.body.data.onlineUsers).toBe(1);
      expect(res.body.data.awayUsers).toBe(1);
    });
  });

  describe('GET /api/presence/count/status', () => {
    it('should count users by status', async () => {
      service.updatePresence('user1', {
        username: 'Alice',
        status: 'online',
        workspaceId: 'ws-123',
        sessionId: 'sess-1',
      });
      service.updatePresence('user2', {
        username: 'Bob',
        status: 'away',
        workspaceId: 'ws-123',
        sessionId: 'sess-2',
      });

      const res = await request(app).get('/api/presence/count/status?workspaceId=ws-123');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.online).toBe(1);
      expect(res.body.data.away).toBe(1);
    });
  });
});
