// @file        apps/backend/src/integrations/slack/__tests__/handler.test.ts
// @module      integrations/slack/tests
// @description Unit tests for Slack integration handler
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { createHmac } from 'crypto';
import Redis from 'ioredis-mock';
import { getSessionInfo, getChannelSessions, revokeSession, verifySlackRequest, createSharedSession, } from '../handler';
// Mock Redis
vi.mock('ioredis', () => ({
    default: Redis,
}));
describe('Slack Integration Handler', () => {
    let redis;
    beforeEach(() => {
        redis = new Redis();
        vi.resetAllMocks();
    });
    afterEach(async () => {
        await redis.flushall();
        redis.disconnect();
    });
    describe('verifySlackRequest', () => {
        it('should verify valid Slack request signature', () => {
            const timestamp = Math.floor(Date.now() / 1000).toString();
            const body = 'test=body';
            const secret = 'test_secret';
            const baseString = `v0:${timestamp}:${body}`;
            const signature = createHmac('sha256', secret)
                .update(baseString)
                .digest('hex');
            const req = {
                headers: {
                    'x-slack-signature': `v0=${signature}`,
                    'x-slack-request-timestamp': timestamp,
                },
                rawBody: body,
            };
            expect(verifySlackRequest(req)).toBe(true);
        });
        it('should reject request with invalid signature', () => {
            const timestamp = Math.floor(Date.now() / 1000).toString();
            const req = {
                headers: {
                    'x-slack-signature': 'v0=invalid_signature',
                    'x-slack-request-timestamp': timestamp,
                },
                rawBody: 'test=body',
            };
            expect(verifySlackRequest(req)).toBe(false);
        });
        it('should reject request with old timestamp', () => {
            const oldTimestamp = (Math.floor(Date.now() / 1000) - 400).toString();
            const req = {
                headers: {
                    'x-slack-signature': 'v0=any_signature',
                    'x-slack-request-timestamp': oldTimestamp,
                },
                rawBody: 'test=body',
            };
            expect(verifySlackRequest(req)).toBe(false);
        });
        it('should reject request without signature headers', () => {
            const req = {
                headers: {},
                rawBody: 'test=body',
            };
            expect(verifySlackRequest(req)).toBe(false);
        });
    });
    describe('createSharedSession', () => {
        it('should create a new shared session', async () => {
            const session = await createSharedSession('U123456', 'alice', 'T123456', 'C987654', '/repo/path');
            expect(session.sessionId).toBeDefined();
            expect(session.createdBy.userId).toBe('U123456');
            expect(session.createdBy.userName).toBe('alice');
            expect(session.shareUrl).toContain(session.sessionId);
            expect(session.repositoryPath).toBe('/repo/path');
        });
        it('should store session in Redis with TTL', async () => {
            const session = await createSharedSession('U123456', 'alice', 'T123456', 'C987654');
            const key = `slack:session:${session.sessionId}`;
            const stored = await redis.get(key);
            expect(stored).toBeDefined();
            const parsed = JSON.parse(stored);
            expect(parsed.sessionId).toBe(session.sessionId);
        });
        it('should generate valid share URL', async () => {
            const session = await createSharedSession('U123456', 'alice', 'T123456', 'C987654');
            expect(session.shareUrl).toMatch(/^https:\/\/.+\/share\/.+$/);
            expect(session.shareUrl).toContain(session.sessionId);
        });
    });
    describe('getSessionInfo', () => {
        it('should retrieve session by ID', async () => {
            const created = await createSharedSession('U123456', 'alice', 'T123456', 'C987654');
            const retrieved = await getSessionInfo(created.sessionId);
            expect(retrieved).toBeDefined();
            expect(retrieved?.sessionId).toBe(created.sessionId);
            expect(retrieved?.createdBy.userName).toBe('alice');
        });
        it('should return null for non-existent session', async () => {
            const session = await getSessionInfo('non-existent-id');
            expect(session).toBeNull();
        });
        it('should return null for expired session', async () => {
            // Create session directly with past expiration
            const sessionId = 'test-expired';
            const session = {
                sessionId,
                createdBy: { userId: 'U123', userName: 'alice', teamId: 'T123' },
                createdAt: Date.now() - 86400000,
                expiresAt: Date.now() - 1000, // Expired 1 second ago
                shareUrl: 'https://example.com/share/test',
                channelId: 'C123',
            };
            const key = `slack:session:${sessionId}`;
            await redis.setex(key, 1, JSON.stringify(session));
            // Wait for expiration
            await new Promise((resolve) => setTimeout(resolve, 1100));
            const retrieved = await getSessionInfo(sessionId);
            expect(retrieved).toBeNull();
        });
    });
    describe('getChannelSessions', () => {
        it('should list active sessions for a channel', async () => {
            const channelId = 'C987654';
            const session1 = await createSharedSession('U1', 'alice', 'T1', channelId);
            const session2 = await createSharedSession('U2', 'bob', 'T1', channelId);
            const sessions = await getChannelSessions(channelId);
            expect(sessions).toHaveLength(2);
            expect(sessions.map((s) => s.sessionId)).toContain(session1.sessionId);
            expect(sessions.map((s) => s.sessionId)).toContain(session2.sessionId);
        });
        it('should return empty list for channel with no sessions', async () => {
            const sessions = await getChannelSessions('C_EMPTY');
            expect(sessions).toHaveLength(0);
        });
        it('should filter out expired sessions', async () => {
            const channelId = 'C987654';
            // Create two sessions
            const session1 = await createSharedSession('U1', 'alice', 'T1', channelId);
            const session2 = await createSharedSession('U2', 'bob', 'T1', channelId);
            // Manually expire session2
            await redis.del(`slack:session:${session2.sessionId}`);
            const sessions = await getChannelSessions(channelId);
            expect(sessions).toHaveLength(1);
            expect(sessions[0].sessionId).toBe(session1.sessionId);
        });
    });
    describe('revokeSession', () => {
        it('should revoke an active session', async () => {
            const session = await createSharedSession('U123', 'alice', 'T123', 'C123');
            const revoked = await revokeSession(session.sessionId);
            expect(revoked).toBe(true);
            const retrieved = await getSessionInfo(session.sessionId);
            expect(retrieved).toBeNull();
        });
        it('should return false when revoking non-existent session', async () => {
            const revoked = await revokeSession('non-existent');
            expect(revoked).toBe(false);
        });
        it('should handle multiple revokes gracefully', async () => {
            const session = await createSharedSession('U123', 'alice', 'T123', 'C123');
            const revoke1 = await revokeSession(session.sessionId);
            const revoke2 = await revokeSession(session.sessionId);
            expect(revoke1).toBe(true);
            expect(revoke2).toBe(false);
        });
    });
    describe('Session lifecycle', () => {
        it('should handle complete session lifecycle', async () => {
            // 1. Create session
            const session = await createSharedSession('U123', 'alice', 'T123', 'C123', '/repo');
            expect(session.sessionId).toBeDefined();
            // 2. Retrieve session
            const retrieved = await getSessionInfo(session.sessionId);
            expect(retrieved?.repositoryPath).toBe('/repo');
            // 3. Add to channel list
            const channelSessions = await getChannelSessions('C123');
            expect(channelSessions).toHaveLength(1);
            // 4. Revoke session
            const revoked = await revokeSession(session.sessionId);
            expect(revoked).toBe(true);
            // 5. Verify removed from channel list
            const updatedSessions = await getChannelSessions('C123');
            expect(updatedSessions).toHaveLength(0);
        });
        it('should support multiple concurrent sessions', async () => {
            const sessions = await Promise.all([
                createSharedSession('U1', 'alice', 'T1', 'C1'),
                createSharedSession('U2', 'bob', 'T1', 'C2'),
                createSharedSession('U3', 'charlie', 'T1', 'C1'),
            ]);
            expect(sessions).toHaveLength(3);
            const c1Sessions = await getChannelSessions('C1');
            expect(c1Sessions).toHaveLength(2);
            const c2Sessions = await getChannelSessions('C2');
            expect(c2Sessions).toHaveLength(1);
        });
    });
});
//# sourceMappingURL=handler.test.js.map