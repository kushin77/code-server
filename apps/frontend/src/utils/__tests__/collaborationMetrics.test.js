// @file        apps/frontend/src/utils/__tests__/collaborationMetrics.test.ts
// @module      utils/__tests__/collaboration-metrics
// @description Unit tests for collaboration metrics helpers
import { describe, expect, it, vi } from 'vitest';
import { DEFAULT_STATUS_BAR_TILES, fetchOpenPullRequestCount, fetchReviewRequestCount, getDemoTeamOnlineCount, getDemoTeamStatusCounts, getGitHubHandleFromEmail, readStatusBarTileConfig, writeStatusBarTileConfig, } from '../collaborationMetrics';
describe('collaborationMetrics', () => {
    it('derives a github handle from an email address', () => {
        expect(getGitHubHandleFromEmail('Alex.Kushnir@example.com')).toBe('alex.kushnir');
        expect(getGitHubHandleFromEmail('')).toBeNull();
    });
    it('exposes the demo team online count', () => {
        expect(getDemoTeamOnlineCount()).toBe(3);
        expect(getDemoTeamStatusCounts()).toEqual({ online: 3, away: 1, offline: 2 });
    });
    it('fetches a PR count from the GitHub search API', async () => {
        const fetchMock = vi.fn().mockResolvedValue({
            ok: true,
            json: vi.fn().mockResolvedValue({ total_count: 7 }),
        });
        vi.stubGlobal('fetch', fetchMock);
        await expect(fetchOpenPullRequestCount('kushin77/code-server', 'alex')).resolves.toBe(7);
        expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining('repo%3Akushin77%2Fcode-server'), expect.objectContaining({
            headers: expect.objectContaining({
                Accept: 'application/vnd.github+json',
            }),
        }));
        vi.unstubAllGlobals();
    });
    it('fetches a review-request count from the GitHub search API', async () => {
        const fetchMock = vi.fn().mockResolvedValue({
            ok: true,
            json: vi.fn().mockResolvedValue({ total_count: 4 }),
        });
        vi.stubGlobal('fetch', fetchMock);
        await expect(fetchReviewRequestCount('kushin77/code-server', 'alex')).resolves.toBe(4);
        expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining('review-requested%3Aalex'), expect.objectContaining({
            headers: expect.objectContaining({
                Accept: 'application/vnd.github+json',
            }),
        }));
        vi.unstubAllGlobals();
    });
    it('reads and writes status bar tile configuration', () => {
        const storage = new MapStorage();
        expect(readStatusBarTileConfig(storage)).toEqual(DEFAULT_STATUS_BAR_TILES);
        writeStatusBarTileConfig(storage, [
            { id: 'team-online', visible: false },
            { id: 'open-prs', visible: true },
            { id: 'pagerduty', visible: true },
            { id: 'branch-ci', visible: false },
        ]);
        expect(readStatusBarTileConfig(storage)).toEqual([
            { id: 'team-online', visible: false },
            { id: 'open-prs', visible: true },
            { id: 'pagerduty', visible: true },
            { id: 'branch-ci', visible: false },
        ]);
    });
});
class MapStorage {
    constructor() {
        this.data = new Map();
    }
    getItem(key) {
        return this.data.has(key) ? this.data.get(key) ?? null : null;
    }
    setItem(key, value) {
        this.data.set(key, value);
    }
}
//# sourceMappingURL=collaborationMetrics.test.js.map