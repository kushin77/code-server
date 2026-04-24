// @file        apps/frontend/src/utils/richPresence.ts
// @module      utils/rich-presence
// @description Frontend helpers for team rich presence snapshots
const RICH_PRESENCE_API_BASE = '/api/rich-presence';
async function requestJson(input, init) {
    const response = await fetch(input, {
        headers: {
            'Content-Type': 'application/json',
            ...(init?.headers ?? {}),
        },
        ...init,
    });
    if (!response.ok) {
        throw new Error(`Rich presence request failed with ${response.status}`);
    }
    return (await response.json());
}
export async function fetchTeamRichPresence(teamId) {
    return requestJson(`${RICH_PRESENCE_API_BASE}/teams/${encodeURIComponent(teamId)}/presence`);
}
export async function upsertRichPresence(teamId, userId, input) {
    return requestJson(`${RICH_PRESENCE_API_BASE}/teams/${encodeURIComponent(teamId)}/users/${encodeURIComponent(userId)}`, {
        method: 'POST',
        body: JSON.stringify(input),
    });
}
//# sourceMappingURL=richPresence.js.map