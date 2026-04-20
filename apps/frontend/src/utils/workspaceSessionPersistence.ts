export type WorkspaceRestorePreferences = {
  files: boolean
  editors: boolean
  terminals: boolean
  tasks: boolean
  debugConfigs: boolean
}

export type WorkspaceRepoIdentity = {
  id: string
  canonicalPath: string
}

export type WorkspaceEditorState = {
  openFiles: string[]
  editorGroups: number
}

export type WorkspaceTerminalDescriptor = {
  id: string
  label: string
  cwd: string
  command?: string
  unsafeReplayBlocked: boolean
}

export type WorkspaceTaskDescriptor = {
  id: string
  label: string
}

export type WorkspaceDebugDescriptor = {
  id: string
  name: string
}

export type WorkspaceSessionSnapshot = {
  schemaVersion: 2
  restoreVersion: 2
  activeRepoId: string
  recentRepoIds: string[]
  repoIdentity: WorkspaceRepoIdentity
  lastBranchRef: string
  editorState: WorkspaceEditorState
  terminalDescriptors: WorkspaceTerminalDescriptor[]
  taskDescriptors: WorkspaceTaskDescriptor[]
  debugDescriptors: WorkspaceDebugDescriptor[]
  savedAt: number
}

type LegacyWorkspaceSessionSnapshot = {
  activeRepoId: string
  recentRepoIds: string[]
  savedAt: number
}

type StorageLike = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>

type IdleWindow = Window & {
  requestIdleCallback?: (callback: () => void, options?: { timeout: number }) => number
}

export const WORKSPACE_SESSION_SNAPSHOT_KEY = 'workspace-session:snapshot'
export const WORKSPACE_RESTORE_PREFERENCES_KEY = 'workspace-session:restore-preferences'

export const DEFAULT_RESTORE_PREFERENCES: WorkspaceRestorePreferences = {
  files: true,
  editors: true,
  terminals: false,
  tasks: true,
  debugConfigs: true,
}

function createDefaultSnapshot(legacy: LegacyWorkspaceSessionSnapshot): WorkspaceSessionSnapshot {
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
  }
}

function isLegacySnapshot(value: unknown): value is LegacyWorkspaceSessionSnapshot {
  if (!value || typeof value !== 'object') {
    return false
  }

  const candidate = value as Partial<LegacyWorkspaceSessionSnapshot>
  return (
    typeof candidate.activeRepoId === 'string' &&
    Array.isArray(candidate.recentRepoIds) &&
    typeof candidate.savedAt === 'number'
  )
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((entry) => typeof entry === 'string')
}

function isValidSnapshot(value: unknown): value is WorkspaceSessionSnapshot {
  if (!value || typeof value !== 'object') {
    return false
  }

  const candidate = value as Partial<WorkspaceSessionSnapshot>
  return (
    candidate.schemaVersion === 2 &&
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
    typeof candidate.savedAt === 'number'
  )
}

export function migrateWorkspaceSessionSnapshot(value: unknown): WorkspaceSessionSnapshot | null {
  if (isValidSnapshot(value)) {
    return {
      ...value,
      terminalDescriptors: value.terminalDescriptors.map((terminalDescriptor) => ({
        ...terminalDescriptor,
        unsafeReplayBlocked: terminalDescriptor.unsafeReplayBlocked !== false,
      })),
    }
  }

  if (isLegacySnapshot(value)) {
    return createDefaultSnapshot({
      activeRepoId: value.activeRepoId,
      recentRepoIds: value.recentRepoIds.filter((repoId): repoId is string => typeof repoId === 'string'),
      savedAt: value.savedAt,
    })
  }

  return null
}

export function readWorkspaceSessionSnapshot(storage: StorageLike | undefined): WorkspaceSessionSnapshot | null {
  if (!storage) {
    return null
  }

  try {
    const rawSnapshot = storage.getItem(WORKSPACE_SESSION_SNAPSHOT_KEY)
    if (!rawSnapshot) {
      return null
    }

    const parsedSnapshot = JSON.parse(rawSnapshot)
    const migratedSnapshot = migrateWorkspaceSessionSnapshot(parsedSnapshot)
    if (!migratedSnapshot) {
      storage.removeItem(WORKSPACE_SESSION_SNAPSHOT_KEY)
      return null
    }

    return migratedSnapshot
  } catch {
    storage.removeItem(WORKSPACE_SESSION_SNAPSHOT_KEY)
    return null
  }
}

export function writeWorkspaceSessionSnapshot(
  storage: StorageLike | undefined,
  snapshot: WorkspaceSessionSnapshot
): void {
  if (!storage) {
    return
  }

  storage.setItem(WORKSPACE_SESSION_SNAPSHOT_KEY, JSON.stringify(snapshot))
}

export function clearWorkspaceSessionSnapshot(storage: StorageLike | undefined): void {
  if (!storage) {
    return
  }

  storage.removeItem(WORKSPACE_SESSION_SNAPSHOT_KEY)
}

export function readWorkspaceRestorePreferences(storage: StorageLike | undefined): WorkspaceRestorePreferences {
  if (!storage) {
    return DEFAULT_RESTORE_PREFERENCES
  }

  try {
    const rawPreferences = storage.getItem(WORKSPACE_RESTORE_PREFERENCES_KEY)
    if (!rawPreferences) {
      return DEFAULT_RESTORE_PREFERENCES
    }

    const parsedPreferences = JSON.parse(rawPreferences) as Partial<WorkspaceRestorePreferences>
    return {
      files: parsedPreferences.files !== false,
      editors: parsedPreferences.editors !== false,
      terminals: parsedPreferences.terminals === true,
      tasks: parsedPreferences.tasks !== false,
      debugConfigs: parsedPreferences.debugConfigs !== false,
    }
  } catch {
    return DEFAULT_RESTORE_PREFERENCES
  }
}

export function writeWorkspaceRestorePreferences(
  storage: StorageLike | undefined,
  preferences: WorkspaceRestorePreferences
): void {
  if (!storage) {
    return
  }

  storage.setItem(WORKSPACE_RESTORE_PREFERENCES_KEY, JSON.stringify(preferences))
}

export function buildSafeWorkspaceRestorePlan(
  snapshot: WorkspaceSessionSnapshot,
  preferences: WorkspaceRestorePreferences,
  allowUnsafeTerminalReplay = false
): WorkspaceSessionSnapshot {
  return {
    ...snapshot,
    editorState: preferences.files || preferences.editors ? snapshot.editorState : { ...snapshot.editorState, openFiles: [] },
    terminalDescriptors:
      preferences.terminals && allowUnsafeTerminalReplay
        ? snapshot.terminalDescriptors.map((terminalDescriptor) => ({
            ...terminalDescriptor,
            unsafeReplayBlocked: terminalDescriptor.unsafeReplayBlocked !== false,
          }))
        : [],
    taskDescriptors: preferences.tasks ? snapshot.taskDescriptors : [],
    debugDescriptors: preferences.debugConfigs ? snapshot.debugDescriptors : [],
  }
}

export function createWorkspaceSessionSnapshot(args: {
  activeRepoId: string
  recentRepoIds: string[]
  branchRef: string
  savedAt?: number
}): WorkspaceSessionSnapshot {
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
  }
}

export function scheduleWorkspaceSessionPersist(callback: () => void): void {
  if (typeof window === 'undefined') {
    callback()
    return
  }

  const idleWindow = window as IdleWindow
  if (typeof idleWindow.requestIdleCallback === 'function') {
    idleWindow.requestIdleCallback(callback, { timeout: 500 })
    return
  }

  window.setTimeout(callback, 0)
}
