export const DEFAULT_SESSION_QUEUE_LANE = 'standard';
export function normalizeSessionQueueLane(value) {
    return value?.trim().toLowerCase() === 'fast' ? 'fast' : 'standard';
}
export function compareSessionQueueDescriptors(left, right) {
    if (left.queueLane !== right.queueLane) {
        return left.queueLane === 'fast' ? -1 : 1;
    }
    if (left.queuedAt !== right.queuedAt) {
        return left.queuedAt - right.queuedAt;
    }
    return left.sequence - right.sequence;
}
export function estimateQueueWaitSeconds(position, queueLane) {
    const baseWait = queueLane === 'fast' ? 45 : 120;
    return Math.max(30, Math.ceil(position * baseWait));
}
//# sourceMappingURL=session-queue.js.map