import { describe, expect, it } from 'vitest'

import {
  buildSafeWorkspaceRestorePlan,
  clearWorkspaceSessionSnapshot,
  createWorkspaceSessionSnapshot,
  DEFAULT_RESTORE_PREFERENCES,
  migrateWorkspaceSessionSnapshot,
  readWorkspaceRestorePreferences,
  readWorkspaceSessionSnapshot,
  scheduleWorkspaceSessionPersist,
  writeWorkspaceRestorePreferences,
  writeWorkspaceSessionSnapshot,
} from '../workspaceSessionPersistence'

class MemoryStorage {
  private readonly store = new Map<string, string>()

  getItem(key: string): string | null {
    return this.store.get(key) ?? null
  }

  setItem(key: string, value: string): void {
    this.store.set(key, value)
  }

  removeItem(key: string): void {
    this.store.delete(key)
  }
}

describe('workspaceSessionPersistence', () => {
  it('round-trips the workspace session snapshot through storage', () => {
    const storage = new MemoryStorage()
    const snapshot = createWorkspaceSessionSnapshot({
      activeRepoId: 'portal-main',
      recentRepoIds: ['docs-review', 'ops-control'],
      branchRef: 'main',
      savedAt: 1_700_000_000_000,
    })

    writeWorkspaceSessionSnapshot(storage, snapshot)

    expect(readWorkspaceSessionSnapshot(storage)).toEqual(snapshot)
  })

  it('migrates legacy snapshots into the current schema', () => {
    const migrated = migrateWorkspaceSessionSnapshot({
      activeRepoId: 'dev-sandbox',
      recentRepoIds: ['portal-main', 'docs-review'],
      savedAt: 1_700_000_000_000,
    })

    expect(migrated?.schemaVersion).toBe(2)
    expect(migrated?.activeRepoId).toBe('dev-sandbox')
    expect(migrated?.repoIdentity.id).toBe('dev-sandbox')
    expect(migrated?.terminalDescriptors).toEqual([])
  })

  it('builds a safe restore plan that strips disabled modules', () => {
    const snapshot = createWorkspaceSessionSnapshot({
      activeRepoId: 'portal-main',
      recentRepoIds: ['docs-review'],
      branchRef: 'feature/multi-repo',
    })

    const unsafeSnapshot = {
      ...snapshot,
      terminalDescriptors: [
        {
          id: 'term-1',
          label: 'shell',
          cwd: '/repos/portal-main',
          command: 'npm run dev',
          unsafeReplayBlocked: false,
        },
      ],
      taskDescriptors: [{ id: 'task-1', label: 'build' }],
      debugDescriptors: [{ id: 'debug-1', name: 'launch' }],
    }

    const plan = buildSafeWorkspaceRestorePlan(unsafeSnapshot, {
      ...DEFAULT_RESTORE_PREFERENCES,
      files: false,
      editors: false,
      terminals: false,
      tasks: true,
      debugConfigs: false,
    })

    expect(plan.editorState.openFiles).toEqual([])
    expect(plan.terminalDescriptors).toEqual([])
    expect(plan.taskDescriptors).toEqual([{ id: 'task-1', label: 'build' }])
    expect(plan.debugDescriptors).toEqual([])
  })

  it('stores and reads restore preferences safely', () => {
    const storage = new MemoryStorage()

    writeWorkspaceRestorePreferences(storage, {
      ...DEFAULT_RESTORE_PREFERENCES,
      terminals: false,
      tasks: false,
    })

    expect(readWorkspaceRestorePreferences(storage)).toEqual({
      ...DEFAULT_RESTORE_PREFERENCES,
      terminals: false,
      tasks: false,
    })
  })

  it('clears invalid workspace snapshots from storage', () => {
    const storage = new MemoryStorage()
    storage.setItem('workspace-session:snapshot', '{bad-json')

    expect(readWorkspaceSessionSnapshot(storage)).toBeNull()
    expect(storage.getItem('workspace-session:snapshot')).toBeNull()

    clearWorkspaceSessionSnapshot(storage)
    expect(storage.getItem('workspace-session:snapshot')).toBeNull()
  })

  it('schedules persistence work immediately when idle callbacks are unavailable', () => {
    let invoked = false

    scheduleWorkspaceSessionPersist(() => {
      invoked = true
    })

    expect(invoked).toBe(true)
  })
})
