import React, { useCallback, useEffect, useMemo, useState } from 'react'

import { fetchSentryErrors, type SentryError, type SentryProjectConfig } from '@/extensions/sentry-errors'
import { measureAsyncExtensionProfiler, useExtensionMountProfiler } from '@/utils/extensionProfiler'

type SentryPageConfig = SentryProjectConfig & {
  refreshInterval: number
}

function readSentryConfig(): SentryPageConfig | null {
  if (typeof window === 'undefined') {
    return null
  }

  const token = window.localStorage.getItem('sentry.token')?.trim() ?? ''
  const organization = window.localStorage.getItem('sentry.organization')?.trim() ?? ''
  const project = window.localStorage.getItem('sentry.project')?.trim() ?? ''
  const environment = window.localStorage.getItem('sentry.environment')?.trim() ?? ''
  const refreshIntervalRaw = window.localStorage.getItem('sentry.refreshInterval')?.trim() ?? '60000'
  const refreshInterval = Number.parseInt(refreshIntervalRaw, 10)

  if (!token || !organization || !project) {
    return null
  }

  return {
    token,
    organization,
    project,
    environment,
    refreshInterval: Number.isFinite(refreshInterval) && refreshInterval > 0 ? refreshInterval : 60000,
  }
}

function sortIssues(issues: SentryError[]): SentryError[] {
  return [...issues].sort((left, right) => right.count - left.count || right.userCount - left.userCount)
}

function severityTone(level: SentryError['level']): string {
  switch (level) {
    case 'fatal':
      return 'border-rose-300 bg-rose-100 text-rose-900'
    case 'error':
      return 'border-orange-300 bg-orange-100 text-orange-900'
    case 'warning':
      return 'border-amber-300 bg-amber-100 text-amber-900'
    case 'info':
      return 'border-sky-300 bg-sky-100 text-sky-900'
    default:
      return 'border-slate-300 bg-slate-100 text-slate-700'
  }
}

function formatTimeLabel(value: string): string {
  if (!value) {
    return 'Unknown'
  }

  const parsed = Date.parse(value)
  return Number.isNaN(parsed) ? value : new Date(parsed).toLocaleString()
}

export function SentryErrorsPage(): React.ReactElement {
  useExtensionMountProfiler({
    id: 'sentry-errors',
    label: 'Sentry errors page',
    category: 'observability',
  })

  const [config, setConfig] = useState<SentryPageConfig | null>(null)
  const [issues, setIssues] = useState<SentryError[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [lastUpdatedAt, setLastUpdatedAt] = useState<number | null>(null)

  useEffect(() => {
    setConfig(readSentryConfig())
  }, [])

  const loadIssues = useCallback(async (currentConfig: SentryPageConfig) => {
    return measureAsyncExtensionProfiler(
      {
        id: 'sentry-errors',
        label: 'Sentry errors page',
        category: 'observability',
        kind: 'load',
      },
      async () => {
        try {
          setLoading(true)
          setError(null)
          const nextIssues = await fetchSentryErrors(currentConfig)
          setIssues(sortIssues(nextIssues))
          setLastUpdatedAt(Date.now())
        } catch (loadError) {
          setError(loadError instanceof Error ? loadError.message : 'Failed to load Sentry issues')
        } finally {
          setLoading(false)
        }
      }
    )
  }, [])

  useEffect(() => {
    if (!config) {
      setLoading(false)
      return undefined
    }

    void loadIssues(config)

    const interval = window.setInterval(() => {
      void loadIssues(config)
    }, config.refreshInterval)

    return () => window.clearInterval(interval)
  }, [config, loadIssues])

  const summary = useMemo(() => {
    const unresolvedCount = issues.filter((issue) => issue.status === 'unresolved').length
    const fatalCount = issues.filter((issue) => issue.level === 'fatal').length
    const totalAffectedUsers = issues.reduce((total, issue) => total + issue.userCount, 0)
    const environments = [...new Set(issues.map((issue) => issue.environment).filter(Boolean))]

    return {
      unresolvedCount,
      fatalCount,
      totalAffectedUsers,
      environments,
    }
  }, [issues])

  if (!config) {
    return (
      <section className="mx-auto max-w-5xl px-4 py-6">
        <div className="rounded-3xl border border-amber-200 bg-amber-50 p-6 shadow-sm">
          <p className="text-xs font-semibold uppercase tracking-[0.24em] text-amber-700">Sentry errors</p>
          <h2 className="mt-2 text-2xl font-bold text-amber-950">Sentry is not configured</h2>
          <p className="mt-2 max-w-2xl text-sm text-amber-900/80">
            Set <span className="font-semibold">sentry.token</span>, <span className="font-semibold">sentry.organization</span>, and <span className="font-semibold">sentry.project</span> in local storage-backed settings to enable live issue monitoring.
          </p>
        </div>
      </section>
    )
  }

  return (
    <section className="mx-auto max-w-7xl px-4 py-6">
      <div className="overflow-hidden rounded-3xl border border-slate-200 bg-white shadow-sm shadow-slate-100">
        <div className="relative bg-slate-950 px-6 py-6 text-white sm:px-8">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_right,_rgba(251,146,60,0.25),_transparent_36%),radial-gradient(circle_at_bottom_left,_rgba(244,114,182,0.18),_transparent_42%)]" />
          <div className="relative flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.28em] text-orange-300">Sentry errors</p>
              <h2 className="mt-2 text-3xl font-bold tracking-tight">Live error monitoring with release-aware context</h2>
              <p className="mt-2 max-w-3xl text-sm text-slate-300">
                Surface unresolved issues, severity, environment, and affected user counts directly in the IDE shell.
              </p>
            </div>

            <div className="flex flex-wrap gap-3">
              <button
                type="button"
                onClick={() => void loadIssues(config)}
                disabled={loading}
                className="rounded-full border border-white/20 bg-white/10 px-4 py-2 text-sm font-semibold text-white transition hover:bg-white/20 disabled:cursor-not-allowed disabled:opacity-60"
              >
                {loading ? 'Refreshing' : 'Refresh'}
              </button>
              <a
                href={`https://sentry.io/organizations/${config.organization}/issues/?project=${encodeURIComponent(config.project)}`}
                target="_blank"
                rel="noreferrer"
                className="rounded-full bg-orange-400 px-4 py-2 text-sm font-semibold text-slate-950 transition hover:bg-orange-300"
              >
                Open in Sentry
              </a>
            </div>
          </div>
        </div>

        <div className="px-6 py-6 sm:px-8">
          <div className="grid gap-3 md:grid-cols-4">
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500">Unresolved</p>
              <p className="mt-2 text-3xl font-bold text-slate-900">{summary.unresolvedCount}</p>
            </div>
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500">Fatal issues</p>
              <p className="mt-2 text-3xl font-bold text-slate-900">{summary.fatalCount}</p>
            </div>
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500">Affected users</p>
              <p className="mt-2 text-3xl font-bold text-slate-900">{summary.totalAffectedUsers}</p>
            </div>
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500">Environments</p>
              <p className="mt-2 text-lg font-semibold text-slate-900">{summary.environments.length ? summary.environments.join(', ') : '—'}</p>
              <p className="mt-1 text-xs text-slate-500">
                Last updated {lastUpdatedAt ? new Date(lastUpdatedAt).toLocaleTimeString() : 'just now'}
              </p>
            </div>
          </div>

          {error ? (
            <div className="mt-6 rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-900">
              {error}
            </div>
          ) : null}

          <div className="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1.1fr)_minmax(0,0.9fr)]">
            <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-500">Issue list</p>
                  <h3 className="mt-1 text-xl font-bold text-slate-900">Unresolved issues</h3>
                </div>
                <span className="rounded-full border border-slate-200 bg-slate-50 px-3 py-1 text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">
                  {issues.length} loaded
                </span>
              </div>

              <div className="mt-4 space-y-3">
                {issues.length === 0 ? (
                  <div className="rounded-2xl border border-dashed border-slate-300 bg-slate-50 px-4 py-6 text-sm text-slate-500">
                    No unresolved issues were returned by the current Sentry query.
                  </div>
                ) : (
                  issues.map((issue) => (
                    <article key={issue.id} className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
                      <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
                        <div>
                          <div className="flex flex-wrap items-center gap-2">
                            <h4 className="text-lg font-semibold text-slate-900">{issue.title}</h4>
                            <span className={`rounded-full border px-2.5 py-1 text-xs font-semibold uppercase tracking-[0.16em] ${severityTone(issue.level)}`}>
                              {issue.level}
                            </span>
                            <span className="rounded-full border border-slate-300 bg-white px-2.5 py-1 text-xs font-semibold uppercase tracking-[0.16em] text-slate-700">
                              {issue.status}
                            </span>
                          </div>
                          <p className="mt-2 text-sm text-slate-600">
                            Environment: {issue.environment} · Last seen {formatTimeLabel(issue.lastSeen)}
                          </p>
                        </div>

                        <div className="flex flex-wrap gap-2">
                          <span className="rounded-full border border-slate-300 bg-white px-3 py-1 text-xs font-medium text-slate-700">
                            {issue.count} events
                          </span>
                          <span className="rounded-full border border-slate-300 bg-white px-3 py-1 text-xs font-medium text-slate-700">
                            {issue.userCount} users
                          </span>
                          {issue.permalink ? (
                            <a
                              href={issue.permalink}
                              target="_blank"
                              rel="noreferrer"
                              className="rounded-full bg-slate-900 px-3 py-1 text-xs font-medium text-white transition hover:bg-slate-700"
                            >
                              Open
                            </a>
                          ) : null}
                        </div>
                      </div>
                    </article>
                  ))
                )}
              </div>
            </div>

            <div className="space-y-4">
              <div className="rounded-2xl border border-slate-200 bg-slate-950 p-5 text-white shadow-sm">
                <p className="text-xs font-semibold uppercase tracking-[0.24em] text-orange-300">Release health</p>
                <div className="mt-4 space-y-3">
                  <div className="rounded-2xl border border-white/10 bg-white/5 px-4 py-3">
                    <p className="text-sm font-semibold text-white">Current project</p>
                    <p className="text-sm text-slate-300">{config.organization}/{config.project}</p>
                  </div>
                  <div className="rounded-2xl border border-white/10 bg-white/5 px-4 py-3">
                    <p className="text-sm font-semibold text-white">Refresh interval</p>
                    <p className="text-sm text-slate-300">{Math.round(config.refreshInterval / 1000)} seconds</p>
                  </div>
                  <div className="rounded-2xl border border-white/10 bg-white/5 px-4 py-3">
                    <p className="text-sm font-semibold text-white">Environment filter</p>
                    <p className="text-sm text-slate-300">{config.environment || 'all environments'}</p>
                  </div>
                </div>
              </div>

              <div className="rounded-2xl border border-dashed border-orange-200 bg-orange-50 p-5">
                <p className="text-xs font-semibold uppercase tracking-[0.24em] text-orange-700">Settings note</p>
                <p className="mt-2 text-sm text-slate-700">
                  Configure Sentry via <span className="font-semibold">sentry.token</span>, <span className="font-semibold">sentry.organization</span>, <span className="font-semibold">sentry.project</span>, and optional <span className="font-semibold">sentry.environment</span> / <span className="font-semibold">sentry.refreshInterval</span>.
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
