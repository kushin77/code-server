// @file        apps/frontend/src/utils/workspaceDiff.ts
// @module      utils/workspace-diff
// @description Frontend helpers for workspace diff snapshots
const WORKSPACE_DIFF_API_BASE = '/api/workspace-diff';
async function requestJson(input, init, allowNotFound = false) {
    const response = await fetch(input, {
        headers: {
            'Content-Type': 'application/json',
            ...(init?.headers ?? {}),
        },
        ...init,
    });
    if (allowNotFound && response.status === 404) {
        return null;
    }
    if (!response.ok) {
        throw new Error(`Workspace diff request failed with ${response.status}`);
    }
    return (await response.json());
}
export async function fetchLatestWorkspaceDiff(userId, repoPath) {
    const params = new URLSearchParams({ repoPath });
    return requestJson(`${WORKSPACE_DIFF_API_BASE}/latest/${encodeURIComponent(userId)}?${params.toString()}`, undefined, true);
}
export async function refreshWorkspaceDiff(userId, repoPath) {
    return requestJson(`${WORKSPACE_DIFF_API_BASE}/refresh/${encodeURIComponent(userId)}`, {
        method: 'POST',
        body: JSON.stringify({ repoPath }),
    });
}
//# sourceMappingURL=workspaceDiff.js.map