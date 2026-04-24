/** @vitest-environment node */
import { describe, expect, it } from 'vitest';
import { formatDate, isApprovedDataProfile, normalizeDataProfile, normalizeUsername, stateTone } from '../ephemeralSessionsUtils';
describe('EphemeralSessions helpers', () => {
    it('normalizes usernames, formats timestamps, and maps session states to tones', () => {
        expect(normalizeUsername('alice@example.com', 'Alice Example')).toBe('aliceexample');
        expect(normalizeUsername('ab@example.com', 'A B')).toBe('ab0');
        expect(normalizeDataProfile('synthetic')).toBe('synthetic');
        expect(normalizeDataProfile('RAW')).toBeNull();
        expect(isApprovedDataProfile('masked')).toBe(true);
        expect(isApprovedDataProfile('production')).toBe(false);
        const formatted = formatDate('2026-04-19T20:00:00Z');
        expect(formatted.length).toBeGreaterThan(0);
        expect(stateTone('ready')).toContain('emerald');
        expect(stateTone('queued')).toContain('amber');
        expect(stateTone('teardown_pending')).toContain('orange');
        expect(stateTone('failed')).toContain('rose');
    });
});
//# sourceMappingURL=EphemeralSessions.test.js.map