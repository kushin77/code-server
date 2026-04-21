import React, { useCallback, useEffect, useMemo, useState } from 'react'

import {
  fetchPagerDutyIncidents,
  type PagerDutyIncident,
  type PagerDutyIncidentConfig,
} from '@/extensions/pagerduty-incidents'
import { measureAsyncExtensionProfiler, useExtensionMountProfiler } from '@/utils/extensionProfiler'

type PagerDutyPageConfig = PagerDutyIncidentConfig & {
  refreshInterval: number
}

function readPagerDutyConfig(): PagerDutyPageConfig | null {
  if (typeof window === 'undefined') {
    return null
  }

  const token = window.localStorage.getItem('pagerduty.token')?.trim() ?? ''
  const refreshIntervalRaw = window.localStorage.getItem('pagerduty.refreshInterval')?.trim() ?? '30000'
  const refreshInterval = Number.parseInt(refreshIntervalRaw, 10)

  if (!token) {
    return null
  }

  return {
    token,
    refreshInterval: Number.isFinite(refreshInterval) && refreshInterval > 0 ? refreshInterval : 30000,
  }
}

function sortIncidents(incidents: PagerDutyIncident[]): PagerDutyIncident[] {
  const statusOrder = { triggered: 0, acknowledged: 1, resolved: 2 }
  const urgencyOrder = { high: 0, low: 1 }

  return [...incidents].sort((left, right) => {
    const statusDiff = statusOrder[left.status] - statusOrder[right.status]
    if (statusDiff !== 0) return statusDiff

    const urgencyDiff = urgencyOrder[left.urgency] - urgencyOrder[right.urgency]
    if (urgencyDiff !== 0) return urgencyDiff

    return new Date(right.created_at).getTime() - new Date(left.created_at).getTime()
  })
}

function statusColor(status: PagerDutyIncident['status']): string {
  switch (status) {
    case 'triggered':
      return 'border-rose-300 bg-rose-100 text-rose-900'
    case 'acknowledged':
      return 'border-amber-300 bg-amber-100 text-amber-900'
    case 'resolved':
      return 'border-green-300 bg-green-100 text-green-900'
    default:
      return 'border-slate-300 bg-slate-100 text-slate-700'
  }
}

function urgencyColor(urgency: PagerDutyIncident['urgency']): string {
  switch (urgency) {
    case 'high':
      return 'border-rose-300 bg-rose-100 text-rose-900'
    case 'low':
      return 'border-blue-300 bg-blue-100 text-blue-900'
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

export function PagerDutyIncidentsPage(): React.ReactElement {
  useExtensionMountProfiler({
    id: 'pagerduty-incidents',
    label: 'PagerDuty incidents page',
    category: 'incident-response',
  })

  const [config, setConfig] = useState<PagerDutyPageConfig | null>(null)
  const [incidents, setIncidents] = useState<PagerDutyIncident[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [filterStatus, setFilterStatus] = useState<'triggered' | 'acknowledged' | 'resolved' | 'all'>(
    'triggered'
  )
  const [lastUpdatedAt, setLastUpdatedAt] = useState<number | null>(null)

  useEffect(() => {
    setConfig(readPagerDutyConfig())
  }, [])

  const loadIncidents = useCallback(
    async (currentConfig: PagerDutyPageConfig, status?: 'triggered' | 'acknowledged' | 'resolved' | 'all') => {
      return measureAsyncExtensionProfiler(
        {
          id: 'pagerduty-incidents',
          label: 'PagerDuty incidents page',
          category: 'incident-response',
          kind: 'load',
        },
        async () => {
          try {
            setLoading(true)
            setError(null)
            const result = await fetchPagerDutyIncidents(
              currentConfig,
              status && status !== 'all' ? (status as 'triggered' | 'acknowledged' | 'resolved') : undefined
            )
            setIncidents(sortIncidents(result.incidents))
            setLastUpdatedAt(Date.now())
          } catch (loadError) {
            setError(loadError instanceof Error ? loadError.message : 'Failed to load PagerDuty incidents')
          } finally {
            setLoading(false)
          }
        }
      )
    },
    []
  )

  useEffect(() => {
    if (!config) {
      setLoading(false)
      return undefined
    }

    const statusToLoad = filterStatus !== 'all' ? filterStatus : undefined
    void loadIncidents(config, statusToLoad)

    const interval = window.setInterval(() => {
      void loadIncidents(config, statusToLoad)
    }, config.refreshInterval)

    return () => window.clearInterval(interval)
  }, [config, filterStatus, loadIncidents])

  const summary = useMemo(() => {
    const triggered = incidents.filter((i) => i.status === 'triggered').length
    const acknowledged = incidents.filter((i) => i.status === 'acknowledged').length
    const resolved = incidents.filter((i) => i.status === 'resolved').length
    const highUrgency = incidents.filter((i) => i.urgency === 'high').length
    const services = new Set(incidents.map((i) => i.service.id)).size

    return {
      triggered,
      acknowledged,
      resolved,
      highUrgency,
      services,
    }
  }, [incidents])

  if (!config) {
    return (
      <section className="mx-auto max-w-5xl px-4 py-6">
        <div className="rounded-3xl border border-amber-200 bg-amber-50 p-6 shadow-sm">
          <p className="text-xs font-semibold uppercase tracking-[0.24em] text-amber-700">PagerDuty</p>
          <h2 className="mt-2 text-2xl font-bold text-amber-950">PagerDuty is not configured</h2>
          <p className="mt-2 max-w-2xl text-sm text-amber-900/80">
            Set <span className="font-semibold">pagerduty.token</span> in local storage-backed settings to enable live incident monitoring. Optionally configure{' '}
            <span className="font-semibold">pagerduty.refreshInterval</span> (milliseconds, default 30000).
          </p>
        </div>
      </section>
    )
  }

  return (
    <section className="mx-auto max-w-7xl px-4 py-6">
      <div className="overflow-hidden rounded-3xl border border-slate-200 bg-white shadow-sm shadow-slate-100">
        <div className="relative bg-slate-950 px-6 py-6 text-white sm:px-8">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_right,_rgba(239,68,68,0.25),_transparent_36%),radial-gradient(circle_at_bottom_left,_rgba(168,85,247,0.18),_transparent_42%)]" />
          <div className="relative flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.28em] text-red-300">Incident Response</p>
              <h2 className="mt-2 text-3xl font-bold tracking-tight">Live incident monitoring & management</h2>
              <p className="mt-2 max-w-3xl text-sm text-slate-300">
                Surface triggered incidents, acknowledgment status, urgency, and service impact directly in the IDE.
              </p>
            </div>

            <div className="flex flex-wrap gap-3">
              <button
                type="button"
                onClick={() => {
                  void loadIncidents(config, filterStatus !== 'all' ? filterStatus : undefined)
                }}
                disabled={loading}
                className="rounded-full border border-white/20 bg-white/10 px-4 py-2 text-sm font-semibold text-white transition hover:bg-white/20 disabled:cursor-not-allowed disabled:opacity-60"
              >
                {loading ? 'Refreshing' : 'Refresh'}
              </button>
              <a
                href="https://www.pagerduty.com/incidents"
                target="_blank"
                rel="noreferrer"
                className="rounded-full bg-red-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-red-400"
              >
                Open in PagerDuty
              </a>
            </div>
          </div>
        </div>

        <div className="px-6 py-6 sm:px-8">
          <div className="grid gap-3 md:grid-cols-5">
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500">Triggered</p>
              <p className="mt-2 text-3xl font-bold text-slate-900">{summary.triggered}</p>
            </div>
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500">Acknowledged</p>
              <p className="mt-2 text-3xl font-bold text-slate-900">{summary.acknowledged}</p>
            </div>
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500">Resolved</p>
              <p className="mt-2 text-3xl font-bold text-slate-900">{summary.resolved}</p>
            </div>
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500">High urgency</p>
              <p className="mt-2 text-3xl font-bold text-slate-900">{summary.highUrgency}</p>
            </div>
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500">Services affected</p>
              <p className="mt-2 text-3xl font-bold text-slate-900">{summary.services}</p>
            </div>
          </div>

          {error ? (
            <div className="mt-6 rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-900">
              {error}
            </div>
          ) : null}

          <div className="mt-6 flex flex-wrap gap-2">
            <button
              onClick={() => setFilterStatus('all')}
              className={`rounded-full px-4 py-2 text-sm font-semibold transition ${
                filterStatus === 'all'
                  ? 'bg-slate-900 text-white'
                  : 'border border-slate-300 bg-white text-slate-900 hover:border-slate-400'
              }`}
            >
              All incidents
            </button>
            <button
              onClick={() => setFilterStatus('triggered')}
              className={`rounded-full px-4 py-2 text-sm font-semibold transition ${
                filterStatus === 'triggered'
                  ? 'bg-rose-600 text-white'
                  : 'border border-rose-300 bg-rose-50 text-rose-900 hover:border-rose-400'
              }`}
            >
              Triggered
            </button>
            <button
              onClick={() => setFilterStatus('acknowledged')}
              className={`rounded-full px-4 py-2 text-sm font-semibold transition ${
                filterStatus === 'acknowledged'
                  ? 'bg-amber-600 text-white'
                  : 'border border-amber-300 bg-amber-50 text-amber-900 hover:border-amber-400'
              }`}
            >
              Acknowledged
            </button>
            <button
              onClick={() => setFilterStatus('resolved')}
              className={`rounded-full px-4 py-2 text-sm font-semibold transition ${
                filterStatus === 'resolved'
                  ? 'bg-green-600 text-white'
                  : 'border border-green-300 bg-green-50 text-green-900 hover:border-green-400'
              }`}
            >
              Resolved
            </button>
          </div>

          <div className="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1.1fr)_minmax(0,0.9fr)]">
            <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-500">Incident list</p>
                  <h3 className="mt-1 text-xl font-bold text-slate-900">
                    {filterStatus === 'all' ? 'All incidents' : `${filterStatus} incidents`}
                  </h3>
                </div>
                <span className="rounded-full border border-slate-200 bg-slate-50 px-3 py-1 text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">
                  {incidents.length} loaded
                </span>
              </div>

              <div className="mt-4 space-y-3">
                {incidents.length === 0 ? (
                  <div className="rounded-2xl border border-dashed border-slate-300 bg-slate-50 px-4 py-6 text-sm text-slate-500">
                    No {filterStatus === 'all' ? '' : filterStatus + ' '} incidents found.
                  </div>
                ) : (
                  incidents.map((incident) => (
                    <article key={incident.id} className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
                      <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
                        <div>
                          <div className="flex flex-wrap items-center gap-2">
                            <h4 className="text-lg font-semibold text-slate-900">
                              #{incident.incident_number} {incident.title}
                            </h4>
                            <span className={`rounded-full border px-2.5 py-1 text-xs font-semibold uppercase tracking-[0.16em] ${statusColor(incident.status)}`}>
                              {incident.status}
                            </span>
                            <span className={`rounded-full border px-2.5 py-1 text-xs font-semibold uppercase tracking-[0.16em] ${urgencyColor(incident.urgency)}`}>
                              {incident.urgency}
                            </span>
                          </div>
                          <p className="mt-2 text-sm text-slate-600">
                            Service: <span className="font-semibold">{incident.service.summary}</span> · Created{' '}
                            {formatTimeLabel(incident.created_at)}
                          </p>
                          {incident.assignees.length > 0 ? (
                            <p className="mt-1 text-xs text-slate-500">
                              Assigned to: {incident.assignees.map((a) => a.summary).join(', ')}
                            </p>
                          ) : null}
                        </div>

                        <div className="flex flex-wrap gap-2">
                          {incident.html_url ? (
                            <a
                              href={incident.html_url}
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
                <p className="text-xs font-semibold uppercase tracking-[0.24em] text-red-300">Incident status</p>
                <div className="mt-4 space-y-3">
                  <div className="rounded-2xl border border-white/10 bg-white/5 px-4 py-3">
                    <p className="text-sm font-semibold text-white">Refresh interval</p>
                    <p className="text-sm text-slate-300">{Math.round(config.refreshInterval / 1000)} seconds</p>
                  </div>
                  <div className="rounded-2xl border border-white/10 bg-white/5 px-4 py-3">
                    <p className="text-sm font-semibold text-white">Last updated</p>
                    <p className="text-sm text-slate-300">
                      {lastUpdatedAt ? new Date(lastUpdatedAt).toLocaleTimeString() : 'just now'}
                    </p>
                  </div>
                  <div className="rounded-2xl border border-white/10 bg-white/5 px-4 py-3">
                    <p className="text-sm font-semibold text-white">Total incidents</p>
                    <p className="text-sm text-slate-300">{incidents.length}</p>
                  </div>
                </div>
              </div>

              <div className="rounded-2xl border border-dashed border-red-200 bg-red-50 p-5">
                <p className="text-xs font-semibold uppercase tracking-[0.24em] text-red-700">Settings note</p>
                <p className="mt-2 text-sm text-slate-700">
                  Configure PagerDuty API token via <span className="font-semibold">pagerduty.token</span> in local storage. Optionally set{' '}
                  <span className="font-semibold">pagerduty.refreshInterval</span> (milliseconds).
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
