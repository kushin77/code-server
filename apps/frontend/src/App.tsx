import React, { useEffect, useMemo, useState } from 'react'
import { BrowserRouter as Router, Routes, Route, Navigate, Link, useNavigate, useLocation } from 'react-router-dom'
import { useAuthStore } from '@/store'
import { LoginPage } from '@/pages/LoginPage'
import { MFASetup } from '@/pages/MFASetup'
import { AdminControlsPage } from '@/pages/AdminControlsPage'
import { WorkspaceOnboardingWizard } from '@/pages/WorkspaceOnboardingWizard'
import { WorkspaceProfilesPage } from '@/pages/WorkspaceProfilesPage'
import { IDEPerformanceProfilerPage } from '@/pages/IDEPerformanceProfilerPage'
import { FigmaDesignEmbedPage } from '@/pages/FigmaDesignEmbedPage'
import { SentryErrorsPage } from '@/pages/SentryErrorsPage'
import { FeatureFlagsPage } from '@/pages/FeatureFlagsPage'
import { PagerDutyIncidentsPage } from '@/pages/PagerDutyIncidentsPage'
import { UserManagementPage } from '@/pages/UserManagement'
import { EphemeralSessionsPage } from '@/pages/EphemeralSessions'
import { RepoHomeView } from '@/pages/RepoHomeView'
import {
  ALL_WORKSPACES,
  PINNED_WORKSPACES,
  RECENT_STORAGE_KEY,
  WORKSPACE_STATE_SYNC_EVENT,
  WORKSPACE_STORAGE_KEY,
  buildRecentWorkspaceIds,
  getWorkspaceById,
  readStoredWorkspaceTabs as readStoredWorkspaceTabsFromStorage,
  scoreWorkspace,
  writeStoredWorkspaceTabs,
  type WorkspaceState,
  type WorkspaceTab,
} from '@/utils/workspaceCatalog'
import {
  assessMultiRepoPolicyConformance,
  buildMultiRepoPolicyAuditRecord,
  resolveMultiRepoPolicy,
  serializeMultiRepoPolicy,
} from '@/utils/multiRepoPolicy'
import { resolveMultiRepoRollout } from '@/utils/multiRepoRollout'
import {
  buildRepoCardActions,
  createDefaultRepoHomeSnapshot,
  readRepoHomeSnapshot,
  RepoCardActionId,
  RepoHomeSnapshot,
  refreshRepoHomeSnapshot,
  writeRepoHomeSnapshot,
} from '@/utils/repoHomeData'
import {
  buildSafeWorkspaceRestorePlan,
  clearWorkspaceSessionSnapshot,
  createWorkspaceSessionSnapshot,
  readWorkspaceRestorePreferences,
  readWorkspaceSessionSnapshot,
  scheduleWorkspaceSessionPersist,
  WorkspaceRestorePreferences,
  WorkspaceSessionSnapshot,
  writeWorkspaceRestorePreferences,
  writeWorkspaceSessionSnapshot,
} from '@/utils/workspaceSessionPersistence'

function useWorkspaceState() {
  const [{ activeRepoId, recentRepoIds }, setWorkspaceState] = useState<WorkspaceState>(() =>
    readStoredWorkspaceTabsFromStorage(typeof window === 'undefined' ? undefined : window.localStorage)
  )
  const [switcherOpen, setSwitcherOpen] = useState(false)
  const [switcherQuery, setSwitcherQuery] = useState('')
  const [sessionSnapshot, setSessionSnapshot] = useState<WorkspaceSessionSnapshot | null>(() =>
    readWorkspaceSessionSnapshot(typeof window === 'undefined' ? undefined : window.localStorage)
  )
  const [restorePreferences, setRestorePreferences] = useState<WorkspaceRestorePreferences>(() =>
    readWorkspaceRestorePreferences(typeof window === 'undefined' ? undefined : window.localStorage)
  )
  const [restoreNotice, setRestoreNotice] = useState<string | null>(null)
  const [actionNotice, setActionNotice] = useState<string | null>(null)
  const [repoHomeSnapshot, setRepoHomeSnapshot] = useState<RepoHomeSnapshot>(() => {
    if (typeof window === 'undefined') {
      return createDefaultRepoHomeSnapshot()
    }

    return readRepoHomeSnapshot(window.localStorage) ?? createDefaultRepoHomeSnapshot()
  })
  const { user } = useAuthStore()
  const workspacePolicy = useMemo(() => resolveMultiRepoPolicy(user?.roles.map((role) => role.roleId) ?? []), [user])
  const rolloutDecision = useMemo(() => resolveMultiRepoRollout(user?.id ?? null), [user?.id])
  const multiRepoTabsEnabled = workspacePolicy.canSwitchWorkspace && rolloutDecision.enabled && rolloutDecision.capabilities.tabs
  const multiRepoSwitcherEnabled =
    workspacePolicy.canUseQuickSwitcher && rolloutDecision.enabled && rolloutDecision.capabilities.switcher
  const multiRepoPersistenceEnabled =
    workspacePolicy.canRestoreSession && rolloutDecision.enabled && rolloutDecision.capabilities.persistence
  const policyReport = useMemo(
    () =>
      assessMultiRepoPolicyConformance(workspacePolicy, {
        recentRepoIds,
        requestedCapabilities: {
          tabs: multiRepoTabsEnabled,
          switcher: multiRepoSwitcherEnabled,
          persistence: multiRepoPersistenceEnabled,
        },
      }),
    [multiRepoPersistenceEnabled, multiRepoSwitcherEnabled, multiRepoTabsEnabled, recentRepoIds, workspacePolicy]
  )
  const repoCardIndex = useMemo(
    () => new Map(repoHomeSnapshot.cards.map((card) => [card.id, card] as const)),
    [repoHomeSnapshot.cards]
  )

  useEffect(() => {
    if (typeof window === 'undefined') {
      return
    }

    writeStoredWorkspaceTabs(window.localStorage, { activeRepoId, recentRepoIds })
    scheduleWorkspaceSessionPersist(() => {
      writeWorkspaceSessionSnapshot(
        window.localStorage,
        createWorkspaceSessionSnapshot({
          activeRepoId,
          recentRepoIds,
          branchRef: (repoCardIndex.get(activeRepoId)?.status.branch ?? getWorkspaceById(activeRepoId)?.branch ?? 'main'),
        })
      )
    })
  }, [activeRepoId, recentRepoIds])

  useEffect(() => {
    if (typeof window === 'undefined') {
      return
    }

    const handleWorkspaceStateSync = () => {
      setWorkspaceState(readStoredWorkspaceTabsFromStorage(window.localStorage))
    }

    const handleStorageEvent = (event: StorageEvent) => {
      if (event.key === WORKSPACE_STORAGE_KEY || event.key === RECENT_STORAGE_KEY || event.key === null) {
        handleWorkspaceStateSync()
      }
    }

    window.addEventListener(WORKSPACE_STATE_SYNC_EVENT, handleWorkspaceStateSync)
    window.addEventListener('storage', handleStorageEvent)

    return () => {
      window.removeEventListener(WORKSPACE_STATE_SYNC_EVENT, handleWorkspaceStateSync)
      window.removeEventListener('storage', handleStorageEvent)
    }
  }, [])

  useEffect(() => {
    if (typeof window === 'undefined') {
      return
    }

    writeWorkspaceRestorePreferences(window.localStorage, restorePreferences)
  }, [restorePreferences])

  useEffect(() => {
    if (typeof window === 'undefined') {
      return
    }

    window.localStorage.setItem('workspace-tabs:policy-definition', serializeMultiRepoPolicy(workspacePolicy))
    window.localStorage.setItem(
      'workspace-tabs:policy-audit',
      JSON.stringify(buildMultiRepoPolicyAuditRecord(workspacePolicy, policyReport))
    )
  }, [policyReport, workspacePolicy])

  useEffect(() => {
    if (typeof window === 'undefined') {
      return
    }

    writeRepoHomeSnapshot(window.localStorage, repoHomeSnapshot)
  }, [repoHomeSnapshot])

  useEffect(() => {
    if (typeof window === 'undefined') {
      return
    }

    const refreshHandle = window.setInterval(() => {
      setRepoHomeSnapshot((currentSnapshot) => refreshRepoHomeSnapshot(currentSnapshot, Date.now()))
    }, repoHomeSnapshot.refreshIntervalMs)

    return () => window.clearInterval(refreshHandle)
  }, [repoHomeSnapshot.refreshIntervalMs])

  const visibleRecentWorkspaces = useMemo(() => {
    return recentRepoIds
      .map((workspaceId) => getWorkspaceById(workspaceId))
      .filter((workspace): workspace is WorkspaceTab => Boolean(workspace) && workspace !== undefined && !workspace.pinned)
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
  const activeRepoCard = repoCardIndex.get(activeRepoId)

  useEffect(() => {
    if (!sessionSnapshot) {
      return
    }

    if (!getWorkspaceById(sessionSnapshot.activeRepoId)) {
      setRestoreNotice('Saved workspace session was invalid and has been discarded')
      clearWorkspaceSessionSnapshot(typeof window === 'undefined' ? undefined : window.localStorage)
      setSessionSnapshot(null)
    }
  }, [sessionSnapshot])

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (!multiRepoSwitcherEnabled) {
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
  }, [multiRepoSwitcherEnabled])

  const selectWorkspace = (workspaceId: string) => {
    const selectedWorkspace = getWorkspaceById(workspaceId)
    if (!selectedWorkspace) {
      return
    }

    if (!multiRepoTabsEnabled) {
      setRestoreNotice(`Pilot ${rolloutDecision.cohort} does not allow workspace switching (${rolloutDecision.reason})`)
      return
    }

    setWorkspaceState((current) => {
      const nextRecent = buildRecentWorkspaceIds(workspaceId, current.recentRepoIds).filter(
        (recentId) => !PINNED_WORKSPACES.some((workspace) => workspace.id === recentId)
      ).slice(0, workspacePolicy.maxRecentWorkspaces)

      return {
        activeRepoId: workspaceId,
        recentRepoIds: nextRecent,
      }
    })
    setSwitcherOpen(false)
    setSwitcherQuery('')
    setActionNotice(null)
    setRestoreNotice(`Restored ${selectedWorkspace.label} from the saved workspace session`)
  }

  const performRepoAction = (workspaceId: string, actionId: RepoCardActionId) => {
    const targetCard = repoCardIndex.get(workspaceId)
    if (!targetCard) {
      return
    }

    const action = buildRepoCardActions(targetCard, workspacePolicy, activeRepoId).find((candidate) => candidate.id === actionId)
    if (!action) {
      return
    }

    if (action.disabled) {
      setActionNotice(action.reason ?? 'This action is currently unavailable')
      return
    }

    handleRepoCardAction(actionId, targetCard, {
      onSwitch: selectWorkspace,
      onNotice: setActionNotice,
    })
  }

  const restoreSavedSession = () => {
    const savedSession = readWorkspaceSessionSnapshot(typeof window === 'undefined' ? undefined : window.localStorage)
    if (!savedSession) {
      setRestoreNotice('No saved workspace session was found')
      return
    }

    if (!multiRepoPersistenceEnabled) {
      setRestoreNotice(`Pilot ${rolloutDecision.cohort} does not allow session restore (${rolloutDecision.reason})`)
      return
    }

    const restoredWorkspace = getWorkspaceById(savedSession.activeRepoId)
    if (!restoredWorkspace) {
      setRestoreNotice('Saved workspace session was invalid and could not be restored')
      clearWorkspaceSessionSnapshot(typeof window === 'undefined' ? undefined : window.localStorage)
      setSessionSnapshot(null)
      return
    }

    const restorePlan = buildSafeWorkspaceRestorePlan(savedSession, restorePreferences, false)

    const nextRecentRepoIds = buildRecentWorkspaceIds(
      restorePlan.activeRepoId,
      restorePlan.recentRepoIds.filter((workspaceId) => !PINNED_WORKSPACES.some((workspace) => workspace.id === workspaceId)),
      workspacePolicy.maxRecentWorkspaces,
    )

    setWorkspaceState({
      activeRepoId: restorePlan.activeRepoId,
      recentRepoIds: nextRecentRepoIds,
    })
    setSessionSnapshot(savedSession)
    setActionNotice(null)
    const disabledModules = Object.entries(restorePreferences)
      .filter(([, enabled]) => !enabled)
      .map(([moduleName]) => moduleName)

    setRestoreNotice(
      disabledModules.length > 0
        ? `Restored ${restoredWorkspace.label} with partial modules disabled: ${disabledModules.join(', ')}`
        : `Restored the saved session for ${restoredWorkspace.label}`
    )
  }

  const forgetSavedSession = () => {
    clearWorkspaceSessionSnapshot(typeof window === 'undefined' ? undefined : window.localStorage)
    setSessionSnapshot(null)
    setRestoreNotice('Saved workspace session cleared')
  }

  const setRestorePreference = (moduleName: keyof WorkspaceRestorePreferences, enabled: boolean) => {
    if (moduleName === 'terminals' && enabled) {
      setRestoreNotice('Unsafe terminal replay is blocked by default in pilot mode')
      setRestorePreferences((currentPreferences) => ({ ...currentPreferences, terminals: false }))
      return
    }

    setRestorePreferences((currentPreferences) => ({ ...currentPreferences, [moduleName]: enabled }))
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
    activeRepoCard,
    sessionSnapshot,
    restoreNotice,
    actionNotice,
    repoHomeSnapshot,
    selectWorkspace,
    performRepoAction,
    restoreSavedSession,
    forgetSavedSession,
    restorePreferences,
    setRestorePreference,
    workspacePolicy,
    policyReport,
    rolloutDecision,
    multiRepoNavigationEnabled: multiRepoTabsEnabled,
    multiRepoTabsEnabled,
    multiRepoSwitcherEnabled,
    multiRepoPersistenceEnabled,
  }
}

export type WorkspaceStateHandle = ReturnType<typeof useWorkspaceState>

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
    multiRepoTabsEnabled,
    multiRepoSwitcherEnabled,
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
            disabled={!multiRepoSwitcherEnabled}
            className="inline-flex items-center gap-2 rounded-full border border-slate-300 bg-white px-3 py-2 text-sm font-medium text-slate-700 transition hover:border-sky-400 hover:text-sky-700 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <span>Quick switcher</span>
            <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[11px] uppercase tracking-[0.18em] text-slate-500">
              Ctrl/⌘ K
            </span>
          </button>

          <div className="flex flex-wrap gap-2">
            {PINNED_WORKSPACES.map((workspace: typeof PINNED_WORKSPACES[0]) => (
              <button
                key={workspace.id}
                type="button"
                onClick={() => selectWorkspace(workspace.id)}
                disabled={!multiRepoTabsEnabled}
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
              visibleRecentWorkspaces.map((workspace: typeof visibleRecentWorkspaces[0]) => (
                <button
                  key={workspace.id}
                  type="button"
                  onClick={() => selectWorkspace(workspace.id)}
                    disabled={!multiRepoTabsEnabled}
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
                {switcherResults.map((workspace: typeof switcherResults[0]) => (
                  <button
                    key={workspace.id}
                    type="button"
                    onClick={() => selectWorkspace(workspace.id)}
                    disabled={!multiRepoSwitcherEnabled}
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
const Layout: React.FC<{ children: React.ReactNode; workspaceState: ReturnType<typeof useWorkspaceState> }> = ({
  children,
  workspaceState,
}) => {
  const navigate = useNavigate()
  const location = useLocation()
  const { user, isAuthenticated } = useAuthStore()
  const isSessionsPage = location.pathname.startsWith('/sessions')
  const isOnboardingPage = location.pathname.startsWith('/onboarding')
  const isWorkspaceProfilesPage = location.pathname.startsWith('/workspace-profiles')
  const isProfilerPage = location.pathname.startsWith('/performance-profiler')
  const isFigmaDesignPage = location.pathname.startsWith('/figma-design')
  const isSentryErrorsPage = location.pathname.startsWith('/sentry-errors')
  const isFeatureFlagsPage = location.pathname.startsWith('/feature-flags')
  const isPagerDutyIncidentsPage = location.pathname.startsWith('/pagerduty-incidents')
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
              aria-current={isOnboardingPage ? 'page' : undefined}
              className={`rounded-lg border px-4 py-2 text-sm font-medium transition ${
                isOnboardingPage
                  ? 'border-emerald-200 bg-emerald-50 text-emerald-900'
                  : 'border-slate-200 text-slate-700 hover:bg-slate-100'
              }`}
              to="/onboarding"
            >
              Onboarding
            </Link>
            <Link
              aria-current={isWorkspaceProfilesPage ? 'page' : undefined}
              className={`rounded-lg border px-4 py-2 text-sm font-medium transition ${
                isWorkspaceProfilesPage
                  ? 'border-violet-200 bg-violet-50 text-violet-900'
                  : 'border-slate-200 text-slate-700 hover:bg-slate-100'
              }`}
              to="/workspace-profiles"
            >
              Workspace Profiles
            </Link>
            <Link
              aria-current={isProfilerPage ? 'page' : undefined}
              className={`rounded-lg border px-4 py-2 text-sm font-medium transition ${
                isProfilerPage
                  ? 'border-sky-200 bg-sky-50 text-sky-900'
                  : 'border-slate-200 text-slate-700 hover:bg-slate-100'
              }`}
              to="/performance-profiler"
            >
              Profiler
            </Link>
            <Link
              aria-current={isFigmaDesignPage ? 'page' : undefined}
              className={`rounded-lg border px-4 py-2 text-sm font-medium transition ${
                isFigmaDesignPage
                  ? 'border-pink-200 bg-pink-50 text-pink-900'
                  : 'border-slate-200 text-slate-700 hover:bg-slate-100'
              }`}
              to="/figma-design"
            >
              Figma Design
            </Link>
            <Link
              aria-current={isSentryErrorsPage ? 'page' : undefined}
              className={`rounded-lg border px-4 py-2 text-sm font-medium transition ${
                isSentryErrorsPage
                  ? 'border-orange-200 bg-orange-50 text-orange-900'
                  : 'border-slate-200 text-slate-700 hover:bg-slate-100'
              }`}
              to="/sentry-errors"
            >
              Sentry Errors
            </Link>
            <Link
              aria-current={isFeatureFlagsPage ? 'page' : undefined}
              className={`rounded-lg border px-4 py-2 text-sm font-medium transition ${
                isFeatureFlagsPage
                  ? 'border-emerald-200 bg-emerald-50 text-emerald-900'
                  : 'border-slate-200 text-slate-700 hover:bg-slate-100'
              }`}
              to="/feature-flags"
            >
              Feature Flags
            </Link>
            <Link
              aria-current={isPagerDutyIncidentsPage ? 'page' : undefined}
              className={`rounded-lg border px-4 py-2 text-sm font-medium transition ${
                isPagerDutyIncidentsPage
                  ? 'border-red-200 bg-red-50 text-red-900'
                  : 'border-slate-200 text-slate-700 hover:bg-slate-100'
              }`}
              to="/pagerduty-incidents"
            >
              PagerDuty Incidents
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
        {!isOnboardingPage ? <RepoHomeView workspaceState={workspaceState} /> : null}
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
 * Helper: Handle individual repo card actions
 * Reduces complexity by isolating action dispatch logic
 * CC reduced from 35-40 to ~8
 */
function handleRepoCardAction(
  actionId: RepoCardActionId,
  targetCard: RepoHomeSnapshot['cards'][number],
  options: {
    onSwitch: (workspaceId: string, cardLabel: string, isOpen: boolean) => void
    onNotice: (message: string) => void
  },
): void {
  const { onSwitch, onNotice } = options

  switch (actionId) {
    case 'open':
    case 'switch':
      onSwitch(targetCard.id, targetCard.label, actionId === 'open')
      onNotice(`${actionId === 'open' ? 'Opened' : 'Switched to'} ${targetCard.label}`)
      break

    case 'pull':
      onNotice(`Pull queued for ${targetCard.label}. Continue from branch ${targetCard.status.branch} in the active terminal.`)
      break

    case 'pullRequests':
      window.open(targetCard.links.pullRequests, '_blank', 'noopener,noreferrer')
      onNotice(`Opened pull requests for ${targetCard.label}`)
      break

    case 'issues':
      window.open(targetCard.links.issues, '_blank', 'noopener,noreferrer')
      onNotice(`Opened issues for ${targetCard.label}`)
      break

    case 'runbook':
      window.open(targetCard.links.runbook, '_blank', 'noopener,noreferrer')
      onNotice(`Opened the runbook for ${targetCard.label}`)
      break
  }
}

/**
 * App Component
 * Main SPA router and layout
 */
export function App() {
  const workspaceState = useWorkspaceState()

  return (
    <Router>
      <Layout workspaceState={workspaceState}>
        <Routes>
          {/* Public Routes */}
          <Route path="/login" element={<LoginPage />} />
          <Route path="/mfa-setup" element={<MFASetup />} />

          {/* Protected Routes */}
          <Route
            path="/onboarding"
            element={
              <ProtectedRoute>
                <WorkspaceOnboardingWizard />
              </ProtectedRoute>
            }
          />
          <Route
            path="/workspace-profiles"
            element={
              <ProtectedRoute>
                <WorkspaceProfilesPage workspaceState={workspaceState} />
              </ProtectedRoute>
            }
          />
          <Route
            path="/performance-profiler"
            element={
              <ProtectedRoute>
                <IDEPerformanceProfilerPage workspaceState={workspaceState} />
              </ProtectedRoute>
            }
          />
          <Route
            path="/figma-design"
            element={
              <ProtectedRoute>
                <FigmaDesignEmbedPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/sentry-errors"
            element={
              <ProtectedRoute>
                <SentryErrorsPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/feature-flags"
            element={
              <ProtectedRoute>
                <FeatureFlagsPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/pagerduty-incidents"
            element={
              <ProtectedRoute>
                <PagerDutyIncidentsPage />
              </ProtectedRoute>
            }
          />
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
