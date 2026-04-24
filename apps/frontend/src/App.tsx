import React, { useEffect, useMemo, useState } from 'react'
import { BrowserRouter as Router, Routes, Route, Navigate, Link, useNavigate, useLocation } from 'react-router-dom'
import { useAuthStore } from '@/store'
import { LoginPage } from '@/pages/LoginPage'
import { MFASetup } from '@/pages/MFASetup'
import { AdminControlsPage } from '@/pages/AdminControlsPage'
import { WorkspaceOnboardingWizard } from '@/pages/WorkspaceOnboardingWizard'
import { UserManagementPage } from '@/pages/UserManagement'
import { EphemeralSessionsPage } from '@/pages/EphemeralSessions'
import { RepoHomeView } from '@/pages/RepoHomeView'
import { PagerDutyIncidentsPage } from '@/pages/PagerDutyIncidentsPage'
import { TeamHubMetricsPage } from '@/pages/TeamHubMetricsPage'
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
  DEFAULT_STATUS_BAR_TILES,
  CI_LOGS_ROUTE,
  fetchActivePagerDutyIncidentCount,
  fetchOpenPullRequestCount,
  fetchReviewRequestCount,
  getDemoTeamOnlineCount,
  getGitHubHandleFromEmail,
  PAGERDUTY_INCIDENTS_ROUTE,
  readStatusBarTileConfig,
  StatusBarTileConfig,
  StatusBarTileId,
  TEAM_HUB_ROUTE,
  writeStatusBarTileConfig,
} from '@/utils/collaborationMetrics'
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

const getWorkspaceById = (workspaceId: string): WorkspaceTab | undefined =>
  ALL_WORKSPACES.find((workspace) => workspace.id === workspaceId)

function useWorkspaceState() {
  const [{ activeRepoId, recentRepoIds }, setWorkspaceState] = useState<WorkspaceState>(readStoredWorkspaceTabs)
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

    window.localStorage.setItem(WORKSPACE_STORAGE_KEY, activeRepoId)
    window.localStorage.setItem(RECENT_STORAGE_KEY, JSON.stringify(recentRepoIds))
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
      .filter((workspace): workspace is WorkspaceTab => {
        if (!workspace) return false
        return !workspace.pinned
      })
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

    const nextRecentRepoIds = restorePlan.recentRepoIds
      .filter((workspaceId) => !PINNED_WORKSPACES.some((workspace) => workspace.id === workspaceId))
      .slice(0, workspacePolicy.maxRecentWorkspaces)

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

const CI_STATUS_LABELS: Record<string, { badge: string; text: string; description: string }> = {
  passing: {
    badge: 'border-emerald-200 bg-emerald-50 text-emerald-700',
    text: 'text-emerald-700',
    description: 'Branch checks passing',
  },
  running: {
    badge: 'border-sky-200 bg-sky-50 text-sky-700',
    text: 'text-sky-700',
    description: 'Branch checks running',
  },
  failing: {
    badge: 'border-rose-200 bg-rose-50 text-rose-700',
    text: 'text-rose-700',
    description: 'Branch checks failing',
  },
  blocked: {
    badge: 'border-amber-200 bg-amber-50 text-amber-700',
    text: 'text-amber-700',
    description: 'Branch checks blocked',
  },
}

const CollaborationStatusStrip: React.FC<{ workspaceState: WorkspaceStateHandle }> = ({ workspaceState }) => {
  const { user } = useAuthStore()
  const { activeRepoCard, activeWorkspace } = workspaceState
  const [openPullRequestCount, setOpenPullRequestCount] = useState<number | null>(null)
  const [reviewRequestCount, setReviewRequestCount] = useState<number | null>(null)
  const [activeIncidentCount, setActiveIncidentCount] = useState<number | null>(null)
  const [tileCustomizerOpen, setTileCustomizerOpen] = useState(false)
  const [statusBarTiles, setStatusBarTiles] = useState<StatusBarTileConfig[]>(() =>
    readStatusBarTileConfig(typeof window === 'undefined' ? undefined : window.localStorage)
  )

  const githubHandle = useMemo(() => getGitHubHandleFromEmail(user?.email), [user?.email])
  const ciStatus = activeRepoCard?.status.ciStatus ?? 'passing'
  const ciStyle = CI_STATUS_LABELS[ciStatus] ?? CI_STATUS_LABELS.passing
  const openPullRequestLabel = githubHandle && activeRepoCard ? `for @${githubHandle}` : 'for the active repo'

  useEffect(() => {
    if (typeof window === 'undefined') {
      return
    }

    writeStatusBarTileConfig(window.localStorage, statusBarTiles)
  }, [statusBarTiles])

  const updateTileVisibility = (tileId: StatusBarTileId, visible: boolean) => {
    setStatusBarTiles((currentTiles) =>
      currentTiles.map((tile) => (tile.id === tileId ? { ...tile, visible } : tile))
    )
  }

  const moveTile = (tileId: StatusBarTileId, direction: -1 | 1) => {
    setStatusBarTiles((currentTiles) => {
      const currentIndex = currentTiles.findIndex((tile) => tile.id === tileId)
      const targetIndex = currentIndex + direction

      if (currentIndex < 0 || targetIndex < 0 || targetIndex >= currentTiles.length) {
        return currentTiles
      }

      const nextTiles = [...currentTiles]
      const [movedTile] = nextTiles.splice(currentIndex, 1)
      nextTiles.splice(targetIndex, 0, movedTile)
      return nextTiles
    })
  }

  const resetTileConfig = () => {
    setStatusBarTiles(DEFAULT_STATUS_BAR_TILES.map((tile) => ({ ...tile })))
    setTileCustomizerOpen(false)
  }

  const renderTileSettings = () => (
    <div className="mx-auto mt-4 max-w-7xl rounded-3xl border border-slate-200 bg-slate-50/80 p-4 shadow-inner shadow-slate-100">
      <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Status bar tiles</p>
          <p className="mt-1 text-sm text-slate-600">Show, hide, and reorder the collaboration tiles.</p>
        </div>
        <button
          type="button"
          onClick={resetTileConfig}
          className="inline-flex items-center rounded-full border border-slate-300 bg-white px-3 py-1.5 text-xs font-medium text-slate-700 transition hover:border-slate-400 hover:text-slate-900"
        >
          Reset defaults
        </button>
      </div>
      <div className="mt-4 grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        {statusBarTiles.map((tile, index) => (
          <div key={tile.id} className="rounded-2xl border border-slate-200 bg-white px-4 py-3">
            <div className="flex items-center justify-between gap-3">
              <div>
                <p className="text-sm font-semibold text-slate-900">
                  {tile.id === 'open-prs' ? 'Open PRs' : tile.id === 'branch-ci' ? 'Branch CI' : tile.id === 'pagerduty' ? 'PagerDuty' : 'Team online'}
                </p>
                <p className="text-xs text-slate-500">{tile.visible ? 'Visible' : 'Hidden'}</p>
              </div>
              <label className="inline-flex items-center gap-2 text-xs font-medium text-slate-600">
                <input
                  type="checkbox"
                  checked={tile.visible}
                  onChange={(event) => updateTileVisibility(tile.id, event.target.checked)}
                  className="h-4 w-4 rounded border-slate-300 text-sky-600 focus:ring-sky-500"
                />
                Show
              </label>
            </div>
            <div className="mt-3 flex items-center gap-2">
              <button
                type="button"
                onClick={() => moveTile(tile.id, -1)}
                disabled={index === 0}
                className="rounded-full border border-slate-300 px-3 py-1 text-xs font-medium text-slate-700 transition enabled:hover:border-slate-400 enabled:hover:text-slate-900 disabled:cursor-not-allowed disabled:opacity-40"
              >
                Move up
              </button>
              <button
                type="button"
                onClick={() => moveTile(tile.id, 1)}
                disabled={index === statusBarTiles.length - 1}
                className="rounded-full border border-slate-300 px-3 py-1 text-xs font-medium text-slate-700 transition enabled:hover:border-slate-400 enabled:hover:text-slate-900 disabled:cursor-not-allowed disabled:opacity-40"
              >
                Move down
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  )

  useEffect(() => {
    let cancelled = false

    const loadPullRequests = async () => {
      if (!activeRepoCard) {
        setOpenPullRequestCount(null)
        setReviewRequestCount(null)
        return
      }

      const [count, requestedReviewCount] = await Promise.all([
        fetchOpenPullRequestCount(activeRepoCard.repoSlug, githubHandle),
        fetchReviewRequestCount(activeRepoCard.repoSlug, githubHandle),
      ])
      if (!cancelled) {
        setOpenPullRequestCount(count)
        setReviewRequestCount(requestedReviewCount)
      }
    }

    void loadPullRequests()
    const refreshHandle = window.setInterval(() => {
      void loadPullRequests()
    }, 60 * 1000)

    return () => {
      cancelled = true
      window.clearInterval(refreshHandle)
    }
  }, [activeRepoCard?.repoSlug, githubHandle])

  useEffect(() => {
    let cancelled = false

    const loadIncidentCount = async () => {
      if (typeof window === 'undefined') {
        return
      }

      const token = window.localStorage.getItem('pagerduty.token')
      const count = await fetchActivePagerDutyIncidentCount(token)
      if (!cancelled) {
        setActiveIncidentCount(count)
      }
    }

    void loadIncidentCount()
    const refreshHandle = window.setInterval(() => {
      void loadIncidentCount()
    }, 60 * 1000)

    return () => {
      cancelled = true
      window.clearInterval(refreshHandle)
    }
  }, [])

  const teamOnlineCount = getDemoTeamOnlineCount()
  const visibleStatusBarTiles = statusBarTiles.filter((tile) => tile.visible)

  const renderStatusBarTile = (tileId: StatusBarTileId) => {
    switch (tileId) {
      case 'open-prs':
        return (
          <a
            href={activeRepoCard?.links.pullRequests ?? '#'}
            target={activeRepoCard ? '_blank' : undefined}
            rel={activeRepoCard ? 'noopener noreferrer' : undefined}
            className="group rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 transition hover:border-sky-400 hover:bg-sky-50"
            title={`Open the pull request list ${openPullRequestLabel}`}
          >
            <div className="flex items-center justify-between gap-3">
              <div>
                <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Open PRs</p>
                <p className="mt-1 text-2xl font-semibold text-slate-900">{openPullRequestCount ?? '—'}</p>
              </div>
              <span className="rounded-full border border-slate-300 bg-white px-2 py-1 text-[11px] font-medium text-slate-600 transition group-hover:border-sky-300 group-hover:text-sky-700">
                {reviewRequestCount === null ? 'Review requests —' : `${reviewRequestCount} review requests`}
              </span>
            </div>
            <p className="mt-2 text-sm text-slate-600">Open the PR list for the active repo.</p>
            <p className="mt-1 text-xs text-slate-500">{openPullRequestLabel}</p>
          </a>
        )
      case 'branch-ci':
        return (
          <Link
            to={{
              pathname: CI_LOGS_ROUTE,
              search:
                activeRepoCard != null
                  ? `?repo=${encodeURIComponent(activeRepoCard.repoSlug)}&workspace=${encodeURIComponent(activeWorkspace.label)}`
                  : '',
            }}
            className={`group rounded-2xl border px-4 py-3 transition ${ciStyle.badge}`}
            title={`Branch CI for ${activeWorkspace.label}`}
          >
            <div className="flex items-center justify-between gap-3">
              <div>
                <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Branch CI</p>
                <p className={`mt-1 text-lg font-semibold ${ciStyle.text}`}>{ciStatus}</p>
              </div>
              <span className="rounded-full border border-current/20 bg-white px-2 py-1 text-[11px] font-medium text-slate-700 transition group-hover:border-current/40">
                {activeRepoCard?.status.branch ?? activeWorkspace.branch}
              </span>
            </div>
            <p className="mt-2 text-sm text-slate-600">{ciStyle.description}</p>
          </Link>
        )
      case 'pagerduty':
        return (
          <Link
            to={PAGERDUTY_INCIDENTS_ROUTE}
            className="group rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 transition hover:border-rose-400 hover:bg-rose-100"
            title="Open the PagerDuty incidents page"
          >
            <div className="flex items-center justify-between gap-3">
              <div>
                <p className="text-xs font-semibold uppercase tracking-[0.2em] text-rose-700">Active incidents</p>
                <p className="mt-1 text-2xl font-semibold text-rose-800">{activeIncidentCount ?? '—'}</p>
              </div>
              <span className="rounded-full border border-rose-200 bg-white px-2 py-1 text-[11px] font-medium text-rose-700 transition group-hover:border-rose-300">
                PagerDuty
              </span>
            </div>
            <p className="mt-2 text-sm text-rose-700">Open incident details and refresh the live count.</p>
          </Link>
        )
      case 'team-online':
        return (
          <Link
            to={TEAM_HUB_ROUTE}
            className="group rounded-2xl border border-emerald-200 bg-emerald-50 px-4 py-3 transition hover:border-emerald-400 hover:bg-emerald-100"
            title="Open the team collaboration metrics page"
          >
            <div className="flex items-center justify-between gap-3">
              <div>
                <p className="text-xs font-semibold uppercase tracking-[0.2em] text-emerald-700">Team online</p>
                <p className="mt-1 text-2xl font-semibold text-emerald-800">{teamOnlineCount}</p>
              </div>
              <span className="rounded-full border border-emerald-200 bg-white px-2 py-1 text-[11px] font-medium text-emerald-700 transition group-hover:border-emerald-300">
                Presence
              </span>
            </div>
            <p className="mt-2 text-sm text-emerald-700">View the collaboration presence snapshot.</p>
          </Link>
        )
      default:
        return null
    }
  }

  return (
    <section className="border-b border-slate-200 bg-white/95 px-4 py-4 shadow-sm shadow-slate-100">
      <div className="mx-auto grid max-w-7xl gap-3 md:grid-cols-2 xl:grid-cols-4">
        {visibleStatusBarTiles.map((tile) => (
          <React.Fragment key={tile.id}>{renderStatusBarTile(tile.id)}</React.Fragment>
        ))}
      </div>
      <div className="mx-auto max-w-7xl">
        <button
          type="button"
          onClick={() => setTileCustomizerOpen((current) => !current)}
          className="mt-4 inline-flex items-center rounded-full border border-slate-300 bg-white px-3 py-1.5 text-xs font-medium text-slate-700 transition hover:border-slate-400 hover:text-slate-900"
        >
          {tileCustomizerOpen ? 'Hide tile settings' : 'Customize tiles'}
        </button>
      </div>
      {tileCustomizerOpen ? renderTileSettings() : null}
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
            {PINNED_WORKSPACES.map((workspace) => (
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
              visibleRecentWorkspaces.map((workspace) => (
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
                {switcherResults.map((workspace) => (
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
const Layout: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const navigate = useNavigate()
  const location = useLocation()
  const { user, isAuthenticated } = useAuthStore()
  const workspaceState = useWorkspaceState()
  const isSessionsPage = location.pathname.startsWith('/sessions')
  const isOnboardingPage = location.pathname.startsWith('/onboarding')
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
            <Link
              aria-current={isOnboardingPage ? 'page' : undefined}
              className={`rounded-lg border px-4 py-2 text-sm font-medium transition ${
                isOnboardingPage
                  ? 'border-sky-200 bg-sky-50 text-sky-900'
                  : 'border-slate-200 text-slate-700 hover:bg-slate-100'
              }`}
              to="/onboarding"
            >
              Onboarding
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

      <CollaborationStatusStrip workspaceState={workspaceState} />
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
            path="/onboarding"
            element={
              <ProtectedRoute>
                <WorkspaceOnboardingWizard />
              </ProtectedRoute>
            }
          />
          <Route
            path={PAGERDUTY_INCIDENTS_ROUTE}
            element={
              <ProtectedRoute>
                <PagerDutyIncidentsPage />
              </ProtectedRoute>
            }
          />
          <Route
            path={TEAM_HUB_ROUTE}
            element={
              <ProtectedRoute>
                <TeamHubMetricsPage />
              </ProtectedRoute>
            }
          />
          <Route
            path={CI_LOGS_ROUTE}
            element={
              <ProtectedRoute>
                <CiLogsPage />
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
