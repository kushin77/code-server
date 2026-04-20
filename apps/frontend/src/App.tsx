import React, { useEffect, useMemo, useState } from 'react'
import { BrowserRouter as Router, Routes, Route, Navigate, Link, useNavigate, useLocation } from 'react-router-dom'
import { useAuthStore } from '@/store'
import { LoginPage } from '@/pages/LoginPage'
import { MFASetup } from '@/pages/MFASetup'
import { AdminControlsPage } from '@/pages/AdminControlsPage'
import { UserManagementPage } from '@/pages/UserManagement'
import { EphemeralSessionsPage } from '@/pages/EphemeralSessions'
import { resolveMultiRepoRollout } from '@/utils/multiRepoRollout'

type WorkspaceTab = {
  id: string
  label: string
  branch: string
  pinned: boolean
}
const RECENT_STORAGE_KEY = 'workspace-tabs:recent-repos'
const WORKSPACE_STORAGE_KEY = 'workspace-tabs:active-repo'

const PINNED_WORKSPACES: WorkspaceTab[] = [
  { id: 'portal-main', label: 'Portal main', branch: 'main', pinned: true },
  { id: 'docs-review', label: 'Docs review', branch: 'docs-sync', pinned: true },
  { id: 'ops-control', label: 'Ops control', branch: 'release-control', pinned: true },
]

const DEFAULT_RECENT_WORKSPACES: WorkspaceTab[] = [
  { id: 'dev-sandbox', label: 'Dev sandbox', branch: 'feature/multi-repo', pinned: false },
  { id: 'security-lab', label: 'Security lab', branch: 'hardening', pinned: false },
]

const ALL_WORKSPACES: WorkspaceTab[] = [...PINNED_WORKSPACES, ...DEFAULT_RECENT_WORKSPACES]

type WorkspaceState = {
  activeRepoId: string
  recentRepoIds: string[]
}

type WorkspaceSessionSnapshot = {
  activeRepoId: string
  recentRepoIds: string[]
  savedAt: number
}

type WorkspacePolicy = {
  label: string
  canSwitchWorkspace: boolean
  canUseQuickSwitcher: boolean
  canRestoreSession: boolean
  canPinWorkspace: boolean
  maxRecentWorkspaces: number
}

const DEFAULT_POLICY: WorkspacePolicy = {
  label: 'Read-only',
  canSwitchWorkspace: false,
  canUseQuickSwitcher: false,
  canRestoreSession: false,
  canPinWorkspace: false,
  maxRecentWorkspaces: 1,
}

const SESSION_SNAPSHOT_KEY = 'workspace-session:snapshot'

function scoreWorkspace(query: string, workspace: WorkspaceTab): number {
  const normalizedQuery = query.trim().toLowerCase()
  if (!normalizedQuery) {
    return workspace.pinned ? 100 : 50
  }

  const haystack = `${workspace.label} ${workspace.branch} ${workspace.id}`.toLowerCase()
  if (haystack === normalizedQuery) {
    return 200
  }
  if (haystack.startsWith(normalizedQuery)) {
    return 150
  }
  if (haystack.includes(normalizedQuery)) {
    return 100 - Math.min(25, haystack.indexOf(normalizedQuery))
  }

  let matchIndex = 0
  for (const character of normalizedQuery) {
    matchIndex = haystack.indexOf(character, matchIndex)
    if (matchIndex === -1) {
      return -1
    }
    matchIndex += 1
  }

  return 40 - normalizedQuery.length
}

function readStoredWorkspaceTabs(): WorkspaceState {
  if (typeof window === 'undefined') {
    return { activeRepoId: PINNED_WORKSPACES[0].id, recentRepoIds: DEFAULT_RECENT_WORKSPACES.map((workspace) => workspace.id) }
  }

  try {
    const activeRepoId = window.localStorage.getItem(WORKSPACE_STORAGE_KEY) || PINNED_WORKSPACES[0].id
    const recentRepoIds = JSON.parse(window.localStorage.getItem(RECENT_STORAGE_KEY) || '[]') as string[]

    return {
      activeRepoId,
      recentRepoIds: Array.isArray(recentRepoIds) ? recentRepoIds : DEFAULT_RECENT_WORKSPACES.map((workspace) => workspace.id),
    }
  } catch {
    return { activeRepoId: PINNED_WORKSPACES[0].id, recentRepoIds: DEFAULT_RECENT_WORKSPACES.map((workspace) => workspace.id) }
  }
}

function readStoredWorkspaceSession(): WorkspaceSessionSnapshot | null {
  if (typeof window === 'undefined') {
    return null
  }

  try {
    const rawSnapshot = window.localStorage.getItem(SESSION_SNAPSHOT_KEY)
    if (!rawSnapshot) {
      return null
    }

    const parsedSnapshot = JSON.parse(rawSnapshot) as Partial<WorkspaceSessionSnapshot>
    if (
      typeof parsedSnapshot.activeRepoId !== 'string' ||
      !Array.isArray(parsedSnapshot.recentRepoIds) ||
      typeof parsedSnapshot.savedAt !== 'number'
    ) {
      return null
    }

    return {
      activeRepoId: parsedSnapshot.activeRepoId,
      recentRepoIds: parsedSnapshot.recentRepoIds.filter((recentRepoId): recentRepoId is string => typeof recentRepoId === 'string'),
      savedAt: parsedSnapshot.savedAt,
    }
  } catch {
    return null
  }
}

function saveWorkspaceSession(snapshot: WorkspaceSessionSnapshot): void {
  if (typeof window === 'undefined') {
    return
  }

  window.localStorage.setItem(SESSION_SNAPSHOT_KEY, JSON.stringify(snapshot))
}

function clearWorkspaceSession(): void {
  if (typeof window === 'undefined') {
    return
  }

  window.localStorage.removeItem(SESSION_SNAPSHOT_KEY)
}

function deriveWorkspacePolicy(roleIds: string[]): WorkspacePolicy {
  const normalizedRoles = new Set(roleIds.map((roleId) => roleId.toLowerCase()))

  if (normalizedRoles.has('admin')) {
    return {
      label: 'Admin',
      canSwitchWorkspace: true,
      canUseQuickSwitcher: true,
      canRestoreSession: true,
      canPinWorkspace: true,
      maxRecentWorkspaces: 3,
    }
  }

  if (normalizedRoles.has('developer')) {
    return {
      label: 'Developer',
      canSwitchWorkspace: true,
      canUseQuickSwitcher: true,
      canRestoreSession: true,
      canPinWorkspace: false,
      maxRecentWorkspaces: 3,
    }
  }

  if (normalizedRoles.has('reviewer')) {
    return {
      label: 'Reviewer',
      canSwitchWorkspace: true,
      canUseQuickSwitcher: true,
      canRestoreSession: false,
      canPinWorkspace: false,
      maxRecentWorkspaces: 2,
    }
  }

  if (normalizedRoles.has('auditor')) {
    return {
      label: 'Auditor',
      canSwitchWorkspace: false,
      canUseQuickSwitcher: false,
      canRestoreSession: false,
      canPinWorkspace: false,
      maxRecentWorkspaces: 1,
    }
  }

  return DEFAULT_POLICY
}

const getWorkspaceById = (workspaceId: string): WorkspaceTab | undefined =>
  ALL_WORKSPACES.find((workspace) => workspace.id === workspaceId)

function useWorkspaceState() {
  const [{ activeRepoId, recentRepoIds }, setWorkspaceState] = useState<WorkspaceState>(readStoredWorkspaceTabs)
  const [switcherOpen, setSwitcherOpen] = useState(false)
  const [switcherQuery, setSwitcherQuery] = useState('')
  const [sessionSnapshot, setSessionSnapshot] = useState<WorkspaceSessionSnapshot | null>(readStoredWorkspaceSession)
  const [restoreNotice, setRestoreNotice] = useState<string | null>(null)
  const { user } = useAuthStore()
  const workspacePolicy = useMemo(() => deriveWorkspacePolicy(user?.roles.map((role) => role.roleId) ?? []), [user])
  const rolloutDecision = useMemo(() => resolveMultiRepoRollout(user?.id ?? null), [user?.id])
  const multiRepoNavigationEnabled = workspacePolicy.canSwitchWorkspace && rolloutDecision.enabled

  useEffect(() => {
    if (typeof window === 'undefined') {
      return
    }

    window.localStorage.setItem(WORKSPACE_STORAGE_KEY, activeRepoId)
    window.localStorage.setItem(RECENT_STORAGE_KEY, JSON.stringify(recentRepoIds))
    saveWorkspaceSession({ activeRepoId, recentRepoIds, savedAt: Date.now() })
  }, [activeRepoId, recentRepoIds])

  const visibleRecentWorkspaces = useMemo(() => {
    return recentRepoIds
      .map((workspaceId) => getWorkspaceById(workspaceId))
      .filter((workspace): workspace is WorkspaceTab => Boolean(workspace) && !workspace.pinned)
      .slice(0, workspacePolicy.maxRecentWorkspaces)
  }, [recentRepoIds, workspacePolicy.maxRecentWorkspaces])

  const switcherResults = useMemo(() => {
    return ALL_WORKSPACES
      .map((workspace) => ({ workspace, score: scoreWorkspace(switcherQuery, workspace) }))
      .filter(({ score }) => score >= 0)
      .sort((left, right) => {
        if (right.score !== left.score) {
          return right.score - left.score
        }
        if (left.workspace.pinned !== right.workspace.pinned) {
          return left.workspace.pinned ? -1 : 1
        }
        return left.workspace.label.localeCompare(right.workspace.label)
      })
      .slice(0, 5)
      .map(({ workspace }) => workspace)
  }, [switcherQuery])

  const activeWorkspace = getWorkspaceById(activeRepoId) ?? PINNED_WORKSPACES[0]

  useEffect(() => {
    if (!sessionSnapshot) {
      return
    }

    if (!getWorkspaceById(sessionSnapshot.activeRepoId)) {
      setRestoreNotice('Saved workspace session was invalid and has been discarded')
      clearWorkspaceSession()
      setSessionSnapshot(null)
    }
  }, [sessionSnapshot])

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (!multiRepoNavigationEnabled) {
        return
      }

      const isQuickSwitchShortcut = (event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k'
      if (!isQuickSwitchShortcut) {
        return
      }

      event.preventDefault()
      setSwitcherOpen((current) => !current)
      setSwitcherQuery('')
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [multiRepoNavigationEnabled])

  const selectWorkspace = (workspaceId: string) => {
    const selectedWorkspace = getWorkspaceById(workspaceId)
    if (!selectedWorkspace) {
      return
    }

    if (!multiRepoNavigationEnabled) {
      setRestoreNotice(`Pilot ${rolloutDecision.cohort} does not allow workspace switching (${rolloutDecision.reason})`)
      return
    }

    setWorkspaceState((current) => {
      const nextRecent = [workspaceId, ...current.recentRepoIds.filter((recentId) => recentId !== workspaceId)]
        .filter((recentId) => !PINNED_WORKSPACES.some((workspace) => workspace.id === recentId))
        .slice(0, workspacePolicy.maxRecentWorkspaces)

      return {
        activeRepoId: workspaceId,
        recentRepoIds: nextRecent,
      }
    })
    setSwitcherOpen(false)
    setSwitcherQuery('')
    setRestoreNotice(`Restored ${selectedWorkspace.label} from the saved workspace session`)
  }

  const restoreSavedSession = () => {
    const savedSession = readStoredWorkspaceSession()
    if (!savedSession) {
      setRestoreNotice('No saved workspace session was found')
      return
    }

    if (!workspacePolicy.canRestoreSession) {
      setRestoreNotice(`Policy ${workspacePolicy.label} does not allow session restore`)
      return
    }

    const restoredWorkspace = getWorkspaceById(savedSession.activeRepoId)
    if (!restoredWorkspace) {
      setRestoreNotice('Saved workspace session was invalid and could not be restored')
      clearWorkspaceSession()
      setSessionSnapshot(null)
      return
    }

    const nextRecentRepoIds = savedSession.recentRepoIds
      .filter((workspaceId) => !PINNED_WORKSPACES.some((workspace) => workspace.id === workspaceId))
      .slice(0, workspacePolicy.maxRecentWorkspaces)

    setWorkspaceState({
      activeRepoId: savedSession.activeRepoId,
      recentRepoIds: nextRecentRepoIds,
    })
    setSessionSnapshot(savedSession)
    setRestoreNotice(`Restored the saved session for ${restoredWorkspace.label}`)
  }

  const forgetSavedSession = () => {
    clearWorkspaceSession()
    setSessionSnapshot(null)
    setRestoreNotice('Saved workspace session cleared')
  }

  return {
    activeRepoId,
    recentRepoIds,
    switcherOpen,
    switcherQuery,
    setSwitcherOpen,
    setSwitcherQuery,
    visibleRecentWorkspaces,
    switcherResults,
    activeWorkspace,
    sessionSnapshot,
    restoreNotice,
    selectWorkspace,
    restoreSavedSession,
    forgetSavedSession,
    workspacePolicy,
    rolloutDecision,
    multiRepoNavigationEnabled,
  }
}

type WorkspaceStateHandle = ReturnType<typeof useWorkspaceState>

const RepoHomeView: React.FC<{ workspaceState: WorkspaceStateHandle }> = ({ workspaceState }) => {
  const {
    activeWorkspace,
    visibleRecentWorkspaces,
    selectWorkspace,
    setSwitcherOpen,
    sessionSnapshot,
    restoreNotice,
    restoreSavedSession,
    forgetSavedSession,
    workspacePolicy,
    rolloutDecision,
    multiRepoNavigationEnabled,
  } = workspaceState
  const allWorkspaceCards = useMemo(() => [...PINNED_WORKSPACES, ...visibleRecentWorkspaces], [visibleRecentWorkspaces])

  return (
    <section className="mx-auto max-w-7xl px-4 py-6">
      <div className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm shadow-slate-100">
        <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.24em] text-sky-700">Multi-repo home</p>
            <h2 className="mt-2 text-2xl font-bold text-slate-900">Repo cards and jump actions</h2>
            <p className="mt-2 max-w-2xl text-sm text-slate-600">
              The home surface shows pinned workspaces, recent workspaces, and one-click actions to switch, inspect, or reopen the active repo.
            </p>
          </div>

          <div className="grid gap-3 sm:grid-cols-2">
            <div className="rounded-2xl bg-sky-50 px-4 py-3">
              <p className="text-xs font-semibold uppercase tracking-[0.2em] text-sky-700">Active workspace</p>
              <p className="mt-1 text-lg font-semibold text-slate-900">{activeWorkspace.label}</p>
              <p className="text-sm text-slate-600">Branch: {activeWorkspace.branch}</p>
            </div>
            <div className="rounded-2xl bg-emerald-50 px-4 py-3">
              <p className="text-xs font-semibold uppercase tracking-[0.2em] text-emerald-700">Jump actions</p>
              <p className="mt-1 text-sm text-slate-700">Open, switch, or revisit recent repos from one surface.</p>
            </div>
          </div>
        </div>

        <div className="mt-6 grid gap-4 lg:grid-cols-3">
          {allWorkspaceCards.map((workspace) => {
            const isActive = workspace.id === activeWorkspace.id
            return (
              <article
                key={workspace.id}
                className={`rounded-2xl border p-4 transition ${
                  isActive ? 'border-sky-500 bg-sky-50 shadow-sm' : 'border-slate-200 bg-slate-50 hover:border-slate-300'
                }`}
              >
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <p className="text-sm font-semibold text-slate-900">{workspace.label}</p>
                    <p className="text-xs text-slate-500">{workspace.id}</p>
                  </div>
                  <span className="rounded-full bg-white px-2 py-1 text-[11px] font-semibold uppercase tracking-[0.18em] text-slate-500">
                    {workspace.pinned ? 'Pinned' : 'Recent'}
                  </span>
                </div>
                <div className="mt-3 space-y-2 text-sm text-slate-600">
                  <p>Branch: {workspace.branch}</p>
                  <p>Status: {isActive ? 'Active' : 'Ready'}</p>
                </div>
                <div className="mt-4 flex flex-wrap gap-2">
                  <button
                    type="button"
                    onClick={() => selectWorkspace(workspace.id)}
                    disabled={!multiRepoNavigationEnabled}
                    className="rounded-full bg-slate-900 px-3 py-2 text-sm font-medium text-white transition hover:bg-slate-700 disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    Switch
                  </button>
                  <button
                    type="button"
                    onClick={() => multiRepoNavigationEnabled && setSwitcherOpen(true)}
                    disabled={!multiRepoNavigationEnabled}
                    className="rounded-full border border-slate-300 px-3 py-2 text-sm font-medium text-slate-700 transition hover:border-sky-400 hover:text-sky-700 disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    Jump via search
                  </button>
                </div>
              </article>
            )
          })}
        </div>

        <div className="mt-6 rounded-2xl border border-dashed border-sky-200 bg-sky-50 px-4 py-4">
          <div className="flex flex-col gap-2 md:flex-row md:items-center md:justify-between">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.24em] text-sky-700">Rollout pilot</p>
              <p className="mt-1 text-sm text-slate-700">
                Mode: <span className="font-semibold text-slate-900">{rolloutDecision.mode}</span> · Cohort: <span className="font-semibold text-slate-900">{rolloutDecision.cohort}</span>
              </p>
              <p className="text-xs text-slate-500">{rolloutDecision.reason}</p>
            </div>
            <div className="rounded-full bg-white px-3 py-1 text-xs font-semibold uppercase tracking-[0.18em] text-slate-600">
              Multi-repo nav: {multiRepoNavigationEnabled ? 'enabled' : 'pilot only'}
            </div>
          </div>
        </div>

        <div className="mt-6 rounded-2xl border border-dashed border-slate-300 bg-slate-50 px-4 py-4">
          <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-500">Session restore</p>
              <p className="mt-1 text-sm text-slate-700">
                Saved snapshot {sessionSnapshot ? `from ${new Date(sessionSnapshot.savedAt).toLocaleString()}` : 'not available'}
              </p>
              <p className="text-xs text-slate-500">
                The app stores the active repo and recent repos locally and falls back to defaults if the snapshot is missing or corrupted.
              </p>
              {restoreNotice ? <p className="mt-2 text-sm font-medium text-emerald-700">{restoreNotice}</p> : null}
            </div>

            <div className="flex flex-wrap gap-2">
              <button
                type="button"
                onClick={restoreSavedSession}
                disabled={!workspacePolicy.canRestoreSession || !multiRepoNavigationEnabled}
                className="rounded-full bg-emerald-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-50"
              >
                Restore session
              </button>
              <button
                type="button"
                onClick={forgetSavedSession}
                className="rounded-full border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 transition hover:border-slate-400 hover:text-slate-900"
              >
                Clear snapshot
              </button>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}

const WorkspaceTabs: React.FC<{ workspaceState: WorkspaceStateHandle }> = ({ workspaceState }) => {
  const {
    activeRepoId,
    switcherOpen,
    switcherQuery,
    setSwitcherOpen,
    setSwitcherQuery,
    visibleRecentWorkspaces,
    switcherResults,
    activeWorkspace,
    selectWorkspace,
    workspacePolicy,
  } = workspaceState

  return (
    <section className="border-t border-slate-200 bg-slate-50/90 px-4 py-3 shadow-inner shadow-slate-100">
      <div className="mx-auto flex max-w-7xl flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <div className="flex flex-wrap items-center gap-2">
          <span className="rounded-full bg-sky-100 px-3 py-1 text-xs font-semibold uppercase tracking-[0.24em] text-sky-800">
            Workspace tabs
          </span>
          <span className="text-sm text-slate-600">
            Active repo: <span className="font-semibold text-slate-900">{activeWorkspace.label}</span>
          </span>
        </div>

        <div className="flex flex-col gap-3 lg:flex-row lg:items-center">
          <button
            type="button"
            onClick={() => setSwitcherOpen(true)}
            disabled={!workspacePolicy.canUseQuickSwitcher}
            className="inline-flex items-center gap-2 rounded-full border border-slate-300 bg-white px-3 py-2 text-sm font-medium text-slate-700 transition hover:border-sky-400 hover:text-sky-700 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <span>Quick switcher</span>
            <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[11px] uppercase tracking-[0.18em] text-slate-500">
              Ctrl/⌘ K
            </span>
          </button>

          <div className="flex flex-wrap gap-2">
            {PINNED_WORKSPACES.map((workspace) => (
              <button
                key={workspace.id}
                type="button"
                onClick={() => selectWorkspace(workspace.id)}
                disabled={!workspacePolicy.canSwitchWorkspace}
                className={`rounded-full border px-3 py-2 text-sm font-medium transition ${
                  workspace.id === activeRepoId
                    ? 'border-sky-600 bg-sky-600 text-white shadow-sm'
                    : 'border-slate-300 bg-white text-slate-700 hover:border-sky-400 hover:text-sky-700'
                } disabled:cursor-not-allowed disabled:opacity-50`}
              >
                <span className="block text-left">{workspace.label}</span>
                <span className={`block text-[11px] ${workspace.id === activeRepoId ? 'text-sky-100' : 'text-slate-500'}`}>
                  {workspace.branch}
                </span>
              </button>
            ))}
          </div>

          <div className="flex flex-wrap items-center gap-2 border-l-0 border-slate-200 pt-1 lg:border-l lg:pl-4 lg:pt-0">
            <span className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Recent</span>
            {visibleRecentWorkspaces.length > 0 ? (
              visibleRecentWorkspaces.map((workspace) => (
                <button
                  key={workspace.id}
                  type="button"
                  onClick={() => selectWorkspace(workspace.id)}
                  className={`rounded-full border px-3 py-2 text-sm transition ${
                    workspace.id === activeRepoId
                      ? 'border-emerald-600 bg-emerald-600 text-white'
                      : 'border-dashed border-slate-300 bg-white text-slate-600 hover:border-emerald-400 hover:text-emerald-700'
                  }`}
                >
                  {workspace.label}
                </button>
              ))
            ) : (
              <span className="text-sm text-slate-500">No recent repos yet</span>
            )}
          </div>
        </div>
      </div>

      {switcherOpen ? (
        <div className="fixed inset-0 z-50 flex items-start justify-center bg-slate-950/50 px-4 py-16 backdrop-blur-sm">
          <div className="w-full max-w-2xl overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-2xl shadow-slate-900/20">
            <div className="border-b border-slate-200 px-4 py-3">
              <div className="flex items-center justify-between gap-4">
                <div>
                  <p className="text-sm font-semibold text-slate-900">Instant repo switcher</p>
                  <p className="text-xs text-slate-500">Search pinned and recent repos. Press Enter to switch.</p>
                </div>
                <button
                  type="button"
                  onClick={() => {
                    setSwitcherOpen(false)
                    setSwitcherQuery('')
                  }}
                  className="rounded-full border border-slate-300 px-3 py-1 text-sm text-slate-600 hover:border-slate-400 hover:text-slate-800"
                >
                  Close
                </button>
              </div>
            </div>

            <div className="p-4">
              <label className="mb-3 block text-xs font-semibold uppercase tracking-[0.24em] text-slate-500" htmlFor="repo-switcher-query">
                Fuzzy search
              </label>
              <input
                id="repo-switcher-query"
                autoFocus
                value={switcherQuery}
                onChange={(event) => setSwitcherQuery(event.target.value)}
                placeholder="Search by repo name, branch, or workspace id"
                className="w-full rounded-xl border border-slate-300 px-4 py-3 text-sm text-slate-900 outline-none ring-0 transition placeholder:text-slate-400 focus:border-sky-500"
              />

              <div className="mt-4 space-y-2">
                {switcherResults.map((workspace) => (
                  <button
                    key={workspace.id}
                    type="button"
                    onClick={() => selectWorkspace(workspace.id)}
                    disabled={!workspacePolicy.canSwitchWorkspace}
                    className={`flex w-full items-center justify-between rounded-xl border px-4 py-3 text-left transition ${
                      workspace.id === activeRepoId
                        ? 'border-sky-500 bg-sky-50'
                        : 'border-slate-200 bg-slate-50 hover:border-slate-300 hover:bg-slate-100'
                    } disabled:cursor-not-allowed disabled:opacity-60`}
                  >
                    <div>
                      <p className="text-sm font-semibold text-slate-900">{workspace.label}</p>
                      <p className="text-xs text-slate-500">{workspace.branch}</p>
                    </div>
                    <span className="text-xs uppercase tracking-[0.2em] text-slate-400">{workspace.pinned ? 'Pinned' : 'Recent'}</span>
                  </button>
                ))}

                {switcherResults.length === 0 ? (
                  <p className="rounded-xl border border-dashed border-slate-300 px-4 py-6 text-center text-sm text-slate-500">
                    No matching repos found
                  </p>
                ) : null}
              </div>
            </div>
          </div>
        </div>
      ) : null}
    </section>
  )
}

/**
 * ProtectedRoute Component
 * Redirects to login if not authenticated
 */
interface ProtectedRouteProps {
  children: React.ReactNode
}

const ProtectedRoute: React.FC<ProtectedRouteProps> = ({ children }) => {
  const { isAuthenticated } = useAuthStore()
  const location = useLocation()

  if (!isAuthenticated) {
    return <Navigate to="/login" replace state={{ from: location }} />
  }

  return <>{children}</>
}

/**
 * Layout Component
 */
const Layout: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const navigate = useNavigate()
  const location = useLocation()
  const { user, isAuthenticated } = useAuthStore()
  const workspaceState = useWorkspaceState()
  const isSessionsPage = location.pathname.startsWith('/sessions')
  const canOpenAdminControls = user?.roles.some((role) => role.roleId === 'admin') ?? false

  if (!isAuthenticated) {
    return <>{children}</>
  }

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col">
      {/* Navigation Bar */}
      <nav className="bg-white shadow-sm">
        <div className="max-w-7xl mx-auto px-4 py-4 flex justify-between items-center">
          <h1 className="text-2xl font-bold text-sky-900">🔐 RBAC Dashboard</h1>
          <div className="hidden md:flex items-center gap-2">
            <Link
              className="rounded-lg border border-slate-200 px-4 py-2 text-sm font-medium text-slate-700 transition hover:bg-slate-100"
              to="/"
            >
              Dashboard
            </Link>
            <Link
              aria-current={isSessionsPage ? 'page' : undefined}
              className={`rounded-lg border px-4 py-2 text-sm font-medium transition ${
                isSessionsPage
                  ? 'border-sky-200 bg-sky-50 text-sky-900'
                  : 'border-slate-200 text-slate-700 hover:bg-slate-100'
              }`}
              to="/sessions"
            >
              Ephemeral Sessions
            </Link>
            {canOpenAdminControls ? (
              <Link
                className="rounded-lg border border-amber-200 px-4 py-2 text-sm font-medium text-amber-900 transition hover:bg-amber-50"
                to="/admin-controls"
              >
                Control Plane
              </Link>
            ) : null}
          </div>
          <div className="flex items-center gap-4">
            <span className="text-gray-600">{user?.email}</span>
            <button
              onClick={() => {
                useAuthStore.getState().clearAuth()
                navigate('/login')
              }}
              className="px-4 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700"
            >
              Logout
            </button>
          </div>
        </div>
      </nav>

      <WorkspaceTabs workspaceState={workspaceState} />

      {/* Main Content */}
      <main className="flex-1">
        <RepoHomeView workspaceState={workspaceState} />
        {children}
      </main>

      {/* Footer */}
      <footer className="bg-gray-100 text-center text-sm text-gray-600 py-4">
        <p>Enterprise RBAC Dashboard • Phase 3B</p>
      </footer>
    </div>
  )
}

/**
 * App Component
 * Main SPA router and layout
 */
export function App() {
  return (
    <Router>
      <Layout>
        <Routes>
          {/* Public Routes */}
          <Route path="/login" element={<LoginPage />} />
          <Route path="/mfa-setup" element={<MFASetup />} />

          {/* Protected Routes */}
          <Route
            path="/"
            element={
              <ProtectedRoute>
                <UserManagementPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/sessions"
            element={
              <ProtectedRoute>
                <EphemeralSessionsPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/admin-controls"
            element={
              <ProtectedRoute>
                <AdminControlsPage />
              </ProtectedRoute>
            }
          />

          {/* Catch-all */}
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Layout>
    </Router>
  )
}
