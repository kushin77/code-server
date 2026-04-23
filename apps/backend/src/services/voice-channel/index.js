// @file        apps/backend/src/services/voice-channel/index.ts
// @module      collaboration/voice-channel
// @description LiveKit-backed voice channel service for IDE collaboration
import { EventEmitter } from 'events';
import * as LiveKitSDK from 'livekit-server-sdk';
/**
 * LiveKit SDK uses CommonJS and ESM in a way that sometimes requires caution with imports
 */
const { AccessToken, VideoGrant } = LiveKitSDK;
/**
 * Voice channel service managing WebRTC sessions via LiveKit
 * - Creates/manages voice sessions for workspace collaboration
 * - Generates LiveKit tokens for client connection
 * - Tracks participant presence and audio quality metrics
 * - Emits events for presence integration
 */
export class VoiceChannelService extends EventEmitter {
    constructor(config, pool, redis) {
        super();
        this.activeSessions = new Map();
        this.sessionParticipants = new Map();
        this.config = config;
        this.pool = pool;
        this.redis = redis;
        // Validate config
        if (!config.liveKitUrl || !config.liveKitApiKey || !config.liveKitApiSecret) {
            throw new Error('LiveKit configuration incomplete');
        }
    }
    /**
     * Initialize voice channel service
     */
    async initialize() {
        // Load existing sessions from Redis
        const sessionKeys = await this.redis.keys('voice:session:*');
        for (const key of sessionKeys) {
            const sessionData = await this.redis.get(key);
            if (sessionData) {
                const session = JSON.parse(sessionData);
                this.activeSessions.set(session.sessionId, session);
            }
        }
        console.log(`[VoiceChannelService] Initialized with ${this.activeSessions.size} existing sessions`);
    }
    /**
     * Create a new voice session for a workspace
     */
    async createSession(workspaceId, userId, userName) {
        const sessionId = `voice-${workspaceId}-${Date.now()}`;
        const roomName = `workspace-${workspaceId}`;
        try {
            // Generate LiveKit token for user
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
            // Store in Redis for persistence
            await this.redis.setex(`voice:session:${sessionId}`, 86400, // 24h expiry
            JSON.stringify(session));
            // Store in memory for fast access
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
            // Emit event for presence integration
            this.emit('session_created', {
                type: 'session_created',
                sessionId,
                timestamp: Date.now(),
                data: { workspaceId, userId, roomName },
            });
            return session;
        }
        catch (error) {
            console.error('[VoiceChannelService] Failed to create session:', error);
            throw new Error(`Failed to create voice session: ${error}`);
        }
    }
    /**
     * Join existing voice session
     */
    async joinSession(sessionId, userId, userName) {
        const session = this.activeSessions.get(sessionId);
        if (!session) {
            throw new Error(`Voice session not found: ${sessionId}`);
        }
        if (session.status !== 'active') {
            throw new Error(`Voice session not active: ${sessionId}`);
        }
        // Generate token for existing room
        const token = this.generateLiveKitToken(userName, session.liveKitRoomName, userId);
        // Add participant to session
        const participants = this.sessionParticipants.get(sessionId) || [];
        if (!participants.find((p) => p.userId === userId)) {
            participants.push({
                userId,
                username: userName,
                displayName: userName,
                status: 'connected',
                joinedAt: Date.now(),
            });
            this.sessionParticipants.set(sessionId, participants);
            // Update participant count
            session.participantCount = participants.length;
            await this.redis.setex(`voice:session:${sessionId}`, 86400, JSON.stringify(session));
            // Emit participant joined event
            this.emit('participant_joined', {
                type: 'participant_joined',
                sessionId,
                timestamp: Date.now(),
                data: { userId, userName },
            });
        }
        return { token, session };
    }
    /**
     * Leave voice session
     */
    async leaveSession(sessionId, userId) {
        const participants = this.sessionParticipants.get(sessionId);
        if (!participants) {
            return;
        }
        const remaining = participants.filter((p) => p.userId !== userId);
        this.sessionParticipants.set(sessionId, remaining);
        const session = this.activeSessions.get(sessionId);
        if (session) {
            session.participantCount = remaining.length;
            // End session if no participants remain
            if (remaining.length === 0) {
                await this.endSession(sessionId);
            }
            else {
                await this.redis.setex(`voice:session:${sessionId}`, 86400, JSON.stringify(session));
            }
        }
        // Emit participant left event
        this.emit('participant_left', {
            type: 'participant_left',
            sessionId,
            timestamp: Date.now(),
            data: { userId },
        });
    }
    /**
     * End voice session
     */
    async endSession(sessionId) {
        const session = this.activeSessions.get(sessionId);
        if (!session) {
            return;
        }
        session.status = 'ended';
        await this.redis.del(`voice:session:${sessionId}`);
        this.activeSessions.delete(sessionId);
        this.sessionParticipants.delete(sessionId);
        // Emit session ended event
        this.emit('session_ended', {
            type: 'session_ended',
            sessionId,
            timestamp: Date.now(),
        });
    }
    /**
     * Get session by ID
     */
    getSession(sessionId) {
        return this.activeSessions.get(sessionId);
    }
    /**
     * Get participants in session
     */
    getParticipants(sessionId) {
        return this.sessionParticipants.get(sessionId) || [];
    }
    /**
     * Get all active sessions for workspace
     */
    getWorkspaceSessions(workspaceId) {
        return Array.from(this.activeSessions.values()).filter((s) => s.workspaceId === workspaceId);
    }
    /**
     * Generate LiveKit access token
     * Uses livekit-server-sdk for production-grade WebRTC authentication
     */
    generateLiveKitToken(identity, room, userId) {
        try {
            const at = new AccessToken(this.config.liveKitApiKey, this.config.liveKitApiSecret, {
                identity,
                name: identity,
                metadata: JSON.stringify({ userId }),
            });
            at.addGrant({
                roomJoin: true,
                room: room,
                canPublish: true,
                canSubscribe: true,
                canPublishData: true,
            });
            return at.toJwt();
        }
        catch (error) {
            console.error('[VoiceChannelService] Token generation failed:', error);
            throw error;
        }
    }
    /**
     * Get voice channel statistics
     */
    async getStats() {
        const sessions = Array.from(this.activeSessions.values());
        const allParticipants = Array.from(this.sessionParticipants.values()).flat();
        // Calculate average latency (would be populated by client metrics in production)
        const latencies = allParticipants
            .map((p) => p.audioLatencyMs || 0)
            .filter((l) => l > 0);
        const avgLatency = latencies.length > 0
            ? latencies.reduce((a, b) => a + b) / latencies.length
            : 0;
        // Calculate audio quality percentiles (would be populated by client metrics)
        const qualities = allParticipants
            .map((p) => p.audioQualityScore || 85)
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
    /**
     * Update participant metrics
     */
    async updateParticipantMetrics(sessionId, userId, metrics) {
        const participants = this.sessionParticipants.get(sessionId);
        if (!participants) {
            return;
        }
        const participant = participants.find((p) => p.userId === userId);
        if (participant) {
            if (metrics.latencyMs !== undefined) {
                participant.audioLatencyMs = metrics.latencyMs;
                // Emit high latency event if > 60ms
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
                // Emit quality degraded event if < 70
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
/**
 * Factory function to initialize voice channel service
 */
export async function initializeVoiceChannelService(config, pool, redis) {
    const service = new VoiceChannelService(config, pool, redis);
    await service.initialize();
    return service;
}
//# sourceMappingURL=index.js.map