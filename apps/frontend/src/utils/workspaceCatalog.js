export const RECENT_STORAGE_KEY = 'workspace-tabs:recent-repos';
export const WORKSPACE_STORAGE_KEY = 'workspace-tabs:active-repo';
export const WORKSPACE_STATE_SYNC_EVENT = 'workspace-tabs:changed';
export const PINNED_WORKSPACES = [
    { id: 'portal-main', label: 'Portal main', branch: 'main', pinned: true },
    { id: 'docs-review', label: 'Docs review', branch: 'docs-sync', pinned: true },
    { id: 'ops-control', label: 'Ops control', branch: 'release-control', pinned: true },
];
export const DEFAULT_RECENT_WORKSPACES = [
    { id: 'dev-sandbox', label: 'Dev sandbox', branch: 'feature/multi-repo', pinned: false },
    { id: 'security-lab', label: 'Security lab', branch: 'hardening', pinned: false },
];
export const ALL_WORKSPACES = [...PINNED_WORKSPACES, ...DEFAULT_RECENT_WORKSPACES];
const ROLE_TO_WORKSPACE = {
    admin: 'ops-control',
    developer: 'dev-sandbox',
    reviewer: 'docs-review',
    viewer: 'portal-main',
    auditor: 'ops-control',
};
export function getWorkspaceById(workspaceId) {
    return ALL_WORKSPACES.find((workspace) => workspace.id === workspaceId);
}
export function scoreWorkspace(query, workspace) {
    const normalizedQuery = query.trim().toLowerCase();
    if (!normalizedQuery) {
        return workspace.pinned ? 100 : 50;
    }
    const haystack = `${workspace.label} ${workspace.branch} ${workspace.id}`.toLowerCase();
    if (haystack === normalizedQuery) {
        return 200;
    }
    if (haystack.startsWith(normalizedQuery)) {
        return 150;
    }
    if (haystack.includes(normalizedQuery)) {
        return 100 - Math.min(25, haystack.indexOf(normalizedQuery));
    }
    let matchIndex = 0;
    for (const character of normalizedQuery) {
        matchIndex = haystack.indexOf(character, matchIndex);
        if (matchIndex === -1) {
            return -1;
        }
        matchIndex += 1;
    }
    return 40 - normalizedQuery.length;
}
export function readStoredWorkspaceTabs(storage) {
    if (!storage) {
        return { activeRepoId: PINNED_WORKSPACES[0].id, recentRepoIds: DEFAULT_RECENT_WORKSPACES.map((workspace) => workspace.id) };
    }
    try {
        const activeRepoId = storage.getItem(WORKSPACE_STORAGE_KEY) || PINNED_WORKSPACES[0].id;
        const recentRepoIds = JSON.parse(storage.getItem(RECENT_STORAGE_KEY) || '[]');
        return {
            activeRepoId,
            recentRepoIds: Array.isArray(recentRepoIds) ? recentRepoIds : DEFAULT_RECENT_WORKSPACES.map((workspace) => workspace.id),
        };
    }
    catch {
        return { activeRepoId: PINNED_WORKSPACES[0].id, recentRepoIds: DEFAULT_RECENT_WORKSPACES.map((workspace) => workspace.id) };
    }
}
export function writeStoredWorkspaceTabs(storage, workspaceState) {
    if (!storage) {
        return;
    }
    storage.setItem(WORKSPACE_STORAGE_KEY, workspaceState.activeRepoId);
    storage.setItem(RECENT_STORAGE_KEY, JSON.stringify(workspaceState.recentRepoIds));
}
export function buildRecentWorkspaceIds(activeRepoId, recentRepoIds, maxCount = DEFAULT_RECENT_WORKSPACES.length) {
    return [activeRepoId, ...recentRepoIds.filter((workspaceId) => workspaceId !== activeRepoId)].slice(0, maxCount);
}
export function getSuggestedWorkspaceId(roleIds) {
    const normalizedRoleIds = roleIds.map((roleId) => roleId.toLowerCase());
    for (const roleId of ['admin', 'developer', 'reviewer', 'auditor', 'viewer']) {
        if (normalizedRoleIds.includes(roleId)) {
            return ROLE_TO_WORKSPACE[roleId] ?? PINNED_WORKSPACES[0].id;
        }
    }
    return PINNED_WORKSPACES[0].id;
}
export function notifyWorkspaceTabsChanged() {
    if (typeof window === 'undefined') {
        return;
    }
    window.dispatchEvent(new Event(WORKSPACE_STATE_SYNC_EVENT));
}
//# sourceMappingURL=workspaceCatalog.js.map