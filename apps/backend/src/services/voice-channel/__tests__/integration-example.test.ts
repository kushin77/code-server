// @file        apps/backend/src/services/voice-channel/__tests__/integration-example.test.ts
// @module      collaboration/voice-channel/tests
// @description Tests for voice channel runtime integration example

import express from 'express';
import Redis from 'ioredis';
import request from 'supertest';
import { describe, expect, it, vi } from 'vitest';

vi.mock('livekit-server-sdk', () => ({
  AccessToken: class MockAccessToken {
    addGrant() {}
    toJwt() {
      return 'mock-jwt-token';
    }
  },
  VideoGrant: class MockVideoGrant {},
}));

import { createVoiceChannelExampleApp, initializeVoiceChannelRuntime, setupVoiceChannelIntegration } from '../integration-example';

describe('voice channel runtime integration example', () => {
  it('boots an express app that mounts the voice runtime and health route', async () => {
    const callback = vi.fn();
    const auditService = { emit: vi.fn() } as any;
    const pool = {
      query: vi.fn().mockResolvedValue({ rows: [] }),
      connect: vi.fn(),
      end: vi.fn(),
    } as any;
    const redis = {
      get: vi.fn(),
      set: vi.fn(),
      setex: vi.fn(),
      del: vi.fn(),
      keys: vi.fn().mockResolvedValue([]),
      subscribe: vi.fn(),
    } as any as Redis;

    const app = await createVoiceChannelExampleApp({
      pool,
      redis,
      auditService,
      config: {
        liveKitUrl: 'wss://livekit.example.com',
        liveKitApiKey: 'test-key',
        liveKitApiSecret: 'test-secret',
        noiseCancellationEnabled: true,
        targetLatencyMs: 60,
        maxParticipantsPerRoom: 50,
        audioCodec: 'opus',
        enableRecording: false,
      },
      onMeetingModeChange: callback,
    });

    const healthResponse = await request(app).get('/health');
    expect(healthResponse.status).toBe(200);
    expect(healthResponse.body.services).toContain('voice-channel');

    const createResponse = await request(app).post('/api/voice/sessions').send({ workspaceId: 'workspace-1' });
    expect(createResponse.status).toBe(200);
    expect(createResponse.body.session.sessionId).toContain('voice-workspace-1');

    const joinResponse = await request(app)
      .post(`/api/voice/sessions/${createResponse.body.session.sessionId}/join`)
      .send({});
    expect(joinResponse.status).toBe(200);

    expect(callback).toHaveBeenCalledWith(
      expect.any(String),
      true,
      createResponse.body.session.sessionId
    );
  });

  it('invokes meeting mode callback when a participant joins or leaves', async () => {
    const app = express();
    const callback = vi.fn();
    const auditService = { emit: vi.fn() } as any;
    const pool = {
      query: vi.fn(),
      connect: vi.fn(),
      end: vi.fn(),
    } as any;
    const redis = {
      get: vi.fn(),
      set: vi.fn(),
      setex: vi.fn(),
      del: vi.fn(),
      keys: vi.fn().mockResolvedValue([]),
      subscribe: vi.fn(),
    } as any as Redis;

    const { service } = await initializeVoiceChannelRuntime(app, {
      pool,
      redis,
      auditService,
      config: {
        liveKitUrl: 'wss://livekit.example.com',
        liveKitApiKey: 'test-key',
        liveKitApiSecret: 'test-secret',
        noiseCancellationEnabled: true,
        targetLatencyMs: 60,
        maxParticipantsPerRoom: 50,
        audioCodec: 'opus',
        enableRecording: false,
      },
      onMeetingModeChange: callback,
    });

    const session = await service.createSession('workspace-1', 'user-1', 'Alice');
    await service.joinSession(session.sessionId, 'user-2', 'Bob');
    await service.leaveSession(session.sessionId, 'user-2');

    expect(callback).toHaveBeenCalledWith('user-2', true, session.sessionId);
    expect(callback).toHaveBeenCalledWith('user-2', false, session.sessionId);
  });

  it('wires the runtime helper directly into an Express app', async () => {
    const app = express();
    const callback = vi.fn();
    const auditService = { emit: vi.fn() } as any;
    const pool = {
      query: vi.fn().mockResolvedValue({ rows: [] }),
      connect: vi.fn(),
      end: vi.fn(),
    } as any;
    const redis = {
      get: vi.fn(),
      set: vi.fn(),
      setex: vi.fn(),
      del: vi.fn(),
      keys: vi.fn().mockResolvedValue([]),
      subscribe: vi.fn(),
    } as any as Redis;

    const { service } = await setupVoiceChannelIntegration(app, {
      pool,
      redis,
      auditService,
      config: {
        liveKitUrl: 'wss://livekit.example.com',
        liveKitApiKey: 'test-key',
        liveKitApiSecret: 'test-secret',
        noiseCancellationEnabled: true,
        targetLatencyMs: 60,
        maxParticipantsPerRoom: 50,
        audioCodec: 'opus',
        enableRecording: false,
      },
      onMeetingModeChange: callback,
    });

    const session = await service.createSession('workspace-1', 'user-1', 'Alice');
    await service.joinSession(session.sessionId, 'user-2', 'Bob');
    await service.leaveSession(session.sessionId, 'user-2');

    expect(callback).toHaveBeenCalledWith('user-2', true, session.sessionId);
    expect(callback).toHaveBeenCalledWith('user-2', false, session.sessionId);
  });
});