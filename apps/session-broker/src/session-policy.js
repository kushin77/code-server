import { createHash } from 'node:crypto';
import { v4 as uuidv4 } from 'uuid';
export const ACTIVE_SESSION_STATES = [
    'requested',
    'provisioning',
    'ready',
    'testing',
];
export const TERMINAL_SESSION_STATES = [
    'teardown_pending',
    'destroyed',
    'failed',
];
export const ALLOWED_TRANSITIONS = {
    requested: ['provisioning', 'failed'],
    queued: ['provisioning', 'teardown_pending', 'failed'],
    provisioning: ['ready', 'failed'],
    ready: ['testing', 'teardown_pending', 'failed'],
    testing: ['ready', 'teardown_pending', 'failed'],
    teardown_pending: ['destroyed', 'failed'],
    destroyed: [],
    failed: [],
};
export const isTransitionAllowed = (current, next) => {
    if (current === next) {
        return true;
    }
    return ALLOWED_TRANSITIONS[current].includes(next);
};
export const ensureCorrelationId = (correlationId) => {
    const normalized = correlationId?.trim();
    return normalized && normalized.length > 0 ? normalized : uuidv4();
};
const stableSerialize = (value) => {
    if (value === null || value === undefined) {
        return 'null';
    }
    if (typeof value !== 'object') {
        return JSON.stringify(value);
    }
    if (value instanceof Date) {
        return JSON.stringify(value.toISOString());
    }
    if (Array.isArray(value)) {
        return `[${value.map((entry) => stableSerialize(entry)).join(',')}]`;
    }
    const record = value;
    const keys = Object.keys(record).sort();
    return `{${keys.map((key) => `${JSON.stringify(key)}:${stableSerialize(record[key])}`).join(',')}}`;
};
export const computeSessionAuditEventHash = (event) => {
    const hashPayload = {
        eventId: event.eventId,
        timestamp: event.timestamp,
        sessionId: event.sessionId,
        actor: event.actor,
        action: event.action,
        fromStatus: event.fromStatus,
        toStatus: event.toStatus,
        reason: event.reason,
        correlationId: event.correlationId,
        details: event.details,
        previousEventHash: event.previousEventHash,
    };
    return createHash('sha256').update(stableSerialize(hashPayload)).digest('hex');
};
export const createSessionAuditEvent = (event) => {
    const nextEvent = {
        eventId: uuidv4(),
        timestamp: event.timestamp ?? Date.now(),
        sessionId: event.sessionId,
        actor: event.actor,
        action: event.action,
        fromStatus: event.fromStatus,
        toStatus: event.toStatus,
        reason: event.reason,
        correlationId: event.correlationId,
        details: event.details,
        previousEventHash: event.previousEventHash,
    };
    return {
        ...nextEvent,
        eventHash: computeSessionAuditEventHash(nextEvent),
    };
};
//# sourceMappingURL=session-policy.js.map