// @file        apps/frontend/src/pages/PagerDutyIncidentsPage.tsx
// @module      pages/pagerduty-incidents
// @description PagerDuty Incidents dashboard page component

import { useEffect, useMemo, useState } from 'react'

import { AlertTriangle, CheckCircle, Clock, ExternalLink, RefreshCw } from '@/common/lucide-react'

import { measureAsyncExtensionProfiler } from '@/common/performance'
import { ErrorBoundary } from '@/common/error-boundary'

import {
  fetchPagerDutyIncidents,
  type IncidentStats,
  type PagerDutyIncident,
  type PagerDutyIncidentConfig,
} from '@/extensions/pagerduty-incidents'

const STATUS_STYLES = {
  triggered: {
    badge: 'bg-red-100 text-red-800',
    button: 'bg-red-600 hover:bg-red-700',
    text: 'text-red-600',
  },
  acknowledged: {
    badge: 'bg-amber-100 text-amber-800',
    button: 'bg-amber-600 hover:bg-amber-700',
    text: 'text-amber-600',
  },
  resolved: {
    badge: 'bg-green-100 text-green-800',
    button: 'bg-green-600 hover:bg-green-700',
    text: 'text-green-600',
  },
}

const URGENCY_ICON = {
  high: <AlertTriangle className="w-4 h-4 text-red-500" />,
  low: <CheckCircle className="w-4 h-4 text-green-500" />,
}

export function PagerDutyIncidentsPage() {
  const [incidents, setIncidents] = useState<PagerDutyIncident[]>([])
  const [stats, setStats] = useState<IncidentStats>({
    triggered: 0,
    acknowledged: 0,
    resolved: 0,
    total: 0,
  })
  const [activeStatus, setActiveStatus] = useState<'all' | 'triggered' | 'acknowledged' | 'resolved'>(
    'all'
  )
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [config, setConfig] = useState<PagerDutyIncidentConfig | null>(null)
  const [refreshInterval, setRefreshInterval] = useState<NodeJS.Timeout | null>(null)

  // Load configuration from localStorage
  useEffect(() => {
    const token = localStorage.getItem('pagerduty.token')
    const interval = parseInt(localStorage.getItem('pagerduty.refreshInterval') || '30000', 10)

    if (token) {
      setConfig({ token, refreshInterval: interval })
    }
  }, [])

  // Fetch incidents when config changes
  const fetchIncidents = async (cfg: PagerDutyIncidentConfig | null) => {
    if (!cfg?.token) {
      setIncidents([])
      setStats({ triggered: 0, acknowledged: 0, resolved: 0, total: 0 })
      return
    }

    setIsLoading(true)
    setError(null)

    try {
      await measureAsyncExtensionProfiler(pageProfiler, 'fetch-incidents', async () => {
        const { incidents: fetchedIncidents, stats: fetchedStats } = await fetchPagerDutyIncidents(
          cfg,
          activeStatus === 'all' ? undefined : activeStatus
        )

        setIncidents(fetchedIncidents)
        setStats(fetchedStats)
      })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch incidents')
      setIncidents([])
    } finally {
      setIsLoading(false)
    }
  }

  // Initial fetch
  useEffect(() => {
    if (config) {
      void fetchIncidents(config)
    }
  }, [config])

  // Auto-refresh
  useEffect(() => {
    if (config?.refreshInterval && config.refreshInterval > 0) {
      if (refreshInterval) clearInterval(refreshInterval)
      const newInterval = setInterval(() => {
        void fetchIncidents(config)
      }, config.refreshInterval)
      setRefreshInterval(newInterval)

      return () => clearInterval(newInterval)
    }
  }, [config, refreshInterval])

  // Filtered incidents based on active status
  const filteredIncidents = useMemo(() => {
    if (activeStatus === 'all') return incidents

    return incidents.filter((incident) => incident.status === activeStatus)
  }, [incidents, activeStatus])

  // Sort incidents: status -> urgency -> created_at
  const sortedIncidents = useMemo(() => {
    const statusPriority = { triggered: 0, acknowledged: 1, resolved: 2 }
    const urgencyPriority = { high: 0, low: 1 }

    return [...filteredIncidents].sort((a, b) => {
      const statusDiff = statusPriority[a.status] - statusPriority[b.status]
      if (statusDiff !== 0) return statusDiff

      const urgencyDiff = urgencyPriority[a.urgency] - urgencyPriority[b.urgency]
      if (urgencyDiff !== 0) return urgencyDiff

      return new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
    })
  }, [filteredIncidents])

  const handleRefresh = () => {
    void fetchIncidents(config)
  }

  const handleStatusFilter = (status: 'all' | 'triggered' | 'acknowledged' | 'resolved') => {
    setActiveStatus(status)
  }

  if (!config?.token) {
    return (
      <ErrorBoundary>
        <div className="p-8 text-center">
          <AlertTriangle className="w-12 h-12 mx-auto mb-4 text-amber-500" />
          <h2 className="text-2xl font-bold mb-2">PagerDuty Not Configured</h2>
          <p className="text-gray-600 mb-4">
            Please configure your PagerDuty API token in localStorage:
          </p>
          <code className="block bg-gray-100 p-4 rounded mb-4 text-sm">
            localStorage.setItem('pagerduty.token', 'YOUR_API_TOKEN')
          </code>
          <p className="text-gray-600 text-sm">
            Optionally set refresh interval:
            <br />
            <code className="bg-gray-100 p-1 rounded">
              localStorage.setItem('pagerduty.refreshInterval', '30000')
            </code>
          </p>
        </div>
      </ErrorBoundary>
    )
  }

  return (
    <ErrorBoundary>
      <div className="flex flex-col h-full bg-gradient-to-b from-slate-900 via-purple-900 to-slate-900">
        {/* Header */}
        <div className="bg-gradient-to-r from-purple-600 to-blue-600 text-white px-6 py-6 border-b border-purple-500">
          <div className="flex items-center justify-between mb-4">
            <h1 className="text-3xl font-bold">PagerDuty Incidents</h1>
            <button
              onClick={handleRefresh}
              disabled={isLoading}
              className="flex items-center gap-2 bg-white text-purple-600 px-4 py-2 rounded-lg font-medium hover:bg-gray-100 disabled:opacity-50 transition"
              title="Refresh incidents"
            >
              <RefreshCw className={`w-4 h-4 ${isLoading ? 'animate-spin' : ''}`} />
              {isLoading ? 'Refreshing...' : 'Refresh'}
            </button>
          </div>

          {/* Summary metrics */}
          <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
            <div className="bg-white bg-opacity-20 rounded-lg p-3">
              <div className="text-sm opacity-90">Total</div>
              <div className="text-2xl font-bold">{stats.total}</div>
            </div>
            <div className="bg-red-500 bg-opacity-30 rounded-lg p-3 border border-red-400">
              <div className="text-sm opacity-90">Triggered</div>
              <div className="text-2xl font-bold text-red-200">{stats.triggered}</div>
            </div>
            <div className="bg-amber-500 bg-opacity-30 rounded-lg p-3 border border-amber-400">
              <div className="text-sm opacity-90">Acknowledged</div>
              <div className="text-2xl font-bold text-amber-200">{stats.acknowledged}</div>
            </div>
            <div className="bg-green-500 bg-opacity-30 rounded-lg p-3 border border-green-400">
              <div className="text-sm opacity-90">Resolved</div>
              <div className="text-2xl font-bold text-green-200">{stats.resolved}</div>
            </div>
            <div className="bg-blue-500 bg-opacity-30 rounded-lg p-3 border border-blue-400">
              <div className="text-sm opacity-90">High Urgency</div>
              <div className="text-2xl font-bold text-blue-200">
                {incidents.filter((i) => i.urgency === 'high').length}
              </div>
            </div>
          </div>
        </div>

        {/* Status filter buttons */}
        <div className="flex gap-2 px-6 py-4 border-b border-gray-700 bg-gray-800 bg-opacity-50">
          {(['all', 'triggered', 'acknowledged', 'resolved'] as const).map((status) => {
            const isActive = activeStatus === status
            const style = status === 'all' ? {} : STATUS_STYLES[status]
            const label =
              status === 'all'
                ? `All (${stats.total})`
                : `${status.charAt(0).toUpperCase() + status.slice(1)} (${stats[status]})`

            return (
              <button
                key={status}
                onClick={() => handleStatusFilter(status)}
                className={`px-4 py-2 rounded-lg font-medium transition ${
                  isActive
                    ? status === 'all'
                      ? 'bg-gray-600 text-white'
                      : style.button + ' text-white'
                    : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
                }`}
              >
                {label}
              </button>
            )
          })}
        </div>

        {/* Error message */}
        {error && (
          <div className="mx-6 mt-4 bg-red-900 bg-opacity-50 border border-red-500 text-red-200 p-4 rounded">
            {error}
          </div>
        )}

        {/* Incidents list */}
        <div className="flex-1 overflow-auto p-6">
          {sortedIncidents.length === 0 ? (
            <div className="text-center text-gray-400 py-12">
              {isLoading ? 'Loading incidents...' : 'No incidents to display'}
            </div>
          ) : (
            <div className="space-y-3">
              {sortedIncidents.map((incident) => (
                <div
                  key={incident.id}
                  className="bg-gray-800 border border-gray-700 rounded-lg p-4 hover:border-gray-600 transition"
                >
                  <div className="flex items-start justify-between gap-4">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-2">
                        <span
                          className={`px-2 py-1 rounded text-xs font-medium ${
                            STATUS_STYLES[incident.status].badge
                          }`}
                        >
                          {incident.status.toUpperCase()}
                        </span>
                        <div className="flex items-center gap-1">
                          {URGENCY_ICON[incident.urgency]}
                          <span className="text-xs text-gray-400">
                            {incident.urgency.toUpperCase()}
                          </span>
                        </div>
                      </div>
                      <h3 className="text-lg font-semibold text-white mb-1 truncate">
                        #{incident.incident_number}: {incident.title}
                      </h3>
                      <div className="flex flex-col gap-1 text-sm text-gray-400">
                        <div>Service: {incident.service.summary}</div>
                        {incident.assignees.length > 0 && (
                          <div>
                            Assigned to:{' '}
                            {incident.assignees.map((a) => a.summary || a.email).join(', ')}
                          </div>
                        )}
                        <div className="flex items-center gap-1">
                          <Clock className="w-3 h-3" />
                          Created: {new Date(incident.created_at).toLocaleString()}
                        </div>
                      </div>
                    </div>
                    {incident.html_url && (
                      <a
                        href={incident.html_url}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="flex items-center gap-1 px-3 py-2 bg-purple-600 hover:bg-purple-700 text-white rounded text-sm font-medium transition"
                        title="Open in PagerDuty"
                      >
                        <ExternalLink className="w-4 h-4" />
                        View
                      </a>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </ErrorBoundary>
  )
}
