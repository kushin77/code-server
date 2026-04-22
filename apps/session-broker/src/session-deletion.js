import { createHash } from 'node:crypto';
const isDeletionPhase = (value) => value === 'quarantined' || value === 'completed' || value === 'partial';
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
const computeChecksum = (record) => {
    return `sha256:${createHash('sha256').update(stableSerialize(record)).digest('hex')}`;
};
export const buildSessionDeletionRecord = (input) => {
    const createdAt = new Date().toISOString();
    const quarantineUntil = input.quarantineUntil ?? new Date(Date.now() + input.quarantineHours * 60 * 60 * 1000).toISOString();
    const recordWithoutChecksum = {
        sessionId: input.sessionId,
        actor: input.actor,
        reason: input.reason,
        correlationId: input.correlationId,
        createdAt,
        status: 'quarantined',
        quarantineUntil,
        quarantineRoot: input.resourcesBefore.quarantineRoot,
        hold: false,
        resourcesBefore: input.resourcesBefore,
        resourcesRemoved: [...new Set(input.resourcesRemoved)],
        resourcesRemaining: [...new Set(input.resourcesRemaining)],
        residualResourceZero: false,
        errors: [...(input.errors ?? [])],
    };
    return {
        ...recordWithoutChecksum,
        checksum: computeChecksum(recordWithoutChecksum),
    };
};
export const normalizeSessionDeletionRecord = (record) => {
    if (!record || typeof record !== 'object') {
        return null;
    }
    const resourcesBefore = record.resourcesBefore && typeof record.resourcesBefore === 'object'
        ? record.resourcesBefore
        : undefined;
    if (!record.sessionId || !record.actor || !record.reason || !record.correlationId || !record.createdAt || !record.quarantineUntil || !record.quarantineRoot || !resourcesBefore) {
        return null;
    }
    return {
        sessionId: record.sessionId,
        actor: record.actor,
        reason: record.reason,
        correlationId: record.correlationId,
        createdAt: record.createdAt,
        status: isDeletionPhase(record.status) ? record.status : 'quarantined',
        quarantineUntil: record.quarantineUntil,
        quarantineRoot: record.quarantineRoot,
        hold: Boolean(record.hold),
        holdReason: record.holdReason,
        holdAppliedBy: record.holdAppliedBy,
        holdAppliedAt: record.holdAppliedAt,
        overrideAppliedBy: record.overrideAppliedBy,
        overrideReason: record.overrideReason,
        purgedAt: record.purgedAt,
        purgeRequestedAt: record.purgeRequestedAt,
        resourcesBefore: {
            containerId: resourcesBefore.containerId,
            containerName: resourcesBefore.containerName,
            storageRoot: resourcesBefore.storageRoot,
            quarantineRoot: resourcesBefore.quarantineRoot,
            workspacePath: resourcesBefore.workspacePath,
            profilePath: resourcesBefore.profilePath,
            sessionRecordPresent: Boolean(resourcesBefore.sessionRecordPresent),
        },
        resourcesRemoved: Array.isArray(record.resourcesRemoved) ? record.resourcesRemoved : [],
        resourcesRemaining: Array.isArray(record.resourcesRemaining) ? record.resourcesRemaining : [],
        residualResourceZero: Boolean(record.residualResourceZero),
        errors: Array.isArray(record.errors) ? record.errors : [],
        checksum: typeof record.checksum === 'string' ? record.checksum : '',
    };
};
export const holdDeletionRecord = (record, input) => {
    const updated = {
        ...record,
        hold: true,
        holdReason: input.reason,
        holdAppliedBy: input.actor,
        holdAppliedAt: new Date().toISOString(),
        overrideAppliedBy: record.overrideAppliedBy,
        overrideReason: record.overrideReason,
        purgeRequestedAt: record.purgeRequestedAt,
        residualResourceZero: record.residualResourceZero,
    };
    return {
        ...updated,
        checksum: computeChecksum(updated),
    };
};
export const releaseDeletionHold = (record, input) => {
    const updated = {
        ...record,
        hold: false,
        holdReason: `${input.reason} (released by ${input.actor})`,
        overrideAppliedBy: record.overrideAppliedBy,
        overrideReason: record.overrideReason,
        purgeRequestedAt: record.purgeRequestedAt,
    };
    return {
        ...updated,
        checksum: computeChecksum(updated),
    };
};
export const finalizeDeletionRecord = (record, input, resourcesRemoved, errors = []) => {
    const mergedRemoved = [...new Set([...record.resourcesRemoved, ...resourcesRemoved])];
    const remaining = record.resourcesRemaining.filter((resource) => !mergedRemoved.includes(resource));
    const updated = {
        ...record,
        status: errors.length > 0 ? 'partial' : 'completed',
        hold: false,
        holdReason: record.holdReason,
        overrideAppliedBy: input.actor,
        overrideReason: input.reason,
        purgeRequestedAt: new Date().toISOString(),
        purgedAt: new Date().toISOString(),
        resourcesRemoved: mergedRemoved,
        resourcesRemaining: remaining,
        residualResourceZero: remaining.length === 0,
        errors: [...record.errors, ...errors],
    };
    return {
        ...updated,
        checksum: computeChecksum(updated),
    };
};
export const isDeletionQuarantineExpired = (record, now = Date.now()) => {
    return new Date(record.quarantineUntil).getTime() <= now;
};
export const isDeletionHoldActive = (record) => record.hold;
//# sourceMappingURL=session-deletion.js.map