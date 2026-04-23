// @file        apps/backend/src/services/voice-channel/__tests__/index.test.ts
// @module      collaboration/voice-channel
// @description Voice channel service unit tests
import { describe, it, expect, beforeEach, vi } from 'vitest';
// Mock livekit-server-sdk before importing the service
vi.mock('livekit-server-sdk', () => ({
    AccessToken: class MockAccessToken {
        constructor() {
            this.identity = '';
        }
        addGrant(grant) { }
        toJwt() {
            return `mock-jwt-token-${Date.now()}`;
        }
    },
    VideoGrant: class MockVideoGrant {
        constructor(options) {
            Object.assign(this, options);
        }
    },
    accessToken: {
        AccessToken: class MockAccessToken {
            constructor() {
                this.identity = '';
            }
            addGrant(grant) { }
            toJwt() {
                return `mock-jwt-token-${Date.now()}`;
            }
        },
        VideoGrant: class MockVideoGrant {
            constructor(options) {
                Object.assign(this, options);
            }
        },
    },
}));
import { VoiceChannelService } from '../index';
describe('VoiceChannelService', () => {
    let pool;
    let redis;
    let voiceService;
    let config;
    beforeEach(async () => {
        // Mock pool and redis
        pool = {
            query: vi.fn(),
            connect: vi.fn(),
            end: vi.fn(),
        };
        redis = {
            get: vi.fn(),
            set: vi.fn(),
            setex: vi.fn(),
            del: vi.fn(),
            keys: vi.fn().mockResolvedValue([]),
            subscribe: vi.fn(),
        };
        config = {
            liveKitUrl: 'wss://livekit.kushnir.cloud',
            liveKitApiKey: 'test-key',
            liveKitApiSecret: 'test-secret',
            noiseCancellationEnabled: true,
            targetLatencyMs: 60,
            maxParticipantsPerRoom: 50,
            audioCodec: 'opus',
            enableRecording: false,
        };
        voiceService = new VoiceChannelService(config, pool, redis);
        await voiceService.initialize();
    });
    describe('Session Management', () => {
        it('should create a new voice session', async () => {
            const session = await voiceService.createSession('workspace-123', 'user-1', 'Alice');
            expect(session).toBeDefined();
            expect(session.workspaceId).toBe('workspace-123');
            expect(session.userId).toBe('user-1');
            expect(session.status).toBe('active');
            expect(session.liveKitToken).toBeDefined();
            expect(session.liveKitRoomName).toBe('workspace-workspace-123');
            expect(session.participantCount).toBe(1);
        });
        it('should emit session_created event', async () => {
            const eventHandler = vi.fn();
            voiceService.on('session_created', eventHandler);
            const session = await voiceService.createSession('workspace-123', 'user-1', 'Alice');
            expect(eventHandler).toHaveBeenCalled();
            expect(eventHandler.mock.calls[0][0].type).toBe('session_created');
            expect(eventHandler.mock.calls[0][0].data.userId).toBe('user-1');
        });
        it('should join existing session', async () => {
            const session = await voiceService.createSession('workspace-123', 'user-1', 'Alice');
            const result = await voiceService.joinSession(session.sessionId, 'user-2', 'Bob');
            expect(result.token).toBeDefined();
            expect(result.session.participantCount).toBe(2);
        });
        it('should emit participant_joined event', async () => {
            const session = await voiceService.createSession('workspace-123', 'user-1', 'Alice');
            const eventHandler = vi.fn();
            voiceService.on('participant_joined', eventHandler);
            await voiceService.joinSession(session.sessionId, 'user-2', 'Bob');
            expect(eventHandler).toHaveBeenCalled();
            expect(eventHandler.mock.calls[0][0].data.userId).toBe('user-2');
        });
        it('should fail to join non-existent session', async () => {
            await expect(voiceService.joinSession('non-existent', 'user-1', 'Alice')).rejects.toThrow('Voice session not found');
        });
        it('should leave session and emit event', async () => {
            const session = await voiceService.createSession('workspace-123', 'user-1', 'Alice');
            const eventHandler = vi.fn();
            voiceService.on('participant_left', eventHandler);
            await voiceService.leaveSession(session.sessionId, 'user-1');
            expect(eventHandler).toHaveBeenCalled();
            expect(eventHandler.mock.calls[0][0].data.userId).toBe('user-1');
        });
        it('should end session when last participant leaves', async () => {
            const session = await voiceService.createSession('workspace-123', 'user-1', 'Alice');
            const endHandler = vi.fn();
            voiceService.on('session_ended', endHandler);
            await voiceService.leaveSession(session.sessionId, 'user-1');
            expect(endHandler).toHaveBeenCalled();
            // Session is deleted from map when ended, so getSession returns undefined
            expect(voiceService.getSession(session.sessionId)).toBeUndefined();
        });
    });
    describe('Participant Management', () => {
        it('should get participants in session', async () => {
            const session = await voiceService.createSession('workspace-123', 'user-1', 'Alice');
            await voiceService.joinSession(session.sessionId, 'user-2', 'Bob');
            const participants = voiceService.getParticipants(session.sessionId);
            expect(participants.length).toBe(2);
            expect(participants[0].userId).toBe('user-1');
            expect(participants[1].userId).toBe('user-2');
        });
        it('should update participant metrics', async () => {
            const session = await voiceService.createSession('workspace-123', 'user-1', 'Alice');
            await voiceService.updateParticipantMetrics(session.sessionId, 'user-1', {
                latencyMs: 45,
                audioQualityScore: 92,
            });
            const participants = voiceService.getParticipants(session.sessionId);
            const participant = participants[0];
            expect(participant.audioLatencyMs).toBe(45);
            expect(participant.audioQualityScore).toBe(92);
        });
        it('should emit high latency event when latency > 60ms', async () => {
            const session = await voiceService.createSession('workspace-123', 'user-1', 'Alice');
            const eventHandler = vi.fn();
            voiceService.on('latency_high', eventHandler);
            await voiceService.updateParticipantMetrics(session.sessionId, 'user-1', {
                latencyMs: 75, // > 60ms SLA
            });
            expect(eventHandler).toHaveBeenCalled();
            expect(eventHandler.mock.calls[0][0].data.latencyMs).toBe(75);
        });
        it('should emit audio quality degraded event when quality < 70', async () => {
            const session = await voiceService.createSession('workspace-123', 'user-1', 'Alice');
            const eventHandler = vi.fn();
            voiceService.on('audio_quality_degraded', eventHandler);
            await voiceService.updateParticipantMetrics(session.sessionId, 'user-1', {
                audioQualityScore: 65, // < 70
            });
            expect(eventHandler).toHaveBeenCalled();
            expect(eventHandler.mock.calls[0][0].data.qualityScore).toBe(65);
        });
    });
    describe('Statistics', () => {
        it('should calculate voice statistics', async () => {
            const session1 = await voiceService.createSession('workspace-123', 'user-1', 'Alice');
            await voiceService.joinSession(session1.sessionId, 'user-2', 'Bob');
            const session2 = await voiceService.createSession('workspace-456', 'user-3', 'Charlie');
            const stats = await voiceService.getStats();
            expect(stats.activeSessionsCount).toBe(2);
            expect(stats.totalParticipants).toBe(3);
            expect(stats.noiseReductionEnabled).toBe(true);
            expect(stats.timestamp).toBeDefined();
        });
    });
    describe('Workspace Sessions', () => {
        it('should get all sessions for a workspace', async () => {
            // Create fresh service for this test to avoid state from other tests
            const freshService = new VoiceChannelService(config, pool, redis);
            await freshService.initialize();
            const sess1 = await freshService.createSession('workspace-123', 'user-1', 'Alice');
            const sess2 = await freshService.createSession('workspace-123', 'user-2', 'Bob');
            const sess3 = await freshService.createSession('workspace-456', 'user-3', 'Charlie');
            // Get sessions for workspace-123
            const sessions123 = freshService.getWorkspaceSessions('workspace-123');
            // Get sessions for workspace-456
            const sessions456 = freshService.getWorkspaceSessions('workspace-456');
            // All returned sessions should have correct workspaceId
            expect(sessions123.every((s) => s.workspaceId === 'workspace-123')).toBe(true);
            expect(sessions456.every((s) => s.workspaceId === 'workspace-456')).toBe(true);
            // Verify we can find the sessions we created
            const allSessions = [...sessions123, ...sessions456];
            expect(allSessions.map((s) => s.sessionId).includes(sess1.sessionId)).toBe(true);
            expect(allSessions.map((s) => s.sessionId).includes(sess3.sessionId)).toBe(true);
        });
    });
    describe('Error Handling', () => {
        it('should throw error for incomplete LiveKit config', () => {
            const badConfig = {
                liveKitUrl: '',
                liveKitApiKey: '',
                liveKitApiSecret: '',
                noiseCancellationEnabled: true,
                targetLatencyMs: 60,
                maxParticipantsPerRoom: 50,
                audioCodec: 'opus',
                enableRecording: false,
            };
            expect(() => new VoiceChannelService(badConfig, pool, redis)).toThrow('LiveKit configuration incomplete');
        });
    });
});
//# sourceMappingURL=index.test.js.map