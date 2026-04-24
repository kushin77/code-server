#!/usr/bin/env node
// @file        apps/backend/src/routes/__tests__/session-recording.test.ts
// @module      routes/session-recording
// @description Comprehensive tests for session recording routes

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import express from 'express';
import sessionRecordingRouter from '../session-recording';
import service from '../../services/session/session-recording-service';

const app = express();
app.use(express.json());
app.use('/api', sessionRecordingRouter);

describe('Session Recording Routes', () => {
  beforeEach(() => {
    service.reset();
  });

  afterEach(() => {
    service.reset();
  });

  describe('POST /api/sessions/:sessionId/recording/start', () => {
    it('should start recording', async () => {
      const res = await request(app).post('/api/sessions/session-123/recording/start').send({
        userId: 'user1',
        workspaceId: 'workspace-123',
      });

      expect(res.status).toBe(201);
      expect(res.body.success).toBe(true);
      expect(res.body.data.sessionId).toBe('session-123');
      expect(res.body.data.userId).toBe('user1');
      expect(res.body.data.isActive).toBe(true);
    });

    it('should return 400 for missing fields', async () => {
      const res = await request(app).post('/api/sessions/session-123/recording/start').send({
        userId: 'user1',
      });

      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
    });
  });

  describe('POST /api/recordings/:recordingId/stop', () => {
    it('should stop recording', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      const res = await request(app).post(`/api/recordings/${recording.id}/stop`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.isActive).toBe(false);
    });

    it('should return 404 for non-existent recording', async () => {
      const res = await request(app).post('/api/recordings/non-existent/stop');

      expect(res.status).toBe(404);
      expect(res.body.success).toBe(false);
    });
  });

  describe('POST /api/recordings/:recordingId/pause', () => {
    it('should pause recording', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      const res = await request(app).post(`/api/recordings/${recording.id}/pause`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.isPaused).toBe(true);
    });
  });

  describe('POST /api/recordings/:recordingId/resume', () => {
    it('should resume recording', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      service.pauseRecording(recording.id);

      const res = await request(app).post(`/api/recordings/${recording.id}/resume`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.isPaused).toBe(false);
    });
  });

  describe('GET /api/recordings/:recordingId', () => {
    it('should get recording', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      const res = await request(app).get(`/api/recordings/${recording.id}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.id).toBe(recording.id);
    });

    it('should return 404 for non-existent recording', async () => {
      const res = await request(app).get('/api/recordings/non-existent');

      expect(res.status).toBe(404);
      expect(res.body.success).toBe(false);
    });
  });

  describe('DELETE /api/recordings/:recordingId', () => {
    it('should delete recording', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      const res = await request(app).delete(`/api/recordings/${recording.id}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(service.getRecording(recording.id)).toBeUndefined();
    });

    it('should return 404 for non-existent recording', async () => {
      const res = await request(app).delete('/api/recordings/non-existent');

      expect(res.status).toBe(404);
      expect(res.body.success).toBe(false);
    });
  });

  describe('GET /api/sessions/:sessionId/recordings', () => {
    it('should list session recordings', async () => {
      service.startRecording('session-123', 'user1', 'workspace-123');
      service.startRecording('session-123', 'user1', 'workspace-456');

      const res = await request(app).get('/api/sessions/session-123/recordings');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toHaveLength(2);
    });

    it('should return empty array for session with no recordings', async () => {
      const res = await request(app).get('/api/sessions/session-123/recordings');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toHaveLength(0);
    });
  });

  describe('GET /api/users/:userId/recordings', () => {
    it('should list user recordings', async () => {
      service.startRecording('session-123', 'user1', 'workspace-123');
      service.startRecording('session-456', 'user1', 'workspace-456');

      const res = await request(app).get('/api/users/user1/recordings');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toHaveLength(2);
    });
  });

  describe('POST /api/recordings/:recordingId/file', () => {
    it('should record file change', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      const res = await request(app)
        .post(`/api/recordings/${recording.id}/file`)
        .send({
          timestamp: Date.now(),
          path: '/file.ts',
          type: 'create',
        });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
    });
  });

  describe('POST /api/recordings/:recordingId/terminal', () => {
    it('should record terminal event', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      const res = await request(app)
        .post(`/api/recordings/${recording.id}/terminal`)
        .send({
          timestamp: Date.now(),
          terminalId: 'term-1',
          type: 'input',
          data: 'npm run dev',
        });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
    });
  });

  describe('POST /api/recordings/:recordingId/debug', () => {
    it('should record debug event', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      const res = await request(app)
        .post(`/api/recordings/${recording.id}/debug`)
        .send({
          timestamp: Date.now(),
          type: 'breakpoint',
          file: '/src/app.ts',
          line: 42,
        });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
    });
  });

  describe('POST /api/recordings/:recordingId/chat', () => {
    it('should record chat message', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      const res = await request(app)
        .post(`/api/recordings/${recording.id}/chat`)
        .send({
          timestamp: Date.now(),
          userId: 'user1',
          username: 'Alice',
          message: 'Hello',
          type: 'message',
        });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
    });
  });

  describe('POST /api/recordings/:recordingId/playback/start', () => {
    it('should start playback', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      const res = await request(app).post(`/api/recordings/${recording.id}/playback/start`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.isPlaying).toBe(true);
    });

    it('should return 404 for non-existent recording', async () => {
      const res = await request(app).post('/api/recordings/non-existent/playback/start');

      expect(res.status).toBe(404);
      expect(res.body.success).toBe(false);
    });
  });

  describe('POST /api/recordings/:recordingId/playback/pause', () => {
    it('should pause playback', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      service.startPlayback(recording.id);

      const res = await request(app).post(`/api/recordings/${recording.id}/playback/pause`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.isPlaying).toBe(false);
    });
  });

  describe('POST /api/recordings/:recordingId/playback/resume', () => {
    it('should resume playback', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      service.startPlayback(recording.id);
      service.pausePlayback(recording.id);

      const res = await request(app).post(`/api/recordings/${recording.id}/playback/resume`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.isPlaying).toBe(true);
    });
  });

  describe('PATCH /api/recordings/:recordingId/playback/speed', () => {
    it('should set playback speed', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      service.startPlayback(recording.id);

      const res = await request(app)
        .patch(`/api/recordings/${recording.id}/playback/speed`)
        .send({ speed: 2 });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.playbackSpeed).toBe(2);
    });

    it('should return 400 for invalid speed', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      service.startPlayback(recording.id);

      const res = await request(app)
        .patch(`/api/recordings/${recording.id}/playback/speed`)
        .send({ speed: 15 });

      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
    });
  });

  describe('POST /api/recordings/:recordingId/playback/seek', () => {
    it('should seek in recording', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      
      // Add events to extend duration
      const startTime = Date.now();
      service.recordFileChange(recording.id, {
        timestamp: startTime,
        path: '/file0.ts',
        type: 'create',
      });
      
      // Wait to ensure duration > 0
      await new Promise((resolve) => setTimeout(resolve, 100));
      
      service.stopRecording(recording.id);
      service.startPlayback(recording.id);

      const res = await request(app)
        .post(`/api/recordings/${recording.id}/playback/seek`)
        .send({ timeMs: 50 });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
    }, 15000);

    it('should return 400 for invalid time', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      service.startPlayback(recording.id);

      const res = await request(app)
        .post(`/api/recordings/${recording.id}/playback/seek`)
        .send({ timeMs: 'invalid' });

      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
    });
  });

  describe('PATCH /api/recordings/:recordingId/playback/layer/:layer', () => {
    it('should toggle layer visibility', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      service.startPlayback(recording.id);

      const res = await request(app).patch(`/api/recordings/${recording.id}/playback/layer/files`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.visibleLayers.files).toBe(false);
    });

    it('should return 400 for invalid layer', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      service.startPlayback(recording.id);

      const res = await request(app).patch(`/api/recordings/${recording.id}/playback/layer/invalid`);

      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
    });
  });

  describe('POST /api/recordings/:recordingId/playback/stop', () => {
    it('should stop playback', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      service.startPlayback(recording.id);

      const res = await request(app).post(`/api/recordings/${recording.id}/playback/stop`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
    });

    it('should return 404 for non-existent playback', async () => {
      const res = await request(app).post('/api/recordings/non-existent/playback/stop');

      expect(res.status).toBe(404);
      expect(res.body.success).toBe(false);
    });
  });

  describe('GET /api/recordings/:recordingId/playback', () => {
    it('should get playback state', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      service.startPlayback(recording.id);

      const res = await request(app).get(`/api/recordings/${recording.id}/playback`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.isPlaying).toBe(true);
    });

    it('should return 404 for non-existent playback', async () => {
      const res = await request(app).get('/api/recordings/non-existent/playback');

      expect(res.status).toBe(404);
      expect(res.body.success).toBe(false);
    });
  });

  describe('POST /api/recordings/:recordingId/share', () => {
    it('should generate share token', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      const res = await request(app).post(`/api/recordings/${recording.id}/share`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.token).toBeDefined();
      expect(res.body.data.url).toBeDefined();
    });

    it('should return 404 for non-existent recording', async () => {
      const res = await request(app).post('/api/recordings/non-existent/share');

      expect(res.status).toBe(404);
      expect(res.body.success).toBe(false);
    });
  });

  describe('GET /api/recordings/share/:token', () => {
    it('should get recording by share token', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const token = service.generateShareToken(recording.id);

      const res = await request(app).get(`/api/recordings/share/${token}`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.id).toBe(recording.id);
    });

    it('should return 404 for invalid token', async () => {
      const res = await request(app).get('/api/recordings/share/invalid-token');

      expect(res.status).toBe(404);
      expect(res.body.success).toBe(false);
    });
  });

  describe('DELETE /api/recordings/:recordingId/share', () => {
    it('should revoke share token', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      service.generateShareToken(recording.id);

      const res = await request(app).delete(`/api/recordings/${recording.id}/share`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(recording.shareToken).toBeUndefined();
    });
  });

  describe('POST /api/recordings/:recordingId/export', () => {
    it('should export recording', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      const res = await request(app)
        .post(`/api/recordings/${recording.id}/export`)
        .send({
          format: 'mp4',
          quality: 'high',
          speed: 1,
          width: 1920,
          height: 1080,
        });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.path).toBeDefined();
      expect(res.body.data.url).toBeDefined();
    });

    it('should return 400 for missing fields', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      const res = await request(app)
        .post(`/api/recordings/${recording.id}/export`)
        .send({ format: 'mp4' });

      expect(res.status).toBe(400);
      expect(res.body.success).toBe(false);
    });
  });

  describe('GET /api/recordings/:recordingId/frame/:timeMs', () => {
    it('should get frame at time', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');
      const now = Date.now();

      service.recordFileChange(recording.id, {
        timestamp: now,
        path: '/file.ts',
        type: 'create',
      });

      const res = await request(app).get(`/api/recordings/${recording.id}/frame/0`);

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data).toBeDefined();
    });

    it('should return 404 for non-existent frame', async () => {
      const recording = service.startRecording('session-123', 'user1', 'workspace-123');

      const res = await request(app).get(`/api/recordings/${recording.id}/frame/999999999`);

      expect(res.status).toBe(404);
      expect(res.body.success).toBe(false);
    });
  });

  describe('GET /api/recordings/stats/all', () => {
    it('should get statistics', async () => {
      service.startRecording('session-123', 'user1', 'workspace-123');
      service.startRecording('session-456', 'user2', 'workspace-456');

      const res = await request(app).get('/api/recordings/stats/all');

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.data.totalRecordings).toBe(2);
      expect(res.body.data.recordingsByUser).toBeDefined();
    });
  });
});
