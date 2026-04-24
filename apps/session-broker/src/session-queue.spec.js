import { describe, expect, it } from 'vitest';
import { compareSessionQueueDescriptors, estimateQueueWaitSeconds, normalizeSessionQueueLane, } from './session-queue.js';
describe('session queue helpers', () => {
    it('normalizes queue lanes and orders fast lanes first', () => {
        expect(normalizeSessionQueueLane('FAST')).toBe('fast');
        expect(normalizeSessionQueueLane('standard')).toBe('standard');
        expect(normalizeSessionQueueLane(undefined)).toBe('standard');
        const ordered = [
            { sessionId: 'b', queueLane: 'standard', queuedAt: 20, sequence: 2 },
            { sessionId: 'a', queueLane: 'fast', queuedAt: 10, sequence: 1 },
            { sessionId: 'c', queueLane: 'fast', queuedAt: 15, sequence: 3 },
        ].sort(compareSessionQueueDescriptors);
        expect(ordered.map((entry) => entry.sessionId)).toEqual(['a', 'c', 'b']);
        expect(estimateQueueWaitSeconds(1, 'fast')).toBeGreaterThan(0);
        expect(estimateQueueWaitSeconds(3, 'standard')).toBeGreaterThan(estimateQueueWaitSeconds(1, 'standard'));
    });
});
//# sourceMappingURL=session-queue.spec.js.map