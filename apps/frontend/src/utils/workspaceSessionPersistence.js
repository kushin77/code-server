export const WORKSPACE_SESSION_SNAPSHOT_KEY = 'workspace-session:snapshot';
export const WORKSPACE_RESTORE_PREFERENCES_KEY = 'workspace-session:restore-preferences';
export const DEFAULT_RESTORE_PREFERENCES = {
    files: true,
    editors: true,
    terminals: false,
    tasks: true,
    debugConfigs: true,
};
function createDefaultSnapshot(legacy) {
    return {
        schemaVersion: 2,
        restoreVersion: 2,
        activeRepoId: legacy.activeRepoId,
        recentRepoIds: legacy.recentRepoIds,
        repoIdentity: {
            id: legacy.activeRepoId,
            canonicalPath: `/repos/${legacy.activeRepoId}`,
        },
        lastBranchRef: 'main',
        editorState: {
            openFiles: [],
            editorGroups: 1,
        },
        terminalDescriptors: [],
        taskDescriptors: [],
        debugDescriptors: [],
        savedAt: legacy.savedAt,
    };
}
function isLegacySnapshot(value) {
    if (!value || typeof value !== 'object') {
        return false;
    }
    const candidate = value;
    return (typeof candidate.activeRepoId === 'string' &&
        Array.isArray(candidate.recentRepoIds) &&
        typeof candidate.savedAt === 'number');
}
function isStringArray(value) {
    return Array.isArray(value) && value.every((entry) => typeof entry === 'string');
}
function isValidSnapshot(value) {
    if (!value || typeof value !== 'object') {
        return false;
    }
    const candidate = value;
    return (candidate.schemaVersion === 2 &&
        candidate.restoreVersion === 2 &&
        typeof candidate.activeRepoId === 'string' &&
        isStringArray(candidate.recentRepoIds) &&
        !!candidate.repoIdentity &&
        typeof candidate.repoIdentity.id === 'string' &&
        typeof candidate.repoIdentity.canonicalPath === 'string' &&
        typeof candidate.lastBranchRef === 'string' &&
        !!candidate.editorState &&
        isStringArray(candidate.editorState.openFiles) &&
        typeof candidate.editorState.editorGroups === 'number' &&
        Array.isArray(candidate.terminalDescriptors) &&
        Array.isArray(candidate.taskDescriptors) &&
        Array.isArray(candidate.debugDescriptors) &&
        typeof candidate.savedAt === 'number');
}
export function migrateWorkspaceSessionSnapshot(value) {
    if (isValidSnapshot(value)) {
        return {
            ...value,
            terminalDescriptors: value.terminalDescriptors.map((terminalDescriptor) => ({
                ...terminalDescriptor,
                unsafeReplayBlocked: terminalDescriptor.unsafeReplayBlocked !== false,
            })),
        };
    }
    if (isLegacySnapshot(value)) {
        return createDefaultSnapshot({
            activeRepoId: value.activeRepoId,
            recentRepoIds: value.recentRepoIds.filter((repoId) => typeof repoId === 'string'),
            savedAt: value.savedAt,
        });
    }
    return null;
}
export function readWorkspaceSessionSnapshot(storage) {
    if (!storage) {
        return null;
    }
    try {
        const rawSnapshot = storage.getItem(WORKSPACE_SESSION_SNAPSHOT_KEY);
        if (!rawSnapshot) {
            return null;
        }
        const parsedSnapshot = JSON.parse(rawSnapshot);
        const migratedSnapshot = migrateWorkspaceSessionSnapshot(parsedSnapshot);
        if (!migratedSnapshot) {
            storage.removeItem(WORKSPACE_SESSION_SNAPSHOT_KEY);
            return null;
        }
        return migratedSnapshot;
    }
    catch {
        storage.removeItem(WORKSPACE_SESSION_SNAPSHOT_KEY);
        return null;
    }
}
export function writeWorkspaceSessionSnapshot(storage, snapshot) {
    if (!storage) {
        return;
    }
    storage.setItem(WORKSPACE_SESSION_SNAPSHOT_KEY, JSON.stringify(snapshot));
}
export function clearWorkspaceSessionSnapshot(storage) {
    if (!storage) {
        return;
    }
    storage.removeItem(WORKSPACE_SESSION_SNAPSHOT_KEY);
}
export function readWorkspaceRestorePreferences(storage) {
    if (!storage) {
        return DEFAULT_RESTORE_PREFERENCES;
    }
    try {
        const rawPreferences = storage.getItem(WORKSPACE_RESTORE_PREFERENCES_KEY);
        if (!rawPreferences) {
            return DEFAULT_RESTORE_PREFERENCES;
        }
        const parsedPreferences = JSON.parse(rawPreferences);
        return {
            files: parsedPreferences.files !== false,
            editors: parsedPreferences.editors !== false,
            terminals: parsedPreferences.terminals === true,
            tasks: parsedPreferences.tasks !== false,
            debugConfigs: parsedPreferences.debugConfigs !== false,
        };
    }
    catch {
        return DEFAULT_RESTORE_PREFERENCES;
    }
}
export function writeWorkspaceRestorePreferences(storage, preferences) {
    if (!storage) {
        return;
    }
    storage.setItem(WORKSPACE_RESTORE_PREFERENCES_KEY, JSON.stringify(preferences));
}
export function buildSafeWorkspaceRestorePlan(snapshot, preferences, allowUnsafeTerminalReplay = false) {
    return {
        ...snapshot,
        editorState: preferences.files || preferences.editors ? snapshot.editorState : { ...snapshot.editorState, openFiles: [] },
        terminalDescriptors: preferences.terminals && allowUnsafeTerminalReplay
            ? snapshot.terminalDescriptors.map((terminalDescriptor) => ({
                ...terminalDescriptor,
                unsafeReplayBlocked: terminalDescriptor.unsafeReplayBlocked !== false,
            }))
            : [],
        taskDescriptors: preferences.tasks ? snapshot.taskDescriptors : [],
        debugDescriptors: preferences.debugConfigs ? snapshot.debugDescriptors : [],
    };
}
export function createWorkspaceSessionSnapshot(args) {
    return {
        schemaVersion: 2,
        restoreVersion: 2,
        activeRepoId: args.activeRepoId,
        recentRepoIds: args.recentRepoIds,
        repoIdentity: {
            id: args.activeRepoId,
            canonicalPath: `/repos/${args.activeRepoId}`,
        },
        lastBranchRef: args.branchRef,
        editorState: {
            openFiles: [],
            editorGroups: 1,
        },
        terminalDescriptors: [],
        taskDescriptors: [],
        debugDescriptors: [],
        savedAt: args.savedAt ?? Date.now(),
    };
}
export function scheduleWorkspaceSessionPersist(callback) {
    if (typeof window === 'undefined') {
        callback();
        return;
    }
    const idleWindow = window;
    if (typeof idleWindow.requestIdleCallback === 'function') {
        idleWindow.requestIdleCallback(callback, { timeout: 500 });
        return;
    }
    window.setTimeout(callback, 0);
}
//# sourceMappingURL=workspaceSessionPersistence.js.map