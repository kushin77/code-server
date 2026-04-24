// @file        apps/frontend/src/utils/collaborationMetrics.ts
// @module      utils/collaboration-metrics
// @description Collaboration status bar metrics and demo presence helpers
import { fetchPagerDutyIncidents } from '@/extensions/pagerduty-incidents.js';
const DEMO_TEAM_USERS = [
    { id: 'alice', displayName: 'Alice Chen', status: 'online' },
    { id: 'bob', displayName: 'Bob Kumar', status: 'online' },
    { id: 'carol', displayName: 'Carol Wang', status: 'online' },
    { id: 'dave', displayName: 'Dave Lee', status: 'away' },
    { id: 'eve', displayName: 'Eve Park', status: 'offline' },
    { id: 'frank', displayName: 'Frank Wu', status: 'offline' },
];
export const PAGERDUTY_INCIDENTS_ROUTE = '/pagerduty-incidents';
export const CI_LOGS_ROUTE = '/ci-logs';
export const TEAM_HUB_ROUTE = '/team-hub';
const STATUS_BAR_TILE_STORAGE_KEY = 'collaboration:status-bar-tiles';
export const DEFAULT_STATUS_BAR_TILES = [
    { id: 'open-prs', visible: true },
    { id: 'branch-ci', visible: true },
    { id: 'pagerduty', visible: true },
    { id: 'team-online', visible: true },
];
export function getGitHubHandleFromEmail(email) {
    if (!email) {
        return null;
    }
    const [localPart] = email.split('@');
    const handle = localPart.trim().toLowerCase();
    return handle.length > 0 ? handle : null;
}
export function getDemoTeamOnlineCount() {
    return DEMO_TEAM_USERS.filter((user) => user.status === 'online').length;
}
export function getDemoTeamStatusCounts() {
    return {
        online: DEMO_TEAM_USERS.filter((user) => user.status === 'online').length,
        away: DEMO_TEAM_USERS.filter((user) => user.status === 'away').length,
        offline: DEMO_TEAM_USERS.filter((user) => user.status === 'offline').length,
    };
}
export function getDemoTeamNamesByStatus(status) {
    return DEMO_TEAM_USERS.filter((user) => user.status === status).map((user) => user.displayName);
}
function getDefaultStatusBarTileConfig() {
    return DEFAULT_STATUS_BAR_TILES.map((tile) => ({ ...tile }));
}
export function readStatusBarTileConfig(storage) {
    if (!storage) {
        return getDefaultStatusBarTileConfig();
    }
    try {
        const rawConfig = storage.getItem(STATUS_BAR_TILE_STORAGE_KEY);
        if (!rawConfig) {
            return getDefaultStatusBarTileConfig();
        }
        const parsedConfig = JSON.parse(rawConfig);
        if (!Array.isArray(parsedConfig)) {
            return getDefaultStatusBarTileConfig();
        }
        const defaultOrder = new Map(DEFAULT_STATUS_BAR_TILES.map((tile) => [tile.id, tile]));
        const normalizedConfig = [];
        const seen = new Set();
        for (const entry of parsedConfig) {
            if (!entry?.id || !defaultOrder.has(entry.id) || seen.has(entry.id)) {
                continue;
            }
            const defaultTile = defaultOrder.get(entry.id);
            normalizedConfig.push({
                id: entry.id,
                visible: entry.visible ?? defaultTile?.visible ?? true,
            });
            seen.add(entry.id);
        }
        for (const tile of DEFAULT_STATUS_BAR_TILES) {
            if (!seen.has(tile.id)) {
                normalizedConfig.push({ ...tile });
            }
        }
        return normalizedConfig;
    }
    catch {
        return getDefaultStatusBarTileConfig();
    }
}
export function writeStatusBarTileConfig(storage, tiles) {
    if (!storage) {
        return;
    }
    storage.setItem(STATUS_BAR_TILE_STORAGE_KEY, JSON.stringify(tiles));
}
export async function fetchOpenPullRequestCount(repoSlug, authorLogin) {
    if (!repoSlug || !authorLogin) {
        return null;
    }
    try {
        const query = `is:open is:pr repo:${repoSlug} author:${authorLogin}`;
        const response = await fetch(`https://api.github.com/search/issues?q=${encodeURIComponent(query)}`, {
            headers: {
                Accept: 'application/vnd.github+json',
            },
        });
        if (!response.ok) {
            return null;
        }
        const data = (await response.json());
        return typeof data.total_count === 'number' ? data.total_count : null;
    }
    catch {
        return null;
    }
}
export async function fetchReviewRequestCount(repoSlug, reviewerLogin) {
    if (!repoSlug || !reviewerLogin) {
        return null;
    }
    try {
        const query = `is:open is:pr repo:${repoSlug} review-requested:${reviewerLogin}`;
        const response = await fetch(`https://api.github.com/search/issues?q=${encodeURIComponent(query)}`, {
            headers: {
                Accept: 'application/vnd.github+json',
            },
        });
        if (!response.ok) {
            return null;
        }
        const data = (await response.json());
        return typeof data.total_count === 'number' ? data.total_count : null;
    }
    catch {
        return null;
    }
}
export async function fetchActivePagerDutyIncidentCount(token) {
    if (!token) {
        return null;
    }
    try {
        const { stats } = await fetchPagerDutyIncidents({ token });
        return stats.total;
    }
    catch {
        return null;
    }
}
//# sourceMappingURL=collaborationMetrics.js.map