import { describe, expect, it } from 'vitest';
import { buildRepoCardActions, buildSeedRepoHomeCards, createDefaultRepoHomeSnapshot, formatRepoHomeRefreshLabel, formatRepoLastActivity, getRepoCardTone, readRepoHomeSnapshot, refreshRepoHomeSnapshot, resolveRepoStatusRefreshIntervalMs, sortRepoHomeCards, writeRepoHomeSnapshot, } from '../repoHomeData';
class MemoryStorage {
    constructor() {
        this.store = new Map();
    }
    getItem(key) {
        return this.store.get(key) ?? null;
    }
    setItem(key, value) {
        this.store.set(key, value);
    }
    removeItem(key) {
        this.store.delete(key);
    }
}
describe('repoHomeData', () => {
    it('round-trips the repo home snapshot through cache storage', () => {
        const storage = new MemoryStorage();
        const snapshot = createDefaultRepoHomeSnapshot(1700000000000);
        writeRepoHomeSnapshot(storage, snapshot);
        expect(readRepoHomeSnapshot(storage)).toEqual(snapshot);
    });
    it('fails safe when the cached snapshot is invalid', () => {
        const storage = new MemoryStorage();
        storage.setItem('repo-home:snapshot', JSON.stringify({ cards: [{ id: 42 }] }));
        expect(readRepoHomeSnapshot(storage)).toBeNull();
    });
    it('builds permission-aware actions for different policies', () => {
        const card = buildSeedRepoHomeCards(1700000000000)[0];
        const developerActions = buildRepoCardActions(card, {
            label: 'Developer',
            canSwitchWorkspace: true,
            canUseQuickSwitcher: true,
            canRestoreSession: true,
            canPinWorkspace: false,
            maxRecentWorkspaces: 3,
        }, 'docs-review');
        const reviewerActions = buildRepoCardActions(card, {
            label: 'Reviewer',
            canSwitchWorkspace: true,
            canUseQuickSwitcher: true,
            canRestoreSession: false,
            canPinWorkspace: false,
            maxRecentWorkspaces: 2,
        }, 'docs-review');
        const auditorActions = buildRepoCardActions(card, {
            label: 'Auditor',
            canSwitchWorkspace: false,
            canUseQuickSwitcher: false,
            canRestoreSession: false,
            canPinWorkspace: false,
            maxRecentWorkspaces: 1,
        }, 'docs-review');
        expect(developerActions.find((action) => action.id === 'pull')?.disabled).toBe(false);
        expect(reviewerActions.find((action) => action.id === 'pull')?.disabled).toBe(true);
        expect(auditorActions.find((action) => action.id === 'runbook')?.disabled).toBe(false);
        expect(auditorActions.find((action) => action.id === 'switch')?.reason).toContain('Audit policy');
    });
    it('refreshes snapshots without changing the card contract', () => {
        const snapshot = createDefaultRepoHomeSnapshot(1700000000000);
        const refreshed = refreshRepoHomeSnapshot(snapshot, 1700000030000);
        expect(refreshed.fetchedAt).toBe(1700000030000);
        expect(refreshed.cards).toEqual(sortRepoHomeCards(snapshot.cards));
    });
    it('keeps data-model operations comfortably under the 1s home-view budget for 20 repos', () => {
        const twentyCards = Array.from({ length: 20 }, (_, index) => ({
            ...buildSeedRepoHomeCards(1700000000000)[index % 5],
            id: `repo-${index}`,
            label: `Repo ${index}`,
        }));
        const startedAt = Date.now();
        const sorted = sortRepoHomeCards(twentyCards);
        const durationMs = Date.now() - startedAt;
        expect(sorted).toHaveLength(20);
        expect(durationMs).toBeLessThan(1000);
    });
    it('formats freshness, activity, refresh interval, and CI tone helpers consistently', () => {
        expect(resolveRepoStatusRefreshIntervalMs('1000')).toBe(5000);
        expect(resolveRepoStatusRefreshIntervalMs('999999')).toBe(300000);
        expect(formatRepoHomeRefreshLabel(1700000000000, 1700000010000)).toBe('10s ago');
        expect(formatRepoLastActivity(1700000000000, 1700000120000)).toBe('active 2m ago');
        expect(getRepoCardTone('passing')).toBe('emerald');
        expect(getRepoCardTone('failing')).toBe('rose');
    });
});
//# sourceMappingURL=repoHomeData.test.js.map