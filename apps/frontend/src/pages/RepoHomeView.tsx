import React, { useMemo } from 'react'

import {
  buildRepoCardActions,
  formatRepoHomeRefreshLabel,
  formatRepoLastActivity,
  getRepoCardTone,
  RepoCardActionId,
  RepoHomeSnapshot,
} from '@/utils/repoHomeData'
import { MultiRepoPolicyConformanceReport } from '@/utils/multiRepoPolicy'
import { WorkspaceRestorePreferences } from '@/utils/workspaceSessionPersistence'

type RepoHomeWorkspace = {
  id: string
  label: string
  branch: string
  pinned: boolean
}

type RepoHomePolicy = {
  schemaVersion: number
  policyVersion: string
  label: string
  canSwitchWorkspace: boolean
  canUseQuickSwitcher: boolean
  canRestoreSession: boolean
  canPinWorkspace: boolean
  maxRecentWorkspaces: number
}

type RepoHomeRolloutDecision = {
  mode: 'off' | 'pilot' | 'on'
  enabled: boolean
  cohort: 'pilot' | 'control' | 'full'
  capabilities: {
    tabs: boolean
    switcher: boolean
    persistence: boolean
  }
  reason: string
}

type RepoHomeSessionSnapshot = {
  activeRepoId: string
  recentRepoIds: string[]
  savedAt: number
}

export type RepoHomeViewState = {
  activeWorkspace: RepoHomeWorkspace
  activeRepoCard?: RepoHomeSnapshot['cards'][number]
  actionNotice: string | null
  performRepoAction: (workspaceId: string, actionId: RepoCardActionId) => void
  repoHomeSnapshot: RepoHomeSnapshot
  sessionSnapshot: RepoHomeSessionSnapshot | null
  restoreNotice: string | null
  restoreSavedSession: () => void
  forgetSavedSession: () => void
  restorePreferences: WorkspaceRestorePreferences
  setRestorePreference: (moduleName: keyof WorkspaceRestorePreferences, enabled: boolean) => void
  workspacePolicy: RepoHomePolicy
  policyReport: MultiRepoPolicyConformanceReport
  rolloutDecision: RepoHomeRolloutDecision
  multiRepoNavigationEnabled: boolean
  multiRepoTabsEnabled: boolean
  multiRepoSwitcherEnabled: boolean
  multiRepoPersistenceEnabled: boolean
}

export const RepoHomeView: React.FC<{ workspaceState: RepoHomeViewState }> = ({ workspaceState }) => {
  const {
    activeWorkspace,
    activeRepoCard,
    actionNotice,
    performRepoAction,
    repoHomeSnapshot,
    sessionSnapshot,
    restoreNotice,
    restoreSavedSession,
    forgetSavedSession,
    restorePreferences,
    setRestorePreference,
    workspacePolicy,
    policyReport,
    rolloutDecision,
    multiRepoNavigationEnabled,
    multiRepoTabsEnabled,
    multiRepoSwitcherEnabled,
    multiRepoPersistenceEnabled,
  } = workspaceState
  const allWorkspaceCards = useMemo(() => repoHomeSnapshot.cards, [repoHomeSnapshot.cards])
  const favoriteCount = allWorkspaceCards.filter((card) => card.favorite).length
  const sharedSetCount = allWorkspaceCards.filter((card) => Boolean(card.sharedSet)).length

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
              <p className="text-sm text-slate-600">Branch: {activeRepoCard?.status.branch ?? activeWorkspace.branch}</p>
            </div>
            <div className="rounded-2xl bg-emerald-50 px-4 py-3">
              <p className="text-xs font-semibold uppercase tracking-[0.2em] text-emerald-700">Status refresh</p>
              <p className="mt-1 text-sm text-slate-700">
                Updates every {Math.round(repoHomeSnapshot.refreshIntervalMs / 1000)}s · last refreshed {formatRepoHomeRefreshLabel(repoHomeSnapshot.fetchedAt)}
              </p>
            </div>
          </div>
        </div>

        <div className="mt-6 grid gap-3 md:grid-cols-3">
          <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Favorite repos</p>
            <p className="mt-1 text-2xl font-semibold text-slate-900">{favoriteCount}</p>
          </div>
          <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Team-shared sets</p>
            <p className="mt-1 text-2xl font-semibold text-slate-900">{sharedSetCount}</p>
          </div>
          <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Policy lane</p>
            <p className="mt-1 text-lg font-semibold text-slate-900">{workspacePolicy.label}</p>
            <p className="mt-1 text-xs text-slate-500">
              Schema v{workspacePolicy.schemaVersion} · {workspacePolicy.policyVersion}
            </p>
            <p className={`mt-1 text-xs font-medium ${policyReport.compliant ? 'text-emerald-700' : 'text-rose-700'}`}>
              {policyReport.compliant ? 'Conformance healthy' : `${policyReport.issues.length} policy drift check(s) flagged`}
            </p>
          </div>
        </div>

        <div className="mt-6 grid gap-4 lg:grid-cols-3">
          {allWorkspaceCards.map((card) => {
            const isActive = card.id === activeWorkspace.id
            const ciTone = getRepoCardTone(card.status.ciStatus)
            const actions = buildRepoCardActions(card, workspacePolicy, activeWorkspace.id)
            return (
              <article
                key={card.id}
                data-testid={`repo-card-${card.id}`}
                className={`rounded-2xl border p-4 transition ${
                  isActive ? 'border-sky-500 bg-sky-50 shadow-sm' : 'border-slate-200 bg-slate-50 hover:border-slate-300'
                }`}
              >
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <p className="text-sm font-semibold text-slate-900">{card.label}</p>
                    <p className="text-xs text-slate-500">{card.repoSlug}</p>
                  </div>
                  <div className="flex flex-wrap justify-end gap-2">
                    {card.favorite ? (
                      <span className="rounded-full bg-white px-2 py-1 text-[11px] font-semibold uppercase tracking-[0.18em] text-slate-500">
                        Favorite
                      </span>
                    ) : null}
                    {card.sharedSet ? (
                      <span className="rounded-full bg-white px-2 py-1 text-[11px] font-semibold uppercase tracking-[0.18em] text-violet-600">
                        {card.sharedSet}
                      </span>
                    ) : null}
                  </div>
                </div>
                <p className="mt-3 text-sm text-slate-600">{card.description}</p>
                <div className="mt-3 space-y-2 text-sm text-slate-600">
                  <div className="flex flex-wrap gap-2">
                    <span className="rounded-full bg-white px-2 py-1 text-xs font-medium text-slate-700">Branch: {card.status.branch}</span>
                    <span
                      className={`rounded-full px-2 py-1 text-xs font-medium ${
                        card.status.dirty ? 'bg-amber-100 text-amber-800' : 'bg-emerald-100 text-emerald-800'
                      }`}
                    >
                      {card.status.dirty ? 'Dirty' : 'Clean'}
                    </span>
                    <span className={`rounded-full px-2 py-1 text-xs font-medium ${ciTone === 'emerald' ? 'bg-emerald-100 text-emerald-800' : ciTone === 'sky' ? 'bg-sky-100 text-sky-800' : ciTone === 'rose' ? 'bg-rose-100 text-rose-800' : 'bg-amber-100 text-amber-800'}`}>
                      CI: {card.status.ciStatus}
                    </span>
                    <span className="rounded-full bg-white px-2 py-1 text-xs font-medium text-slate-700">
                      {formatRepoLastActivity(card.status.lastActivityAt)}
                    </span>
                  </div>
                  <p>Status: {isActive ? 'Active workspace' : 'Ready to switch'}</p>
                </div>

                {card.errorHint ? (
                  <div className="mt-4 rounded-2xl border border-amber-200 bg-amber-50 px-3 py-3 text-sm text-amber-900">
                    <p className="font-semibold">{card.errorHint.title}</p>
                    <p className="mt-1 text-amber-800">{card.errorHint.remediation}</p>
                  </div>
                ) : null}

                <div className="mt-4 flex flex-wrap gap-2">
                  {actions.map((action) => {
                    const shouldDisableForRollout =
                      (action.id === 'open' || action.id === 'switch' || action.id === 'pull') && !multiRepoTabsEnabled
                    return (
                      <button
                        key={action.id}
                        type="button"
                        onClick={() => performRepoAction(card.id, action.id)}
                        disabled={action.disabled || shouldDisableForRollout}
                        title={action.reason}
                        className={`rounded-full px-3 py-2 text-sm font-medium transition ${
                          action.id === 'switch' || action.id === 'open'
                            ? 'bg-slate-900 text-white hover:bg-slate-700'
                            : 'border border-slate-300 text-slate-700 hover:border-sky-400 hover:text-sky-700'
                        } disabled:cursor-not-allowed disabled:opacity-50`}
                      >
                        {action.label}
                      </button>
                    )
                  })}
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
          <div className="mt-3 grid gap-2 sm:grid-cols-3">
            <p className="rounded-full bg-white px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-slate-600">
              Tabs: {multiRepoTabsEnabled ? 'on' : 'off'}
            </p>
            <p className="rounded-full bg-white px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-slate-600">
              Switcher: {multiRepoSwitcherEnabled ? 'on' : 'off'}
            </p>
            <p className="rounded-full bg-white px-3 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-slate-600">
              Persistence: {multiRepoPersistenceEnabled ? 'on' : 'off'}
            </p>
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
              {actionNotice ? <p className="mt-2 text-sm font-medium text-sky-700">{actionNotice}</p> : null}
              <div className="mt-3 flex flex-wrap gap-3">
                {([
                  ['files', 'Files'],
                  ['editors', 'Editor groups'],
                  ['terminals', 'Terminals'],
                  ['tasks', 'Tasks'],
                  ['debugConfigs', 'Debug configs'],
                ] as Array<[keyof WorkspaceRestorePreferences, string]>).map(([moduleName, label]) => (
                  <label key={moduleName} className="inline-flex items-center gap-2 text-xs text-slate-600">
                    <input
                      type="checkbox"
                      checked={restorePreferences[moduleName]}
                      onChange={(event) => setRestorePreference(moduleName, event.target.checked)}
                    />
                    {label}
                  </label>
                ))}
              </div>
            </div>

            <div className="flex flex-wrap gap-2">
              <button
                type="button"
                onClick={restoreSavedSession}
                disabled={!workspacePolicy.canRestoreSession || !multiRepoPersistenceEnabled}
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