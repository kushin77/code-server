// @file        apps/backend/src/services/voice-channel/index.ts
// @module      collaboration/voice-channel
// @description LiveKit-backed voice channel service for IDE collaboration

import { EventEmitter } from 'events';
import * as LiveKitSDK from 'livekit-server-sdk';

const { AccessToken } = LiveKitSDK;

export class VoiceChannelService extends EventEmitter {
  constructor(config, pool, redis) {
    super();
    this.config = config;
    this.pool = pool;
    this.redis = redis;
    this.activeSessions = new Map();
    this.sessionParticipants = new Map();

    if (!config.liveKitUrl || !config.liveKitApiKey || !config.liveKitApiSecret) {
      throw new Error('LiveKit configuration incomplete');
    }
  }

  async initialize() {
    const sessionKeys = await this.redis.keys('voice:session:*');
    for (const key of sessionKeys) {
      const sessionData = await this.redis.get(key);
      if (sessionData) {
        const session = JSON.parse(sessionData);
        this.activeSessions.set(session.sessionId, session);
      }
    }

    console.log(
      `[VoiceChannelService] Initialized with ${this.activeSessions.size} existing sessions`
    );
  }

  async createSession(workspaceId, userId, userName) {
    const sessionId = `voice-${workspaceId}-${Date.now()}`;
    const roomName = `workspace-${workspaceId}`;

    try {
      const token = this.generateLiveKitToken(userName, roomName, userId);

      const session = {
        sessionId,
        workspaceId,
        userId,
        liveKitToken: token,
        liveKitRoomName: roomName,
        startedAt: Date.now(),
        participantCount: 1,
        status: 'active',
      };

      await this.redis.setex(`voice:session:${sessionId}`, 86400, JSON.stringify(session));

      this.activeSessions.set(sessionId, session);
      this.sessionParticipants.set(sessionId, [
        {
          userId,
          username: userName,
          displayName: userName,
          status: 'connected',
          joinedAt: Date.now(),
        },
      ]);

      this.emit('session_created', {
        type: 'session_created',
        sessionId,
        timestamp: Date.now(),
        data: { workspaceId, userId, roomName },
      });

      return session;
    } catch (error) {
      console.error('[VoiceChannelService] Failed to create session:', error);
      throw new Error(`Failed to create voice session: ${error}`);
    }
  }

  async joinSession(sessionId, userId, userName) {
    const session = this.activeSessions.get(sessionId);
    if (!session) {
      throw new Error(`Voice session not found: ${sessionId}`);
    }

    if (session.status !== 'active') {
      throw new Error(`Voice session not active: ${sessionId}`);
    }

    const token = this.generateLiveKitToken(userName, session.liveKitRoomName, userId);

    const participants = this.sessionParticipants.get(sessionId) || [];
    if (!participants.find((participant) => participant.userId === userId)) {
      participants.push({
        userId,
        username: userName,
        displayName: userName,
        status: 'connected',
        joinedAt: Date.now(),
      });
      this.sessionParticipants.set(sessionId, participants);

      session.participantCount = participants.length;
      await this.redis.setex(`voice:session:${sessionId}`, 86400, JSON.stringify(session));

      this.emit('participant_joined', {
        type: 'participant_joined',
        sessionId,
        timestamp: Date.now(),
        data: { userId, userName },
      });
    }

    return { token, session };
  }

  async leaveSession(sessionId, userId) {
    const participants = this.sessionParticipants.get(sessionId);
    if (!participants) {
      return;
    }

    const remaining = participants.filter((participant) => participant.userId !== userId);
    this.sessionParticipants.set(sessionId, remaining);

    const session = this.activeSessions.get(sessionId);
    if (session) {
      session.participantCount = remaining.length;

      if (remaining.length === 0) {
        await this.endSession(sessionId);
      } else {
        await this.redis.setex(`voice:session:${sessionId}`, 86400, JSON.stringify(session));
      }
    }

    this.emit('participant_left', {
      type: 'participant_left',
      sessionId,
      timestamp: Date.now(),
      data: { userId },
    });
  }

  async endSession(sessionId) {
    const session = this.activeSessions.get(sessionId);
    if (!session) {
      return;
    }

    session.status = 'ended';
    await this.redis.del(`voice:session:${sessionId}`);
    this.activeSessions.delete(sessionId);
    this.sessionParticipants.delete(sessionId);

    this.emit('session_ended', {
      type: 'session_ended',
      sessionId,
      timestamp: Date.now(),
    });
  }

  getSession(sessionId) {
    return this.activeSessions.get(sessionId);
  }

  getParticipants(sessionId) {
    return this.sessionParticipants.get(sessionId) || [];
  }

  getWorkspaceSessions(workspaceId) {
    return Array.from(this.activeSessions.values()).filter(
      (session) => session.workspaceId === workspaceId
    );
  }

  generateLiveKitToken(identity, room, userId) {
    try {
      const token = new AccessToken(this.config.liveKitApiKey, this.config.liveKitApiSecret, {
        identity,
        name: identity,
        metadata: JSON.stringify({ userId }),
      });

      token.addGrant({
        roomJoin: true,
        room,
        canPublish: true,
        canSubscribe: true,
        canPublishData: true,
      });

      return token.toJwt();
    } catch (error) {
      console.error('[VoiceChannelService] Token generation failed:', error);
      throw error;
    }
  }

  async getStats() {
    const sessions = Array.from(this.activeSessions.values());
    const allParticipants = Array.from(this.sessionParticipants.values()).flat();

    const latencies = allParticipants
      .map((participant) => participant.audioLatencyMs || 0)
      .filter((latency) => latency > 0);
    const avgLatency =
      latencies.length > 0 ? latencies.reduce((sum, value) => sum + value, 0) / latencies.length : 0;

    const qualities = allParticipants
      .map((participant) => participant.audioQualityScore || 85)
      .sort((a, b) => a - b);

    return {
      activeSessionsCount: sessions.length,
      totalParticipants: allParticipants.length,
      averageLatencyMs: avgLatency,
      audioQualityP50: qualities[Math.floor(qualities.length * 0.5)] || 85,
      audioQualityP95: qualities[Math.floor(qualities.length * 0.95)] || 85,
      noiseReductionEnabled: this.config.noiseCancellationEnabled,
      timestamp: Date.now(),
    };
  }

  async updateParticipantMetrics(sessionId, userId, metrics) {
    const participants = this.sessionParticipants.get(sessionId);
    if (!participants) {
      return;
    }

    const participant = participants.find((item) => item.userId === userId);
    if (participant) {
      if (metrics.latencyMs !== undefined) {
        participant.audioLatencyMs = metrics.latencyMs;

        if (metrics.latencyMs > 60) {
          this.emit('latency_high', {
            type: 'latency_high',
            sessionId,
            timestamp: Date.now(),
            data: { userId, latencyMs: metrics.latencyMs },
          });
        }
      }

      if (metrics.audioQualityScore !== undefined) {
        participant.audioQualityScore = metrics.audioQualityScore;

        if (metrics.audioQualityScore < 70) {
          this.emit('audio_quality_degraded', {
            type: 'audio_quality_degraded',
            sessionId,
            timestamp: Date.now(),
            data: { userId, qualityScore: metrics.audioQualityScore },
          });
        }
      }
    }
  }
}

export async function initializeVoiceChannelService(config, pool, redis) {
  const service = new VoiceChannelService(config, pool, redis);
  await service.initialize();
  return service;
}