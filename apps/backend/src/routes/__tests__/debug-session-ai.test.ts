#!/usr/bin/env node
// @file        apps/backend/src/routes/__tests__/debug-session-ai.test.ts
// @module      routes/collaboration
// @description Tests for debug session AI routes

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import express, { Express } from 'express';
import debugSessionAIRouter from '../debug-session-ai';
import service from '../../services/debugging/debug-session-ai-service';

describe('Debug Session AI Routes', () => {
  let app: Express;

  beforeEach(() => {
    app = express();
    app.use(express.json());
    app.use('/api/debug', debugSessionAIRouter);
    service.reset();
    service.removeAllListeners();
  });

  afterEach(() => {
    service.reset();
    service.removeAllListeners();
  });

  describe('POST /api/debug/sessions', () => {
    it('should create a new debug session', async () => {
      const response = await request(app)
        .post('/api/debug/sessions')
        .send({
          userId: 'user1',
          workspaceId: 'ws-123',
          sessionId: 'sess-123',
          type: 'node',
        });

      expect(response.status).toBe(201);
      expect(response.body.success).toBe(true);
      expect(response.body.data.id).toBeDefined();
      expect(response.body.data.userId).toBe('user1');
      expect(response.body.data.type).toBe('node');
    });

    it('should return 400 for missing required fields', async () => {
      const response = await request(app)
        .post('/api/debug/sessions')
        .send({
          userId: 'user1',
          // missing other fields
        });

      expect(response.status).toBe(400);
      expect(response.body.success).toBe(false);
    });
  });

  describe('GET /api/debug/sessions/:sessionId', () => {
    it('should get an existing debug session', async () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');

      const response = await request(app)
        .get(`/api/debug/sessions/${session.id}`);

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.data.id).toBe(session.id);
      expect(response.body.data.userId).toBe('user1');
    });

    it('should return 404 for non-existent session', async () => {
      const response = await request(app)
        .get('/api/debug/sessions/non-existent');

      expect(response.status).toBe(404);
      expect(response.body.success).toBe(false);
    });
  });

  describe('PATCH /api/debug/sessions/:sessionId/state', () => {
    it('should update session state to paused', async () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');

      const response = await request(app)
        .patch(`/api/debug/sessions/${session.id}/state`)
        .send({ state: 'paused' });

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.data.state).toBe('paused');
    });

    it('should return 400 for invalid state', async () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');

      const response = await request(app)
        .patch(`/api/debug/sessions/${session.id}/state`)
        .send({ state: 'invalid' });

      expect(response.status).toBe(400);
      expect(response.body.success).toBe(false);
    });

    it('should return 404 for non-existent session', async () => {
      const response = await request(app)
        .patch('/api/debug/sessions/non-existent/state')
        .send({ state: 'paused' });

      expect(response.status).toBe(404);
      expect(response.body.success).toBe(false);
    });
  });

  describe('POST /api/debug/sessions/:sessionId/breakpoints', () => {
    it('should set a breakpoint', async () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');

      const response = await request(app)
        .post(`/api/debug/sessions/${session.id}/breakpoints`)
        .send({
          id: 'bp-1',
          file: '/src/app.ts',
          line: 42,
          verified: true,
        });

      expect(response.status).toBe(201);
      expect(response.body.success).toBe(true);
      expect(response.body.data.breakpoints.length).toBe(1);
    });

    it('should return 400 for missing required fields', async () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');

      const response = await request(app)
        .post(`/api/debug/sessions/${session.id}/breakpoints`)
        .send({
          id: 'bp-1',
          // missing file and line
        });

      expect(response.status).toBe(400);
      expect(response.body.success).toBe(false);
    });

    it('should return 404 for non-existent session', async () => {
      const response = await request(app)
        .post('/api/debug/sessions/non-existent/breakpoints')
        .send({
          id: 'bp-1',
          file: '/src/app.ts',
          line: 42,
        });

      expect(response.status).toBe(404);
      expect(response.body.success).toBe(false);
    });
  });

  describe('DELETE /api/debug/sessions/:sessionId/breakpoints/:breakpointId', () => {
    it('should remove a breakpoint', async () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      service.setBreakpoint(session.id, {
        id: 'bp-1',
        file: '/src/app.ts',
        line: 42,
        verified: true,
      });

      const response = await request(app)
        .delete(`/api/debug/sessions/${session.id}/breakpoints/bp-1`);

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.data.breakpoints.length).toBe(0);
    });

    it('should return 404 for non-existent session', async () => {
      const response = await request(app)
        .delete('/api/debug/sessions/non-existent/breakpoints/bp-1');

      expect(response.status).toBe(404);
      expect(response.body.success).toBe(false);
    });
  });

  describe('POST /api/debug/sessions/:sessionId/variables', () => {
    it('should capture variables', async () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      service.setBreakpoint(session.id, {
        id: 'bp-1',
        file: '/src/app.ts',
        line: 42,
        verified: true,
      });

      const response = await request(app)
        .post(`/api/debug/sessions/${session.id}/variables`)
        .send({
          breakpointId: 'bp-1',
          variables: [
            { name: 'x', value: '10', type: 'number' },
            { name: 'y', value: 'hello', type: 'string' },
          ],
        });

      expect(response.status).toBe(201);
      expect(response.body.success).toBe(true);
      expect(response.body.data.variables.length).toBe(2);
    });

    it('should return 400 for missing breakpointId', async () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');

      const response = await request(app)
        .post(`/api/debug/sessions/${session.id}/variables`)
        .send({
          // missing breakpointId
          variables: [],
        });

      expect(response.status).toBe(400);
      expect(response.body.success).toBe(false);
    });

    it('should return 404 for non-existent session', async () => {
      const response = await request(app)
        .post('/api/debug/sessions/non-existent/variables')
        .send({
          breakpointId: 'bp-1',
          variables: [],
        });

      expect(response.status).toBe(404);
      expect(response.body.success).toBe(false);
    });
  });

  describe('POST /api/debug/sessions/:sessionId/stack-frames', () => {
    it('should capture stack frames', async () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');

      const response = await request(app)
        .post(`/api/debug/sessions/${session.id}/stack-frames`)
        .send({
          stackFrames: [
            { id: 1, name: 'main', file: '/src/app.ts', line: 42 },
            { id: 2, name: 'getData', file: '/src/lib.ts', line: 10 },
          ],
        });

      expect(response.status).toBe(201);
      expect(response.body.success).toBe(true);
      expect(response.body.data.stackFrames.length).toBe(2);
    });

    it('should return 400 for missing stackFrames', async () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');

      const response = await request(app)
        .post(`/api/debug/sessions/${session.id}/stack-frames`)
        .send({
          // missing stackFrames
        });

      expect(response.status).toBe(400);
      expect(response.body.success).toBe(false);
    });

    it('should return 404 for non-existent session', async () => {
      const response = await request(app)
        .post('/api/debug/sessions/non-existent/stack-frames')
        .send({
          stackFrames: [],
        });

      expect(response.status).toBe(404);
      expect(response.body.success).toBe(false);
    });
  });

  describe('POST /api/debug/sessions/:sessionId/analyze', () => {
    it('should analyze root cause', async () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      service.setBreakpoint(session.id, {
        id: 'bp-1',
        file: '/src/app.ts',
        line: 42,
        verified: true,
      });
      service.captureVariables(session.id, 'bp-1', [
        { name: 'x', value: 'null', type: 'null' },
      ]);

      const response = await request(app)
        .post(`/api/debug/sessions/${session.id}/analyze`);

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.data.likely).toBeDefined();
      expect(response.body.data.confidence).toBeGreaterThanOrEqual(0);
    });

    it('should return 404 for non-existent session', async () => {
      const response = await request(app)
        .post('/api/debug/sessions/non-existent/analyze');

      expect(response.status).toBe(404);
      expect(response.body.success).toBe(false);
    });
  });

  describe('POST /api/debug/sessions/:sessionId/fix-suggestions', () => {
    it('should generate fix suggestions', async () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      service.setBreakpoint(session.id, {
        id: 'bp-1',
        file: '/src/app.ts',
        line: 42,
        verified: true,
      });
      service.captureVariables(session.id, 'bp-1', [
        { name: 'x', value: 'null', type: 'null' },
      ]);

      const response = await request(app)
        .post(`/api/debug/sessions/${session.id}/fix-suggestions`);

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(Array.isArray(response.body.data)).toBe(true);
    });
  });

  describe('GET /api/debug/sessions/:sessionId/docs', () => {
    it('should get relevant documentation', async () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      service.setBreakpoint(session.id, {
        id: 'bp-1',
        file: '/src/app.ts',
        line: 42,
        verified: true,
      });
      service.captureVariables(session.id, 'bp-1', [
        { name: 'x', value: 'null', type: 'null' },
      ]);
      service.generateFixSuggestions(session.id);

      const response = await request(app)
        .get(`/api/debug/sessions/${session.id}/docs`);

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(Array.isArray(response.body.data)).toBe(true);
    });
  });

  describe('GET /api/debug/stats', () => {
    it('should get debug session statistics', async () => {
      service.startSession('user1', 'ws-123', 'sess-1', 'node');
      service.startSession('user2', 'ws-456', 'sess-2', 'python');

      const response = await request(app)
        .get('/api/debug/stats');

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.data.totalSessions).toBe(2);
      expect(response.body.data.activeSessions).toBe(2);
    });

    it('should return empty stats for no sessions', async () => {
      const response = await request(app)
        .get('/api/debug/stats');

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.data.totalSessions).toBe(0);
    });
  });

  describe('DELETE /api/debug/sessions/:sessionId', () => {
    it('should delete a debug session', async () => {
      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');

      const response = await request(app)
        .delete(`/api/debug/sessions/${session.id}`);

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.data.state).toBe('stopped');
    });

    it('should return 404 for non-existent session', async () => {
      const response = await request(app)
        .delete('/api/debug/sessions/non-existent');

      expect(response.status).toBe(404);
      expect(response.body.success).toBe(false);
    });
  });

  describe('Error Handling', () => {
    it('should handle unexpected errors gracefully', async () => {
      // Mock service to throw an error
      const originalAnalyze = service.analyzeRootCause;
      service.analyzeRootCause = () => {
        throw new Error('Unexpected error');
      };

      const session = service.startSession('user1', 'ws-123', 'sess-123', 'node');
      service.setBreakpoint(session.id, {
        id: 'bp-1',
        file: '/src/app.ts',
        line: 42,
        verified: true,
      });

      const response = await request(app)
        .post(`/api/debug/sessions/${session.id}/analyze`);

      expect(response.status).toBe(500);
      expect(response.body.success).toBe(false);

      // Restore original method
      service.analyzeRootCause = originalAnalyze;
    });
  });

  describe('Integration Tests', () => {
    it('should handle a complete debugging workflow', async () => {
      // Create session
      const createResponse = await request(app)
        .post('/api/debug/sessions')
        .send({
          userId: 'user1',
          workspaceId: 'ws-123',
          sessionId: 'sess-123',
          type: 'node',
        });

      const sessionId = createResponse.body.data.id;
      expect(createResponse.status).toBe(201);

      // Set breakpoint
      const bpResponse = await request(app)
        .post(`/api/debug/sessions/${sessionId}/breakpoints`)
        .send({
          id: 'bp-1',
          file: '/src/app.ts',
          line: 42,
          verified: true,
        });
      expect(bpResponse.status).toBe(201);

      // Capture variables
      const varResponse = await request(app)
        .post(`/api/debug/sessions/${sessionId}/variables`)
        .send({
          breakpointId: 'bp-1',
          variables: [{ name: 'x', value: 'null', type: 'null' }],
        });
      expect(varResponse.status).toBe(201);

      // Analyze
      const analyzeResponse = await request(app)
        .post(`/api/debug/sessions/${sessionId}/analyze`);
      expect(analyzeResponse.status).toBe(200);

      // Get suggestions
      const suggestResponse = await request(app)
        .post(`/api/debug/sessions/${sessionId}/fix-suggestions`);
      expect(suggestResponse.status).toBe(200);

      // Get docs
      const docsResponse = await request(app)
        .get(`/api/debug/sessions/${sessionId}/docs`);
      expect(docsResponse.status).toBe(200);

      // Delete session
      const deleteResponse = await request(app)
        .delete(`/api/debug/sessions/${sessionId}`);
      expect(deleteResponse.status).toBe(200);
    });
  });
});
