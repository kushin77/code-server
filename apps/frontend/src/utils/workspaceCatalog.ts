/**
 * @file apps/frontend/src/utils/workspaceCatalog.ts
 * @module workspace/catalog
 * @description Workspace catalog and management utilities for multi-root workspace support
 */

export const RECENT_STORAGE_KEY = 'workspace-recent'
export const WORKSPACE_STORAGE_KEY = 'workspace-tabs'
export const WORKSPACE_STATE_SYNC_EVENT = 'workspace:state:sync'

export interface WorkspaceTab {
  id: string
  label: string
  path: string
  icon?: string
  description?: string
  branch?: string
  pinned?: boolean
}

export type WorkspaceState = string

export interface WorkspaceTabsState {
  activeRepoId: string
  recentRepoIds: string[]
}

/**
 * All available workspaces in the catalog
 */
export const ALL_WORKSPACES: WorkspaceTab[] = [
  {
    id: 'primary',
    label: 'Primary Workspace',
    path: '/workspace/primary',
    icon: 'folder',
    description: 'Main development workspace',
  },
  {
    id: 'sandbox',
    label: 'Sandbox',
    path: '/workspace/sandbox',
    icon: 'beaker',
    description: 'Isolated testing environment',
  },
  {
    id: 'archive',
    label: 'Archive',
    path: '/workspace/archive',
    icon: 'archive',
    description: 'Historical projects and reference code',
  },
]

/**
 * Pinned workspaces shown by default in workspace switcher
 */
export const PINNED_WORKSPACES: WorkspaceTab[] = [
  {
    id: 'primary',
    label: 'Primary Workspace',
    path: '/workspace/primary',
    icon: 'folder',
    description: 'Main development workspace',
  },
]

export const DEFAULT_RECENT_WORKSPACES: string[] = []

/**
 * Get a workspace by ID
 * @param id Workspace ID
 * @returns Workspace tab or undefined if not found
 */
export function getWorkspaceById(id: string): WorkspaceTab | undefined {
  return ALL_WORKSPACES.find((ws) => ws.id === id)
}

/**
 * Get workspace label by ID
 * @param id Workspace ID
 * @returns Workspace label or the ID itself if not found
 */
export function getWorkspaceLabel(id: string): string {
  return getWorkspaceById(id)?.label ?? id
}

/**
 * Get workspace path by ID
 * @param id Workspace ID
 * @returns Workspace path or undefined if not found
 */
export function getWorkspacePath(id: string): string | undefined {
  return getWorkspaceById(id)?.path
}

/**
 * Score a workspace for relevance in workspace switcher
 */
export function scoreWorkspace(workspaceId: string, query: string): number {
  const workspace = getWorkspaceById(workspaceId)
  if (!workspace) return 0

  if (workspace.id.includes(query)) return 100
  if (workspace.label.toLowerCase().includes(query.toLowerCase())) return 80
  if (workspace.path?.includes(query)) return 60
  return 0
}
export function buildRecentWorkspaceIds(activeId: string, recent: string[], maxCount: number): string[] {
  const ids = [activeId, ...recent].filter((v, i, a) => a.indexOf(v) === i)
  return ids.slice(0, maxCount)
}

/**
 * Get suggested workspace ID based on availability
 */
export function getSuggestedWorkspaceId(roleIds?: string[]): string {
  return PINNED_WORKSPACES[0]?.id ?? 'primary'
}

/**
 * Notify listeners that workspace tabs have changed
 */
export function notifyWorkspaceTabsChanged(state: WorkspaceTabsState): void {
  window.dispatchEvent(new CustomEvent('workspaceTabs:changed', { detail: state }))
}

/**
 * Read stored workspace tabs from localStorage
 */
export function readStoredWorkspaceTabs(storage?: Storage): WorkspaceTabsState {
  try {
    const stored = (storage ?? (typeof window !== 'undefined' ? window.localStorage : null))?.getItem('workspace-tabs')
    return stored
      ? JSON.parse(stored)
      : {
          activeRepoId: PINNED_WORKSPACES[0]?.id ?? 'primary',
          recentRepoIds: [],
        }
  } catch {
    return {
      activeRepoId: PINNED_WORKSPACES[0]?.id ?? 'primary',
      recentRepoIds: [],
    }
  }
}

/**
 * Write workspace tabs to localStorage
 */
export function writeStoredWorkspaceTabs(storage: Storage | undefined, state: WorkspaceTabsState): void {
  try {
    if (storage) {
      storage.setItem('workspace-tabs', JSON.stringify(state))
    }
  } catch {
    // Silently fail if localStorage is unavailable
  }
}
