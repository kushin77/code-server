import { describe, expect, it } from 'vitest';
import { createSessionAuditEvent, ensureCorrelationId, isTransitionAllowed, } from './session-policy.js';
describe('session policy helpers', () => {
    it('allows only declared lifecycle transitions', () => {
        expect(isTransitionAllowed('requested', 'provisioning')).toBe(true);
        expect(isTransitionAllowed('provisioning', 'ready')).toBe(true);
        expect(isTransitionAllowed('ready', 'destroyed')).toBe(false);
        expect(isTransitionAllowed('destroyed', 'requested')).toBe(false);
    });
    it('preserves an explicit correlation id and generates one when missing', () => {
        expect(ensureCorrelationId('trace-123')).toBe('trace-123');
        expect(ensureCorrelationId()).toMatch(/[0-9a-f-]{36}/);
    });
    it('creates immutable audit events with timestamps and details', () => {
        const event = createSessionAuditEvent({
            sessionId: 'session-1',
            actor: 'system',
            action: 'transition',
            fromStatus: 'requested',
            toStatus: 'provisioning',
            reason: 'boot',
            correlationId: 'trace-456',
            details: { containerPort: 8081 },
            timestamp: 1234567890,
        });
        expect(event.eventId).toHaveLength(36);
        expect(event.timestamp).toBe(1234567890);
        expect(event.sessionId).toBe('session-1');
        expect(event.correlationId).toBe('trace-456');
        expect(event.details).toEqual({ containerPort: 8081 });
        expect(event.previousEventHash).toBeUndefined();
        expect(event.eventHash).toMatch(/^[0-9a-f]{64}$/);
    });
    it('chains audit event hashes deterministically', () => {
        const first = createSessionAuditEvent({
            sessionId: 'session-1',
            actor: 'system',
            action: 'create',
            fromStatus: 'requested',
            toStatus: 'provisioning',
            reason: 'boot',
            correlationId: 'trace-1',
            timestamp: 123,
        });
        const second = createSessionAuditEvent({
            sessionId: 'session-1',
            actor: 'system',
            action: 'transition',
            fromStatus: 'provisioning',
            toStatus: 'ready',
            reason: 'started',
            correlationId: 'trace-1',
            previousEventHash: first.eventHash,
            timestamp: 456,
        });
        expect(second.previousEventHash).toBe(first.eventHash);
        expect(second.eventHash).not.toBe(first.eventHash);
    });
});
//# sourceMappingURL=session-policy.spec.js.map